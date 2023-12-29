const descriptor = @import("descriptor.zig");
const ConfigurationDescriptor = descriptor.ConfigurationDescriptor;
const DeviceDescriptor = descriptor.DeviceDescriptor;
const EndpointDescriptor = descriptor.EndpointDescriptor;
const InterfaceDescriptor = descriptor.InterfaceDescriptor;

const driver = @import("driver.zig");
const DeviceDriver = driver.DeviceDriver;

const transfer = @import("transfer.zig");
const setup = transfer.setup;
const SetupPacket = transfer.SetupPacket;
const TransferType = transfer.TransferType;

pub const DeviceAddress = u7;
pub const DEFAULT_ADDRESS: DeviceAddress = 0;
pub const FIRST_DEDICATED_ADDRESS = 1;

pub const MAX_ADDRESS: DeviceAddress = 63;
pub const MAX_INTERFACES: usize = 8;
pub const MAX_ENDPOINTS: usize = 8;

pub const STATUS_SELF_POWERED: u32 = 0b01;
pub const STATUS_REMOTE_WAKEUP: u32 = 0b10;

pub const DeviceStatus = extern struct {
    status: u16 = 0,
};

pub const UsbSpeed = enum {
    Low,
    Full,
    High,
    Super,
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

pub const DeviceState = enum {
    attached,
    detaching,
};

pub const Device = struct {
    in_use: bool = false,
    address: DeviceAddress,
    speed: UsbSpeed,

    /// Hub this is attached to. Null means this is the root hub.
    parent: ?*Device,
    /// Port on the parent hub this is attached to
    parent_port: u32,

    configuration_index: u8,

    device_descriptor: DeviceDescriptor,
    configuration_descriptor: ?*ConfigurationDescriptor,
    interfaces: [MAX_INTERFACES]?*InterfaceDescriptor,
    endpoints: [MAX_INTERFACES][MAX_ENDPOINTS]?*EndpointDescriptor,

    product: []u8,
    configuration: []u8,

    state: DeviceState,

    // the follow members are controlled by the core driver
    driver: *DeviceDriver,
    driver_private: *anyopaque,
};

pub fn setupSetAddress(address: DeviceAddress) SetupPacket {
    return setup(.device, .standard, .host_to_device, @intFromEnum(StandardDeviceRequests.set_address), address, 0, 0);
}

pub fn setupGetConfiguration() SetupPacket {
    return setup(.device, .standard, .device_to_host, @intFromEnum(StandardDeviceRequests.get_configuration), 0, 0, 1);
}

pub fn setupSetConfiguration(config: u16) SetupPacket {
    return setup(.device, .standard, .host_to_device, @intFromEnum(StandardDeviceRequests.set_configuration), config, 0, 0);
}
