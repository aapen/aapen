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

const ChannelSet = @import("../channel_set.zig");
const mailbox = @import("../mailbox.zig");

const semaphore = @import("../semaphore.zig");
const SID = semaphore.SID;
const NO_SEM = semaphore.NO_SEM;

const Logger = @import("../logger.zig");
var log: *Logger = undefined;

const synchronize = @import("../synchronize.zig");
const OneShot = synchronize.OneShot;
const TicketLock = synchronize.TicketLock;

const schedule = @import("../schedule.zig");
const TID = schedule.TID;

const time = @import("../time.zig");
const delayMillis = time.delayMillis;

const device = @import("device.zig");
const Device = device.Device;
const DeviceAddress = device.DeviceAddress;
const DeviceDriver = device.DeviceDriver;
const TransactionTranslator = device.TransactionTranslator;
const UsbSpeed = device.UsbSpeed;

const enumerate = @import("enumerate.zig");

const Error = @import("status.zig").Error;

const spec = @import("spec.zig");

const transfer = @import("transfer.zig");
const SetupPacket = transfer.SetupPacket;
const TransferRequest = transfer.TransferRequest;
const TransferType = transfer.TransferType;

const usb = @import("../usb.zig");

pub fn deviceSpeed(self: *const usb.HubPortStatus) UsbSpeed {
    if (self.port_status.low_speed_device == .low_speed) {
        return UsbSpeed.Low;
    } else if (self.port_status.high_speed_device == .high_speed) {
        return UsbSpeed.High;
    } else {
        // This may not be correct for USB 3
        return UsbSpeed.Full;
    }
}

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
    ep: [MAX_ENDPOINTS]Endpoint,
};

