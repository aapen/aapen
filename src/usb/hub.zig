/// Protocol definition for USB 2.0 Hub devices
///
/// See USB 2.0 specification, revision 2.0 (dated April 27, 2000),
/// chapter 11 for all the details
const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const DMA = root.HAL.USBHCI.DMA_ALIGNMENT;

const arch = @import("../architecture.zig");
const cpu = arch.cpu;

const Logger = @import("../logger.zig");
var log: *Logger = undefined;

const mailbox = @import("../mailbox.zig");
const semaphore = @import("../semaphore.zig");
const synchronize = @import("../synchronize.zig");
const AllocationSet = synchronize.AllocationSet;
const schedule = @import("../schedule.zig");
const time = @import("../time.zig");
const usb = @import("../usb.zig");

const class = @import("class.zig");
const core = @import("core.zig");
const enumerate = @import("enumerate.zig");
const spec = @import("spec.zig");

// some timing constants from the USB spec
const RESET_TIMEOUT = 100;
const PORT_RESET_TIMEOUT = 800;
const ROOT_RESET_DELAY = 60;
const SHORT_RESET_DELAY = 10;

// ----------------------------------------------------------------------
// Local implementation
// ----------------------------------------------------------------------
pub const MAX_HUBS = 8;
pub const MAX_INTERFACES = 8;
pub const MAX_INTERFACE_ALTERNATES = 8;
pub const MAX_ENDPOINTS = 4;

pub const Endpoint = struct {
    ep_desc: spec.EndpointDescriptor,
};

pub const InterfaceAlternate = struct {
    interface_descriptor: spec.InterfaceDescriptor,
    hid: spec.HidDescriptor,
    ep: [MAX_ENDPOINTS]Endpoint,
    ep_count: u8 = 0,
};

pub const Interface = struct {
    class_driver: *const class.Driver = undefined,
    device_name: []u8 = undefined,
    alternate: [MAX_INTERFACE_ALTERNATES]InterfaceAlternate = undefined,
    altsetting_count: u8 = 0,
};

