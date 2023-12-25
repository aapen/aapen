/// USB subsystem, hardware agnostic.
///
/// This module contains two things: definitions that come from the
/// USB specification, and the hardware-agnostic portion of USB
/// handling for the kernel.
pub const Bus = @import("usb/bus.zig");

const descriptor = @import("usb/descriptor.zig");
pub const DescriptorIndex = descriptor.DescriptorIndex;
pub const DEFAULT_DESCRIPTOR_INDEX = descriptor.DEFAULT_DESCRIPTOR_INDEX;
pub const DescriptorType = descriptor.DescriptorType;
pub const Descriptor = descriptor.Descriptor;
pub const DeviceDescriptor = descriptor.DeviceDescriptor;
pub const ConfigurationDescriptor = descriptor.ConfigurationDescriptor;
pub const Header = descriptor.Header;
pub const InterfaceDescriptor = descriptor.InterfaceDescriptor;
pub const IsoSynchronizationType = descriptor.IsoSynchronizationType;
pub const IsoUsageType = descriptor.IsoUsageType;
pub const EndpointDescriptor = descriptor.EndpointDescriptor;
pub const StringDescriptor = descriptor.StringDescriptor;
pub const StringIndex = descriptor.StringIndex;
pub const setupDescriptorQuery = descriptor.setupDescriptorQuery;

const device = @import("usb/device.zig");
pub const DeviceAddress = device.DeviceAddress;
pub const DEFAULT_ADDRESS = device.DEFAULT_ADDRESS;
pub const FIRST_DEDICATED_ADDRESS = device.FIRST_DEDICATED_ADDRESS;
pub const MAX_ADDRESS = device.MAX_ADDRESS;
pub const UsbSpeed = device.UsbSpeed;
pub const StandardDeviceRequests = device.StandardDeviceRequests;
pub const setupSetAddress = device.setupSetAddress;

const endpoint = @import("usb/endpoint.zig");
pub const EndpointDirection = endpoint.EndpointDirection;
pub const EndpointNumber = endpoint.EndpointNumber;
pub const EndpointType = endpoint.EndpointType;
pub const StandardEndpointRequests = endpoint.StandardEndpointRequests;

const function = @import("usb/function.zig");
pub const MAX_FUNCTIONS = function.MAX_FUNCTIONS;

const hub = @import("usb/hub.zig");
pub const Characteristics = hub.Characteristics;
pub const ChangeStatusP = hub.ChangeStatusP;
pub const OvercurrentStatusP = hub.OvercurrentStatusP;
pub const Hub = hub.Hub;
pub const HubStatusAndChangeStatus = hub.HubStatusAndChangeStatus;
pub const PortStatus = hub.PortStatus;
pub const HubDescriptor = hub.HubDescriptor;
pub const ClassRequestCode = hub.ClassRequestCode;
pub const FeatureSelector = hub.FeatureSelector;
pub const TTDirection = hub.TTDirection;

const interface = @import("usb/interface.zig");
pub const InterfaceClass = interface.InterfaceClass;
pub const StandardInterfaceRequests = interface.StandardInterfaceRequests;

const language = @import("usb/language.zig");
pub const LangID = language.LangID;

const request = @import("usb/request.zig");
pub const RequestType = request.RequestType;
pub const request_type_in = request.request_type_in;
pub const request_type_out = request.request_type_out;

const transaction = @import("usb/transaction.zig");
pub const DEFAULT_MAX_PACKET_SIZE = transaction.DEFAULT_MAX_PACKET_SIZE;
pub const SetupPacket = transaction.SetupPacket;
pub const TransactionStage = transaction.TransactionStage;
pub const TransferBytes = transaction.TransferBytes;
pub const TransferType = transaction.TransferType;
pub const PacketSize = transaction.PacketSize;
pub const PID = transaction.PID;
pub const PID2 = transaction.PID2;
