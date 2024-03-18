const std = @import("std");
const Allocator = std.mem.Allocator;
const bufPrint = std.fmt.bufPrint;
const log = std.log.scoped(.usb);

const descriptor = @import("descriptor.zig");
const ConfigurationDescriptor = descriptor.ConfigurationDescriptor;
const DescriptorType = descriptor.DescriptorType;
const DeviceDescriptor = descriptor.DeviceDescriptor;
const EndpointDescriptor = descriptor.EndpointDescriptor;
const InterfaceDescriptor = descriptor.InterfaceDescriptor;
const StringDescriptor = descriptor.StringDescriptor;

const Error = @import("status.zig").Error;

const LangID = @import("language.zig").LangID;
const DEFAULT_LANG = LangID.en_US;

const transfer = @import("transfer.zig");
const setup = transfer.setup;
const SetupPacket = transfer.SetupPacket;
const TransferType = transfer.TransferType;

const TransferFactory = @import("transfer_factory.zig");

const usb = @import("../usb.zig");
const InterfaceClass = usb.InterfaceClass;

pub const DeviceAddress = u7;
pub const DEFAULT_ADDRESS: DeviceAddress = 0;
pub const FIRST_DEDICATED_ADDRESS = 1;

pub const MAX_ADDRESS: DeviceAddress = 63;
pub const MAX_INTERFACES: usize = 8;
pub const MAX_ENDPOINTS: usize = 8;

pub const DeviceStatus = u16;
pub const STATUS_SELF_POWERED: u32 = 0b01;
pub const STATUS_REMOTE_WAKEUP: u32 = 0b10;

pub const UsbSpeed = enum {
    Low,
    Full,
    High,
    Super,
};

pub const StandardDeviceRequests = struct {
    pub const get_status: u8 = 0x00;
    pub const clear_feature: u8 = 0x01;
    pub const set_feature: u8 = 0x03;
    pub const set_address: u8 = 0x05;
    pub const get_descriptor: u8 = 0x06;
    pub const set_descriptor: u8 = 0x07;
    pub const get_configuration: u8 = 0x08;
    pub const set_configuration: u8 = 0x09;
};

/// See https://www.usb.org/defined-class-codes
pub const DeviceClass = struct {
    pub const interface_specific: u8 = 0x00;
    pub const audio: u8 = 0x01;
    pub const cdc_control: u8 = 0x02;
    pub const hid: u8 = 0x03;
    pub const physical: u8 = 0x05;
    pub const image: u8 = 0x06;
    pub const printer: u8 = 0x07;
    pub const mass_storage: u8 = 0x08;
    pub const hub: u8 = 0x09;
    pub const cdc_data: u8 = 0x0a;
    pub const smart_card: u8 = 0x0b;
    pub const content_security: u8 = 0x0d;
    pub const video: u8 = 0x0e;
    pub const personal_healthcare: u8 = 0x0f;
    pub const audio_video: u8 = 0x10;
    pub const billboard: u8 = 0x11;
    pub const type_c_bridge: u8 = 0x12;
    pub const bulk_display: u8 = 0x13;
    pub const mctp_over_usb: u8 = 0x14;
    pub const i3c: u8 = 0x3c;
    pub const diagnostic: u8 = 0xdc;
    pub const wireless_controller: u8 = 0xe0;
    pub const miscellaneous: u8 = 0xef;
    pub const application_specific: u8 = 0xfe;
    pub const vendor_specific: u8 = 0xff;
};

pub const HubProtocol = struct {
    pub const full_speed_hub: u8 = 0x00;
    pub const high_speed_hub_single_tt: u8 = 0x01;
    pub const high_speed_hub_multiple_tt: u8 = 0x02;
};

/// See https://www.usb.org/sites/default/files/documents/hid1_11.pdf,
/// page 9
pub const HidProtocol = struct {
    pub const none: u8 = 0x00;
    pub const keyboard: u8 = 0x01;
    pub const mouse: u8 = 0x02;
};

pub const DeviceState = enum {
    unconfigured,
    attached,
    detaching,
};

