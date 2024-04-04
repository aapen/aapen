/// Protocol definition for USB 2.0 Hub devices
///
/// See USB 2.0 specification, revision 2.0 (dated April 27, 2000),
/// chapter 11 for all the details
const std = @import("std");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.usb_hub);

const root = @import("root");
const delayMillis = root.HAL.delayMillis;

const arch = @import("../architecture.zig");
const cpu = arch.cpu;

const semaphore = @import("../semaphore.zig");
const SID = semaphore.SID;

const synchronize = @import("../synchronize.zig");
const OneShot = synchronize.OneShot;
const TicketLock = synchronize.TicketLock;

const schedule = @import("../schedule.zig");
const TID = schedule.TID;

const time = @import("../time.zig");

const descriptor = @import("descriptor.zig");
const ConfigurationDescriptor = descriptor.ConfigurationDescriptor;
const DescriptorIndex = descriptor.DescriptorIndex;
const DescriptorType = descriptor.DescriptorType;
const Header = descriptor.Header;

const device = @import("device.zig");
const Device = device.Device;
const DeviceAddress = device.DeviceAddress;
const DeviceClass = device.DeviceClass;
const DeviceDriver = device.DeviceDriver;
const StandardDeviceRequests = device.StandardDeviceRequests;
const UsbSpeed = device.UsbSpeed;

const endpoint = @import("endpoint.zig");
const EndpointNumber = endpoint.EndpointNumber;

const Error = @import("status.zig").Error;

const request = @import("request.zig");
const RequestTypeDirection = request.RequestTypeDirection;
const RequestTypeRecipient = request.RequestTypeRecipient;
const RequestTypeType = request.RequestTypeType;
const device_standard_in = request.device_standard_in;
const device_standard_out = request.device_standard_out;
const device_class_in = request.device_class_in;
const device_class_out = request.device_class_out;
const other_class_in = request.other_class_in;
const other_class_out = request.other_class_out;

const transfer = @import("transfer.zig");
const SetupPacket = transfer.SetupPacket;
const setup = transfer.setup;
const TransferRequest = transfer.TransferRequest;
const TransferType = transfer.TransferType;

const TransferFactory = @import("transfer_factory.zig");

const usb = @import("../usb.zig");

// ----------------------------------------------------------------------
// Hub definitions from USB 2.0 spec
// ----------------------------------------------------------------------

pub const HubDescriptor = extern struct {
    header: Header,
    number_ports: u8,
    characteristics: Characteristics,
    power_on_to_power_good: u8, // in 2 millisecond intervals
    controller_current: u8, // in milliamps

    // following controller_current is a variable # of bytes
    // containing a bitmap for "device removable". there is one bit
    // per number_ports, padded out to byte granularity

    // following the device removable bitmap is _another_ bitmap for
    // "port power control". it remains for compatibility but should
    // be set to all 1s.

    // we ignore both of those

    pub fn dump(self: *const HubDescriptor) void {
        log.debug("HubDescriptor [", .{});
        log.debug("  ports = {d}", .{self.number_ports});
        log.debug("  characteristics = [", .{});
        log.debug("    power_switching_mode = 0x{x}", .{self.characteristics.power_switching_mode});

        log.debug("    compound = 0x{x}", .{self.characteristics.compound});
        log.debug("    overcurrent mode = 0x{x}", .{self.characteristics.overcurrent_protection_mode});
        log.debug("    tt_think_time = 0x{x}", .{self.characteristics.tt_think_time});
        log.debug("    port indicators = 0x{x}", .{self.characteristics.port_indicators});
        log.debug("  ]", .{});
        log.debug("  power on to power good = {d} ms", .{self.power_on_to_power_good});
        log.debug("  max current = {d} mA", .{self.controller_current});
        log.debug("]", .{});
    }
};

