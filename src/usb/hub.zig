/// Protocol definition for USB 2.0 Hub devices
///
/// See USB 2.0 specification, revision 2.0 (dated April 27, 2000),
/// chapter 11 for all the details
const std = @import("std");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.usb);

const root = @import("root");
const delayMillis = root.HAL.delayMillis;

const synchronize = @import("../synchronize.zig");
const TicketLock = synchronize.TicketLock;

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

const transfer = @import("transfer.zig");
const SetupPacket = transfer.SetupPacket;
const setup = transfer.setup;
const Transfer = transfer.Transfer;
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
        log.debug("    power_switching_mode = {s}", .{@tagName(self.characteristics.power_switching_mode)});

        log.debug("    compound = {s}", .{@tagName(self.characteristics.compound)});
        log.debug("    overcurrent mode = {s}", .{@tagName(self.characteristics.overcurrent_protection_mode)});
        log.debug("    tt_think_time = {s}", .{@tagName(self.characteristics.tt_think_time)});
        log.debug("    port indicators = {s}", .{@tagName(self.characteristics.port_indicators)});
        log.debug("  ]", .{});
        log.debug("  power on to power good = {d} ms", .{self.power_on_to_power_good});
        log.debug("  max current = {d} mA", .{self.controller_current});
        log.debug("]", .{});
    }
};

/// See USB 2.0 specification, revision 2.0, section 11.24.2
pub const ClassRequest = enum(u8) {
    get_status = 0x00,
    clear_feature = 0x01,
    set_feature = 0x03,
    get_descriptor = 0x06,
    set_descriptor = 0x07,
    clear_tt_buffer = 0x08,
    reset_tt = 0x09,
    get_tt_state = 0x0a,
    stop_tt = 0x0b,
};

pub const HubFeature = enum(u16) {
    c_hub_local_power = 0,
    c_hub_over_current = 1,
};

pub const PortFeature = enum(u16) {
    port_connection = 0,
    port_enable = 1,
    port_suspend = 2,
    port_over_current = 3,
    port_reset = 4,
    port_power = 8,
    port_low_speed = 9,
    port_high_speed = 10,
    c_port_connection = 16,
    c_port_enable = 17,
    c_port_suspend = 18,
    c_port_over_current = 19,
    c_port_reset = 20,
    port_test = 21,
    port_indicator = 22,
};

/// See USB 2.0 specification, revision 2.0, section 11.23.2.1
pub const Characteristics = packed struct {
    power_switching_mode: enum(u2) {
        ganged = 0b00,
        individual = 0b01,
        _unused_in_usb2_0b10 = 0b10,
        _unused_in_usb2_0b11 = 0b11,
    },
    compound: enum(u1) {
        not_compound = 0b0,
        compound = 0b1,
    },
    overcurrent_protection_mode: enum(u2) {
        global = 0b00,
        individual = 0b01,
        none = 0b10,
        none2 = 0b11,
    },
    tt_think_time: enum(u2) {
        tt_8 = 0b00,
        tt_16 = 0b01,
        tt_24 = 0b10,
        tt_32 = 0b11,
    },
    port_indicators: enum(u1) {
        not_supported = 0b0,
        supported = 0b1,
    },
    _reserved_0: u8 = 0,
};

pub const TTDirection = enum(u1) {
    out = 0,
    in = 1,
};