pub const Device = struct {
    in_use: bool = false,
    depth: u8 = 0,
    address: DeviceAddress,
    speed: UsbSpeed,

    /// Hub this is attached to. Null means this is the root hub.
    parent: ?*Device,
    /// Port on the parent hub this is attached to
    parent_port: u32,

    device_descriptor: DeviceDescriptor,
    configuration: *DeviceConfiguration,

    product: []u8,

    state: DeviceState,

    // the follow members are controlled by the core driver
    driver: ?*DeviceDriver,
    driver_private: *anyopaque,

    pub fn init(self: *Device) void {
        const nothing_private = [_]u8{};
        self.* = .{
            .in_use = false,
            .depth = 0,
            .address = 0,
            .speed = .Full,
            .parent = null,
            .parent_port = 0,
            .device_descriptor = undefined,
            .product = "",
            .state = .unconfigured,
            .driver = null,
            .driver_private = &nothing_private,
            .configuration = undefined,
        };
    }

    pub fn deinit(self: *Device) void {
        // release any dynamically allocated memory
        if (self.product.len > 0) {
            usb.allocator.free(self.product);
        }
    }

    pub fn isRootHub(self: *Device) bool {
        return self.parent == null;
    }

    pub fn description(self: *Device, buffer: []u8) []u8 {
        const usb_standard = self.device_descriptor.usb_standard_compliance;

        return bufPrint(
            buffer,
            "{s}-speed USB {d}.{d} {s} device ({s}) (vendor = 0x{x:0>4}, product = 0x{x:0>4})",
            .{
                @tagName(self.speed),
                (usb_standard >> 8) & 0xff,
                (usb_standard >> 4) & 0xf,
                self.deviceClassString(),
                self.deviceProductName(),
                self.device_descriptor.vendor,
                self.device_descriptor.product,
            },
        ) catch "";
    }

    fn deviceProductName(self: *Device) []const u8 {
        if (self.product.len > 0) {
            return self.product;
        }

        var desc: StringDescriptor = undefined;

        if (usb.deviceGetStringDescriptor(self, self.device_descriptor.product_name, DEFAULT_LANG, std.mem.asBytes(&desc))) {
            if (desc.asSlice(usb.allocator)) |s| {
                self.product = s;
            } else |err| {
                log.err("error extracting product name, err {any}", .{err});
            }
        } else |err| {
            log.err("error fetching product name, index {d}, err {any}", .{ self.device_descriptor.product_name, err });
        }

        return self.product;
    }

    fn deviceClassString(self: *const Device) []const u8 {
        var class = self.device_descriptor.device_class;

        if (class == 0) {
            for (0..self.configuration.configuration_descriptor.interface_count) |i| {
                if (self.configuration.interfaces[i]) |iface| {
                    if (iface.interface_class != InterfaceClass.reserved) {
                        class = iface.interface_class;
                    }
                }
            }
        }

        return switch (class) {
            0 => "Unspecified",
            DeviceClass.audio => "Audio",
            DeviceClass.cdc_control => "Communications and CDC control",
            DeviceClass.hid => "HID (Human interface device)",
            DeviceClass.image => "Image",
            DeviceClass.printer => "Printer",
            DeviceClass.mass_storage => "Mass storage",
            DeviceClass.hub => "Hub",
            DeviceClass.video => "Video",
            DeviceClass.wireless_controller => "Wireless controller",
            DeviceClass.miscellaneous => "Miscellaneous",
            DeviceClass.vendor_specific => "Vendor specific",
            else => "Unknown",
        };
    }
};