pub const Interface = struct {
    class_driver: *usb.DeviceDriver = undefined,
    device_name: []u8 = undefined,
    alternate: [MAX_INTERFACE_ALTERNATES]InterfaceAlternate = undefined,
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
    setup: SetupPacket align(DMA),
    ep0: spec.EndpointDescriptor,
    ep0_urb: usb.URB,
    mutex: SID,

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

        try self.parent.hubControlMessage(spec.HUB_REQUEST_CLEAR_FEATURE, spec.USB_REQUEST_TYPE_OTHER_CLASS_OUT, feature, self.port, null);
    }

    pub fn statusGet(self: *HubPort) !void {
        log.debug(@src(), "hub {d} port {d} statusGet (new API)", .{ self.parent.index, self.port });

        try self.parent.hubControlMessage(spec.HUB_REQUEST_GET_STATUS, spec.USB_REQUEST_TYPE_OTHER_CLASS_IN, 0, self.port, self.parent.transfer_buffer[0..4]);

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
            return Error.ResetTimeout;
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
            self.featureClear(usb.HUB_PORT_FEATURE_C_PORT_CONNECTION) catch {};
            self.connectChanged() catch {};
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
    pub const Port = struct {
        number: u7,
        status: usb.HubPortStatus,
        device_speed: UsbSpeed,
        device: ?*Device,
    };

    in_use: bool = false,
    index: u5 = undefined,
    is_roothub: bool = false,
    hub_address: u7 = undefined, // device address of this hub
    device: *Device = undefined,
    descriptor: usb.HubDescriptor = undefined,
    parent: ?*HubPort = null,
    port_count: u8 = 0,
    ports: []Port = undefined,
    ports2: []HubPort = undefined,
    speed: u8 = undefined,
    status_change_buffer: [8]u8 = [_]u8{0} ** 8,
    status_change_request: TransferRequest = undefined,
    tt: TransactionTranslator = .{ .hub = null, .think_time = 0 },

    error_count: u64 = 0,

    transfer_buffer: [64]u8 align(DMA) = [_]u8{0} ** 64,

    pub fn init(table_index: u5) Hub {
        return .{
            .index = table_index,
        };
    }

    pub fn driverBind(self: *Hub, ep: *spec.EndpointDescriptor, parent_port: *HubPort) !void {
        _ = ep;
        _ = parent_port;
        _ = self;
    }

    pub fn deviceBind(self: *Hub, dev: *Device) !void {
        // The device should already have it's device descriptor and
        // configuration descriptor populated.
        if (dev.device_descriptor.device_class != usb.USB_DEVICE_HUB or
            dev.configuration.configuration_descriptor.interface_count != 1 or
            dev.configuration.interfaces[0].?.endpoint_count != 1 or
            !dev.configuration.endpoints[0][0].?.isType(TransferType.interrupt))
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

        log.debug(@src(), "deviceBind reading hub descriptor", .{});
        try self.hubDescriptorRead();

        log.debug(@src(), "{any}", .{self.descriptor});

        self.port_count = self.descriptor.number_ports;

        log.debug(@src(), "deviceBind attaching {s}USB hub with {d} ports", .{
            if (self.descriptor.characteristics.compound == 1) "compound device " else "",
            self.port_count,
        });

        switch (dev.device_descriptor.device_protocol) {
            usb.USB_HUB_PROTOCOL_FULL_SPEED => {},
            usb.USB_HUB_PROTOCOL_HIGH_SPEED_SINGLE_TT,
            usb.USB_HUB_PROTOCOL_HIGH_SPEED_MULTIPLE_TT,
            => self.tt = .{ .hub = self.device },
            else => {},
        }

        const full_speed_bit_time = 666;
        self.tt.think_time = switch (self.descriptor.characteristics.tt_think_time) {
            usb.USB_HUB_TT_THINK_TIME_8 => full_speed_bit_time,
            usb.USB_HUB_TT_THINK_TIME_16 => full_speed_bit_time * 2,
            usb.USB_HUB_TT_THINK_TIME_24 => full_speed_bit_time * 3,
            usb.USB_HUB_TT_THINK_TIME_32 => full_speed_bit_time * 4,
        };

        try self.initPorts();
        try self.initPorts2();
        try self.powerOnPorts();

        log.debug(@src(), "hub {d} starting interrupt transfer", .{self.index});

        dev.driver_private = self;
        self.status_change_request = TransferRequest.initInterrupt(dev, &self.status_change_buffer);
        self.status_change_request.completion = statusChangeCompletion;

        try usb.transferSubmit(&self.status_change_request);
    }

    fn hubDescriptorRead(self: *Hub) !void {
        try self.hubControlMessage(
            spec.HUB_REQUEST_GET_DESCRIPTOR,
            spec.USB_REQUEST_TYPE_DEVICE_CLASS_IN,
            @as(u16, usb.USB_DESCRIPTOR_TYPE_HUB) << 8 | 0,
            0,
            self.transfer_buffer[0..@sizeOf(spec.HubDescriptor)],
        );

        @memcpy(std.mem.asBytes(&self.descriptor), self.transfer_buffer[0..@sizeOf(spec.HubDescriptor)]);
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

    pub fn initPorts2(self: *Hub) !void {
        self.ports2 = try allocator.alloc(HubPort, self.port_count);
        for (1..self.port_count + 1) |i| {
            self.ports2[i - 1] = try HubPort.init(self, @truncate(i));
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
                    self.portFeatureSet(port, usb.HUB_PORT_FEATURE_PORT_POWER) catch return;
                }

                delayMillis(2 * self.descriptor.power_on_to_power_good);
            },
            .powered_ganged => {
                log.debug(@src(), "powering on all ports", .{});
                self.portFeatureSet(&self.ports[0], usb.HUB_PORT_FEATURE_PORT_POWER) catch |err| {
                    log.err(@src(), "hub {d} ganged ports failed to power on: {any}", .{ self.index, err });
                };
                delayMillis(2 * self.descriptor.power_on_to_power_good);
            },
        }
    }

    fn powerOnPorts2(self: *Hub) !void {
        switch (self.decidePowerOnStrategy()) {
            .unpowered => {},
            .powered_individual => {
                log.debug(@src(), "powering on {d} ports", .{self.port_count});

                for (self.ports2) |*port| {
                    port.featureSet(usb.HUB_PORT_FEATURE_PORT_POWER) catch return;
                }

                delayMillis(2 * self.descriptor.power_on_to_power_good);
            },
            .powered_ganged => {
                log.debug(@src(), "powering on all ports", .{});
                self.ports2[0].featureSet(usb.HUB_PORT_FEATURE_PORT_POWER) catch |err| {
                    log.err(@src(), "hub {d} ganged ports failed to power on: {any}", .{ self.index, err });
                };
                delayMillis(2 * self.descriptor.power_on_to_power_good);
            },
        }
    }

    fn hubControlMessage(self: *Hub, req: u8, req_type: u8, value: u16, index: u16, data: ?[]align(DMA) u8) !void {
        if (self.is_roothub) {
            var setup: transfer.SetupPacket = .{
                .request_type = req_type,
                .request = req,
                .value = value,
                .index = index,
                .data_size = if (data) |d| @truncate(d.len) else 0,
            };
            _ = usb.rootHubControl(&setup, data);
        } else {
            const port = self.parent orelse return Error.InvalidData;

            var setup: *transfer.SetupPacket = &port.setup;
            setup.* = .{
                .request_type = req_type,
                .request = req,
                .value = value,
                .index = index,
                .data_size = if (data) |d| @truncate(d.len) else 0,
            };

            const result = usb.controlTransfer(port, setup, data) catch {
                return error.TransferFailed;
            };

            if (result != setup.data_size) {
                return error.TransferFailed;
            }
        }
    }

    fn portStatusGet(self: *Hub, port: *Port) !void {
        log.debug(@src(), "hub {d} port {d} statusGet", .{ self.index, port.number });

        self.hubControlMessage(
            spec.HUB_REQUEST_GET_STATUS,
            spec.USB_REQUEST_TYPE_OTHER_CLASS_IN,
            0,
            port.number,
            std.mem.asBytes(&port.status),
        ) catch |err| {
            log.err(@src(), "hub {d} port {d} statusGet error: {any}", .{ self.index, port.number, err });
            return err;
        };
    }

    fn portFeatureSet(self: *Hub, port: *Port, feature: u16) !void {
        log.debug(@src(), "hub {d} port {d} featureSet {d}", .{ self.index, port.number, feature });

        self.hubControlMessage(
            spec.HUB_REQUEST_SET_FEATURE,
            spec.USB_REQUEST_TYPE_OTHER_CLASS_OUT,
            feature,
            port.number,
            &.{},
        ) catch |err| {
            log.err(@src(), "hub {d} port {d} featureSet error: {any}", .{ self.index, port.number, err });
            return err;
        };
    }

    fn portFeatureClear(self: *Hub, port: *Port, feature: u16) !void {
        log.debug(@src(), "hub {d} port {d} featureClear {d}", .{ self.index, port.number, feature });

        self.hubControlMessage(
            spec.HUB_REQUEST_CLEAR_FEATURE,
            spec.USB_REQUEST_TYPE_OTHER_CLASS_OUT,
            feature,
            port.number,
            &.{},
        ) catch |err| {
            log.err(@src(), "hub {d} port {d} featureClear error: {any}", .{ self.index, port.number, err });
            return err;
        };
    }

    pub fn portReset(self: *Hub, port: *Port, delay: u32) !void {
        log.debug(@src(), "hub {d} port {d} initiate reset", .{ self.index, port.number });

        self.portFeatureSet(port, usb.HUB_PORT_FEATURE_PORT_RESET) catch return;

        const deadline = time.deadlineMillis(PORT_RESET_TIMEOUT);
        while (port.status.port_status.reset == 1 and time.ticks() < deadline) {
            try schedule.sleep(delay);
            try self.portStatusGet(port);
        }

        if (time.ticks() > deadline) {
            return Error.ResetTimeout;
        }
        try schedule.sleep(30);

        log.debug(@src(), "hub {d} port {d} reset finished", .{ self.index, port.number });
    }

    fn portAttachDevice(self: *Hub, port: *Port, portstatus: usb.HubPortStatus) !void {
        const port_reset_delay: u32 = if (self.device.isRootHub()) ROOT_RESET_DELAY else SHORT_RESET_DELAY;

        try self.portReset(port, port_reset_delay);
        errdefer {
            log.err(@src(), "hub {d} failed to attach device, disabling port {d}", .{ self.index, port.number });
            self.portFeatureClear(port, usb.HUB_PORT_FEATURE_PORT_ENABLE) catch {};
        }

        const new_device = try usb.deviceAlloc(self.device);
        errdefer {
            log.err(@src(), "hub {d} failed to configure device {d} on port {d}, freeing it", .{ self.index, new_device, port.number });
            usb.deviceFree(new_device);
        }

        const dev: *Device = &usb.devices[new_device];

        try self.portStatusGet(port);
        log.debug(@src(), "hub {d} port {d} reports speed is {s}", .{
            self.index,
            port.number,
            if (portstatus.port_status.high_speed_device == 1) "high" else if (port.status.port_status.low_speed_device == 1) "low" else "full",
        });

        if (portstatus.port_status.high_speed_device == 1) {
            dev.speed = .High;
        } else if (portstatus.port_status.low_speed_device == 1) {
            dev.speed = .Low;
        } else {
            dev.speed = .Full;
        }

        log.debug(@src(), "hub {d} {s}-speed device connected to port {d}", .{ self.index, @tagName(dev.speed), port.number });

        try usb.attachDevice(new_device, dev.speed, self, port);

        port.device = dev;
    }

    fn portDetachDevice(self: *Hub, port: *Port, dev: *Device) !void {
        _ = dev;
        _ = self;
        _ = port;
        // TODO
    }

    fn portConnectChange(self: *Hub, port: *Port, portstatus: usb.HubPortStatus) !void {
        const connected: bool = (portstatus.port_status.connected == 1);

        // TODO  detach the old device
        if (port.device) |old_dev| {
            self.portDetachDevice(port, old_dev) catch |err| {
                log.err(@src(), "hub {d} port {d} detach device error {any}", .{
                    self.index,
                    port.number,
                    err,
                });
                return err;
            };
        }

        // attach the new device
        if (connected) {
            self.portAttachDevice(port, portstatus) catch |err| {
                log.err(@src(), "hub {d} port {d} attach device error {any}", .{
                    self.index,
                    port.number,
                    err,
                });
                return err;
            };
        }
    }

    fn portStatusChanged(self: *Hub, port: *Port) void {
        self.portStatusGet(port) catch return;

        log.debug(@src(), "hub {d} portStatusChanged port {d} status = 0x{x:0>4}, change = 0x{x:0>4}", .{
            self.index,
            port.number,
            @as(u16, @bitCast(port.status.port_status)),
            @as(u16, @bitCast(port.status.port_change)),
        });

        if (port.status.port_change.connected_changed == 1) {
            self.portFeatureClear(port, usb.HUB_PORT_FEATURE_C_PORT_CONNECTION) catch {};
            self.portConnectChange(port, port.status) catch {};
        }

        if (port.status.port_change.enabled_changed == 1) {
            self.portFeatureClear(port, usb.HUB_PORT_FEATURE_C_PORT_ENABLE) catch {};
        }

        if (port.status.port_change.reset_changed == 1) {
            self.portFeatureClear(port, usb.HUB_PORT_FEATURE_C_PORT_RESET) catch {};
        }

        if (port.status.port_change.suspended_changed == 1) {
            self.portFeatureClear(port, usb.HUB_PORT_FEATURE_C_PORT_SUSPEND) catch {};
        }

        if (port.status.port_change.overcurrent_changed == 1) {
            self.portFeatureClear(port, usb.HUB_PORT_FEATURE_C_PORT_OVER_CURRENT) catch {};
        }
    }
};

