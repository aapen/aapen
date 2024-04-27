const std = @import("std");
const usb = @import("../usb.zig");

pub const DeviceDescriptor = extern struct {
    pub const STANDARD_LENGTH = 18;

    length: u8,
    descriptor_type: u8,
    usb_standard_compliance: usb.BCD,
    device_class: u8,
    device_subclass: u8,
    device_protocol: u8,
    max_packet_size: u8,
    vendor: usb.ID,
    product: usb.ID,
    device_release: usb.BCD,
    manufacturer_name: usb.StringIndex,
    product_name: usb.StringIndex,
    serial_number: usb.StringIndex,
    configuration_count: u8,
};

pub const ConfigurationDescriptor = packed struct {
    pub const STANDARD_LENGTH = 9;

    length: u8,
    descriptor_type: u8,
    total_length: u16,
    interface_count: u8,
    configuration_value: u8,
    configuration: usb.StringIndex,
    attributes: u8,
    power_max: u8,
};

pub const HidDescriptor = extern struct {
    length: u8,
    descriptor_type: u8,
    hid_specification: usb.BCD,
    country_code: u8,
    descriptor_count: u8,
    class_descriptor_type: u8,
    class_descriptor_length: u16,
    optional_descriptor_type: u8,
    optional_descriptor_length: u16,
};

pub const InterfaceDescriptor = packed struct {
    pub const STANDARD_LENGTH = 9;

    length: u8,
    descriptor_type: u8,
    interface_number: u8,
    alternate_setting: u8,
    endpoint_count: u8,
    interface_class: u8,
    interface_subclass: u8,
    interface_protocol: u8,
    interface_string: usb.StringIndex,

    pub fn isHid(self: *const InterfaceDescriptor) bool {
        return self.interface_class == usb.USB_DEVICE_HID and
            (self.interface_subclass == 0x00 or self.interface_subclass == 0x01);
    }
};

pub const EndpointDescriptor = packed struct {
    pub const STANDARD_LENGTH = 7;

    length: u8,
    descriptor_type: u8,
    endpoint_address: u8,
    attributes: u8,
    max_packet_size: u16,
    interval: u8, // polling interval in frames

    /// Return the direction (in == 1, out == 0) of this endpoint
    pub fn direction(self: *const EndpointDescriptor) u1 {
        return @truncate((self.endpoint_address >> 7) & 0x1);
    }

    pub fn getType(self: *const EndpointDescriptor) u2 {
        return @truncate(self.attributes & 0x03);
    }

    pub fn isType(self: *const EndpointDescriptor, ty: u2) bool {
        return self.getType() == ty;
    }
};

pub const StringDescriptor = extern struct {
    length: u8,
    descriptor_type: u8,

    // For string descriptor 0, the remaining bytes (length - 2)
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

    pub fn asSlice(self: *const StringDescriptor, allocator: std.mem.Allocator) ![]u8 {
        const actual_length = (self.length - 2) / 2;
        const result = try allocator.alloc(u8, actual_length);
        @memset(result, 0);

        for (0..actual_length) |i| {
            const unicode_char = self.body[i];
            const ascii_char: u8 = @truncate(unicode_char);
            result[i] = ascii_char;
        }
        return result;
    }

    pub fn intoSlice(self: *const StringDescriptor, dest: []u8) []u8 {
        const actual_length = @min((self.length - 2) / 2, dest.len);
        for (0..actual_length) |i| {
            dest[i] = @truncate(self.body[i]);
        }
        return dest[0..actual_length];
    }
};
