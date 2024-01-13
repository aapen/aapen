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

const time = @import("time.zig");

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
pub const DeviceDriver = device.DeviceDriver;
pub const DeviceStatus = device.DeviceStatus;
pub const DEFAULT_ADDRESS = device.DEFAULT_ADDRESS;
pub const FIRST_DEDICATED_ADDRESS = device.FIRST_DEDICATED_ADDRESS;
pub const MAX_ADDRESS = device.MAX_ADDRESS;
pub const StandardDeviceRequests = device.StandardDeviceRequests;
pub const STATUS_SELF_POWERED = device.STATUS_SELF_POWERED;
pub const UsbSpeed = device.UsbSpeed;

const endpoint = @import("usb/endpoint.zig");
pub const EndpointDirection = endpoint.EndpointDirection;
pub const EndpointNumber = endpoint.EndpointNumber;
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
    try auto.defineNamespace(Self, .{.{ "init", "usb-init" }}, forth);

    try HCI.defineModule(forth);
    try forth.defineConstant("usbhci", @intFromPtr(&root.hal.usb_hci));
}

// ----------------------------------------------------------------------
// Core subsystem
// ----------------------------------------------------------------------
const Drivers = std.ArrayList(*const DeviceDriver);
const MAX_DEVICES = 16;

var allocator: Allocator = undefined;
var devices: [MAX_DEVICES]Device = undefined;
var drivers: Drivers = undefined;
var root_hub: ?*Device = undefined;
var bus_lock: Spinlock = undefined;

pub fn init() !void {
    allocator = root.heap.allocator;
    drivers = Drivers.init(allocator);
    bus_lock = Spinlock.initWithTargetLevel("usb bus", true, .FIQ);

    bus_lock.acquire();
    defer bus_lock.release();

    for (0..MAX_DEVICES) |i| {
        devices[i].init();
    }

    try registerDriver(&usb_hub_driver);
    log.debug("registered hub driver", .{});

    try root.hal.usb_hci.initialize();
    log.debug("started host controller", .{});

    const dev0 = try allocateDevice(null);
    errdefer freeDevice(dev0);

    log.debug("attaching root hub", .{});
    if (attachDevice(dev0)) {
        log.debug("usb initialized", .{});
        root_hub = &devices[dev0];
        return;
    } else |err| {
        log.err("usb init failed: {any}", .{err});
        return err;
    }
}

pub fn registerDriver(device_driver: *const DeviceDriver) !void {
    synchronize.criticalEnter(.FIQ);
    defer synchronize.criticalLeave();

    var already_registered = false;
    for (drivers.items) |drv| {
        if (drv == device_driver) {
            log.err("device driver is already registered, skipping it", .{});
            already_registered = true;
            break;
        }
    }

    if (!already_registered) {
        try drivers.append(device_driver);
    }
}

pub fn allocateDevice(parent: ?*Device) !DeviceAddress {
    synchronize.criticalEnter(.FIQ);
    defer synchronize.criticalLeave();

    for (0..MAX_DEVICES) |i| {
        const addr: DeviceAddress = @truncate(i);
        if (!devices[addr].in_use) {
            var dev = &devices[addr];
            dev.in_use = true;
            errdefer dev.in_use = false;
            dev.parent = parent;
            if (parent != null) {
                dev.depth = parent.?.depth + 1;
            }
            dev.state = .attached;
            return addr + 1;
        }
    }

    return Error.TooManyDevices;
}

pub fn freeDevice(devid: DeviceAddress) void {
    synchronize.criticalEnter(.FIQ);
    defer synchronize.criticalLeave();

    var dev = &devices[devid - 1];
    dev.state = .detaching;

    if (dev.driver != null) {
        dev.driver.?.unbind.?(dev);
    }

    dev.deinit();
    dev.in_use = false;
}

