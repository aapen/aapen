// Placeholder for when I know how to separate the controller-specific
// portions of USB from the generic device model and protocol.

const device = @import("usb/device.zig");
pub const DeviceAddress = device.DeviceAddress;
pub const DEFAULT_ADDRESS = device.DEFAULT_ADDRESS;
pub const FIRST_DEDICATED_ADDRESS = device.FIRST_DEDICATED_ADDRESS;
pub const MAX_ADDRESS = device.MAX_ADDRESS;

const endpoint = @import("usb/endpoint.zig");
pub const EndpointDirection = endpoint.EndpointDirection;
pub const EndpointNumber = endpoint.EndpointNumber;
pub const EndpointType = endpoint.EndpointType;

const request = @import("usb/request.zig");
pub const RequestType = request.RequestType;
pub const request_type_in = request.request_type_in;
pub const StandardDeviceRequests = request.StandardDeviceRequests;
pub const StandardInterfaceRequests = request.StandardInterfaceRequests;
pub const StandardEndpointRequests = request.StandardEndpointRequests;
pub const TransferType = request.TransferType;

const descriptor = @import("usb/descriptor.zig");
pub const DescriptorIndex = descriptor.DescriptorIndex;
pub const DEFAULT_DESCRIPTOR_INDEX = descriptor.DEFAULT_DESCRIPTOR_INDEX;
pub const DescriptorType = descriptor.DescriptorType;
pub const Descriptor = descriptor.Descriptor;
pub const descriptorExpectedSize = descriptor.descriptorExpectedSize;
pub const DeviceDescriptor = descriptor.DeviceDescriptor;
pub const ConfigurationDescriptor = descriptor.ConfigurationDescriptor;
pub const InterfaceDescriptor = descriptor.InterfaceDescriptor;
pub const IsoSynchronizationType = descriptor.IsoSynchronizationType;
pub const IsoUsageType = descriptor.IsoUsageType;
pub const EndpointDescriptor = descriptor.EndpointDescriptor;
pub const StringDescriptor = descriptor.StringDescriptor;

const transaction = @import("usb/transaction.zig");
pub const TransactionStage = transaction.TransactionStage;

pub const TransferBytes = u19;
pub const PacketSize = u11;
pub const DEFAULT_MAX_PACKET_SIZE = 8;
pub const MAX_FUNCTIONS = 10;

pub const PID = enum(u8) {
    Setup,
    Data0,
    Data1,
};

pub const PID2 = enum(u4) {
    token_out = 0b0001,
    token_in = 0b1001,
    token_sof = 0b0101,
    token_setup = 0b1101,
    data_data0 = 0b0011,
    data_data1 = 0b1011,
    data_data2 = 0b0111,
    data_mdata = 0b1111,
    handshake_ack = 0b0010,
    handshake_nak = 0b1010,
    handshake_stall = 0b1110,
    handshake_nyet = 0b0110,
    special_preamble_or_err = 0b1100,
    special_split = 0b1000,
    special_ping = 0b0100,
};

pub const UsbSpeed = enum {
    Low,
    Full,
    High,
    Super,
};
