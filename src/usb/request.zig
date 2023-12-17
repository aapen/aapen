const descriptor = @import("descriptor.zig");
const DescriptorType = descriptor.DescriptorType;

const device = @import("device.zig");
const DeviceAddress = device.DeviceAddress;

const transaction = @import("transaction.zig");
const setup = transaction.setup;
const SetupPacket = transaction.SetupPacket;

pub const RequestTypeRecipient = enum(u5) {
    device = 0b00000,
    interface = 0b00001,
    endpoint = 0b00010,
    other = 0b00011,
    // all other bit patterns are reserved
};

pub const RequestTypeType = enum(u2) {
    standard = 0b00,
    class = 0b01,
    vendor = 0b10,
    reserved = 0b11,
};

pub const RequestTypeDirection = enum(u1) {
    host_to_device = 0b0,
    device_to_host = 0b1,
};

pub const RequestType = packed struct {
    recipient: RequestTypeRecipient, // 0 .. 4
    type: RequestTypeType, // 5..6
    transfer_direction: RequestTypeDirection, // 7
};

pub fn RT(r: RequestTypeRecipient, t: RequestTypeType, d: RequestTypeDirection) RequestType {
    return .{ .recipient = r, .type = t, .transfer_direction = d };
}

pub const request_type_in = RT(.device, .standard, .device_to_host);
pub const request_type_out = RT(.device, .standard, .host_to_device);

pub const StandardDeviceRequests = enum(u8) {
    get_status = 0x00,
    clear_feature = 0x01,
    set_feature = 0x03,
    set_address = 0x05,
    get_descriptor = 0x06,
    set_descriptor = 0x07,
    get_configuration = 0x08,
    set_configuration = 0x09,
};

pub fn setupDescriptorQuery(descriptor_type: DescriptorType, descriptor_index: u8, lang_id: u16, length: u16) SetupPacket {
    const val: u16 = @as(u16, @intFromEnum(descriptor_type)) << 8 | @as(u8, descriptor_index);
    return setup(.device, .standard, .device_to_host, @intFromEnum(StandardDeviceRequests.get_descriptor), val, lang_id, length);
}

pub fn setupSetAddress(address: device.DeviceAddress) SetupPacket {
    return setup(.device, .standard, .host_to_device, @intFromEnum(StandardDeviceRequests.set_address), address, 0, 0);
}

pub const StandardInterfaceRequests = enum(u8) {
    get_status = 0x00,
    clear_feature = 0x01,
    set_feature = 0x03,
    get_interface = 0x0a,
    set_interface = 0x11,
};

pub const StandardEndpointRequests = enum(u8) {
    get_status = 0x00,
    clear_feature = 0x01,
    set_feature = 0x03,
    synch_frame = 0x12,
};
