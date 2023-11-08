/// High level interface to USB devices
///

// ----------------------------------------------------------------------
// Host, Device, Endpoint, Transfers
// ----------------------------------------------------------------------

// TODO all of it

// ----------------------------------------------------------------------
// Definitions from USB spec: Constants, Structures, and Packet Definitions
// ----------------------------------------------------------------------

pub const DEFAULT_MAX_PACKET_SIZE = 8;
pub const FIRST_DEDICATED_ADDRESS = 1;
pub const MAX_FUNCTIONS = 10;

pub const Address = u8;
pub const DEFAULT_ADDRESS: Address = 0;
pub const MAX_ADDRESS: Address = 63;

/// Index of a string descriptor
pub const StringIndex = u8;

/// BCD coded number
pub const BCD = u16;

/// Assigned ID number
pub const ID = u16;

pub const PID = enum {
    Setup,
    Data0,
    Data1,
};

pub const UsbSpeed = enum {
    Low,
    Full,
    High,
    Super,
};

pub const SetupPacket = extern struct {
    request_type: packed struct {
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
    },
    request: u8,
    value: u16,
    index: u16,
    length: u16,
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

pub const RequestType = enum(u8) {
    out = 0,
    in = 0x80,
    class = 0x20,
    vendor = 0x40,
};

pub const DescriptorType = enum(u8) {
    // general
    device = 1,
    configuration = 2,
    string = 3,
    interface = 4,
    endpoint = 5,

    // class specific
    class_interface = 36,
    class_endpoint = 37,
};

pub const DEFAULT_DESCRIPTOR_INDEX = 0;

pub const DeviceDescriptor = extern struct {
    length: u8,
    descriptor_type: DescriptorType,
    usb_standard_compliance: BCD,
    device_class: u8,
    device_subclass: u8,
    device_protocol: u8,
    max_packet_size: u8,
    vendor: ID,
    product: ID,
    device_release: BCD,
    manufacturer_name: StringIndex,
    product_name: StringIndex,
    serial_number: StringIndex,
    configuration_count: u8,
};

pub const ConfigurationDescriptor = extern struct {
    length: u8,
    descriptor_type: DescriptorType,
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
    length: u8,
    descriptor_type: DescriptorType,
    interface_number: u8,
    alternate_setting: u8,
    endpoint_count: u8,
    interface_class: u8,
    interface_subclass: u8,
    interface_protocol: u8,
    interface_string: StringIndex,
};

pub const TransferType = enum(u2) {
    control = 0b00,
    isochronous = 0b01,
    bulk = 0b10,
    interrupt = 0b11,
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
    length: u8,
    descriptor_type: DescriptorType,
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
    length: u8,
    descriptor_type: DescriptorType,
    // remaining bytes (length - 2 / 2) consists of u16's with the
    // language codes of each language this string is available in.
};

pub const Descriptor = extern union {
    header: packed struct {
        length: u8,
        descriptor_type: DescriptorType,
    },
    configuration: ConfigurationDescriptor,
    interface: InterfaceDescriptor,
    endpoint: EndpointDescriptor,
    string: StringDescriptor,
};

pub const EndpointType = enum {
    Control,
    Bulk,
    Interrupt,
    Isochronous,
};
