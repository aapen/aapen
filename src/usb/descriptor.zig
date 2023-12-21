const std = @import("std");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.usb);

const device = @import("device.zig");
const DeviceClass = device.DeviceClass;

const transaction = @import("transaction.zig");
const setup = transaction.setup;
const SetupPacket = transaction.SetupPacket;
const TransferType = transaction.TransferType;

/// Index of a string descriptor
pub const StringIndex = u8;

pub const BCD = u16;
pub const SpecRelease = enum(BCD) {
    usb1_0 = 0x0100,
    usb1_1 = 0x0110,
    usb2_0 = 0x0200,
};

/// Assigned ID number
pub const ID = u16;

/// Index of a descriptor
pub const DescriptorIndex = u8;

pub const DEFAULT_DESCRIPTOR_INDEX = 0;

pub const DescriptorType = enum(u8) {
    // not for use
    unknown = 0,

    // general
    device = 1,
    configuration = 2,
    string = 3,
    interface = 4,
    endpoint = 5,

    // device classes
    hub = 0x29, // descriptor layout is in hub.zig

    // class specific
    class_interface = 36,
    class_endpoint = 37,
};

pub const Header = packed struct {
    length: u8,
    descriptor_type: DescriptorType,
};

pub const Descriptor = extern union {
    header: Header,
    device: DeviceDescriptor,
    configuration: ConfigurationDescriptor,
    interface: InterfaceDescriptor,
    endpoint: EndpointDescriptor,
    string: StringDescriptor,

    const Error = error{
        LengthMismatch,
        UnexpectedType,
    };
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
        log.debug("DeviceDescriptor [", .{});
        log.debug("  class-subclass-protocol = {d}-{d}-{d}", .{ self.device_class, self.device_subclass, self.device_protocol });
        log.debug("  vendor = 0x{x:0>4}", .{self.vendor});
        log.debug("  product = 0x{x:0>4}", .{self.product});
        log.debug("  max_packet_size = 0x{d}", .{self.max_packet_size});
        log.debug("  usb_standard_compliance = {s}", .{@tagName(@as(SpecRelease, @enumFromInt(self.usb_standard_compliance)))});
        log.debug("  configuration_count = 0x{d}", .{self.configuration_count});
        log.debug("]", .{});
    }

    pub fn fromSlice(buffer: []u8) !*DeviceDescriptor {
        const maybe_device_descriptor: *DeviceDescriptor = @ptrCast(@alignCast(buffer.ptr));
        if (maybe_device_descriptor.header.length != @sizeOf(DeviceDescriptor)) {
            return Descriptor.Error.LengthMismatch;
        }

        if (maybe_device_descriptor.header.descriptor_type != DescriptorType.device)
            return Descriptor.Error.UnexpectedType;

        return maybe_device_descriptor;
    }

    pub fn isHub(self: *const DeviceDescriptor) bool {
        return self.device_class == @intFromEnum(DeviceClass.hub);
    }
};

pub const ConfigurationDescriptor = extern struct {
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
};

pub const InterfaceDescriptor = extern struct {
    header: Header,
    interface_number: u8,
    alternate_setting: u8,
    endpoint_count: u8,
    interface_class: u8,
    interface_subclass: u8,
    interface_protocol: u8,
    interface_string: StringIndex,
};

pub const IsoSynchronizationType = enum(u2) {
    none = 0b00,
    asynchronous = 0b01,
    adaptive = 0b10,
    synchronous = 0b11,
};

pub const IsoUsageType = enum(u2) {
    data = 0b00,
    feedback = 0b01,
    explicit_feedback = 0b10,
    reserved = 0b11,
};

pub const EndpointDescriptor = extern struct {
    header: Header,
    endpoint_address: u8,
    attributes: packed struct {
        transfer_type: TransferType, // 0..1
        iso_synch_type: IsoSynchronizationType, // 2..3
        usage_type: IsoUsageType, // 4..5
        _reserved_0: u2 = 0,
    },
    max_packet_size: u16,
    interval: u8, // polling interval in frames
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
    body: [31]u16,

    pub fn asSlice(self: *const StringDescriptor, allocator: Allocator) ![]u8 {
        const actual_length = (self.header.length - 2) / 2;
        const result = try allocator.alloc(u8, actual_length + 1);
        @memset(result, 0);

        for (0..actual_length) |i| {
            const unicode_char = self.body[i];
            const ascii_char: u8 = @truncate(unicode_char);
            result[i] = ascii_char;
        }
        return result;
    }
};