fn statusChangeCompletion(req: *TransferRequest) void {
    const self: *Hub = @fieldParentPtr(Hub, "status_change_request", req);
    log.debug(@src(), "hub {d} finished interrupt transfer, {any}", .{ self.index, req.status });
    hubThreadWakeup(self);
}

pub fn hubThreadWakeup(hub_with_notification: *Hub) void {
    hub_mailbox.send(hub_with_notification.index) catch |err| {
        log.err(@src(), "hub mailbox send error {}", .{err});
    };
}

const HubAlloc = ChannelSet.init("hub devices", u5, MAX_HUBS);

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

var hubs_lock: TicketLock = undefined;
var hub_thread: TID = undefined;
var allocator: Allocator = undefined;
var shutdown_signal: OneShot = .{};
var hub_status_change_semaphore: SID = undefined;
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

pub fn initialize(alloc: Allocator) !void {
    log = Logger.init("usbh", .debug);

    allocator = alloc;

    hubs_lock = TicketLock.initWithTargetLevel("usb hubs", true, .FIQ);

    try hub_mailbox.init(allocator, MAX_HUBS);

    // hubs_with_pending_status_change = 0;
    // hub_status_change_semaphore = try semaphore.create(1);
    hub_thread = try schedule.spawn(hubThread, "hub thread", &.{});
}

