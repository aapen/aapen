const std = @import("std");
const Allocator = std.mem.Allocator;
const bufPrint = std.fmt.bufPrint;

const root = @import("root");

const Error = @import("status.zig").Error;

const transaction_translator = @import("transaction_translator.zig");
const TT = transaction_translator.TransactionTranslator;

const core = @import("core.zig");
const descriptor = @import("descriptor.zig");
const hub = @import("hub.zig");
const spec = @import("spec.zig");

pub const DEFAULT_ADDRESS: spec.DeviceAddress = 0;
pub const FIRST_DEDICATED_ADDRESS = 1;

pub const MAX_ADDRESS: spec.DeviceAddress = 63;
pub const MAX_INTERFACES: usize = 8;
pub const MAX_ENDPOINTS: usize = 8;
pub const FRAMES_PER_MS: u32 = 8;
pub const UFRAMES_PER_MS: u32 = 8;

pub const STATUS_SELF_POWERED: u32 = 0b01;
pub const STATUS_REMOTE_WAKEUP: u32 = 0b10;

pub const UsbSpeed = enum {
    Low,
    Full,
    High,
    Super,
};

pub const DeviceState = enum {
    unconfigured,
    attached,
    detaching,
};

pub const Device = struct {
    in_use: bool = false,
    depth: u8 = 0,
    address: spec.DeviceAddress,
    speed: UsbSpeed,

    /// Hub this is attached to. Null means this is the root hub.
    parent: ?*Device,

    /// Port on the parent hub this is attached to
    parent_port: u7,

    /// Transaction Translator to use for this device
    tt: ?*TT,

    device_descriptor: descriptor.DeviceDescriptor,
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

    pub fn deinit(_: *Device) void {}

    pub fn isRootHub(self: *Device) bool {
        return self.parent == null;
    }

    pub fn description(self: *Device, buffer: []u8) ![]u8 {
        const usb_standard = self.device_descriptor.usb_standard_compliance;
        var pname_buf: [31]u8 = undefined;
        const pname = try self.deviceProductName(&pname_buf);

        return bufPrint(
            buffer,
            "{s}-speed USB {d}.{d} {s} device ({s}) (vendor = 0x{x:0>4}, product = 0x{x:0>4})",
            .{
                @tagName(self.speed),
                (usb_standard >> 8) & 0xff,
                (usb_standard >> 4) & 0xf,
                self.deviceClassString(),
                pname,
                self.device_descriptor.vendor,
                self.device_descriptor.product,
            },
        ) catch "";
    }

    fn deviceProductName(self: *Device, buf: []u8) ![]u8 {
        var desc: descriptor.StringDescriptor = undefined;
        try core.deviceGetStringDescriptor(self, self.device_descriptor.product_name, spec.USB_LANGID_EN_US, std.mem.asBytes(&desc));
        return desc.intoSlice(buf);
    }

    fn deviceClassString(self: *const Device) []const u8 {
        var class = self.device_descriptor.device_class;

        if (class == 0) {
            for (0..self.configuration.configuration_descriptor.interface_count) |i| {
                if (self.configuration.interfaces[i]) |iface| {
                    if (iface.interface_class != spec.USB_INTERFACE_CLASS_RESERVED) {
                        class = iface.interface_class;
                    }
                }
            }
        }

        return switch (class) {
            // zig fmt: off
            0                                   => "Unspecified",
            spec.USB_DEVICE_AUDIO               => "Audio",
            spec.USB_DEVICE_CDC_CONTROL         => "Communications and CDC control",
            spec.USB_DEVICE_HID                 => "HID (Human interface device)",
            spec.USB_DEVICE_IMAGE               => "Image",
            spec.USB_DEVICE_PRINTER             => "Printer",
            spec.USB_DEVICE_MASS_STORAGE        => "Mass storage",
            spec.USB_DEVICE_HUB                 => "Hub",
            spec.USB_DEVICE_VIDEO               => "Video",
            spec.USB_DEVICE_WIRELESS_CONTROLLER => "Wireless controller",
            spec.USB_DEVICE_MISCELLANEOUS       => "Miscellaneous",
            spec.USB_DEVICE_VENDOR_SPECIFIC     => "Vendor specific",
            else                                => "Unknown",
            // zig fmt: on
        };
    }

    pub fn interfaceCount(self: *const Device) usize {
        return self.configuration.configuration_descriptor.interface_count;
    }

    pub fn interface(self: *const Device, i: usize) ?*descriptor.InterfaceDescriptor {
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
    configuration_descriptor: descriptor.ConfigurationDescriptor,
    interfaces: [MAX_INTERFACES]?*descriptor.InterfaceDescriptor,
    hids: [MAX_INTERFACES]?*descriptor.HidDescriptor,
    endpoints: [MAX_INTERFACES][MAX_ENDPOINTS]?*descriptor.EndpointDescriptor,

    pub fn initFromBytes(allocator: Allocator, configuration_tree: []const u8) !*DeviceConfiguration {
        var self = try allocator.create(DeviceConfiguration);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .configuration_descriptor = std.mem.zeroes(descriptor.ConfigurationDescriptor),
            .interfaces = std.mem.zeroes([MAX_INTERFACES]?*descriptor.InterfaceDescriptor),
            .hids = std.mem.zeroes([MAX_INTERFACES]?*descriptor.HidDescriptor),
            .endpoints = std.mem.zeroes([MAX_INTERFACES][MAX_ENDPOINTS]?*descriptor.EndpointDescriptor),
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

        try state.expect(spec.USB_DESCRIPTOR_TYPE_CONFIGURATION);

        const partial_copy = try state.copy(descriptor.ConfigurationDescriptor, self.allocator);
        self.configuration_descriptor = partial_copy.*;
        self.allocator.destroy(partial_copy);

        const expect_interfaces = self.configuration_descriptor.interface_count;

        for (0..expect_interfaces) |iface_num| {
            try state.expect(spec.USB_DESCRIPTOR_TYPE_INTERFACE);
            const iface = try state.copy(descriptor.InterfaceDescriptor, self.allocator);
            errdefer self.allocator.destroy(iface);
            self.interfaces[iface_num] = iface;

            // question: is the HID descriptor _mandatory_ when the
            // interface class is 0x03?
            if (iface.isHid()) {
                if (state.expect(spec.USB_DESCRIPTOR_TYPE_HID)) {
                    // For now, assume that the HID descriptor is
                    // optional and if the type doesn't match, then
                    // jump to parsing endpoint descriptors.
                    const hid = try state.copy(descriptor.HidDescriptor, self.allocator);
                    errdefer self.allocator.destroy(hid);
                    self.hids[iface_num] = hid;
                } else |_| {
                    // it wasn't a HID descriptor, but that's OK. for
                    // now we are assuming the HID descriptor is optional
                }
            }

            const expect_endpoints = iface.endpoint_count;
            for (0..expect_endpoints) |endpoint_num| {
                try state.expect(spec.USB_DESCRIPTOR_TYPE_ENDPOINT);
                const endpoint = try state.copy(descriptor.EndpointDescriptor, self.allocator);
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
};

pub const DeviceDriver = struct {
    name: []const u8,
    initialize: *const fn (allocator: std.mem.Allocator) Error!void,
    canBind: *const fn (device: *Device) bool,
    bind: *const fn (device: *Device) Error!void,
    unbind: ?*const fn (device: *Device) void,
};
