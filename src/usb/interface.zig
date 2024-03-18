pub const StandardInterfaceRequests = struct {
    pub const get_status: u8 = 0x00;
    pub const clear_feature: u8 = 0x01;
    pub const set_feature: u8 = 0x03;
    pub const get_interface: u8 = 0x0a;
    pub const set_interface: u8 = 0x11;
};

pub const InterfaceClass = struct {
    pub const reserved: u8 = 0x0;
    pub const audio: u8 = 0x1;
    pub const communications: u8 = 0x2;
    pub const hid: u8 = 0x3;
    pub const physical: u8 = 0x5;
    pub const image: u8 = 0x6;
    pub const printer: u8 = 0x7;
    pub const mass_storage: u8 = 0x8;
    pub const hub: u8 = 0x9;
    pub const cdc_data: u8 = 0xa;
    pub const smart_card: u8 = 0xb;
    pub const content_security: u8 = 0xd;
    pub const video: u8 = 0xe;
    pub const personal_health_care: u8 = 0xf;
    pub const audio_video: u8 = 0x10;
    pub const diagnostic_device: u8 = 0xdc;
    pub const wireless_controller: u8 = 0xe0;
    pub const miscellaneous: u8 = 0xef;
    pub const application_specific: u8 = 0xfe;
    pub const vendor_specific: u8 = 0xff;
};
