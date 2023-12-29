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

pub const standard_device_in = RT(.device, .standard, .device_to_host);
pub const standard_device_out = RT(.device, .standard, .host_to_device);
pub const class_device_in = RT(.other, .standard, .device_to_host);
pub const class_device_out = RT(.other, .standard, .host_to_device);
