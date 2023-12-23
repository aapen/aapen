/// High-level description of a configuration
/// This is created from the configuration and interface descriptors
/// returned by the low level interface
const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
pub const HCI = root.HAL.USBHCI;
pub const Device = HCI.Device;

const descriptor = @import("descriptor.zig");
const ConfigurationDescriptor = descriptor.ConfigurationDescriptor;
const DescriptorType = descriptor.DescriptorType;
const Header = descriptor.Header;
const InterfaceDescriptor = descriptor.InterfaceDescriptor;

pub const Error = error{
    ParseError,
};

pub const Interface = struct {
    name: []const u8,
    interface_number: u8,
    endpoint_count: u8,
    class: u8,
    subclass: u8,
    protocol: u8,
};

pub const Configuration = struct {
    name: []u8,
    interfaces: []Interface,
    configuration_id: u8,
    self_powered: bool,
    remote_wakeup: bool,
    power_max: u8,

    pub fn parseConfiguration(allocator: Allocator, host: *HCI, buffer: []const u8) !*Configuration {
        var self = try allocator.create(Configuration);
        errdefer allocator.destroy(self);

        var offset = 0;
        const config_desc = try sliceAs(ConfigurationDescriptor, DescriptorType.configuration, buffer);
        offset += @sizeOf(ConfigurationDescriptor);

        // get the configuration name
        self.name = host.stringQuery(config_desc.configuration);
        self.configuration_id = config_desc.configuration_value;
        self.endpoint_count = config_desc.endpoint_count;
        self.self_powered = config_desc.attributes.self_powered == 1;
        self.remote_wakeup = config_desc.attributes.remote_wakeup == 1;
        self.power_max = config_desc.power_max;

        // Look for interface descriptors following the configuration
        // descriptor
        self.interfaces = try allocator.alloc(
        for (0..config_desc.interface_count) |iface_num| {
            _ = iface_num;

            const iface_desc = try sliceAs(InterfaceDescriptor, DescriptorType.interface, buffer[offset..]);
            offset += @sizeOf(iface_desc);


        }

        return self;
    }

    fn sliceAs(comptime T: type, expected_type: DescriptorType, buffer: []u8) !T {
        const expected_size = @sizeOf(T);

        // Buffer must be at least big enough to hold the header
        if (buffer.len < @sizeOf(Header)) return Error.ParseError;

        const header = std.mem.bytesAsValue(Header, buffer[0..@sizeOf(Header)]);

        // Buffer must be at least as big as the type we're trying to
        // extract
        if (buffer.len < header.length or buffer.len < expected_size) return Error.ParseError;

        // The descriptor type must be the one we expect
        if (header.descriptor_type != expected_type) return Error.ParseError;

        return std.mem.bytesAsValue(T, buffer[0..expected_size]);
    }
};
