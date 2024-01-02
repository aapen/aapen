/// USB subsystem, hardware agnostic.
///
/// This module contains two things: definitions that come from the
/// USB specification, and the hardware-agnostic portion of USB
/// handling for the kernel.
const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.usb);

const root = @import("root");
const HCI = root.HAL.USBHCI;

const Forth = root.Forth;

const auto = @import("forty/auto.zig");

const synchronize = @import("synchronize.zig");
const Spinlock = synchronize.Spinlock;

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
//pub const setupDescriptorQuery = descriptor.setupDescriptorQuery;

const device = @import("usb/device.zig");
pub const Device = device.Device;
pub const DeviceAddress = device.DeviceAddress;
pub const DeviceClass = device.DeviceClass;
pub const DeviceConfiguration = device.DeviceConfiguration;
pub const DeviceStatus = device.DeviceStatus;
pub const DEFAULT_ADDRESS = device.DEFAULT_ADDRESS;
pub const FIRST_DEDICATED_ADDRESS = device.FIRST_DEDICATED_ADDRESS;
pub const MAX_ADDRESS = device.MAX_ADDRESS;
pub const StandardDeviceRequests = device.StandardDeviceRequests;
pub const STATUS_SELF_POWERED = device.STATUS_SELF_POWERED;
pub const UsbSpeed = device.UsbSpeed;

const driver = @import("usb/driver.zig");
pub const DeviceDriver = driver.DeviceDriver;

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
pub const HubStatus = hub.HubStatus;
pub const PortFeature = hub.PortFeature;
pub const PortStatus = hub.PortStatus;
pub const HubDescriptor = hub.HubDescriptor;
pub const ClassRequestCode = hub.ClassRequest;
//pub const FeatureSelector = hub.FeatureSelector;
pub const TTDirection = hub.TTDirection;
const usb_hub_driver = hub.usb_hub_driver;

const interface = @import("usb/interface.zig");
pub const InterfaceClass = interface.InterfaceClass;
pub const StandardInterfaceRequests = interface.StandardInterfaceRequests;

const language = @import("usb/language.zig");
pub const LangID = language.LangID;

const request = @import("usb/request.zig");
pub const RequestType = request.RequestType;
pub const RequestTypeType = request.RequestTypeType;
pub const RequestTypeRecipient = request.RequestTypeRecipient;
pub const request_type_in = request.standard_device_in;
pub const request_type_out = request.standard_device_out;

const status = @import("usb/status.zig");
pub const Error = status.Error;

const transfer = @import("usb/transfer.zig");
pub const DEFAULT_MAX_PACKET_SIZE = transfer.DEFAULT_MAX_PACKET_SIZE;
pub const PacketSize = transfer.PacketSize;
pub const PID = transfer.PID;
pub const PID2 = transfer.PID2;
pub const SetupPacket = transfer.SetupPacket;
pub const Transfer = transfer.Transfer;
pub const TransferBytes = transfer.TransferBytes;
pub const TransferCompletionStatus = transfer.Transfer.CompletionStatus;
pub const TransferType = transfer.TransferType;

pub const TransferFactory = @import("usb/transfer_factory.zig");

const Self = @This();

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------

pub fn defineModule(forth: *Forth) !void {
    try auto.defineNamespace(Self, "usb.", forth);

    try HCI.defineModule(forth);
    try forth.defineConstant("usbhci", @intFromPtr(&root.hal.usb_hci));
}

// ----------------------------------------------------------------------
// Core subsystem
// ----------------------------------------------------------------------
const Drivers = std.ArrayList(*const DeviceDriver);

var allocator: Allocator = undefined;
var drivers: Drivers = undefined;
var root_hub: ?*Device = undefined;
var bus_lock: Spinlock = undefined;

pub fn init(iop: auto.InteropCall) !void {
    allocator = root.heap.allocator;
    drivers = Drivers.init(allocator);
    bus_lock = Spinlock.initWithTargetLevel("usb bus", true, .FIQ);

    bus_lock.acquire();
    defer bus_lock.release();

    try registerDriver(&usb_hub_driver);
    try root.hal.usb_hci.initialize(iop);
}

pub fn registerDriver(device_driver: *const DeviceDriver) !void {
    try drivers.append(device_driver);
}