fn hubThread(_: *anyopaque) void {
    root.hal.usb_hci.initialize() catch |err| {
        log.err(@src(), "USB host control initialization error {}", .{err});
        return;
    };
    log.debug(@src(), "started host controller", .{});

    while (!shutdown_signal.isSignalled()) {
        const hub_with_status_change = hub_mailbox.receive() catch |err| {
            log.err(@src(), "hubThread: hub mailbox receive error {}", .{err});
            break;
        };
        log.debug(@src(), "hubThread: hub with pending status change 0x{x}", .{hub_with_status_change});

        const hub = &hubs[hub_with_status_change];

        const req = &hub.status_change_request;

        if (hub.is_roothub or req.status == .ok) {
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
            for (hub.ports2) |*port| {
                check_mask = @as(u32, 1) << @truncate(port.port);
                if ((portmask & check_mask) != 0) {
                    port.statusChanged();
                }
            }
        } else {
            log.err(@src(), "hub {d} status change request failed: {s}", .{ hub.index, @tagName(req.status) });
        }

        if (!hub.is_roothub) {
            // resend the status change interrupt request
            log.debug(@src(), "hub {d} resubmitting status change request", .{hub.index});
            usb.transferSubmit(req) catch |err| {
                log.err(@src(), "hub {d} transfer submit error: {any}", .{ hub.index, err });
            };
        }
    }
}

pub fn hubDriverCanBind(dev: *Device) bool {
    return dev.device_descriptor.device_class == usb.USB_DEVICE_HUB;
}

pub fn hubDriverDeviceBind(dev: *Device) Error!void {
    hubs_lock.acquire();
    defer hubs_lock.release();

    var next_hub = hubClassAlloc() catch {
        log.err(@src(), "too many hubs attached", .{});
        return error.TooManyHubs;
    };
    errdefer hubClassFree(next_hub);

    try next_hub.deviceBind(dev);
}

pub fn hubDriverDeviceUnbind(dev: *Device) void {
    hubs_lock.acquire();
    defer hubs_lock.release();

    for (&hubs) |*h| {
        if (h.device == dev) {
            hubClassFree(h);
            return;
        }
    }
}

pub const driver: DeviceDriver = .{
    .name = "USB Hub",
    .initialize = initialize,
    .canBind = hubDriverCanBind,
    .bind = hubDriverDeviceBind,
    .unbind = hubDriverDeviceUnbind,
};