/// See USB 2.0 specification, revision 2.0, section 11.24.2
pub const ClassRequest = struct {
    pub const get_status: u8 = 0x00;
    pub const clear_feature: u8 = 0x01;
    pub const set_feature: u8 = 0x03;
    pub const get_descriptor: u8 = 0x06;
    pub const set_descriptor: u8 = 0x07;
    pub const clear_tt_buffer: u8 = 0x08;
    pub const reset_tt: u8 = 0x09;
    pub const get_tt_state: u8 = 0x0a;
    pub const stop_tt: u8 = 0x0b;
};

pub const HubFeature = struct {
    pub const c_hub_local_power: u16 = 0;
    pub const c_hub_over_current: u16 = 1;
};

pub const PortFeature = struct {
    pub const port_connection: u16 = 0;
    pub const port_enable: u16 = 1;
    pub const port_suspend: u16 = 2;
    pub const port_over_current: u16 = 3;
    pub const port_reset: u16 = 4;
    pub const port_power: u16 = 8;
    pub const port_low_speed: u16 = 9;
    pub const port_high_speed: u16 = 10;
    pub const c_port_connection: u16 = 16;
    pub const c_port_enable: u16 = 17;
    pub const c_port_suspend: u16 = 18;
    pub const c_port_over_current: u16 = 19;
    pub const c_port_reset: u16 = 20;
    pub const port_test: u16 = 21;
    pub const port_indicator: u16 = 22;
};

/// See USB 2.0 specification, revision 2.0, section 11.23.2.1
pub const PowerSwitching = struct {
    pub const ganged: u2 = 0b00;
    pub const individual: u2 = 0b01;
};

pub const Compound = struct {
    pub const not_compound: u1 = 0b0;
    pub const compound: u1 = 0b1;
};

pub const OvercurrentProtection = struct {
    pub const global: u2 = 0b00;
    pub const individual: u2 = 0b01;
    pub const none: u2 = 0b10;
    pub const none_2: u2 = 0b11;
};

pub const TtThinkTime = struct {
    pub const tt_8: u2 = 0b00;
    pub const tt_16: u2 = 0b01;
    pub const tt_24: u2 = 0b10;
    pub const tt_32: u2 = 0b11;
};

pub const PortIndicators = struct {
    pub const not_supported: u1 = 0b0;
    pub const supported: u1 = 0b1;
};

pub const Characteristics = packed struct {
    pub const power_switching_ganged: u2 = 0b00;
    pub const power_switching_individual: u2 = 0b01;

    power_switching_mode: u2, // 0..1
    compound: u1, // 2
    overcurrent_protection_mode: u2, // 3..4
    tt_think_time: u2, // 5..6
    port_indicators: u1, // 7
    _reserved_0: u8 = 0, // 8..15
};

pub const TTDirection = struct {
    pub const out: u1 = 0;
    pub const in: u1 = 1;
};

const ClearTTBufferValue = packed struct {
    endpoint_number: EndpointNumber,
    device_address: DeviceAddress,
    endpoint_type: TransferType,
    _reserved: u2 = 0,
    direction: u1,
};

/// See USB 2.0 specification, revision 2.0, table 11-19
pub const HubStatus = packed struct {
    hub_status: packed struct {
        local_power_source: u1 = 0,
        overcurrent: u1 = 0,
        _reserved: u14 = 0,
    },
    change_status: packed struct {
        local_power_changed: u1 = 0,
        overcurrent_changed: u1 = 0,
        _reserved: u14 = 0,
    },
};

