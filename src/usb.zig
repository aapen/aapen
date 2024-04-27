/// USB subsystem, hardware agnostic.
///
/// This module contains two things: definitions that come from the
/// USB specification, and the hardware-agnostic portion of USB
/// handling for the kernel.
const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const HCI = root.HAL.USBHCI;

const arch = @import("architecture.zig");
const cpu = arch.cpu;

const Forth = @import("forty/forth.zig").Forth;

const Logger = @import("logger.zig");
pub var log: *Logger = undefined;

const time = @import("time.zig");

const synchronize = @import("synchronize.zig");
const TicketLock = synchronize.TicketLock;

pub usingnamespace @import("usb/spec.zig");
pub usingnamespace @import("usb/descriptor.zig");

const device = @import("usb/device.zig");
pub const Device = device.Device;
pub const DeviceConfiguration = device.DeviceConfiguration;
pub const DeviceDriver = device.DeviceDriver;
pub const DeviceState = device.DeviceState;
pub const DEFAULT_ADDRESS = device.DEFAULT_ADDRESS;
pub const FIRST_DEDICATED_ADDRESS = device.FIRST_DEDICATED_ADDRESS;
pub const MAX_ADDRESS = device.MAX_ADDRESS;
pub const STATUS_SELF_POWERED = device.STATUS_SELF_POWERED;
pub const UsbSpeed = device.UsbSpeed;
pub const FRAMES_PER_MS = device.FRAMES_PER_MS;
pub const UFRAMES_PER_MS = device.UFRAMES_PER_MS;

const hid_keyboard = @import("usb/hid_keyboard.zig");

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
pub const TTDirection = hub.TTDirection;

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
pub const TransferCompletionStatus = transfer.TransferRequest.CompletionStatus;
pub const TransferType = transfer.TransferType;

pub const TransferFactory = @import("usb/transfer_factory.zig");

const Self = @This();

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------

pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(Self, .{
        .{ "initialize", "usb-init" },
        .{ "getDevice", "usb-device" },
    });
    try forth.defineConstant("usbhci", @intFromPtr(root.hal.usb_hci));
    try forth.defineStruct("Device", Device, .{});

    try hid_keyboard.defineModule(forth);
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

// `init` does the allocations and registrations needed, but does not
// activate the hardware
pub fn init() !void {
    log = Logger.init("usb", .info);

    allocator = root.kernel_allocator;
    drivers = Drivers.init(allocator);

    drivers_lock = TicketLock.initWithTargetLevel("usb drivers", true, .FIQ);
    bus_lock = TicketLock.initWithTargetLevel("usb bus", true, .FIQ);

    for (0..MAX_DEVICES) |i| {
        devices[i].init();
    }

    try registerDriver(&hub.driver);
    try registerDriver(&hid_keyboard.driver);

    try initializeDrivers();
}

// `initialize` activates the hardware and does the initial port scan
pub fn initialize() !void {
    try root.hal.usb_hci.initialize();
    log.debug(@src(), "started host controller", .{});

    const dev0 = try allocateDevice(null);
    errdefer freeDevice(dev0);

    log.debug(@src(), "attaching root hub", .{});
    if (attachDevice(dev0, UsbSpeed.Full, null, null)) {
        log.debug(@src(), "usb initialized", .{});
        root_hub = &devices[dev0];
        return;
    } else |err| {
        log.err(@src(), "usb init failed: {any}", .{err});
        return err;
    }
}

pub fn registerDriver(device_driver: *const DeviceDriver) !void {
    drivers_lock.acquire();
    defer drivers_lock.release();

    var already_registered = false;
    for (drivers.items) |drv| {
        if (drv == device_driver) {
            log.err(@src(), "device driver is already registered, skipping it", .{});
            already_registered = true;
            break;
        }
    }

    if (!already_registered) {
        log.debug(@src(), "registering {s}", .{device_driver.name});
        try drivers.append(device_driver);
    }
}

fn initializeDrivers() !void {
    drivers_lock.acquire();
    defer drivers_lock.release();

    for (drivers.items) |drv| {
        drv.initialize(allocator) catch |err| {
            log.err(@src(), "driver {s} initialization error {any}", .{ drv.name, err });
        };
    }
}

