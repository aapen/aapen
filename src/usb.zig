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

const arch = @import("architecture.zig");

const forty = @import("forty/forth.zig");
const Forth = forty.Forth;

const time = @import("time.zig");

const synchronize = @import("synchronize.zig");
const TicketLock = synchronize.TicketLock;

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
pub const FRAMES_PER_MS = device.FRAMES_PER_MS;
pub const UFRAMES_PER_MS = device.UFRAMES_PER_MS;

const endpoint = @import("usb/endpoint.zig");
pub const EndpointDirection = endpoint.EndpointDirection;
pub const EndpointNumber = endpoint.EndpointNumber;

const function = @import("usb/function.zig");
pub const MAX_FUNCTIONS = function.MAX_FUNCTIONS;

const hub = @import("usb/hub.zig");
pub const Characteristics = hub.Characteristics;
pub const ChangeStatusP = hub.ChangeStatusP;
pub const OvercurrentStatusP = hub.OvercurrentStatusP;
pub const Hub = hub.Hub;
pub const HubFeature = hub.HubFeature;
pub const HubStatus = hub.HubStatus;
pub const PortFeature = hub.PortFeature;
pub const PortStatus = hub.PortStatus;
pub const HubDescriptor = hub.HubDescriptor;
pub const ClassRequest = hub.ClassRequest;
//pub const FeatureSelector = hub.FeatureSelector;
pub const TTDirection = hub.TTDirection;
const usb_hub_driver = hub.usb_hub_driver;

const interface = @import("usb/interface.zig");
pub const InterfaceClass = interface.InterfaceClass;
pub const StandardInterfaceRequests = interface.StandardInterfaceRequests;

const language = @import("usb/language.zig");
pub const LangID = language.LangID;

const request = @import("usb/request.zig");
pub const Request = request.Request;
pub const RequestType = request.RequestType;
pub const RequestTypeDirection = request.RequestTypeDirection;
pub const RequestTypeType = request.RequestTypeType;
pub const RequestTypeRecipient = request.RequestTypeRecipient;
pub const request_device_standard_in = request.device_standard_in;
pub const request_device_standard_out = request.device_standard_out;

const semaphore = @import("semaphore.zig");
const SID = semaphore.SID;

const status = @import("usb/status.zig");
pub const Error = status.Error;

const transfer = @import("usb/transfer.zig");
pub const DEFAULT_MAX_PACKET_SIZE = transfer.DEFAULT_MAX_PACKET_SIZE;
pub const PacketSize = transfer.PacketSize;
pub const PID2 = transfer.PID2;
pub const SetupPacket = transfer.SetupPacket;
pub const TransferRequest = transfer.TransferRequest;
pub const TransferBytes = transfer.TransferBytes;
pub const TransferCompletionStatus = transfer.TransferRequest.CompletionStatus;
pub const TransferType = transfer.TransferType;

pub const TransferFactory = @import("usb/transfer_factory.zig");

const Self = @This();

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------

pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(Self, .{
        .{ "init", "usb-init" },
        .{ "getDevice", "usb-device" },
    });
    try forth.defineConstant("usbhci", @intFromPtr(root.hal.usb_hci));
    try forth.defineStruct("Device", Device, .{});

    try root.HAL.USBHCI.defineModule(forth);
}

pub fn getDevice(id: u64) ?*Device {
    if (id < MAX_DEVICES and devices[id].state != .unconfigured) {
        return &devices[id];
    } else {
        return null;
    }
}

// ----------------------------------------------------------------------
// Core subsystem
// ----------------------------------------------------------------------
const Drivers = std.ArrayList(*const DeviceDriver);
const MAX_DEVICES = 16;

pub var allocator: Allocator = undefined;
pub var devices: [MAX_DEVICES]Device = undefined;
var drivers: Drivers = undefined;
var drivers_lock: TicketLock = undefined;
var root_hub: ?*Device = undefined;
var bus_lock: TicketLock = undefined;

pub fn init() !void {
    allocator = root.kernel_allocator;
    drivers = Drivers.init(allocator);

    drivers_lock = TicketLock.initWithTargetLevel("usb drivers", true, .FIQ);
    bus_lock = TicketLock.initWithTargetLevel("usb bus", true, .FIQ);

    for (0..MAX_DEVICES) |i| {
        devices[i].init();
    }

    try hub.initialize(allocator);

    try registerDriver(&usb_hub_driver);
    log.debug("registered hub driver", .{});

    try root.hal.usb_hci.initialize(allocator);
    log.debug("started host controller", .{});

    const dev0 = try allocateDevice(null);
    errdefer freeDevice(dev0);

    log.debug("attaching root hub", .{});
    if (attachDevice(dev0, UsbSpeed.High)) {
        log.debug("usb initialized", .{});
        root_hub = &devices[dev0];
        return;
    } else |err| {
        log.err("usb init failed: {any}", .{err});
        return err;
    }
}

