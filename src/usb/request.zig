pub const RequestType = packed struct {
    recipient: enum(u5) {
        device = 0b00000,
        interface = 0b00001,
        endpoint = 0b00010,
        other = 0b00011,
        // all other bit patterns are reserved
    }, // 0 .. 4
    type: enum(u2) {
        standard = 0b00,
        class = 0b01,
        vendor = 0b10,
        reserved = 0b11,
    }, // 5..6
    transfer_direction: enum(u1) {
        host_to_device = 0b0,
        device_to_host = 0b1,
    },
};

pub const request_type_in: RequestType = .{
    .recipient = .device,
    .type = .standard,
    .transfer_direction = .device_to_host,
};

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

pub const TransferType = enum(u2) {
    control = 0b00,
    isochronous = 0b01,
    bulk = 0b10,
    interrupt = 0b11,
};
