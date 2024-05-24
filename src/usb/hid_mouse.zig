/// Protocol definition for USB HID devices
///
/// See USB Device Class Definition for Human Interface Devices
/// Revision 1.1
const std = @import("std");
const Allocator = std.mem.Allocator;
const RingBuffer = std.RingBuffer;

const root = @import("root");
const DMA = root.HAL.USBHCI.DMA_ALIGNMENT;

const InputBuffer = @import("../input_buffer.zig");

const Forth = @import("../forty/forth.zig");

const Logger = @import("../logger.zig");
var log: *Logger = undefined;

const mouse = @import("../mouse.zig");

const schedule = @import("../schedule.zig");

const semaphore = @import("../semaphore.zig");
const SID = semaphore.SID;

const synchronize = @import("../synchronize.zig");

const class = @import("class.zig");
const core = @import("core.zig");
const hub = @import("hub.zig");
const spec = @import("spec.zig");
const usb = @import("../usb.zig");

const Self = @This();

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------

pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(Self, .{
        .{ "startPolling", "mouse-poll-loop" },
        .{ "stopPolling", "kill-mouse-poll-loop" },
    });
}

// ----------------------------------------------------------------------
// Mouse polling
// ----------------------------------------------------------------------
var driver_initialized: synchronize.OneShot = .{};
var shutdown_signal: synchronize.OneShot = .{};

var mouse_port: ?*hub.HubPort = null;
var mouse_endpoint: ?*hub.Endpoint = null;
var mouse_int_urb: core.URB = undefined;
var mouse_interval: u8 = 1;

const REPORT_SIZE = 4;
var report: [REPORT_SIZE]u8 align(DMA) = [_]u8{0} ** REPORT_SIZE;
var last_report: [REPORT_SIZE]u8 = [_]u8{0} ** REPORT_SIZE;

fn processCurrentReport() void {
    const changed = brk: {
        inline for (0..REPORT_SIZE) |i| {
            if (report[i] != last_report[i]) {
                break :brk true;
            }
        }
        break :brk false;
    };

    if (!changed) return;

    mouse.update(report[0], @as(i8, @bitCast(report[1])), @as(i8, @bitCast(report[2])));

    @memcpy(&last_report, &report);
}

pub fn pollMouse(_: *anyopaque) void {
    while (!driver_initialized.isSignalled()) {
        schedule.sleep(1000) catch |err| {
            log.err(@src(), "schedule sleep error {any}", .{err});
            return;
        };
    }

    mouse_int_urb.fillInterrupt(mouse_port.?, mouse_endpoint.?, &report, REPORT_SIZE, 0, null);

    while (!shutdown_signal.isSignalled()) {
        const ret = usb.interruptTransfer(&mouse_int_urb) catch 0;
        _ = ret;

        if (mouse_int_urb.status == .OK) {
            processCurrentReport();
        } else if (mouse_int_urb.status_detail == .Nak) {
            // no data available. wait a while
        } else {
            // probably an error
            log.err(@src(), "interrupt transfer status {any}:{any}", .{ mouse_int_urb.status, mouse_int_urb.status_detail });
        }

        schedule.sleep(mouse_interval) catch |err| {
            log.err(@src(), "sleep mouse interval error {any}", .{err});
            return;
        };
    }
}

pub fn startPolling() !void {
    _ = try schedule.spawn(pollMouse, "usb-mouse", &.{});
}

pub fn stopPolling() void {
    shutdown_signal.signal();
}

// ----------------------------------------------------------------------
// Driver interface
// ----------------------------------------------------------------------
fn selectInterruptEndpoint(iface: *const hub.Interface) ?u8 {
    for (0..iface.alternate[0].ep_count) |ep_num| {
        const ep_desc = &iface.alternate[0].ep[ep_num].ep_desc;

        if (ep_desc.isType(spec.USB_ENDPOINT_TYPE_INTERRUPT) and
            ep_desc.direction() == spec.USB_ENDPOINT_DIRECTION_IN)
        {
            log.debug(@src(), "selecting ep addr 0x{x:0>2}, type 0x{x}", .{ ep_desc.endpoint_address, ep_desc.getType() });
            return @truncate(ep_num);
        }
    }

    return null;
}

pub fn hidMouseClassDriverBind(port: *hub.HubPort, interface: u8) core.Error!void {
    const iface = &port.interfaces[interface];
    const ep_int_in = selectInterruptEndpoint(iface) orelse return core.Error.ConfigurationError;

    mouse_port = port;
    mouse_endpoint = &iface.alternate[0].ep[ep_int_in];
    mouse_interval = iface.alternate[0].ep[ep_int_in].ep_desc.interval;

    port.setup = .{
        .request_type = usb.USB_REQUEST_TYPE_INTERFACE_CLASS_OUT,
        .request = usb.HID_REQUEST_SET_PROTOCOL,
        .value = 0,
        .index = interface,
        .data_size = 0,
    };

    _ = usb.controlTransfer(port, &port.setup, null) catch |err| {
        log.warn(@src(), "cannot set mouse to use boot protocol {any}", .{err});
        return err;
    };

    driver_initialized.signal();
}

pub fn hidMouseClassDriverUnbind(port: *hub.HubPort, interface: u8) !void {
    _ = interface;
    _ = port;
}

pub fn hidMouseDriverInitialize(allocator: Allocator) !void {
    _ = allocator;
    log = Logger.init("usb_hid_mouse", .info);
}

pub const class_driver: class.Driver = .{
    .name = "USB Keyboard",
    .initialize = hidMouseDriverInitialize,
    .bind = hidMouseClassDriverBind,
    .unbind = hidMouseClassDriverUnbind,
};
