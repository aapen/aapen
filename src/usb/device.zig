pub const DeviceAddress = u7;
pub const DEFAULT_ADDRESS: DeviceAddress = 0;
pub const FIRST_DEDICATED_ADDRESS = 1;
pub const MAX_ADDRESS: DeviceAddress = 63;

pub const UsbSpeed = enum {
    Low,
    Full,
    High,
    Super,
};

/// See https://www.usb.org/defined-class-codes
pub const DeviceClass = enum(u8) {
    interface_specific = 0x00,
    audio = 0x01,
    cdc_control = 0x02,
    hid = 0x03,
    physical = 0x05,
    image = 0x06,
    printer = 0x07,
    mass_storage = 0x08,
    hub = 0x09,
    cdc_data = 0x0a,
    smart_card = 0x0b,
    content_security = 0x0d,
    video = 0x0e,
    personal_healthcare = 0x0f,
    audio_video = 0x10,
    billboard = 0x11,
    type_c_bridge = 0x12,
    bulk_display = 0x13,
    mctp_over_usb = 0x14,
    i3c = 0x3c,
    diagnostic = 0xdc,
    wireless_controller = 0xe0,
    miscellaneous = 0xef,
    application_specific = 0xfe,
    vendor_specific = 0xff,
};

pub const HubProtocol = enum(u8) {
    full_speed_hub = 0x00,
    high_speed_hub_single_tt = 0x01,
    high_speed_hub_multiple_tt = 0x02,
};

/// See https://www.usb.org/sites/default/files/documents/hid1_11.pdf,
/// page 9
pub const HidProtocol = enum(u8) {
    none = 0x00,
    keyboard = 0x01,
    mouse = 0x02,
};