const ClearTTBufferValue = packed struct {
    endpoint_number: EndpointNumber,
    device_address: DeviceAddress,
    endpoint_type: TransferType,
    _reserved: u2 = 0,
    direction: TTDirection,
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
        connected: u1 = 0,
        enabled: u1 = 0,
        suspended: u1 = 0,
        overcurrent: u1 = 0,
        reset: u1 = 0,
        _reserved_0: u3 = 0,
        power: u1 = 0,
        low_speed_device: u1 = 0,
        high_speed_device: u1 = 0,
        test_mode: u1 = 0,
        indicator_control: u1 = 0,
        _reserved_1: u3 = 0,
    },
    port_change: packed struct {
        connected_changed: u1 = 0,
        enabled_changed: u1 = 0,
        suspended_changed: u1 = 0,
        overcurrent_changed: u1 = 0,
        reset_changed: u1 = 0,
        _reserved: u11 = 0,
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

// ----------------------------------------------------------------------
// Local implementation
// ----------------------------------------------------------------------
pub const MAX_HUBS = 8;

pub const Hub = struct {
    const reset_timeout = 100;

    const Port = struct {
        number: u8,
        status: PortStatus,
        device_speed: UsbSpeed,
        device: *Device,
    };

    in_use: bool = false,
    device: *Device,
    descriptor: HubDescriptor,
    port_count: u8,
    ports: []Port,
    status_change_buffer: [1]u8,
    status_change_request: Transfer,

    pub fn init(self: *Hub) void {
        self.* = .{
            .in_use = false,
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
        if (dev.device_descriptor.device_class != @intFromEnum(DeviceClass.hub) or
            dev.configuration.configuration_descriptor.interface_count != 1 or
            dev.configuration.interfaces[0].?.endpoint_count != 1 or
            dev.configuration.endpoints[0][0].?.attributes.transfer_type != .interrupt)
        {
            return Error.DeviceUnsupported;
        }

        self.device = dev;

        log.debug("reading hub descriptor", .{});
        try self.hubDescriptorRead();

        self.descriptor.dump();

        self.port_count = self.descriptor.number_ports;

        log.debug("attaching {s}USB hub with {d} ports", .{
            if (self.descriptor.characteristics.compound == .compound) "compound device " else "",
            self.port_count,
        });

        try self.initPorts();
        try self.powerOnPorts();

        dev.driver_private = self;
        self.status_change_request = TransferFactory.initInterruptTransfer(&self.status_change_buffer);
        self.status_change_request.addressTo(dev);
        self.status_change_request.completion = handleStatusChange;

        try usb.transferSubmit(&self.status_change_request);
    }

    fn hubDescriptorRead(self: *Hub) !void {
        var xfer = TransferFactory.initGetHubDescriptorTransfer(0, std.mem.asBytes(&self.descriptor));
        xfer.addressTo(self.device);

        try usb.transferSubmit(&xfer);
        try usb.transferAwait(&xfer, 100);
    }

    fn initPorts(self: *Hub) !void {
        self.ports = try allocator.alloc(Port, self.port_count);
        for (0..self.port_count) |i| {
            self.ports[i].number = @truncate(i + 1);
        }
    }

    fn powerOnPorts(self: *Hub) !void {
        log.debug("powering on {d} ports", .{self.port_count});

        for (0..self.port_count) |i| {
            self.portFeatureSet(@truncate(i), .port_power) catch |err| {
                log.err("failed to power on port {d}: {any}", .{ i, err });
            };
        }

        delayMillis(2 * self.descriptor.power_on_to_power_good);
    }

    fn portStatusGet(self: *Hub, port_number: u8) !void {
        log.debug("portStatusGet for {d}", .{port_number});
        var xfer = TransferFactory.initHubGetPortStatusTransfer(port_number, std.mem.asBytes(&self.ports[port_number].status));
        xfer.addressTo(self.device);
        try usb.transferSubmit(&xfer);
        try usb.transferAwait(&xfer, 100);
    }

    fn portFeatureSet(self: *Hub, port_number: u8, feature: PortFeature) !void {
        log.debug("setPortFeature {d} with feature {any}", .{ port_number, feature });
        var xfer = TransferFactory.initHubSetPortFeatureTransfer(feature, port_number, 0);
        xfer.addressTo(self.device);
        try usb.transferSubmit(&xfer);
        try usb.transferAwait(&xfer, 100);
    }

    fn portFeatureClear(self: *Hub, port_number: u8, feature: PortFeature) !void {
        log.debug("portFeatureClear {d} with feature {any}", .{ port_number, feature });
        var xfer = TransferFactory.initHubClearPortFeatureTransfer(feature, port_number);
        xfer.addressTo(self.device);
        try usb.transferSubmit(&xfer);
        try usb.transferAwait(&xfer, 100);
    }

    fn portStatusChanged(self: *Hub, port_number: u8) void {
        if (self.portStatusGet(port_number)) {
            log.debug("port {d} status = 0x{x:0>4}, change = 0x{x:0>4}", .{
                port_number,
                @as(u16, @bitCast(self.ports[port_number].status.port_status)),
                @as(u16, @bitCast(self.ports[port_number].status.port_change)),
            });

            if (self.ports[port_number].status.port_change.connected_changed == 1) {
                // connection changed: either device connect or
                // disconnect
                log.debug("port {d} device now {s}", .{
                    port_number,
                    if (self.ports[port_number].status.port_status.connected == 1) "connected" else "disconnected",
                });

                self.portFeatureClear(port_number, .c_port_connection) catch |err| {
                    log.err("attempt to clear .c_port_connection on {d}: {any}", .{ port_number, err });
                };

                // TODO  detach the old device
                // TODO  if the status is connected, attach the new device
            }

            if (self.ports[port_number].status.port_change.enabled_changed == 1) {
                self.portFeatureClear(port_number, .c_port_enable) catch |err| {
                    log.err("attempt to clear .c_port_enable on {d}: {any}", .{ port_number, err });
                };
            }

            if (self.ports[port_number].status.port_change.reset_changed == 1) {
                self.portFeatureClear(port_number, .c_port_reset) catch |err| {
                    log.err("attempt to clear .c_port_reset on {d}: {any}", .{ port_number, err });
                };
            }

            if (self.ports[port_number].status.port_change.suspended_changed == 1) {
                self.portFeatureClear(port_number, .c_port_suspend) catch |err| {
                    log.err("attempt to clear .c_port_suspend on {d}: {any}", .{ port_number, err });
                };
            }

            if (self.ports[port_number].status.port_change.overcurrent_changed == 1) {
                self.portFeatureClear(port_number, .c_port_over_current) catch |err| {
                    log.err("attempt to clear .c_port_over_current on {d}: {any}", .{ port_number, err });
                };
            }
        } else |err| {
            log.err("error getting status of port {d}: {any}", .{ port_number, err });
        }
    }

    pub fn dump(self: *const Hub) void {
        log.info("Hub [", .{});
        log.info("  port count = {d}", .{self.port_count});
        log.info("]", .{});
    }
};

fn handleStatusChange(xfer: *Transfer) void {
    var self: *Hub = @fieldParentPtr(Hub, "status_change_request", xfer);

    if (xfer.status == .ok) {
        var portmask: u32 = 0;
        for (self.status_change_buffer) |b| {
            portmask = (portmask << 8) | b;
        }

        log.debug("handleStatusChange, portmask 0b{b:0>8}", .{portmask});

        for (0..self.port_count) |i| {
            const port_number: u5 = @truncate(i);
            if ((portmask & (@as(u32, 2) << port_number)) != 0) {
                self.portStatusChanged(port_number);
            }
        }
    } else {
        log.err("status change request failed: {any}", .{xfer.status});
    }
}

var hubs: [MAX_HUBS]Hub = undefined;
var hubs_lock: TicketLock = undefined;

var allocator: Allocator = undefined;

pub fn initialize(alloc: Allocator) void {
    allocator = alloc;

    for (0..MAX_HUBS) |i| {
        hubs[i].init();
    }

    hubs_lock = TicketLock.initWithTargetLevel("usb hubs", true, .FIQ);
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
                log.debug("error binding device: {any}", .{e});
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
    .bind = hubDriverDeviceBind,
    .unbind = hubDriverDeviceUnbind,
};