pub fn registerDriver(device_driver: *const DeviceDriver) !void {
    drivers_lock.acquire();
    defer drivers_lock.release();

    var already_registered = false;
    for (drivers.items) |drv| {
        if (drv == device_driver) {
            log.err("device driver is already registered, skipping it", .{});
            already_registered = true;
            break;
        }
    }

    if (!already_registered) {
        log.info("registering {s}", .{device_driver.name});
        try drivers.append(device_driver);
    }
}

pub fn allocateDevice(parent: ?*Device) !DeviceAddress {
    bus_lock.acquire();
    defer bus_lock.release();

    for (0..MAX_DEVICES) |i| {
        const addr: DeviceAddress = @truncate(i);
        if (!devices[addr].in_use) {
            var dev = &devices[addr];
            dev.in_use = true;
            //            dev.speed = UsbSpeed.High;

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
    bus_lock.acquire();
    defer bus_lock.release();

    var dev = &devices[devid - 1];
    dev.state = .detaching;

    if (dev.driver != null) {
        dev.driver.?.unbind.?(dev);
    }

    dev.deinit();
    dev.state = .unconfigured;
    dev.in_use = false;
}

pub fn attachDevice(devid: DeviceAddress, speed: UsbSpeed) !void {
    var dev = &devices[devid - 1];

    // assume the speed detected by the hub this device is attached to
    dev.speed = speed;

    // default to max packet size of 8 until we can read the device
    // descriptor to find the real max packet size.
    dev.device_descriptor.max_packet_size = 8;

    log.debug("attach device: read device descriptor, irq flags = 0x{x:0>8}", .{arch.cpu.irqFlagsRead()});

    // when attaching a device, it will be in the default state:
    // responding to address 0, endpoint 0
    try deviceDescriptorRead(dev, 8);

    // dev.device_descriptor.dump();

    log.debug("device descriptor read class {d} subclass {d} protocol {d}", .{ dev.device_descriptor.device_class, dev.device_descriptor.device_subclass, dev.device_descriptor.device_protocol });

    log.debug("assigning address {d}", .{devid});
    try deviceSetAddress(dev, devid);

    // now read the real descriptor
    try deviceDescriptorRead(dev, @sizeOf(DeviceDescriptor));

    log.debug("reading configuration descriptor", .{});
    try deviceConfigurationDescriptorRead(dev);

    // dev.configuration.dump();

    const use_config = dev.configuration.configuration_descriptor.configuration_value;
    //    log.debug("setting device to use configuration {d}", .{use_config});
    try deviceSetConfiguration(dev, use_config);

    var buf: [512]u8 = [_]u8{0} ** 512;
    log.debug("attaching {s}", .{dev.description(&buf)});

    try bindDriver(dev);
}

fn bindDriver(dev: *Device) !void {
    if (dev.driver != null) {
        // device already has a driver
        return;
    }

    for (drivers.items) |drv| {
        if (drv.canBind(dev)) {
            log.debug("Attempting to bind driver {s} to device", .{drv.name});
            if (drv.bind(dev)) {
                var buf: [512]u8 = [_]u8{0} ** 512;
                log.info("Bound driver {s} to {s}", .{ drv.name, dev.description(&buf) });
                return;
            } else |e| {
                switch (e) {
                    error.DeviceUnsupported => {
                        log.debug("Driver {s} doesn't support this device", .{drv.name});
                        // move on to the next driver.
                        continue;
                    },
                    else => {
                        log.err("Driver bind error {any}", .{e});
                        return e;
                    },
                }
            }
        }
    }
}

// ----------------------------------------------------------------------
// Transfer handling
// ----------------------------------------------------------------------

// submit a transfer for asynchronous processing
pub fn transferSubmit(req: *TransferRequest) !void {
    // check if the device is being detached or has not been configured
    if (req.device) |dev| {
        switch (dev.state) {
            .detaching => return Error.DeviceDetaching,
            .unconfigured => return Error.DeviceUnconfigured,
            inline else => {},
        }
    } else {
        return Error.NoDevice;
    }

    // TODO track how many requests are pending for a device
    try root.hal.usb_hci.perform(req);
}

fn controlMessageDone(xfer: *TransferRequest) void {
    log.debug("signalling completion semaphore {d}", .{xfer.semaphore.?});
    semaphore.signal(xfer.semaphore.?) catch {
        log.err("failed to signal semaphore {?d} on completion of control msg", .{xfer.semaphore});
    };
}

// ----------------------------------------------------------------------
// Specific transfers
// ----------------------------------------------------------------------
pub fn controlMessage(
    dev: *Device,
    req_code: Request,
    req_type: RequestType,
    val: u16,
    index: u16,
    data: []u8,
) !TransferRequest.CompletionStatus {
    const sem: SID = try semaphore.create(0);
    defer {
        semaphore.free(sem) catch |err| {
            log.err("semaphore {d} free error: {any}", .{ sem, err });
        };
    }

    log.debug("[{d}:{d}] completion semaphore id {d}", .{ dev.address, 0, sem });

    const setup: SetupPacket = SetupPacket.init2(req_type, req_code, val, index, @truncate(data.len));
    var req: *TransferRequest = try allocator.create(TransferRequest);
    req.initControlAllocated(dev, setup, data);

    const debug = @import("debug.zig");
    log.debug("[{d}:{d}] req_type 0x{x}, req_code 0x{x}, SETUP contents", .{ dev.address, 0, @as(u8, @bitCast(req_type)), req_code });

    debug.sliceDump(std.mem.asBytes(&req.setup_data));

    req.completion = controlMessageDone;
    req.semaphore = sem;
    try transferSubmit(req);
    // TODO add the ability to time out
    semaphore.wait(sem) catch |err| {
        log.err("semaphore {d} wait error: {any}", .{ sem, err });
    };

    if (data.len > 0) {
        log.debug("[{d}:{d}] req_type 0x{x}, req_code 0x{x}, received", .{ dev.address, 0, @as(u8, @bitCast(req_type)), req_code });
        debug.sliceDump(data[0..req.actual_size]);
    } else {
        log.debug("[{d}:{d}] req_type 0x{x}, req_code 0x{x}, no data expected", .{ dev.address, 0, @as(u8, @bitCast(req_type)), req_code });
    }

    var st = req.status;
    if (st == .ok and req.actual_size != data.len) {
        st = .incomplete;
    }
    req.deinit();
    allocator.destroy(req);
    return st;
}

pub fn deviceDescriptorRead(dev: *Device, maxlen: TransferBytes) !void {
    log.debug("[{d}:{d}] read device descriptor (maxlen {d} bytes)", .{ dev.address, 0, maxlen });
    const buffer: []u8 = std.mem.asBytes(&dev.device_descriptor);
    const readlen = @min(maxlen, buffer.len);
    const result = try controlMessage(
        dev,
        StandardDeviceRequests.get_descriptor, //req
        request_device_standard_in, // req type
        @as(u16, DescriptorType.device) << 8, // value
        LangID.none, // index
        buffer[0..readlen], // data
    );
    if (result == .failed) {
        return Error.TransferFailed;
    }
}

pub fn deviceSetAddress(dev: *Device, address: DeviceAddress) !void {
    log.debug("[{d}:{d}] set address {d}", .{ dev.address, 0, address });

    const result = try controlMessage(
        dev,
        StandardDeviceRequests.set_address, // req
        request_device_standard_out, // req type
        address, // value
        0, // index (not used for this transfer)
        &.{}, // data (not used for this transfer)
    );

    if (result == .failed) {
        return Error.TransferFailed;
    }

    dev.address = address;
}

pub fn deviceConfigurationDescriptorRead(dev: *Device) !void {
    log.debug("[{d}:{d}] configuration descriptor read", .{ dev.address, 0 });
    // first transfer returns the configuration descriptor which
    // includes the total length of the whole configuration tree
    var desc: ConfigurationDescriptor = undefined;

    const result = try controlMessage(
        dev,
        StandardDeviceRequests.get_descriptor, // req
        request_device_standard_in, // req type
        @as(u16, DescriptorType.configuration) << 8, // value
        0, // index
        std.mem.asBytes(&desc),
    );
    if (result != .ok) {
        log.debug("configuration descriptor read, first read result {s}", .{@tagName(result)});
        return Error.TransferFailed;
    }

    // now allocate enough space for the whole configuration (which
    // includes the interface descriptors and endpoint descriptors)
    const buffer_size = desc.total_length;
    const configuration: []u8 = try allocator.alloc(u8, buffer_size);
    defer allocator.free(configuration);

    const result2 = try controlMessage(
        dev,
        StandardDeviceRequests.get_descriptor, // req
        request_device_standard_in, // req type
        @as(u16, DescriptorType.configuration) << 8, // value
        0, // index
        configuration,
    );
    if (result2 != .ok) {
        log.debug("configuration descriptor read part 2, second read result {s}", .{@tagName(result2)});
        return Error.TransferFailed;
    }

    dev.configuration = try DeviceConfiguration.initFromBytes(allocator, configuration);
    dev.configuration.dump();
}

pub fn deviceSetConfiguration(dev: *Device, use_config: u8) !void {
    log.debug("[{d}:{d}] set configuration {d}", .{ dev.address, 0, use_config });

    _ = try controlMessage(
        dev,
        StandardDeviceRequests.set_configuration, // req
        request_device_standard_out, // req type
        use_config, // value
        0, // index (not used for this transfer)
        &.{}, // data (not used for this transfer)
    );
}

pub fn deviceGetStringDescriptor(dev: *Device, index: StringIndex, lang_id: u16, buffer: []u8) !void {
    log.debug("[{d}:{d}] get string descriptor {d}", .{ dev.address, 0, index });

    _ = try controlMessage(
        dev,
        StandardDeviceRequests.get_descriptor, // req
        request_device_standard_in, // req type
        @as(u16, DescriptorType.string) << 8 | index,
        lang_id,
        buffer,
    );
}