pub const PortStatus = packed struct {
    port_status: packed struct {
        connected: u1 = 0, // 0
        enabled: u1 = 0, // 1
        suspended: u1 = 0, // 2 (reserved in USB 3.x)
        overcurrent: u1 = 0, // 3
        reset: u1 = 0, // 4
        _reserved_0: u3 = 0, // 5..7 (port link state in USB 3.x)
        power: u1 = 0, // 8
        low_speed_device: u1 = 0, // 9
        high_speed_device: u1 = 0, // 10
        test_mode: u1 = 0, // 11
        indicator_control: u1 = 0, // 12
        _reserved_1: u3 = 0, // 13..15
    },

    port_change: packed struct {
        connected_changed: u1 = 0, // 0
        enabled_changed: u1 = 0, // 1 (reserved in USB 3.x)
        suspended_changed: u1 = 0, // 2 (reserved in USB 3.x)
        overcurrent_changed: u1 = 0, // 3
        reset_changed: u1 = 0, // 4
        _bh_reset_changed: u1 = 0, // 5 (only in USB 3.x)
        _port_link_state_changed: u1 = 0, // 6 (only in USB 3.x)
        _port_config_error: u1 = 0, // 7 (only in USB 3.x)
        _reserved_0: u8 = 0, // 8..15
    },

    pub fn deviceSpeed(self: *const PortStatus) UsbSpeed {
        if (self.port_status.low_speed_device == .low_speed) {
            return UsbSpeed.Low;
        } else if (self.port_status.high_speed_device == .high_speed) {
            return UsbSpeed.High;
        } else {
            // This may not be correct for USB 3
            return UsbSpeed.Full;
        }
    }
};

// some timing constants from the USB spec
const RESET_TIMEOUT = 100;
const PORT_RESET_TIMEOUT = 800;
const PORT_RESET_DELAY = 10;

// ----------------------------------------------------------------------
// Local implementation
// ----------------------------------------------------------------------
pub const MAX_HUBS = 8;

