/// Protocol definition for USB HID devices
///
/// See USB Device Class Definition for Human Interface Devices
/// Revision 1.1
const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const delayMillis = root.HAL.delayMillis;

const Forth = @import("../forty/forth.zig").Forth;

const Logger = @import("../logger.zig");
var log: *Logger = undefined;

const semaphore = @import("../semaphore.zig");
const SID = semaphore.SID;

const descriptor = @import("descriptor.zig");
const EndpointDescriptor = descriptor.EndpointDescriptor;
const HidDescriptor = descriptor.HidDescriptor;
const InterfaceDescriptor = descriptor.InterfaceDescriptor;

const device = @import("device.zig");
const Device = device.Device;
const DeviceClass = device.DeviceClass;
const DeviceDriver = device.DeviceDriver;
const HidProtocol = device.HidProtocol;
const HidSubclass = device.HidSubclass;

const endpoint = @import("endpoint.zig");
const EndpointDirection = endpoint.EndpointDirection;

const transfer = @import("transfer.zig");
const TransferRequest = transfer.TransferRequest;
const TransferType = transfer.TransferType;

const usb = @import("../usb.zig");

const Error = @import("status.zig").Error;

const Self = @This();

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------

pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(Self, .{
        .{ "readKeySync", "usb-read-key" },
    });
}

// ----------------------------------------------------------------------
// Keyboard polling
// ----------------------------------------------------------------------
var keyboard_device: ?*Device = null;
var keyboard_interface: ?*InterfaceDescriptor = null;
var keyboard_endpoint: ?*EndpointDescriptor = null;

// this is a quick & dirty way to see key press and release events via
// polling.
const POLLING_BUFFER_SIZE = 8;

var polling_semaphore: ?SID = null;
var polling_buffer: [POLLING_BUFFER_SIZE]u8 = [_]u8{0} ** POLLING_BUFFER_SIZE;
var poll: TransferRequest = undefined;

fn keyboardPollCompletion(req: *TransferRequest) void {
    _ = req;
    semaphore.signal(polling_semaphore.?) catch |err| {
        log.err(@src(), "keyboard poll completion cannot signal {?d}: {any}", .{ polling_semaphore, err });
    };
}

pub fn readKeySync() []u8 {
    if (keyboard_interface == null) {
        log.err(@src(), "No keyboard", .{});
        return polling_buffer[0..0];
    }

    // on first invocation, create a semaphore and transfer request
    if (polling_semaphore == null) {
        polling_semaphore = semaphore.create(0) catch |err| {
            log.err(@src(), "semaphore create error {any}", .{err});
            return polling_buffer[0..0];
        };
        poll = .{
            .device = keyboard_device.?,
            .endpoint_desc = keyboard_endpoint.?,
            .setup_data = undefined,
            .data = &polling_buffer,
            .size = POLLING_BUFFER_SIZE,
            .completion = keyboardPollCompletion,
        };
    }

    usb.transferSubmit(&poll) catch |err| {
        log.err(@src(), "transfer submit error {any}", .{err});
        return polling_buffer[0..0];
    };

    semaphore.wait(polling_semaphore.?) catch |err| {
        log.err(@src(), "semaphore wait error {any}", .{err});
        return polling_buffer[0..0];
    };

    return &polling_buffer;
}

// ----------------------------------------------------------------------
// Driver interface
// ----------------------------------------------------------------------
fn isKeyboard(iface: *InterfaceDescriptor) bool {
    return iface.isHid() and
        iface.interface_protocol == HidProtocol.keyboard and
        (iface.interface_subclass == 0 or iface.interface_subclass == 1);
}

pub fn hidKeyboardDriverCanBind(dev: *Device) bool {
    const configuration = dev.configuration;
    _ = configuration;

    for (0..dev.interfaceCount()) |i| {
        const iface = dev.interface(i);
        if (iface != null and isKeyboard(iface.?)) {
            return true;
        }
    }

    return false;
}

pub fn hidKeyboardDriverDeviceBind(dev: *Device) Error!void {
    for (0..dev.interfaceCount()) |i| {
        const iface = dev.interface(i).?;

        if (!isKeyboard(iface)) {
            continue;
        }

        const in_interrupt_endpoint: ?*EndpointDescriptor = for (0..iface.endpoint_count) |e| {
            if (dev.configuration.endpoints[i][e]) |ep| {
                if (ep.isType(TransferType.interrupt) and
                    ep.direction() == 1)
                {
                    break ep;
                }
            }
        } else null;

        if (in_interrupt_endpoint == null) {
            continue;
        }

        log.debug(@src(), "selecting interface {d}, endpoint {d}", .{ i, in_interrupt_endpoint.?.endpoint_address });
        keyboard_device = dev;
        keyboard_interface = iface;
        keyboard_endpoint = in_interrupt_endpoint;
    }
}

pub fn hidKeyboardDriverDeviceUnbind(dev: *Device) void {
    log.debug(@src(), "hid keyboard driver pretending to unbind device {d}", .{dev.address});
}

pub fn hidKeyboardDriverInitialize(allocator: Allocator) !void {
    _ = allocator;
    log = Logger.init("usb_hid_keyboard", .info);
}

pub const driver: DeviceDriver = .{
    .name = "USB Keyboard",
    .initialize = hidKeyboardDriverInitialize,
    .canBind = hidKeyboardDriverCanBind,
    .bind = hidKeyboardDriverDeviceBind,
    .unbind = hidKeyboardDriverDeviceUnbind,
};