pub const HubPort = struct {
    // Connecting to the hub tree
    parent: *Hub,
    port: u7,
    speed: u8,
    status: usb.HubPortStatus,

    // About the device connected to this port
    connected: bool,
    device_address: u7,
    device_desc: spec.DeviceDescriptor,
    config_desc: spec.ConfigurationDescriptor,
    interfaces: [MAX_INTERFACES]Interface,
    raw_config_descriptor: []u8,

    // Reserved space for activities
    setup: spec.SetupPacket align(DMA),
    ep0: spec.EndpointDescriptor,
    ep0_urb: usb.URB,
    mutex: semaphore.SID,

    pub fn init(parent: *Hub, port_number: u7) !HubPort {
        var self: HubPort = .{
            .parent = parent,
            .port = port_number,
            .speed = spec.USB_SPEED_FULL,
            .status = @bitCast(@as(u32, 0)),
            .connected = false,
            .device_address = 0,
            .device_desc = std.mem.zeroes(spec.DeviceDescriptor),
            .config_desc = std.mem.zeroes(spec.ConfigurationDescriptor),
            .raw_config_descriptor = undefined,
            .interfaces = undefined,
            .setup = undefined,
            .ep0 = std.mem.zeroes(spec.EndpointDescriptor),
            .ep0_urb = undefined,
            .mutex = try semaphore.create(1),
        };

        return self;
    }

    pub fn create(alloc: Allocator, parent: *Hub, port_number: u7) !*HubPort {
        var hp = try alloc.create(HubPort);
        hp.* = init(parent, port_number);
        return hp;
    }

    pub fn featureSet(self: *HubPort, feature: u16) !void {
        log.debug(@src(), "hub {d} port {d} featureSet {d} (new API)", .{ self.parent.index, self.port, feature });

        try self.parent.hubControlMessage(spec.HUB_REQUEST_SET_FEATURE, spec.USB_REQUEST_TYPE_OTHER_CLASS_OUT, feature, self.port, null);
    }

    pub fn featureClear(self: *HubPort, feature: u16) !void {
        log.debug(@src(), "hub {d} port {d} featureClear {d} (new API)", .{ self.parent.index, self.port, feature });

        try self.parent.hubControlMessage(
            spec.HUB_REQUEST_CLEAR_FEATURE,
            spec.USB_REQUEST_TYPE_OTHER_CLASS_OUT,
            feature,
            self.port,
            null,
        );
    }

    pub fn statusGet(self: *HubPort) !void {
        log.debug(@src(), "hub {d} port {d} statusGet (new API)", .{ self.parent.index, self.port });

        try self.parent.hubControlMessage(
            spec.HUB_REQUEST_GET_STATUS,
            spec.USB_REQUEST_TYPE_OTHER_CLASS_IN,
            0,
            self.port,
            self.parent.transfer_buffer[0..4],
        );

        @memcpy(std.mem.asBytes(&self.status), self.parent.transfer_buffer[0..4]);
    }

    pub fn reset(self: *HubPort, delay: u32) !void {
        log.debug(@src(), "hub {d} port {d} initiate reset (new API)", .{ self.parent.index, self.port });

        try self.featureSet(usb.HUB_PORT_FEATURE_PORT_RESET);

        const deadline = time.deadlineMillis(PORT_RESET_TIMEOUT);
        while (self.status.port_status.reset == 1 and time.ticks() < deadline) {
            try schedule.sleep(delay);
            try self.statusGet();
        }

        if (time.ticks() > deadline) {
            return core.Error.ResetTimeout;
        }

        try self.featureClear(usb.HUB_PORT_FEATURE_C_PORT_RESET);

        log.debug(@src(), "hub {d} port {d} reset finished", .{ self.parent.index, self.port });
    }

    pub fn statusChanged(self: *HubPort) void {
        self.statusGet() catch return;

        log.debug(@src(), "hub {d} port {d} port status changed: status 0x{x:0>4}, change 0x{x:0>4}", .{
            self.parent.index,
            self.port,
            @as(u16, @bitCast(self.status.port_status)),
            @as(u16, @bitCast(self.status.port_change)),
        });

        const chg = self.status.port_change;

        if (chg.connected_changed != 0) {
            self.featureClear(usb.HUB_PORT_FEATURE_C_PORT_CONNECTION) catch |err| {
                log.err(@src(), "feature clear error {}", .{err});
            };
            self.connectChanged() catch |err| {
                log.err(@src(), "connect changed error {}", .{err});
            };
        }

        if (chg.enabled_changed != 0) {
            self.featureClear(usb.HUB_PORT_FEATURE_C_PORT_ENABLE) catch {};
        }

        if (chg.reset_changed != 0) {
            self.featureClear(usb.HUB_PORT_FEATURE_C_PORT_RESET) catch {};
        }

        if (chg.suspended_changed != 0) {
            self.featureClear(usb.HUB_PORT_FEATURE_C_PORT_SUSPEND) catch {};
        }

        if (chg.overcurrent_changed != 0) {
            self.featureClear(usb.HUB_PORT_FEATURE_C_PORT_OVER_CURRENT) catch {};
        }
    }

    fn connectChanged(self: *HubPort) !void {
        const connected_now: bool = (self.status.port_status.connected != 0);

        // TODO detach the old device, if any

        if (connected_now) {
            self.attachDevice() catch |err| {
                log.err(@src(), "hub {d} port {d} attach device error {any}", .{
                    self.parent.index,
                    self.port,
                    err,
                });
                return err;
            };
        }
    }

    fn attachDevice(self: *HubPort) !void {
        log.debug(@src(), "hub {d} port {d} attach device", .{ self.parent.index, self.port });

        const port_reset_delay: u32 = if (self.parent.is_roothub) ROOT_RESET_DELAY else SHORT_RESET_DELAY;

        try self.reset(port_reset_delay);

        errdefer |err| {
            log.err(@src(), "hub {d} failed to attach device, disabling port {d}: {}", .{
                self.parent.index,
                self.port,
                err,
            });
            self.featureClear(usb.HUB_PORT_FEATURE_PORT_ENABLE) catch {};
        }

        try self.statusGet();

        if (self.status.port_status.high_speed_device != 0) {
            self.speed = usb.USB_SPEED_HIGH;
        } else if (self.status.port_status.low_speed_device != 0) {
            self.speed = usb.USB_SPEED_LOW;
        } else {
            self.speed = usb.USB_SPEED_FULL;
        }

        log.debug(@src(), "hub {d} port {d} reports speed is {d}", .{ self.parent.index, self.port, self.speed });

        self.connected = true;

        // schedule enumeration for later
        try enumerate.later(self);
    }

    fn detachDevice(self: *HubPort) !void {
        // TODO buncha stuff: kill pending transfers, unbind drivers
        // for endpoints,

        usb.addressFree(self.device_address);

        self.device_desc = .{};
        self.config_desc = .{};
        self.ep0 = .{};
        self.device_address = 0;
        self.connected = false;
    }
};