pub const Hub = struct {
    const Port = struct {
        number: u7,
        status: PortStatus,
        device_speed: UsbSpeed,
        device: ?*Device,
    };

    in_use: bool = false,
    index: u5 = undefined,
    device: *Device,
    descriptor: HubDescriptor,
    port_count: u8,
    ports: []Port,
    status_change_buffer: [1]u8,
    status_change_request: TransferRequest,

    pub fn init(self: *Hub, table_index: u5) void {
        self.* = .{
            .in_use = false,
            .index = table_index,
            .device = undefined,
            .descriptor = undefined,
            .port_count = 0,
            .ports = undefined,
            .status_change_buffer = [1]u8{0},
            .status_change_request = undefined,
        };
    }

    pub fn deviceBind(self: *Hub, dev: *Device) !void {
        // The device should already have it's device descriptor and
        // configuration descriptor populated.
        if (dev.device_descriptor.device_class != DeviceClass.hub or
            dev.configuration.configuration_descriptor.interface_count != 1 or
            dev.configuration.interfaces[0].?.endpoint_count != 1 or
            dev.configuration.endpoints[0][0].?.attributes.endpoint_type != TransferType.interrupt)
        {
            return Error.DeviceUnsupported;
        }

        self.device = dev;

        // set the device's speed according to the hub's interface
        // protocol
        self.device.speed = switch (dev.configuration.interfaces[0].?.interface_protocol) {
            0x00 => UsbSpeed.Full,
            else => UsbSpeed.High,
        };

        log.debug("deviceBind reading hub descriptor", .{});
        try self.hubDescriptorRead();

        self.descriptor.dump();

        self.port_count = self.descriptor.number_ports;

        log.debug("deviceBind attaching {s}USB hub with {d} ports", .{
            if (self.descriptor.characteristics.compound == Compound.compound) "compound device " else "",
            self.port_count,
        });

        try self.initPorts();
        try self.powerOnPorts();

        log.debug("hub {d} starting interrupt transfer", .{self.index});

        dev.driver_private = self;
        self.status_change_request = TransferFactory.initInterruptTransfer(dev, &self.status_change_buffer);
        self.status_change_request.completion = statusChangeCompletion;

        try usb.transferSubmit(&self.status_change_request);
    }

    fn hubDescriptorRead(self: *Hub) !void {
        const result = try usb.controlMessage(
            self.device,
            ClassRequest.get_descriptor,
            device_class_in,
            @as(u16, DescriptorType.hub) << 8 | 0,
            0,
            std.mem.asBytes(&self.descriptor),
        );

        if (result != .ok) {
            return Error.TransferFailed;
        }
    }

    fn initPorts(self: *Hub) !void {
        self.ports = try allocator.alloc(Port, self.port_count);
        for (1..self.port_count + 1) |i| {
            self.ports[i - 1] = .{
                .number = @truncate(i),
                .status = @bitCast(@as(u32, 0)),
                .device_speed = .High,
                .device = null,
            };
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
        } else if (self.descriptor.characteristics.power_switching_mode == Characteristics.power_switching_ganged) {
            return .powered_ganged;
        } else {
            return .powered_individual;
        }
    }

    fn powerOnPorts(self: *Hub) !void {
        switch (self.decidePowerOnStrategy()) {
            .unpowered => {},
            .powered_individual => {
                log.debug("powering on {d} ports", .{self.port_count});

                for (self.ports) |*port| {
                    self.portFeatureSet(port, PortFeature.port_power) catch |err| {
                        log.err("hub {d} failed to power on port {d}: {any}", .{ self.index, port.number, err });
                    };
                }

                delayMillis(2 * self.descriptor.power_on_to_power_good);
            },
            .powered_ganged => {
                log.debug("powering on all ports", .{});
                self.portFeatureSet(&self.ports[0], PortFeature.port_power) catch |err| {
                    log.err("hub {d} failed to power on ports: {any}", .{ self.index, err });
                };
                delayMillis(2 * self.descriptor.power_on_to_power_good);
            },
        }
    }

    fn portStatusGet(self: *Hub, port: *Port) !void {
        log.debug("hub {d} portStatusGet port {d}", .{ self.index, port.number });

        const result = try usb.controlMessage(
            self.device,
            ClassRequest.get_status,
            other_class_in,
            0,
            port.number,
            std.mem.asBytes(&port.status),
        );
        if (result != .ok) {
            return Error.TransferFailed;
        }
    }

    fn portFeatureSet(self: *Hub, port: *Port, feature: u16) !void {
        log.debug("hub {d} portFeatureSet port {d} with feature {any}", .{ self.index, port.number, feature });
        const result = try usb.controlMessage(
            self.device,
            ClassRequest.set_feature,
            other_class_out,
            feature,
            port.number,
            &.{},
        );
        if (result != .ok) {
            return Error.TransferFailed;
        }
    }

    fn portFeatureClear(self: *Hub, port: *Port, feature: u16) !void {
        log.debug("hub {d} portFeatureClear port {d} with feature {any}", .{ self.index, port.number, feature });
        const result = try usb.controlMessage(
            self.device,
            ClassRequest.clear_feature,
            other_class_out,
            feature,
            port.number,
            &.{},
        );
        if (result != .ok) {
            return Error.TransferFailed;
        }
    }

    fn portReset(self: *Hub, port: *Port) !void {
        log.debug("hub {d} portReset {d}", .{ self.index, port.number });

        try self.portFeatureSet(port, PortFeature.port_reset);

        const deadline = time.deadlineMillis(PORT_RESET_TIMEOUT);
        while (port.status.port_status.reset == 1 and
            time.ticks() < deadline)
        {
            try schedule.sleep(PORT_RESET_DELAY);
            try self.portStatusGet(port);
        }

        if (time.ticks() > deadline) {
            return Error.ResetTimeout;
        }
        try schedule.sleep(30);
        log.debug("hub {d} portReset {d} finished", .{ self.index, port.number });
    }

    fn portAttachDevice(self: *Hub, port: *Port) !void {
        try self.portReset(port);
        errdefer {
            log.err("hub {d} failed to attach device, disabling port {d}", .{ self.index, port.number });
            self.portFeatureClear(port, PortFeature.port_enable) catch {};
        }

        const new_device = try usb.allocateDevice(self.device);
        errdefer {
            log.err("hub {d} failed to configure device {d} on port {d}, freeing it", .{ self.index, new_device, port.number });
            usb.freeDevice(new_device);
        }

        const dev: *Device = &usb.devices[new_device];

        try self.portStatusGet(port);

        log.debug("hub {d} port {d} reports speed is {s}", .{
            self.index,
            port.number,
            if (port.status.port_status.high_speed_device == 1) "high" else if (port.status.port_status.low_speed_device == 1) "low" else "full",
        });

        if (port.status.port_status.high_speed_device == 1) {
            dev.speed = .High;
        } else if (port.status.port_status.low_speed_device == 1) {
            dev.speed = .Low;
        } else {
            dev.speed = .Full;
        }

        log.debug("hub {d} {s}-speed device connected to port {d}", .{ self.index, @tagName(dev.speed), port.number });

        dev.port_number = port.number;

        try usb.attachDevice(new_device, dev.speed);

        port.device = dev;
    }

    fn portDetachDevice(self: *Hub, port: *Port) !void {
        _ = port;
        // TODO
        _ = self;
    }

    fn portStatusChanged(self: *Hub, port: *Port) void {
        log.debug("hub {d} portStatusChanged: checking status for port {d}", .{ self.index, port.number });

        if (self.portStatusGet(port)) {
            log.debug("hub {d} portStatusChanged port {d} status = 0x{x:0>4}, change = 0x{x:0>4}", .{
                self.index,
                port.number,
                @as(u16, @bitCast(port.status.port_status)),
                @as(u16, @bitCast(port.status.port_change)),
            });

            if (port.status.port_change.connected_changed == 1) {
                // connection changed: either device connect or
                // disconnect
                log.debug("hub {d} port {d} device now {s}", .{
                    self.index,
                    port.number,
                    if (port.status.port_status.connected == 1) "connected" else "disconnected",
                });

                self.portFeatureClear(port, PortFeature.c_port_connection) catch |err| {
                    log.err("hub {d} attempt to clear PortFeature.c_port_connection on {d}: {any}", .{ self.index, port.number, err });
                };

                // TODO  detach the old device
                // self.portDetachDevice(port_number);

                // TODO  if the status is connected, attach the new
                // device
                if (port.status.port_status.connected == 1) {
                    self.portAttachDevice(port) catch |err| {
                        log.err("hub {d} attempt to attach device on {d}: {any}", .{ self.index, port.number, err });
                    };
                }
            }

            if (port.status.port_change.enabled_changed == 1) {
                log.debug("hub {d} portStatusChanged: port {d} has enabled_changed == 1", .{ self.index, port.number });
                self.portFeatureClear(port, PortFeature.c_port_enable) catch |err| {
                    log.err("hub {d} attempt to clear PortFeature.c_port_enable on {d}: {any}", .{ self.index, port.number, err });
                };
            }

            if (port.status.port_change.reset_changed == 1) {
                self.portFeatureClear(port, PortFeature.c_port_reset) catch |err| {
                    log.err("hub {d} attempt to clear PortFeature.c_port_reset on {d}: {any}", .{ self.index, port.number, err });
                };
            }

            if (port.status.port_change.suspended_changed == 1) {
                self.portFeatureClear(port, PortFeature.c_port_suspend) catch |err| {
                    log.err("hub {d} attempt to clear PortFeature.c_port_suspend on {d}: {any}", .{ self.index, port.number, err });
                };
            }

            if (port.status.port_change.overcurrent_changed == 1) {
                self.portFeatureClear(port, PortFeature.c_port_over_current) catch |err| {
                    log.err("hub {d} attempt to clear PortFeature.c_port_over_current on {d}: {any}", .{ self.index, port.number, err });
                };
            }
        } else |err| {
            log.err("hub {d} error getting status of port {d}: {any}", .{ self.index, port.number, err });
        }
    }

    pub fn dump(self: *const Hub) void {
        log.info("Hub [", .{});
        log.info("  port count = {d}", .{self.port_count});
        log.info("]", .{});
    }
};

