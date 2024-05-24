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

const Forth = @import("forty/forth.zig").Forth;

const Logger = @import("logger.zig");
pub var log: *Logger = undefined;

const time = @import("time.zig");

const semaphore = @import("semaphore.zig");
const SID = semaphore.SID;

const synchronize = @import("synchronize.zig");
const AllocationSet = synchronize.AllocationSet;
const TicketLock = synchronize.TicketLock;

const class = @import("usb/class.zig");
const enumerate = @import("usb/enumerate.zig");
const hidkbd = @import("usb/hid_keyboard.zig");
const hidmouse = @import("usb/hid_mouse.zig");

pub usingnamespace @import("usb/core.zig");
pub usingnamespace @import("usb/hub.zig");
pub usingnamespace @import("usb/spec.zig");

const Self = @This();

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------

pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(Self, .{
        .{ "initialize", "usb-init" },
    });
    try forth.defineConstant("usbhci", @intFromPtr(root.hal.usb_hci));

    try HCI.defineModule(forth);
    try hidkbd.defineModule(forth);
    try hidmouse.defineModule(forth);
}

// ----------------------------------------------------------------------
// Core subsystem
// ----------------------------------------------------------------------
// const Drivers = std.ArrayList(*const Self.DeviceDriver);

const MAX_DEVICES = 16;

pub var devices: [MAX_DEVICES]Self.Device = init: {
    var initial_value: [MAX_DEVICES]Self.Device = undefined;
    for (&initial_value) |*d| {
        d.init();
    }
    break :init initial_value;
};
var devices_allocated: AllocationSet("devices", Self.DeviceAddress, MAX_DEVICES) = .{};

var allocator: std.mem.Allocator = undefined;
pub var root_hub: *Self.Hub = undefined;
var bus_lock: TicketLock = undefined;

const root_hub_default_endpoint = Self.Endpoint{
    .ep_desc = .{
        .length = 7,
        .descriptor_type = Self.USB_DESCRIPTOR_TYPE_ENDPOINT,
        .endpoint_address = 0x80,
        .attributes = Self.USB_ENDPOINT_TYPE_INTERRUPT,
        .max_packet_size = 0x08,
        .interval = 1,
    },
};

// `init` does the allocations and registrations needed, but does not
// activate the hardware
pub fn init() !void {
    log = Logger.init("usb", .info);

    allocator = root.kernel_allocator;
    Self.initCore(allocator);
    enumerate.init(allocator);

    bus_lock = TicketLock.init("usb bus", true);
}

// `initialize` activates the hardware and does the initial port scan
pub fn initialize() !void {
    try busInit();

    try class.initializeDrivers(allocator);
}

fn busInit() !void {
    const roothub_addr = try addressAllocate();
    errdefer addressFree(roothub_addr);

    var rh = try Self.hubClassAlloc();
    errdefer {
        Self.hubClassFree(rh);
    }

    rh.is_roothub = true;
    rh.hub_address = roothub_addr;
    rh.speed = Self.USB_SPEED_FULL;
    rh.port_count = 1;
    rh.descriptor = root.HAL.USBHCI.root_hub_hub_descriptor;
    // rh.interrupt_in = &root_hub_default_endpoint;
    rh.ports = try allocator.alloc(Self.HubPort, 1);
    rh.ports[0] = try Self.HubPort.init(rh, 1);
    rh.ports[0].connected = true;

    root_hub = rh;
}

pub fn rootHubControl(setup: *Self.SetupPacket, data: ?[]u8) Self.URB.Status {
    return HCI.rootHubControl(setup, data);
}

pub fn addressAllocate() !Self.DeviceAddress {
    bus_lock.acquire();
    defer bus_lock.release();

    const addr: Self.DeviceAddress = try devices_allocated.allocate();
    return addr + 1;
}

pub fn addressFree(dev_addr: Self.DeviceAddress) void {
    bus_lock.acquire();
    defer bus_lock.release();
    devices_allocated.free(dev_addr);
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