pub const Hub = struct {
    in_use: bool = false,
    index: u5 = undefined,
    interrupt_in: *Endpoint = undefined,
    interrupt_interval: u8 = 1,
    is_roothub: bool = false,
    hub_address: u7 = undefined, // device address of this hub

    descriptor: usb.HubDescriptor = undefined,
    parent: ?*HubPort = null,
    port_count: u8 = 0,
    ports: []HubPort = undefined,
    speed: u8 = undefined,
    status_change_buffer: [8]u8 align(DMA) = [_]u8{0} ** 8,
    status_change_urb: usb.URB = undefined,

    transfer_buffer: [64]u8 align(DMA) = [_]u8{0} ** 64,

    pub fn init(table_index: u5) Hub {
        return .{
            .index = table_index,
        };
    }

    pub fn bind(self: *Hub, parent_port: *HubPort, int_in_iface: u8, int_in_ep: u8) !void {
        self.parent = parent_port;
        self.interrupt_in = &parent_port.interfaces[int_in_iface].alternate[0].ep[int_in_ep];
        self.interrupt_interval = self.interrupt_in.ep_desc.interval;

        log.debug(@src(), "reading hub descriptor", .{});
        try self.hubDescriptorRead();

        log.debug(@src(), "Hub Descriptor:                ", .{});
        log.debug(@src(), "bLength: 0x{x:0>2}             ", .{self.descriptor.length});
        log.debug(@src(), "bDescriptorType: 0x{x:0>2}     ", .{self.descriptor.descriptor_type});
        log.debug(@src(), "bNbrPorts: 0x{x:0>2}           ", .{self.descriptor.number_ports});
        log.debug(@src(), "wHubCharacteristics: 0x{x:0>4} ", .{@as(u16, @bitCast(self.descriptor.characteristics))});
        log.debug(@src(), "bPwrOn2PwrGood: 0x{x:0>2}      ", .{self.descriptor.power_on_to_power_good});
        log.debug(@src(), "bHubContrCurrent: 0x{x:0>2}    ", .{self.descriptor.controller_current});

        self.port_count = self.descriptor.number_ports;

        log.debug(@src(), "attaching {s}USB hub with {d} ports", .{
            if (self.descriptor.characteristics.compound == 1) "compound device " else "",
            self.port_count,
        });

        try self.initPorts();
        try self.powerOnPorts();

        log.debug(@src(), "hub {d} starting interrupt transfer", .{self.index});

        self.status_change_urb.fillInterrupt(self.parent.?, self.interrupt_in, &self.status_change_buffer, 1, 0, statusChangeCompletion);

        _ = try core.interruptTransfer(&self.status_change_urb);
    }

    fn hubDescriptorRead(self: *Hub) !void {
        try self.hubControlMessage(
            spec.HUB_REQUEST_GET_DESCRIPTOR,
            spec.USB_REQUEST_TYPE_DEVICE_CLASS_IN,
            @as(u16, usb.USB_DESCRIPTOR_TYPE_HUB) << 8 | 0,
            0,
            self.transfer_buffer[0..@sizeOf(spec.HubDescriptor)],
        );

        self.descriptor = std.mem.bytesAsValue(spec.HubDescriptor, self.transfer_buffer[0..@sizeOf(spec.HubDescriptor)]).*;
    }

    pub fn initPorts(self: *Hub) !void {
        self.ports = try allocator.alloc(HubPort, self.port_count);
        for (1..self.port_count + 1) |i| {
            self.ports[i - 1] = try HubPort.init(self, @truncate(i));
        }
    }

    const PowerOnStrategy = enum {
        unpowered,
        powered_ganged,
        powered_individual,
    };

    fn decidePowerOnStrategy(self: *Hub) PowerOnStrategy {
        if (self.descriptor.controller_current == 0) {
            return .unpowered;
        } else if (self.descriptor.characteristics.power_switching_mode == usb.HUB_POWER_SWITCHING_MODE_GANGED) {
            return .powered_ganged;
        } else {
            return .powered_individual;
        }
    }

    fn powerOnPorts(self: *Hub) !void {
        switch (self.decidePowerOnStrategy()) {
            .unpowered => {},
            .powered_individual => {
                log.debug(@src(), "powering on {d} ports", .{self.port_count});

                for (self.ports) |*port| {
                    port.featureSet(usb.HUB_PORT_FEATURE_PORT_POWER) catch return;
                }

                time.delayMillis(2 * self.descriptor.power_on_to_power_good);
            },
            .powered_ganged => {
                log.debug(@src(), "powering on all ports", .{});
                self.ports[0].featureSet(usb.HUB_PORT_FEATURE_PORT_POWER) catch |err| {
                    log.err(@src(), "hub {d} ganged ports failed to power on: {any}", .{ self.index, err });
                };
                time.delayMillis(2 * self.descriptor.power_on_to_power_good);
            },
        }
    }

    fn hubControlMessage(self: *Hub, req: u8, req_type: u8, value: u16, index: u16, data: ?[]align(DMA) u8) core.Error!void {
        if (self.is_roothub) {
            var setup: spec.SetupPacket = .{
                .request_type = req_type,
                .request = req,
                .value = value,
                .index = index,
                .data_size = if (data) |d| @truncate(d.len) else 0,
            };
            const ret = usb.rootHubControl(&setup, data);
            if (ret != .OK) {
                log.err(@src(), "hubControlMessage not OK {}", .{ret});
            }
        } else {
            const port = self.parent orelse return core.Error.InvalidData;

            var setup: *spec.SetupPacket = &port.setup;
            setup.* = .{
                .request_type = req_type,
                .request = req,
                .value = value,
                .index = index,
                .data_size = if (data) |d| @truncate(d.len) else 0,
            };

            const result = usb.controlTransfer(port, setup, data) catch |err| {
                log.err(@src(), "control transfer error {}", .{err});
                return error.TransferFailed;
            };

            if (result != setup.data_size) {
                return error.TransferFailed;
            }
        }
    }
};

