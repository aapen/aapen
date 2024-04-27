const std = @import("std");
const Allocator = std.mem.Allocator;
const bufPrint = std.fmt.bufPrint;

const root = @import("root");

const descriptor = @import("descriptor.zig");
const ConfigurationDescriptor = descriptor.ConfigurationDescriptor;
const DeviceDescriptor = descriptor.DeviceDescriptor;
const EndpointDescriptor = descriptor.EndpointDescriptor;
const HidDescriptor = descriptor.HidDescriptor;
const InterfaceDescriptor = descriptor.InterfaceDescriptor;
const StringDescriptor = descriptor.StringDescriptor;

const Error = @import("status.zig").Error;

const transaction_translator = @import("transaction_translator.zig");
const TT = transaction_translator.TransactionTranslator;

const transfer = @import("transfer.zig");
const setup = transfer.setup;
const SetupPacket = transfer.SetupPacket;
const TransferType = transfer.TransferType;

const TransferFactory = @import("transfer_factory.zig");

const usb = @import("../usb.zig");
const Hub = usb.Hub;

pub const DeviceAddress = u7;
pub const DEFAULT_ADDRESS: DeviceAddress = 0;
pub const FIRST_DEDICATED_ADDRESS = 1;

pub const MAX_ADDRESS: DeviceAddress = 63;
pub const MAX_INTERFACES: usize = 8;
pub const MAX_ENDPOINTS: usize = 8;
pub const FRAMES_PER_MS: u32 = 8;
pub const UFRAMES_PER_MS: u32 = 8;

pub const DeviceStatus = u16;
pub const STATUS_SELF_POWERED: u32 = 0b01;
pub const STATUS_REMOTE_WAKEUP: u32 = 0b10;

pub const UsbSpeed = enum {
    Low,
    Full,
    High,
    Super,
};

pub const HubProtocol = struct {
    pub const full_speed_hub: u8 = 0x00;
    pub const high_speed_hub_single_tt: u8 = 0x01;
    pub const high_speed_hub_multiple_tt: u8 = 0x02;
};

pub const HidSubclass = struct {
    pub const boot: u8 = 0x01;
};

/// See https://www.usb.org/sites/default/files/documents/hid1_11.pdf,
/// page 9
pub const HidProtocol = struct {
    pub const none: u8 = 0x00;
    pub const keyboard: u8 = 0x01;
    pub const mouse: u8 = 0x02;
};

