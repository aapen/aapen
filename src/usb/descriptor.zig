const std = @import("std");
const Allocator = std.mem.Allocator;

const device = @import("device.zig");
const DeviceClass = device.DeviceClass;
const StandardDeviceRequests = device.StandardDeviceRequests;

const interface = @import("interface.zig");
const InterfaceClass = interface.InterfaceClass;

const transfer = @import("transfer.zig");
const setup = transfer.setup;
const SetupPacket = transfer.SetupPacket;
const Transfer = transfer.TransferRequest;
const TransferType = transfer.TransferType;

var log = @import("../logger.zig").initWithLevel("usb", .info);

/// Index of a string descriptor
pub const StringIndex = u8;

pub const BCD = u16;
pub const SpecRelease = struct {
    pub const usb1_0: BCD = 0x0100;
    pub const usb1_1: BCD = 0x0110;
    pub const usb2_0: BCD = 0x0200;
};

/// Assigned ID number
pub const ID = u16;

/// Index of a descriptor
pub const DescriptorIndex = u8;

pub const DEFAULT_DESCRIPTOR_INDEX = 0;

pub const DescriptorType = struct {
    // not for use
    pub const unknown: u8 = 0;

    // general
    pub const device: u8 = 1;
    pub const configuration: u8 = 2;
    pub const string: u8 = 3;
    pub const interface: u8 = 4;
    pub const endpoint: u8 = 5;

    // hid
    pub const hid: u8 = 0x21;

    // class
    pub const class_interface: u8 = 0x24;
    pub const class_endpoint: u8 = 0x25;

    // device
    pub const hub: u8 = 0x29;
};

pub const Header = packed struct {
    length: u8,
    descriptor_type: u8,
};

const Error = error{
    LengthMismatch,
    UnexpectedType,
};

pub const DeviceDescriptor = extern struct {
    header: Header,
    usb_standard_compliance: BCD = 0,
    device_class: u8 = 0,
    device_subclass: u8 = 0,
    device_protocol: u8 = 0,
    max_packet_size: u8 = 0,
    vendor: ID = 0,
    product: ID = 0,
    device_release: BCD = 0,
    manufacturer_name: StringIndex = 0,
    product_name: StringIndex = 0,
    serial_number: StringIndex = 0,
    configuration_count: u8 = 0,

    pub fn dump(self: *const DeviceDescriptor) void {
        log.debug(@src(), "DeviceDescriptor [", .{});
        log.debug(@src(), "  class-subclass-protocol = {d}-{d}-{d}", .{ self.device_class, self.device_subclass, self.device_protocol });
        log.debug(@src(), "  vendor = 0x{x:0>4}", .{self.vendor});
        log.debug(@src(), "  product = 0x{x:0>4}", .{self.product});
        log.debug(@src(), "  max_packet_size = 0x{d}", .{self.max_packet_size});
        log.debug(@src(), "  usb_standard_compliance = 0x{x}", .{self.usb_standard_compliance});
        log.debug(@src(), "  configuration_count = 0x{d}", .{self.configuration_count});
        log.debug(@src(), "]", .{});
    }

    pub fn fromSlice(buffer: []u8) !*DeviceDescriptor {
        const maybe_device_descriptor: *DeviceDescriptor = @ptrCast(@alignCast(buffer.ptr));
        if (maybe_device_descriptor.header.length != @sizeOf(DeviceDescriptor)) {
            return Error.LengthMismatch;
        }

        if (maybe_device_descriptor.header.descriptor_type != DescriptorType.device)
            return Error.UnexpectedType;

        return maybe_device_descriptor;
    }
};

pub const ConfigurationDescriptor = packed struct {
    // Zig's @sizeOf() rounds up to natural alignment (in this case
    // 10) so we use this constant for the length defined by the
    // standard
    pub const STANDARD_LENGTH = 9;

    header: Header,
    total_length: u16,
    interface_count: u8,
    configuration_value: u8,
    configuration: StringIndex,
    attributes: packed struct {
        _reserved_0: u5 = 0, // 0..5
        remote_wakeup: u1 = 0, // 5
        self_powered: u1 = 0, // 6
        _reserved_1: u1 = 1, // unused since USB 2.0
    },
    power_max: u8,

    pub fn dump(self: *const ConfigurationDescriptor) void {
        log.debug(@src(), "ConfigurationDescriptor [", .{});
        log.debug(@src(), "  total length = {d}", .{self.total_length});
        log.debug(@src(), "  interface count = {d}", .{self.interface_count});
        log.debug(@src(), "  configuration value = {d}", .{self.configuration_value});
        log.debug(@src(), "  configuration = {d}", .{self.configuration});
        log.debug(@src(), "  remote wakeup = {d}", .{self.attributes.remote_wakeup});
        log.debug(@src(), "  self powered = {d}", .{self.attributes.self_powered});
        log.debug(@src(), "  power max = {d} mA", .{self.power_max});
        log.debug(@src(), "]", .{});
    }
};