fn statusChangeCompletion(urb: *usb.URB, actual_length: spec.TransferBytes) void {
    const self: *Hub = @fieldParentPtr(Hub, "status_change_urb", urb);
    log.debug(@src(), "hub {d} finished interrupt transfer, status {any}:{any} length {d}", .{ self.index, urb.status, urb.status_detail, actual_length });

    log.sliceDump(@src(), urb.transfer_buffer.?[0..actual_length]);

    hubThreadWakeup(self);
}

pub fn hubThreadWakeup(hub_with_notification: *Hub) void {
    log.debug(@src(), "hub {d} wakeup message send", .{hub_with_notification.index});
    hubs_lock.acquire();
    hubs_with_pending_status_change |= @as(u32, 1) << hub_with_notification.index;
    hubs_lock.release();
    semaphore.signal(hub_status_change_semaphore) catch |err| {
        log.err(@src(), "hub {d} status change signal error {}", .{ hub_with_notification.index, err });
    };
}

const HubAlloc = AllocationSet("hub devices", u5, MAX_HUBS);

var hubs: [MAX_HUBS]Hub = init: {
    var initial_value: [MAX_HUBS]Hub = undefined;
    for (&initial_value, 0..) |*h, idx| {
        h.* = Hub.init(@truncate(idx));
    }
    break :init initial_value;
};
var hubs_allocated: HubAlloc = .{};

const HubMailbox = mailbox.Mailbox(u32);
var hub_mailbox: HubMailbox = undefined;

var hubs_lock: synchronize.TicketLock = undefined;
var hub_thread: schedule.TID = undefined;
var allocator: Allocator = undefined;
var shutdown_signal: synchronize.OneShot = .{};
var hub_status_change_semaphore: semaphore.SID = undefined;
var hubs_with_pending_status_change: u32 = 0;

pub fn hubClassAlloc() !*Hub {
    const hub_id = try hubs_allocated.allocate();
    hubs[hub_id].in_use = true;
    return &hubs[hub_id];
}

pub fn hubClassFree(hub: *Hub) void {
    hub.in_use = false;
    hubs_allocated.free(hub.index);
}

