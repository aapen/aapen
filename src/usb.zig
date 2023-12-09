// Placeholder for when I know how to separate the controller-specific
// portions of USB from the generic device model and protocol.

const endpoint = @import("usb/endpoint.zig");
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
pub const DeviceDescriptor = descriptor.DeviceDescriptor;
pub const ConfigurationDescriptor = descriptor.ConfigurationDescriptor;
pub const InterfaceDescriptor = descriptor.InterfaceDescriptor;
pub const IsoSynchronizationType = descriptor.IsoSynchronizationType;
pub const IsoUsageType = descriptor.IsoUsageType;
pub const EndpointDescriptor = descriptor.EndpointDescriptor;
pub const StringDescriptor = descriptor.StringDescriptor;

pub const Address = u8;
pub const DEFAULT_ADDRESS: Address = 0;
pub const FIRST_DEDICATED_ADDRESS = 1;
pub const MAX_ADDRESS: Address = 63;

pub const DEFAULT_MAX_PACKET_SIZE = 8;
pub const MAX_FUNCTIONS = 10;

pub const PID = enum(u8) {
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
