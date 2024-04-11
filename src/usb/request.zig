pub const Request = u8;

pub const RequestTypeRecipient = struct {
    pub const device: u5 = 0b00000;
    pub const interface: u5 = 0b00001;
    pub const endpoint: u5 = 0b00010;
    pub const other: u5 = 0b00011;
    // all other bit patterns are reserved
};

pub const RequestTypeType = struct {
    pub const standard: u2 = 0b00;
    pub const class: u2 = 0b01;
    pub const vendor: u2 = 0b10;
    pub const reserved: u2 = 0b11;
};

pub const RequestTypeDirection = struct {
    pub const host_to_device: u1 = 0b0;
    pub const device_to_host: u1 = 0b1;
};

pub const RequestType = packed struct {
    recipient: u5, // 0 .. 4
    type: u2, // 5..6
    transfer_direction: u1, // 7
};

pub fn RT(r: u5, t: u2, d: u1) RequestType {
    return .{ .recipient = r, .type = t, .transfer_direction = d };
}

pub const device_standard_in = RT(RequestTypeRecipient.device, RequestTypeType.standard, RequestTypeDirection.device_to_host);
pub const device_standard_out = RT(RequestTypeRecipient.device, RequestTypeType.standard, RequestTypeDirection.host_to_device);
pub const other_class_in = RT(RequestTypeRecipient.other, RequestTypeType.class, RequestTypeDirection.device_to_host);
pub const other_class_out = RT(RequestTypeRecipient.other, RequestTypeType.class, RequestTypeDirection.host_to_device);
pub const device_class_in = RT(RequestTypeRecipient.device, RequestTypeType.class, RequestTypeDirection.device_to_host);
pub const device_class_out = RT(RequestTypeRecipient.device, RequestTypeType.class, RequestTypeDirection.host_to_device);
pub const interface_class_in = RT(RequestTypeRecipient.interface, RequestTypeType.class, RequestTypeDirection.device_to_host);
pub const interface_class_out = RT(RequestTypeRecipient.interface, RequestTypeType.class, RequestTypeDirection.host_to_device);