fn hubThread(_: *anyopaque) void {
    root.hal.usb_hci.initialize() catch |err| {
        log.err(@src(), "USB host control initialization error {}", .{err});
        return;
    };
    log.debug(@src(), "started host controller", .{});

    while (!shutdown_signal.isSignalled()) {
        semaphore.wait(hub_status_change_semaphore) catch |err| {
            log.err(@src(), "hubThread semaphore wait error {}", .{err});
            return;
        };

        while (hubs_with_pending_status_change != 0) {
            var hubs_to_process: u32 = 0;
            var hub_with_status_change: u6 = 0;

            {
                hubs_lock.acquire();
                defer hubs_lock.release();

                hubs_to_process = hubs_with_pending_status_change;
                hub_with_status_change = @ctz(hubs_to_process);
                if (hub_with_status_change < 32 and hub_with_status_change < MAX_HUBS) {
                    hubs_with_pending_status_change &= ~(@as(u32, 1) << @truncate(hub_with_status_change));
                } else {
                    break;
                }
            }

            log.debug(@src(), "hubThread: in loop, remaining hubs 0x{x}, next is {d}", .{ hubs_to_process, hub_with_status_change });

            hubs_to_process &= ~(@as(u32, 1) << @truncate(hub_with_status_change));
            const hub = &hubs[hub_with_status_change];
            const urb = &hub.status_change_urb;

            if (hub.is_roothub or urb.status == .OK) {
                const status_change_bytes = (hub.port_count + 7) / 8;
                const status: []u8 = hub.status_change_buffer[0..status_change_bytes];
                log.debug(@src(), "hub {d} processing status change: 0x{x}", .{ hub.index, status[0] });

                // find which ports have changes to report
                // the request buffer has a bitmask
                var portmask: u32 = 0;
                for (status, 0..) |b, i| {
                    portmask |= @as(u32, b) << @truncate(i * 8);
                }

                // now process the ports that have changes
                var check_mask: u32 = 0;
                for (hub.ports) |*port| {
                    check_mask = @as(u32, 1) << @truncate(port.port);
                    if ((portmask & check_mask) != 0) {
                        port.statusChanged();
                    }
                }
            } else if (urb.status == .Failed and urb.status_detail == .Nak) {
                // hub doesn't have any update for us, this is normal

                // THIS IS A HACK
                // We need to wait `interval` millis before polling
                // again. At the moment we have no way to do that
                // other than making a thread go to sleep. The problem
                // is that this is the only thread handling hub
                // events. So we're gating the response latency of the
                // hub thread by the sum of the sleep intervals of any
                // hub that had an event.
                schedule.sleep(hub.interrupt_interval) catch |err| {
                    log.err(@src(), "sleep hub interrupt interval error {any}", .{err});
                };
            } else {
                log.err(@src(), "hub {d} status change request failed: {any}:{any}", .{ hub.index, urb.status, urb.status_detail });
            }

            if (!hub.is_roothub) {
                // wait the hub's "interval" before polling again
                log.debug(@src(), "hub {d} resubmitting interrupt request", .{hub.index});

                // resend the status change interrupt request
                _ = core.interruptTransfer(&hub.status_change_urb) catch |err| {
                    log.err(@src(), "hub {d} interrupt request submit error: {any}", .{ hub.index, err });
                };
            }
        }
    }
}

fn selectInterruptEndpoint(iface: *const Interface) ?u8 {
    for (0..iface.alternate[0].ep_count) |ep_num| {
        const ep_desc = &iface.alternate[0].ep[ep_num].ep_desc;

        if (ep_desc.isType(spec.USB_ENDPOINT_TYPE_INTERRUPT) and
            ep_desc.direction() == spec.USB_ENDPOINT_DIRECTION_IN)
        {
            log.debug(@src(), "selecting ep addr 0x{x:0>2}, type 0x{x}", .{ ep_desc.endpoint_address, ep_desc.getType() });
            return @truncate(ep_num);
        }
    }

    return null;
}

pub fn hubClassDriverInitialize(alloc: Allocator) !void {
    log = Logger.init("usbh", .info);

    allocator = alloc;

    hubs_lock = synchronize.TicketLock.initWithTargetLevel("usb hubs", true, .FIQ);
    hub_status_change_semaphore = try semaphore.create(0);
    hubs_with_pending_status_change = 0;

    hub_thread = try schedule.spawn(hubThread, "hub thread", &.{});
}

fn hubClassDriverBind(port: *HubPort, interface: u8) core.Error!void {
    log.debug(@src(), "hub class driver bind, hub {d} port {d} intf {d}", .{ port.parent.index, port.port, interface });

    var next_hub = try hubClassAlloc();

    const iface = &port.interfaces[interface];
    const ep_int_in = selectInterruptEndpoint(iface) orelse return core.Error.ConfigurationError;

    try next_hub.bind(port, interface, ep_int_in);
}

fn hubClassDriverUnbind(port: *HubPort, interface: u8) core.Error!void {
    log.info(@src(), "hub class driver bind, hub {d} port {d} intf {d}", .{ port.parent.index, port.port, interface });
}

pub const class_driver: class.Driver = .{
    .name = "USB Hub",
    .initialize = hubClassDriverInitialize,
    .bind = hubClassDriverBind,
    .unbind = hubClassDriverUnbind,
};