fn statusChangeCompletion(req: *TransferRequest) void {
    const self: *Hub = @fieldParentPtr(Hub, "status_change_request", req);
    log.debug("hub {d} finished interrupt transfer, 0x{x}", .{ self.index, req.data[0] });
    hubs_with_pending_status_change |= @as(u32, 1) << @truncate(self.index);
    semaphore.signal(hub_status_change_semaphore) catch |err| {
        log.err("hub status change semaphore signal error: {any}", .{err});
    };
}

var hubs: [MAX_HUBS]Hub = undefined;
var hubs_lock: TicketLock = undefined;
var hub_thread: TID = undefined;
var allocator: Allocator = undefined;
var shutdown_signal: OneShot = .{};
var hub_status_change_semaphore: SID = undefined;
var hubs_with_pending_status_change: u32 = 0;

pub fn initialize(alloc: Allocator) !void {
    allocator = alloc;

    for (0..MAX_HUBS) |i| {
        hubs[i].init(@truncate(i));
    }

    hubs_lock = TicketLock.initWithTargetLevel("usb hubs", true, .FIQ);

    hubs_with_pending_status_change = 0;
    hub_status_change_semaphore = try semaphore.create(1);
    hub_thread = try schedule.spawn(hubThread, "hub thread", &.{});
}