pub const InterfaceDescriptor = packed struct {
    // Zig's @sizeOf() rounds up to natural alignment (in this case
    // 10) so we use this constant for the length defined by the
    // standard
    pub const STANDARD_LENGTH = 9;

    header: Header,
    interface_number: u8,
    alternate_setting: u8,
    endpoint_count: u8,
    interface_class: u8,
    interface_subclass: u8,
    interface_protocol: u8,
    interface_string: StringIndex,

    pub fn isHid(self: *const InterfaceDescriptor) bool {
        return self.interface_class == DeviceClass.hid and (self.interface_subclass == 0x00 or self.interface_subclass == 0x01);
    }

    pub fn dump(self: *const InterfaceDescriptor) void {
        log.debug(@src(), "InterfaceDescriptor [", .{});
        log.debug(@src(), "  interface number = {d}", .{self.interface_number});
        log.debug(@src(), "  alternate_setting = {d}", .{self.alternate_setting});
        log.debug(@src(), "  endpoint count = {d}", .{self.endpoint_count});
        log.debug(@src(), "  class-subclass-protocol = {d}-{d}-{d}", .{ self.interface_class, self.interface_subclass, self.interface_protocol });
        log.debug(@src(), "  interface string = {d}", .{self.interface_string});
        log.debug(@src(), "]", .{});
    }
};

pub const IsoSynchronizationType = struct {
    pub const none: u2 = 0b00;
    pub const asynchronous: u2 = 0b01;
    pub const adaptive: u2 = 0b10;
    pub const synchronous: u2 = 0b11;
};

pub const IsoUsageType = struct {
    pub const data: u2 = 0b00;
    pub const feedback: u2 = 0b01;
    pub const explicit_feedback: u2 = 0b10;
    pub const reserved: u2 = 0b11;
};

pub const EndpointDescriptor = packed struct {
    // Zig's @sizeOf() rounds up to natural alignment (in this case
    // 8) so we use this constant for the length defined by the
    // standard
    pub const STANDARD_LENGTH = 7;

    header: Header,
    endpoint_address: u8,
    attributes: packed struct {
        endpoint_type: u2, // 0..1
        iso_synch_type: u2, // 2..3
        usage_type: u2, // 4..5
        _reserved_0: u2 = 0,
    },
    max_packet_size: u16,
    interval: u8, // polling interval in frames

    /// Return the direction (in == 1, out == 0) of this endpoint
    pub fn direction(self: *const EndpointDescriptor) u1 {
        return @truncate((self.endpoint_address >> 7) & 0x1);
    }

    pub fn isType(self: *const EndpointDescriptor, ty: u2) bool {
        return self.attributes.endpoint_type == ty;
    }

    pub fn dump(self: *const EndpointDescriptor) void {
        log.debug(@src(), "EndpointDescriptor [", .{});
        log.debug(@src(), "  endpoint_address = {d}", .{self.endpoint_address});
        log.debug(@src(), "  attributes = 0x{x}", .{@as(u8, @bitCast(self.attributes))});
        log.debug(@src(), "  max_packet_size = {d}", .{self.max_packet_size});
        log.debug(@src(), "  interval = {d}", .{self.interval});
        log.debug(@src(), "]", .{});
    }
};

pub const StringDescriptor = extern struct {
    header: Header,

    // For string descriptor 0, the remaining bytes (header.length - 2)
    // contain an array of u16's with the language codes of each
    // language this string is available in. The index of the
    // desired language in the array will be the `index` field in a request
    // to get string decriptor. That response will contain a unicode
    // encoded string of `length` bytes.
    //
    // For all other string descriptors, the body will be the unicode
    // bytes of the string itself.
    //
    // For simplicity, we only read up to the first 62 bytes of this
    // descriptor. Otherwise we have to do one control transfer to
    // find the length then another to read the actual contents.
    body: [31]u16 align(1),

    pub fn asSlice(self: *const StringDescriptor, allocator: Allocator) ![]u8 {
        const actual_length = (self.header.length - @sizeOf(Header)) / 2;
        const result = try allocator.alloc(u8, actual_length);
        @memset(result, 0);

        for (0..actual_length) |i| {
            const unicode_char = self.body[i];
            const ascii_char: u8 = @truncate(unicode_char);
            result[i] = ascii_char;
        }
        return result;
    }
};

pub const HidDescriptor = extern struct {
    header: Header,
    hid_specification: BCD,
    country_code: u8,
    descriptor_count: u8,
    class_descriptor_type: u8,
    class_descriptor_length: u16,
    optional_descriptor_type: u8,
    optional_descriptor_length: u16,

    pub fn dump(self: *const HidDescriptor) void {
        log.debug(@src(), "HidDescriptor [", .{});
        log.debug(@src(), "  hid_specification = 0x{x}", .{self.hid_specification});
        log.debug(@src(), "  country_code = {d}", .{self.country_code});
        log.debug(@src(), "  descriptor_count = {d}", .{self.descriptor_count});
        log.debug(@src(), "  class_descriptor_type = {d}", .{self.class_descriptor_type});
        log.debug(@src(), "  class_descriptor_length = {d}", .{self.class_descriptor_length});
        log.debug(@src(), "]", .{});
    }
};