pub fn allocateDevice(parent: ?*Device) !Self.DeviceAddress {
    bus_lock.acquire();
    defer bus_lock.release();

    for (0..MAX_DEVICES) |i| {
        const addr: Self.DeviceAddress = @truncate(i);
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

pub fn freeDevice(devid: Self.DeviceAddress) void {
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

pub fn attachDevice(devid: Self.DeviceAddress, speed: UsbSpeed, parent_hub: ?*Hub, parent_port: ?*Hub.Port) !void {
    var dev = &devices[devid - 1];

    // assume the speed detected by the hub this device is attached to
    dev.speed = speed;

    // default to max packet size according to speed until we can read the device
    // descriptor to find the real max packet size.
    dev.device_descriptor.max_packet_size = switch (speed) {
        UsbSpeed.Super => 255, // super speed is supposed to have mps
        // of 512, but we're re-using the descriptor's field which is
        // a u8
        UsbSpeed.High => 64,
        UsbSpeed.Full => 64,
        UsbSpeed.Low => 8,
    };

    log.debug(@src(), "attach device: read device descriptor, irq flags = 0x{x:0>8}", .{arch.cpu.irqFlagsRead()});

    // when attaching a device, it will be in the default state:
    // responding to address 0, endpoint 0
    try deviceDescriptorRead(dev, 8);

    log.debug(@src(), "device descriptor read class {d} subclass {d} protocol {d}", .{ dev.device_descriptor.device_class, dev.device_descriptor.device_subclass, dev.device_descriptor.device_protocol });

    if (parent_hub) |h| {
        try h.portReset(parent_port.?, 10);
        dev.parent_port = parent_port.?.number;
    }

    log.debug(@src(), "assigning address {d}", .{devid});
    try deviceSetAddress(dev, devid);

    // now read the real descriptor
    try deviceDescriptorRead(dev, @sizeOf(Self.DeviceDescriptor));

    log.debug(@src(), "reading configuration descriptor", .{});
    try deviceConfigurationDescriptorRead(dev);

    const use_config = dev.configuration.configuration_descriptor.configuration_value;
    //    log.debug(@src(), "setting device to use configuration {d}", .{use_config});
    try deviceSetConfiguration(dev, use_config);

    var buf: [512]u8 = [_]u8{0} ** 512;
    log.debug(@src(), "attaching {s}", .{dev.description(&buf)});

    try bindDriver(dev);
}

fn bindDriver(dev: *Device) !void {
    if (dev.driver != null) {
        // device already has a driver
        return;
    }

    for (drivers.items) |drv| {
        if (drv.canBind(dev)) {
            log.debug(@src(), "Attempting to bind '{s}' driver to device", .{drv.name});
            if (drv.bind(dev)) {
                var buf: [512]u8 = [_]u8{0} ** 512;
                log.info(@src(), "Bound '{s}' driver to '{s}'", .{ drv.name, dev.description(&buf) });
                return;
            } else |e| {
                switch (e) {
                    error.DeviceUnsupported => {
                        log.debug(@src(), "Driver {s} doesn't support this device", .{drv.name});
                        // move on to the next driver.
                        continue;
                    },
                    else => {
                        log.err(@src(), "Driver bind error {any}", .{e});
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
    const im = cpu.disable();
    defer cpu.restore(im);

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
    log.debug(@src(), "signalling completion semaphore {d}", .{xfer.semaphore.?});
    semaphore.signal(xfer.semaphore.?) catch {
        log.err(@src(), "failed to signal semaphore {?d} on completion of control msg", .{xfer.semaphore});
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
        log.debug(@src(), "freeing semaphore {d}", .{sem});
        semaphore.free(sem) catch |err| {
            log.err(@src(), "semaphore {d} free error: {any}", .{ sem, err });
        };
    }

    log.debug(@src(), "[{d}:{d}] completion semaphore id {d}", .{ dev.address, 0, sem });

    const setup: SetupPacket = SetupPacket.init2(req_type, req_code, val, index, @truncate(data.len));
    var req: *TransferRequest = try allocator.create(TransferRequest);
    req.initControlAllocated(dev, setup, data);

    log.debug(@src(), "[{d}:{d}] req_type 0x{x}, req_code 0x{x}, SETUP contents", .{ dev.address, 0, @as(u8, @bitCast(req_type)), req_code });

    log.sliceDump(@src(), std.mem.asBytes(&req.setup_data));

    req.completion = controlMessageDone;
    req.semaphore = sem;
    try transferSubmit(req);
    // TODO add the ability to time out
    semaphore.wait(sem) catch |err| {
        log.err(@src(), "semaphore {d} wait error: {any}", .{ sem, err });
    };
    log.debug(@src(), "[{d}:{d}] awakened from semaphore.wait", .{ dev.address, 0 });

    if (data.len > 0) {
        log.debug(@src(), "[{d}:{d}] req_type 0x{x}, req_code 0x{x}, received", .{ dev.address, 0, @as(u8, @bitCast(req_type)), req_code });
        log.sliceDump(@src(), data[0..req.actual_size]);
    } else {
        log.debug(@src(), "[{d}:{d}] req_type 0x{x}, req_code 0x{x}, no data expected", .{ dev.address, 0, @as(u8, @bitCast(req_type)), req_code });
    }

    var st = req.status;
    if (st == .ok and req.actual_size != data.len) {
        st = .incomplete;
    }
    req.deinit();
    allocator.destroy(req);
    return st;
}

pub fn deviceDescriptorRead(dev: *Device, maxlen: Self.TransferBytes) !void {
    log.debug(@src(), "[{d}:{d}] read device descriptor (maxlen {d} bytes)", .{ dev.address, 0, maxlen });
    const buffer: []u8 = std.mem.asBytes(&dev.device_descriptor);
    const readlen = @min(maxlen, buffer.len);
    const result = try controlMessage(
        dev,
        Self.USB_REQUEST_GET_DESCRIPTOR, // req
        request_device_standard_in, // req type
        @as(u16, Self.USB_DESCRIPTOR_TYPE_DEVICE) << 8, // value
        Self.USB_LANGID_NONE, // index
        buffer[0..readlen], // data
    );
    if (result == .failed) {
        return Error.TransferFailed;
    }
}

pub fn deviceSetAddress(dev: *Device, address: Self.DeviceAddress) !void {
    log.debug(@src(), "[{d}:{d}] set address {d}", .{ dev.address, 0, address });

    const result = try controlMessage(
        dev,
        Self.USB_REQUEST_SET_ADDRESS, // req
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
    log.debug(@src(), "[{d}:{d}] configuration descriptor read", .{ dev.address, 0 });
    // first transfer returns the configuration descriptor which
    // includes the total length of the whole configuration tree
    var desc: Self.ConfigurationDescriptor = undefined;

    const result = try controlMessage(
        dev,
        Self.USB_REQUEST_GET_DESCRIPTOR,
        request_device_standard_in, // req type
        @as(u16, Self.USB_DESCRIPTOR_TYPE_CONFIGURATION) << 8, // value
        0, // index
        std.mem.asBytes(&desc),
    );
    if (result != .ok) {
        log.debug(@src(), "configuration descriptor read, first read result {s}", .{@tagName(result)});
        return Error.TransferFailed;
    }

    // now allocate enough space for the whole configuration (which
    // includes the interface descriptors and endpoint descriptors)
    const buffer_size = desc.total_length;
    const configuration: []u8 = try allocator.alloc(u8, buffer_size);
    defer allocator.free(configuration);

    const result2 = try controlMessage(
        dev,
        Self.USB_REQUEST_GET_DESCRIPTOR, // req
        request_device_standard_in, // req type
        @as(u16, Self.USB_DESCRIPTOR_TYPE_CONFIGURATION) << 8, // value
        0, // index
        configuration,
    );
    if (result2 != .ok) {
        log.debug(@src(), "configuration descriptor read part 2, second read result {s}", .{@tagName(result2)});
        return Error.TransferFailed;
    }

    dev.configuration = try DeviceConfiguration.initFromBytes(allocator, configuration);
    log.debug(@src(), "{any}", .{dev.configuration});
}

pub fn deviceSetConfiguration(dev: *Device, use_config: u8) !void {
    log.debug(@src(), "[{d}:{d}] set configuration {d}", .{ dev.address, 0, use_config });

    _ = try controlMessage(
        dev,
        Self.USB_REQUEST_SET_CONFIGURATION, // req
        request_device_standard_out, // req type
        use_config, // value
        0, // index (not used for this transfer)
        &.{}, // data (not used for this transfer)
    );
}

pub fn deviceGetStringDescriptor(dev: *Device, index: Self.StringIndex, lang_id: u16, buffer: []u8) !void {
    log.debug(@src(), "[{d}:{d}] get string descriptor {d}", .{ dev.address, 0, index });

    _ = try controlMessage(
        dev,
        Self.USB_REQUEST_GET_DESCRIPTOR, // req
        request_device_standard_in, // req type
        @as(u16, Self.USB_DESCRIPTOR_TYPE_STRING) << 8 | index,
        lang_id,
        buffer,
    );
}