pub fn attachDevice(devid: DeviceAddress) !void {
    var dev = &devices[devid - 1];
    // when attaching a device, it will be in the default state:
    // responding to address 0, endpoint 0
    try deviceDescriptorRead(dev);

    dev.device_descriptor.dump();

    log.debug("device descriptor read class {d} subclass {d} protocol {d}", .{ dev.device_descriptor.device_class, dev.device_descriptor.device_subclass, dev.device_descriptor.device_protocol });

    log.debug("assigning address {d}", .{devid});
    try deviceSetAddress(dev, devid);

    log.debug("reading configuration descriptor", .{});
    try deviceConfigurationDescriptorRead(dev);

    dev.configuration.dump();

    const use_config = dev.configuration.configuration_descriptor.configuration_value;
    log.debug("setting device to use configuration {d}", .{use_config});
    try deviceSetConfiguration(dev, use_config);

    var buf: [512]u8 = [_]u8{0} ** 512;
    log.info("attaching {s}", .{dev.description(&buf)});
}

// ----------------------------------------------------------------------
// Transfer handling
// ----------------------------------------------------------------------

// submit a transfer for asynchronous processing
pub fn transferSubmit(xfer: *Transfer) !void {
    // TODO check if the request is already in flight

    // TODO check if the device is being detached

    // TODO track how many requests are pending for a device

    synchronize.criticalEnter(.FIQ);
    defer synchronize.criticalLeave();

    xfer.completion = transferNotify;

    try root.hal.usb_hci.perform(xfer);
}

// callback from the HCD when the transfer has finished
fn transferNotify(xfer: *Transfer) void {
    _ = xfer;
}

pub fn transferAwait(xfer: *Transfer, timeout: u32) !void {
    const deadline = time.deadlineMillis(timeout);

    while (time.ticks() < deadline and xfer.status == .incomplete) {}

    switch (xfer.status) {
        .incomplete => return Error.TransferIncomplete,
        .timeout => return Error.TransferTimeout,
        .unsupported_request => return Error.UnsupportedRequest,
        .protocol_error => return Error.InvalidData,
        inline else => return,
    }
}

// ----------------------------------------------------------------------
// Specific transfers
// ----------------------------------------------------------------------
pub fn deviceDescriptorRead(dev: *Device) !void {
    var xfer = TransferFactory.initDeviceDescriptorTransfer(0, 0, std.mem.asBytes(&dev.device_descriptor));
    xfer.addressTo(dev);

    try transferSubmit(&xfer);
    try transferAwait(&xfer, 100);
}

pub fn deviceSetAddress(dev: *Device, address: DeviceAddress) !void {
    var xfer = TransferFactory.initSetAddressTransfer(address);
    xfer.addressTo(dev);

    try transferSubmit(&xfer);
    try transferAwait(&xfer, 100);

    dev.address = address;
}

pub fn deviceConfigurationDescriptorRead(dev: *Device) !void {
    // first transfer returns the configuration descriptor which
    // includes the total length of the whole configuration tree
    var desc: ConfigurationDescriptor = undefined;
    var xfer = TransferFactory.initConfigurationDescriptorTransfer(0, std.mem.asBytes(&desc));
    xfer.addressTo(dev);

    try transferSubmit(&xfer);
    try transferAwait(&xfer, 100);

    // now allocate enough space for the whole configuration (which
    // includes the interface descriptors and endpoint descriptors)
    const buffer_size = desc.total_length;
    var configuration: []u8 = try allocator.alloc(u8, buffer_size);
    defer allocator.free(configuration);

    xfer = TransferFactory.initConfigurationDescriptorTransfer(0, configuration);
    xfer.addressTo(dev);

    try transferSubmit(&xfer);
    try transferAwait(&xfer, 100);

    dev.configuration = try DeviceConfiguration.initFromBytes(allocator, configuration);
}

pub fn deviceSetConfiguration(dev: *Device, use_config: u8) !void {
    var xfer = TransferFactory.initSetConfigurationTransfer(use_config);
    xfer.addressTo(dev);

    try transferSubmit(&xfer);
    try transferAwait(&xfer, 100);
}
