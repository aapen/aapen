/// Protocol definition for USB 2.0 Hub devices
///
/// See USB 2.0 specification, revision 2.0 (dated April 27, 2000),
/// chapter 11 for all the details
const std = @import("std");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.usb);

const synchronize = @import("../synchronize.zig");
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
    get_status = 0,
    clear_feature = 1,
    set_feature = 3,
    get_descriptor = 6,
    set_descriptor = 7,
    clear_tt_buffer = 8,
    reset_tt = 9,
    get_tt_state = 10,
    stop_tt = 11,
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

pub const ChangeStatusP = enum(u1) {
    not_changed = 0b0,
    changed = 0b1,
};

pub const OvercurrentStatusP = enum(u1) {
    not_detected = 0b0,
    detected = 0b1,
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
        local_power_source: enum(u1) {
            local_power_good = 0b0,
            local_power_lost = 0b1,
        },
        overcurrent: OvercurrentStatusP,
        _reserved: u14 = 0,
    },
    change_status: packed struct {
        local_power_changed: ChangeStatusP,
        overcurrent_changed: ChangeStatusP,
        _reserved: u14 = 0,
    },
};

pub const PortStatus = packed struct {
    port_status: packed struct {
        connected: enum(u1) {
            not_connected = 0b0,
            connected = 0b1,
        } = .not_connected,
        enabled: enum(u1) {
            disabled = 0b0,
            enabled = 0b1,
        } = .disabled,
        suspended: enum(u1) {
            not_suspended = 0b0,
            suspended = 0b1,
        } = .not_suspended,
        overcurrent: OvercurrentStatusP = .not_detected,
        reset: enum(u1) {
            not_asserted = 0b0,
            asserted = 0b1,
        } = .not_asserted,
        _reserved_0: u3 = 0,
        power: enum(u1) {
            off = 0b0,
            on = 0b1,
        } = .off,
        low_speed_device: enum(u1) {
            not_low_speed = 0b0,
            low_speed = 0b1,
        } = .not_low_speed,
        high_speed_device: enum(u1) {
            not_high_speed = 0b0,
            high_speed = 0b1,
        } = .not_high_speed,
        test_mode: enum(u1) {
            disabled = 0b0,
            enabled = 0b1,
        } = .disabled,
        indicator_control: enum(u1) {
            default_colors = 0b0,
            controllable_colors = 0b1,
        } = .default_colors,
        _reserved_1: u3 = 0,
    } = .{},
    port_change: packed struct {
        connected_changed: ChangeStatusP = .not_changed,
        enabled_changed: ChangeStatusP = .not_changed,
        suspended_changed: ChangeStatusP = .not_changed,
        overcurrent_changed: ChangeStatusP = .not_changed,
        reset_changed: ChangeStatusP = .not_changed,
        _reserved: u11 = 0,
    },

    pub fn isConnected(self: *const PortStatus) bool {
        return self.port_status.connected == .connected;
    }

    pub fn isEnabled(self: *const PortStatus) bool {
        return self.port_status.enabled == .enabled;
    }

    pub fn isSuspended(self: *const PortStatus) bool {
        return self.port_status.suspended == .suspended;
    }

    pub fn isOvercurrent(self: *const PortStatus) bool {
        return self.port_status.overcurrent == .detected;
    }

    pub fn isReset(self: *const PortStatus) bool {
        return self.port_status.reset == .asserted;
    }

    pub fn isPowered(self: *const PortStatus) bool {
        return self.port_status.power == .on;
    }

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
        connected: bool,
        enabled: bool,
        suspended: bool,
        overcurrent: bool,
        reset: bool,
        powered: bool,
        device_speed: UsbSpeed,
        device: *Device,
    };

    in_use: bool = false,
    //    host: *HCI,
    device: *Device,
    descriptor: HubDescriptor,
    port_count: u8,
    port: []Port,

    pub fn init(self: *Hub) !void {
        self.* = .{
            .in_use = false,
            .host = undefined,
            .device = undefined,
            .descriptor = undefined,
            .port_count = 0,
            .port = undefined,
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
        try self.hubReadHubDescriptor();

        self.descriptor.dump();
    }

    fn hubReadHubDescriptor(self: *Hub) !void {
        var xfer = TransferFactory.initHubDescriptorTransfer(0, std.mem.asBytes(&self.descriptor));
        xfer.addressTo(self.device);

        try usb.transferSubmit(&xfer);
        try usb.transferAwait(&xfer, 100);
    }

    // pub fn initialize(self: *Hub, allocator: Allocator) !void {
    //     self.allocator = allocator;

    //     // get hub descriptor

    //     var desc = TransferFactory.initHubDescriptorTransfer(0, std.mem.asBytes(&self.descriptor));

    //     try self.host.perform(&desc);

    //     if (self.descriptor.header.descriptor_type != .hub) {
    //         return Error.InvalidResponse;
    //     }

    //     self.descriptor.dump();

    //     self.port_count = self.descriptor.number_ports;
    //     self.port = try self.allocator.alloc(Port, self.port_count);

    //     // for (0..self.port_count) |i| {
    //     //     const port_number: u8 = @truncate(i + 1);
    //     //     log.debug("Port status check {d}", .{port_number});
    //     //     try self.checkPort(port_number);

    //     //     if (self.port[i].connected) {
    //     //         try self.initializePortDevice(port_number);
    //     //     }
    //     // }

    //     self.dump();
    // }

    pub fn checkPort(self: *Hub, port_number: u8) !void {
        // ports are numbered from 1, arrays count from 0
        const i = port_number - 1;
        const status = try self.getPortStatus(port_number);
        self.port[i].connected = status.isConnected();
        self.port[i].enabled = status.isEnabled();
        self.port[i].suspended = status.isSuspended();
        self.port[i].overcurrent = status.isOvercurrent();
        self.port[i].reset = status.isReset();
        self.port[i].powered = status.isPowered();
        self.port[i].device_speed = status.deviceSpeed();

        log.debug("Port {d} status 0x{x:0>16}, change 0x{x:0>16}", .{ port_number, @as(u16, @bitCast(status.port_status)), @as(u16, @bitCast(status.port_change)) });
    }

    fn getPortStatus(self: *Hub, port_number: u8) !PortStatus {
        const buffer_size = 4;
        var buffer: [buffer_size]u8 = undefined;
        var xfer = TransferFactory.initHubGetPortStatusTransfer(port_number, buffer);
        try self.host.perform(&xfer);

        return std.mem.bytesAsValue(PortStatus, buffer);
    }

    fn initializePortDevice(self: *Hub, port_number: u8) !void {
        const i = port_number - 1;
        var port_device = try Device.init(self.allocator);

        // Reset the device, so it will appear with address 0
        try self.resetPort(port_number);

        // Initialize the device, this will assign it an address
        try port_device.initialize(self.host, self.port[i].device_speed);
        self.port[i].device = port_device;
    }

    fn resetPort(self: *Hub, port_number: u8) !void {
        // set port feature PORT_RESET
        try self.setPortFeature(port_number, .port_reset);

        // it will be turned off by the hub
        // poll port feature until PORT_RESET is observed as 0
        const expected_change: PortStatus = .{ .port_change = .{ .reset_changed = .changed } };
        return self.waitForPortStatus(port_number, expected_change, Hub.reset_timeout);
    }

    fn setPortFeature(self: *Hub, port_number: u8, feature: PortFeature) !void {
        var xfer = TransferFactory.initHubSetPortFeatureTransfer(feature, port_number, 0);
        try self.host.perform(&xfer);

        log.debug("setPortFeature {d} with feature {any}", .{ port_number, feature });
    }

    fn waitForPortStatus(self: *Hub, port_number: u8, expected: PortStatus, timeout: u16) !void {
        const expected_bits: u32 = @as(u32, @bitCast(expected));
        const deadline = time.deadlineMillis(timeout);
        while (time.ticks() < deadline) {
            const status = try self.getPortStatus(port_number);
            const actual_bits: u32 = @as(u32, @bitCast(status));
            if (expected_bits & actual_bits != 0) {
                return;
            }
        }
        return Error.Timeout;
    }

    pub fn dump(self: *const Hub) void {
        log.info("Hub [", .{});
        log.info("  port count = {d}", .{self.port_count});
        log.info("]", .{});
    }
};

var hubs: [MAX_HUBS]Hub = undefined;

var allocator: Allocator = undefined;

pub fn initialize(alloc: Allocator) void {
    allocator = alloc;

    for (0..MAX_HUBS) |i| {
        hubs[i].init();
    }
}

pub fn hubDriverDeviceBind(dev: *Device) Error!void {
    synchronize.criticalEnter(.FIQ);
    defer synchronize.criticalLeave();

    for (0..MAX_HUBS) |i| {
        if (!hubs[i].in_use) {
            var hub = &hubs[i];
            hub.in_use = true;
            errdefer hub.in_use = false;

            try hub.deviceBind(dev);
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
