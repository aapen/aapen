/// USB subsystem, hardware agnostic.
///
/// This module contains two things: definitions that come from the
/// USB specification, and the hardware-agnostic portion of USB
/// handling for the kernel.
const std = @import("std");

const root = @import("root");
const HCI = root.HAL.USBHCI;

const arch = @import("architecture.zig");
const cpu = arch.cpu;

const ChannelSet = @import("channel_set.zig");

const Forth = @import("forty/forth.zig").Forth;

const Logger = @import("logger.zig");
pub var log: *Logger = undefined;

const time = @import("time.zig");

const semaphore = @import("semaphore.zig");
const SID = semaphore.SID;

const synchronize = @import("synchronize.zig");
const TicketLock = synchronize.TicketLock;

pub usingnamespace @import("usb/spec.zig");
pub usingnamespace @import("usb/core.zig");
pub usingnamespace @import("usb/device.zig");
pub usingnamespace @import("usb/status.zig");
pub usingnamespace @import("usb/transfer.zig");

const hid_keyboard = @import("usb/hid_keyboard.zig");

const hub = @import("usb/hub.zig");

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
    try forth.defineStruct("Device", Self.Device, .{});

    try hid_keyboard.defineModule(forth);
    try HCI.defineModule(forth);
}

pub fn getDevice(id: u64) ?*Self.Device {
    if (id < MAX_DEVICES and devices[id].state != .unconfigured) {
        return &devices[id];
    } else {
        return null;
    }
}

// ----------------------------------------------------------------------
// Core subsystem
// ----------------------------------------------------------------------
const Drivers = std.ArrayList(*const Self.DeviceDriver);

const MAX_DEVICES = 16;
const DeviceAlloc = ChannelSet.init("devices", Self.DeviceAddress, MAX_DEVICES);

pub var devices: [MAX_DEVICES]Self.Device = init: {
    var initial_value: [MAX_DEVICES]Self.Device = undefined;
    for (&initial_value) |*d| {
        d.init();
    }
    break :init initial_value;
};
var devices_allocated: DeviceAlloc = .{};

var allocator: std.mem.Allocator = undefined;
var drivers: Drivers = undefined;
var drivers_lock: TicketLock = undefined;
var root_hub: ?*Self.Device = undefined;
var bus_lock: TicketLock = undefined;

// `init` does the allocations and registrations needed, but does not
// activate the hardware
pub fn init() !void {
    log = Logger.init("usb", .info);

    allocator = root.kernel_allocator;
    drivers = Drivers.init(allocator);
    Self.initCore(allocator);

    drivers_lock = TicketLock.initWithTargetLevel("usb drivers", true, .FIQ);
    bus_lock = TicketLock.initWithTargetLevel("usb bus", true, .FIQ);

    try registerDriver(&hub.driver);
    try registerDriver(&hid_keyboard.driver);

    try initializeDrivers();
}

// `initialize` activates the hardware and does the initial port scan
pub fn initialize() !void {
    try root.hal.usb_hci.initialize();
    log.debug(@src(), "started host controller", .{});

    const dev0 = try deviceAlloc(null);
    errdefer deviceFree(dev0);

    log.debug(@src(), "attaching root hub", .{});

    attachDevice(dev0, Self.UsbSpeed.Full, null, null) catch |err| {
        log.err(@src(), "usb init failed: {any}", .{err});
        return err;
    };

    log.debug(@src(), "usb initialized", .{});
    root_hub = &devices[dev0];
}

pub fn registerDriver(device_driver: *const Self.DeviceDriver) !void {
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

pub fn deviceAlloc(parent: ?*Self.Device) !Self.DeviceAddress {
    bus_lock.acquire();
    defer bus_lock.release();

    const addr: Self.DeviceAddress = try devices_allocated.allocate();
    var dev = &devices[addr];
    dev.in_use = true;
    dev.parent = parent;
    if (parent != null) {
        dev.depth = parent.?.depth + 1;
    }
    dev.state = .attached;
    return addr + 1;
}

pub fn deviceFree(devid: Self.DeviceAddress) void {
    bus_lock.acquire();
    defer bus_lock.release();

    const devindex = devid - 1;
    var dev = &devices[devindex];
    dev.state = .detaching;

    if (dev.driver != null) {
        dev.driver.?.unbind.?(dev);
    }

    dev.deinit();
    dev.state = .unconfigured;
    dev.in_use = false;
    devices_allocated.free(devindex);
}

pub fn attachDevice(devid: Self.DeviceAddress, speed: Self.UsbSpeed, parent_hub: ?*hub.Hub, parent_port: ?*hub.Hub.Port) !void {
    var dev = &devices[devid - 1];

    // assume the speed detected by the hub this device is attached to
    dev.speed = speed;

    // default to max packet size according to speed until we can read the device
    // descriptor to find the real max packet size.
    dev.device_descriptor.max_packet_size = switch (speed) {
        // super speed is supposed to have mps of 512, but we're
        // re-using the descriptor's field which is a u8
        Self.UsbSpeed.Super => 255,
        Self.UsbSpeed.High => 64,
        Self.UsbSpeed.Full => 64,
        Self.UsbSpeed.Low => 8,
    };

    log.debug(@src(), "attach device: read device descriptor, irq flags = 0x{x:0>8}", .{arch.cpu.irqFlagsRead()});

    // when attaching a device, it will be in the default state:
    // responding to address 0, endpoint 0
    try Self.deviceDescriptorRead(dev, 8);

    log.debug(@src(), "device descriptor read class {d} subclass {d} protocol {d}", .{ dev.device_descriptor.device_class, dev.device_descriptor.device_subclass, dev.device_descriptor.device_protocol });

    if (parent_hub) |h| {
        try h.portReset(parent_port.?, 10);
        dev.parent_port = parent_port.?.number;
    }

    log.debug(@src(), "assigning address {d}", .{devid});
    try Self.deviceSetAddress(dev, devid);

    // now read the real descriptor
    try Self.deviceDescriptorRead(dev, @sizeOf(Self.DeviceDescriptor));

    log.debug(@src(), "reading configuration descriptor", .{});
    try Self.deviceConfigurationDescriptorRead(dev);

    const use_config = dev.configuration.configuration_descriptor.configuration_value;
    //    log.debug(@src(), "setting device to use configuration {d}", .{use_config});
    try Self.deviceSetConfiguration(dev, use_config);

    var buf: [512]u8 = [_]u8{0} ** 512;
    log.debug(@src(), "attaching {s}", .{dev.description(&buf) catch ""});

    try bindDriver(dev);
}

fn bindDriver(dev: *Self.Device) !void {
    if (dev.driver != null) {
        // device already has a driver
        return;
    }

    for (drivers.items) |drv| {
        if (drv.canBind(dev)) {
            log.debug(@src(), "Attempting to bind '{s}' driver to device", .{drv.name});
            if (drv.bind(dev)) {
                var buf: [512]u8 = [_]u8{0} ** 512;
                log.info(@src(), "Bound '{s}' driver to '{s}'", .{ drv.name, dev.description(&buf) catch "" });
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