pub const HidClassRequest = struct {
    pub const get_report: u8 = 0x01;
    pub const get_idle: u8 = 0x02;
    pub const get_protocol: u8 = 0x03;
    pub const set_report: u8 = 0x09;
    pub const set_idle: u8 = 0x0a;
    pub const set_protocol: u8 = 0x0b;
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
    parent_port: u7,

    /// Transaction Translator to use for this device
    tt: ?*TT,

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
            .tt = null,
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

        if (usb.deviceGetStringDescriptor(self, self.device_descriptor.product_name, usb.USB_LANGID_EN_US, std.mem.asBytes(&desc))) {
            if (desc.asSlice(usb.allocator)) |s| {
                self.product = s;
            } else |err| {
                usb.log.err(@src(), "error extracting product name, err {any}", .{err});
            }
        } else |err| {
            usb.log.err(@src(), "error fetching product name, index {d}, err {any}", .{ self.device_descriptor.product_name, err });
        }

        return self.product;
    }

    fn deviceClassString(self: *const Device) []const u8 {
        var class = self.device_descriptor.device_class;

        if (class == 0) {
            for (0..self.configuration.configuration_descriptor.interface_count) |i| {
                if (self.configuration.interfaces[i]) |iface| {
                    if (iface.interface_class != usb.USB_INTERFACE_CLASS_RESERVED) {
                        class = iface.interface_class;
                    }
                }
            }
        }

        return switch (class) {
            // zig fmt: off
            0                                  => "Unspecified",
            usb.USB_DEVICE_AUDIO               => "Audio",
            usb.USB_DEVICE_CDC_CONTROL         => "Communications and CDC control",
            usb.USB_DEVICE_HID                 => "HID (Human interface device)",
            usb.USB_DEVICE_IMAGE               => "Image",
            usb.USB_DEVICE_PRINTER             => "Printer",
            usb.USB_DEVICE_MASS_STORAGE        => "Mass storage",
            usb.USB_DEVICE_HUB                 => "Hub",
            usb.USB_DEVICE_VIDEO               => "Video",
            usb.USB_DEVICE_WIRELESS_CONTROLLER => "Wireless controller",
            usb.USB_DEVICE_MISCELLANEOUS       => "Miscellaneous",
            usb.USB_DEVICE_VENDOR_SPECIFIC     => "Vendor specific",
            else                               => "Unknown",
            // zig fmt: on
        };
    }

    pub fn interfaceCount(self: *const Device) usize {
        return self.configuration.configuration_descriptor.interface_count;
    }

    pub fn interface(self: *const Device, i: usize) ?*InterfaceDescriptor {
        if (i < self.interfaceCount()) {
            return self.configuration.interfaces[i].?;
        } else {
            return null;
        }
    }

    pub fn interfaceClass(self: *const Device, i: usize) ?u8 {
        if (self.interface(i)) |iface| {
            return iface.interface_class;
        } else {
            return null;
        }
    }

    pub fn interfaceProtocol(self: *const Device, i: usize) ?u8 {
        if (self.interface(i)) |iface| {
            return iface.interface_protocol;
        } else {
            return null;
        }
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
    hids: [MAX_INTERFACES]?*HidDescriptor,
    endpoints: [MAX_INTERFACES][MAX_ENDPOINTS]?*EndpointDescriptor,

    pub fn initFromBytes(allocator: Allocator, configuration_tree: []const u8) !*DeviceConfiguration {
        var self = try allocator.create(DeviceConfiguration);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .configuration_descriptor = std.mem.zeroes(ConfigurationDescriptor),
            .interfaces = std.mem.zeroes([MAX_INTERFACES]?*InterfaceDescriptor),
            .hids = std.mem.zeroes([MAX_INTERFACES]?*HidDescriptor),
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

    const ParseState = struct {
        here: usize = 0,
        tree: []const u8,

        fn expect(self: *const ParseState, v: u8) !void {
            // note that this looks ahead by one byte because the
            // descriptor header is always {length: u8, type: u8}
            if (self.tree[self.here + 1] != v) {
                return DeviceConfiguration.ParseError.BadData;
            }
        }

        fn copy(state: *ParseState, comptime T: type, allocator: Allocator) !*T {
            const struct_start = state.here;
            const struct_length = state.tree[state.here];
            state.here += struct_length;
            const struct_end = state.here;
            return try alignedCopy(T, allocator, state.tree[struct_start..struct_end]);
        }
    };

    fn parseConfiguration(self: *DeviceConfiguration, configuration_tree: []const u8) !void {
        var state: ParseState = .{
            .here = 0,
            .tree = configuration_tree,
        };

        try state.expect(usb.USB_DESCRIPTOR_TYPE_CONFIGURATION);

        const partial_copy = try state.copy(ConfigurationDescriptor, self.allocator);
        self.configuration_descriptor = partial_copy.*;
        self.allocator.destroy(partial_copy);

        const expect_interfaces = self.configuration_descriptor.interface_count;

        for (0..expect_interfaces) |iface_num| {
            try state.expect(usb.USB_DESCRIPTOR_TYPE_INTERFACE);
            const iface = try state.copy(InterfaceDescriptor, self.allocator);
            errdefer self.allocator.destroy(iface);
            self.interfaces[iface_num] = iface;

            // question: is the HID descriptor _mandatory_ when the
            // interface class is 0x03?
            if (iface.isHid()) {
                if (state.expect(usb.USB_DESCRIPTOR_TYPE_HID)) {
                    // For now, assume that the HID descriptor is
                    // optional and if the type doesn't match, then
                    // jump to parsing endpoint descriptors.
                    const hid = try state.copy(HidDescriptor, self.allocator);
                    errdefer self.allocator.destroy(hid);
                    self.hids[iface_num] = hid;
                } else |_| {
                    // it wasn't a HID descriptor, but that's OK. for
                    // now we are assuming the HID descriptor is optional
                }
            }

            const expect_endpoints = iface.endpoint_count;
            for (0..expect_endpoints) |endpoint_num| {
                try state.expect(usb.USB_DESCRIPTOR_TYPE_ENDPOINT);
                const endpoint = try state.copy(EndpointDescriptor, self.allocator);
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
        usb.log.debug(@src(), "DeviceConfiguration [", .{});
        self.configuration_descriptor.dump();
        for (0..MAX_INTERFACES) |i| {
            if (self.interfaces[i]) |iface| {
                iface.dump();

                if (self.hids[i]) |hid| {
                    hid.dump();
                }

                for (0..MAX_ENDPOINTS) |e| {
                    if (self.endpoints[i][e]) |endp| {
                        endp.dump();
                    }
                }
            }
        }
        usb.log.debug(@src(), "]", .{});
    }
};

pub const DeviceDriver = struct {
    name: []const u8,
    initialize: *const fn (allocator: std.mem.Allocator) Error!void,
    canBind: *const fn (device: *Device) bool,
    bind: *const fn (device: *Device) Error!void,
    unbind: ?*const fn (device: *Device) void,
};