fn hubThread(_: *anyopaque) void {
    while (!shutdown_signal.isSignalled()) {
        semaphore.wait(hub_status_change_semaphore) catch |err| {
            log.err("hub status change wait: {any}", .{err});
        };

        // loop through the hubs that have pending status changes
        log.debug("hubThread: hubs with pending status change 0x{x}", .{hubs_with_pending_status_change});

        while (hubs_with_pending_status_change != 0) {
            const hub_id: u5 = @truncate(@ctz(hubs_with_pending_status_change));
            const hub = &hubs[hub_id];
            const req = &hub.status_change_request;

            const im = cpu.disable();
            hubs_with_pending_status_change &= ~(@as(u32, 1) << hub_id);
            cpu.restore(im);

            if (req.status == .ok) {
                log.debug("hub {d} processing status change: 0x{x}", .{ hub_id, req.data[0] });

                if (req.actual_size != req.size) {
                    log.debug("hub {d} actual_size = {d}, expected = {d}", .{ hub_id, req.actual_size, req.size });
                }
                // find which ports have changes to report
                // the request buffer has a bitmask
                var portmask: u32 = 0;
                for (0..req.actual_size) |i| {
                    portmask |= @as(u32, req.data[i]) << @truncate(i * 8);
                }

                // now process the ports that have changes
                var check_mask: u32 = 1;
                for (hub.ports) |*port| {
                    check_mask = @as(u32, 1) << @truncate(port.number);
                    if ((portmask & check_mask) != 0) {
                        hub.portStatusChanged(port);
                    }
                }
            } else {
                log.err("hub {d} status change request failed: {s}", .{ hub_id, @tagName(req.status) });
            }

            // resend the status change interrupt request
            log.debug("hub {d} resubmitting status change request", .{hub_id});
            usb.transferSubmit(req) catch |err| {
                log.err("hub {d} transfer submit error: {any}", .{ hub_id, err });
            };
        }
    }
}

pub fn hubDriverCanBind(dev: *Device) bool {
    return dev.device_descriptor.device_class == DeviceClass.hub;
}

pub fn hubDriverDeviceBind(dev: *Device) Error!void {
    hubs_lock.acquire();
    defer hubs_lock.release();

    for (0..MAX_HUBS) |i| {
        if (!hubs[i].in_use) {
            var hub = &hubs[i];
            hub.in_use = true;
            errdefer hub.in_use = false;

            if (hub.deviceBind(dev)) {
                return;
            } else |e| {
                log.debug("hub {d} error binding device: {any}", .{ hub.index, e });
                return e;
            }
        }
    }
    return Error.TooManyHubs;
}

pub fn hubDriverDeviceUnbind(dev: *Device) void {
    _ = dev;
}

pub const usb_hub_driver: DeviceDriver = .{
    .name = "USB Hub",
    .canBind = hubDriverCanBind,
    .bind = hubDriverDeviceBind,
    .unbind = hubDriverDeviceUnbind,
};