/// This represents the parsed configuration tree
pub const DeviceConfiguration = struct {
    const ParseError = error{
        BadData,
    };

    allocator: Allocator,
    configuration_descriptor: ConfigurationDescriptor,
    interfaces: [MAX_INTERFACES]?*InterfaceDescriptor,
    endpoints: [MAX_INTERFACES][MAX_ENDPOINTS]?*EndpointDescriptor,

    pub fn initFromBytes(allocator: Allocator, configuration_tree: []const u8) !*DeviceConfiguration {
        var self = try allocator.create(DeviceConfiguration);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .configuration_descriptor = std.mem.zeroes(ConfigurationDescriptor),
            .interfaces = std.mem.zeroes([MAX_INTERFACES]?*InterfaceDescriptor),
            .endpoints = std.mem.zeroes([MAX_INTERFACES][MAX_ENDPOINTS]?*EndpointDescriptor),
        };

        try self.parseConfiguration(configuration_tree);

        return self;
    }

    pub fn deinit(self: *DeviceConfiguration) void {
        for (0..MAX_INTERFACES) |i| {
            if (self.interfaces[i]) |face| {
                for (0..MAX_ENDPOINTS) |e| {
                    if (self.endpoints[i][e]) |endp| {
                        self.allocator.destroy(endp);
                    }
                }

                self.allocator.destroy(face);
                self.interfaces[i] = null;
            }
        }
    }

    fn parseConfiguration(self: *DeviceConfiguration, configuration_tree: []const u8) !void {
        var here: usize = 0;
        const config_start = here;
        const config_length = configuration_tree[here];

        if (configuration_tree[here + 1] != DescriptorType.configuration) {
            return DeviceConfiguration.ParseError.BadData;
        }

        here = here + config_length;
        const config_end = here;

        const partial_copy = try alignedCopy(ConfigurationDescriptor, self.allocator, configuration_tree[config_start..config_end]);
        self.configuration_descriptor = partial_copy.*;
        self.allocator.destroy(partial_copy);

        const expect_interfaces = self.configuration_descriptor.interface_count;

        for (0..expect_interfaces) |iface_num| {
            const iface_length = configuration_tree[here];

            if (configuration_tree[here + 1] != DescriptorType.interface) {
                return DeviceConfiguration.ParseError.BadData;
            }

            const iface_start = here;
            here = here + iface_length;
            const iface_end = here;

            const iface = try alignedCopy(InterfaceDescriptor, self.allocator, configuration_tree[iface_start..iface_end]);
            errdefer self.allocator.destroy(iface);

            self.interfaces[iface_num] = iface;

            const expect_endpoints = iface.endpoint_count;
            for (0..expect_endpoints) |endpoint_num| {
                const endpoint_length = configuration_tree[here];

                if (configuration_tree[here + 1] != DescriptorType.endpoint) {
                    return DeviceConfiguration.ParseError.BadData;
                }

                const endpoint_start = here;
                here = here + endpoint_length;
                const endpoint_end = here;

                const endpoint = try alignedCopy(EndpointDescriptor, self.allocator, configuration_tree[endpoint_start..endpoint_end]);
                errdefer self.allocator.destroy(endpoint);

                self.endpoints[iface_num][endpoint_num] = endpoint;
            }
        }
    }

    fn alignedCopy(comptime T: type, allocator: Allocator, unaligned_buffer: []const u8) !*T {
        // res will now have the natural alignment of T
        const res: *T = try allocator.create(T);

        @memset(std.mem.asBytes(res), 0);
        @memcpy(std.mem.asBytes(res)[0..unaligned_buffer.len], unaligned_buffer[0..]);

        return res;
    }

    pub fn dump(self: *const DeviceConfiguration) void {
        log.debug("DeviceConfiguration [", .{});
        self.configuration_descriptor.dump();
        for (0..MAX_INTERFACES) |i| {
            if (self.interfaces[i]) |iface| {
                iface.dump();

                for (0..MAX_ENDPOINTS) |e| {
                    if (self.endpoints[i][e]) |endp| {
                        endp.dump();
                    }
                }
            }
        }
        log.debug("]", .{});
    }
};

pub const DeviceDriver = struct {
    name: []const u8,
    bind: *const fn (device: *Device) Error!void,
    unbind: ?*const fn (device: *Device) void,
};

// ----------------------------------------------------------------------
// Testing
// ----------------------------------------------------------------------
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "we can parse a configuration tree into a device" {
    std.debug.print("\n", .{});

    const canned_configuration_descriptor = [_]u8{ 0x09, 0x02, 0x19, 0x00, 0x01, 0x01, 0x00, 0xe0, 0x00, 0x09, 0x04, 0x00, 0x00, 0x01, 0x09, 0x00, 0x00, 0x00, 0x07, 0x05, 0x81, 0x03, 0x02, 0x00, 0xff };

    var config = try DeviceConfiguration.initFromBytes(std.testing.allocator, &canned_configuration_descriptor);
    defer {
        config.deinit();
        std.testing.allocator.destroy(config);
    }

    try expectEqual(@as(u8, 1), config.configuration_descriptor.interface_count);
    try expect(config.interfaces[0] != null);
    try expectEqual(@as(u8, 1), config.interfaces[0].?.endpoint_count);
    try expect(config.endpoints[0][0] != null);
    try expectEqual(@as(u8, 0x81), config.endpoints[0][0].?.endpoint_address);
    try expectEqual(TransferType.interrupt, config.endpoints[0][0].?.attributes.transfer_type);
}
