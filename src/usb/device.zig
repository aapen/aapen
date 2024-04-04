const std = @import("std");
const Allocator = std.mem.Allocator;
const bufPrint = std.fmt.bufPrint;
const log = std.log.scoped(.usb);

const root = @import("root");

const descriptor = @import("descriptor.zig");
const ConfigurationDescriptor = descriptor.ConfigurationDescriptor;
const DescriptorType = descriptor.DescriptorType;
const DeviceDescriptor = descriptor.DeviceDescriptor;
const EndpointDescriptor = descriptor.EndpointDescriptor;
const HidDescriptor = descriptor.HidDescriptor;
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
    port_number: u7,

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
            .port_number = 0,
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

        try state.expect(DescriptorType.configuration);

        const partial_copy = try state.copy(ConfigurationDescriptor, self.allocator);
        self.configuration_descriptor = partial_copy.*;
        self.allocator.destroy(partial_copy);

        const expect_interfaces = self.configuration_descriptor.interface_count;

        for (0..expect_interfaces) |iface_num| {
            try state.expect(DescriptorType.interface);
            const iface = try state.copy(InterfaceDescriptor, self.allocator);
            errdefer self.allocator.destroy(iface);
            self.interfaces[iface_num] = iface;

            // question: is the HID descriptor _mandatory_ when the
            // interface class is 0x03?
            if (iface.isHid()) {
                if (state.expect(DescriptorType.hid)) {
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
                try state.expect(DescriptorType.endpoint);
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
        log.debug("DeviceConfiguration [", .{});
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
        log.debug("]", .{});
    }
};

pub const DeviceDriver = struct {
    name: []const u8,
    canBind: *const fn (device: *Device) bool,
    bind: *const fn (device: *Device) Error!void,
    unbind: ?*const fn (device: *Device) void,
};
