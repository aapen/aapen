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

const p = @import("../printf.zig");
const printf = p.printf;

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
const HidClassRequest = device.HidClassRequest;
const HidProtocol = device.HidProtocol;
const HidSubclass = device.HidSubclass;

const endpoint = @import("endpoint.zig");
const EndpointDirection = endpoint.EndpointDirection;

const request = @import("request.zig");
const request_interface_class_out = request.interface_class_out;

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
        .{ "decodeKey", "key-decode" },
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

pub fn readKeySync() ?[*]u8 {
    if (keyboard_interface == null) {
        log.err(@src(), "No keyboard", .{});
        return null;
    }

    // on first invocation, create a semaphore and transfer request
    if (polling_semaphore == null) {
        polling_semaphore = semaphore.create(0) catch |err| {
            log.err(@src(), "semaphore create error {any}", .{err});
            return null;
        };
    }

    poll = .{
        .device = keyboard_device.?,
        .endpoint_desc = keyboard_endpoint.?,
        .setup_data = undefined,
        .data = &polling_buffer,
        .size = POLLING_BUFFER_SIZE,
        .completion = keyboardPollCompletion,
    };

    usb.transferSubmit(&poll) catch |err| {
        log.err(@src(), "transfer submit error {any}", .{err});
        return null;
    };

    semaphore.wait(polling_semaphore.?) catch |err| {
        log.err(@src(), "semaphore wait error {any}", .{err});
        return null;
    };

    if (poll.status == .ok) {
        return &polling_buffer;
    } else {
        return null;
    }
}

// ----------------------------------------------------------------------
// Translation
// ----------------------------------------------------------------------
const Modifiers = packed struct {
    pub const any_shift: u8 = @bitCast(Modifiers{
        .left_shift = 1,
        .right_shift = 1,
    });

    pub const any_control: u8 = @bitCast(Modifiers{
        .left_control = 1,
        .right_control = 1,
    });

    pub const any_alt: u8 = @bitCast(Modifiers{
        .left_alt = 1,
        .right_alt = 1,
    });

    left_control: u1 = 0,
    left_shift: u1 = 0,
    left_alt: u1 = 0,
    left_hyper: u1 = 0,
    right_control: u1 = 0,
    right_shift: u1 = 0,
    right_alt: u1 = 0,
    right_hyper: u1 = 0,
};

// See HID Usage Tables for USB, version 1.3, section 10
// https://usb.org/sites/default/files/hut1_3_0.pdf
const boot_protocol_usage = .{
    .{ 0x04, .none, 'a' },
    .{ 0x05, .none, 'b' },
    .{ 0x06, .none, 'c' },
    .{ 0x07, .none, 'd' },
    .{ 0x08, .none, 'e' },
    .{ 0x09, .none, 'f' },
    .{ 0x0A, .none, 'g' },
    .{ 0x0B, .none, 'h' },
    .{ 0x0C, .none, 'i' },
    .{ 0x0D, .none, 'j' },
    .{ 0x0E, .none, 'k' },
    .{ 0x0F, .none, 'l' },
    .{ 0x10, .none, 'm' },
    .{ 0x11, .none, 'n' },
    .{ 0x12, .none, 'o' },
    .{ 0x13, .none, 'p' },
    .{ 0x14, .none, 'q' },
    .{ 0x15, .none, 'r' },
    .{ 0x16, .none, 's' },
    .{ 0x17, .none, 't' },
    .{ 0x18, .none, 'u' },
    .{ 0x19, .none, 'v' },
    .{ 0x1A, .none, 'w' },
    .{ 0x1B, .none, 'x' },
    .{ 0x1C, .none, 'y' },
    .{ 0x1D, .none, 'z' },
    .{ 0x1E, .none, '1' },
    .{ 0x1F, .none, '2' },
    .{ 0x20, .none, '3' },
    .{ 0x21, .none, '4' },
    .{ 0x22, .none, '5' },
    .{ 0x23, .none, '6' },
    .{ 0x24, .none, '7' },
    .{ 0x25, .none, '8' },
    .{ 0x26, .none, '9' },
    .{ 0x27, .none, '0' },
    .{ 0x28, .none, '\n' }, // newline
    .{ 0x29, .none, '\x1b' }, // escape
    .{ 0x2A, .none, '\x08' }, // backspace
    .{ 0x2B, .none, '\x09' }, // tab
    .{ 0x2C, .none, ' ' },
    .{ 0x2D, .none, '-' },
    .{ 0x2E, .none, '=' },
    .{ 0x2F, .none, '[' },
    .{ 0x30, .none, ']' },
    .{ 0x31, .none, '\\' },
    .{ 0x33, .none, ';' },
    .{ 0x34, .none, '\'' },
    .{ 0x35, .none, '`' },
    .{ 0x36, .none, ',' },
    .{ 0x37, .none, '.' },
    .{ 0x38, .none, '/' },
    .{ 0x3A, .none, '\x93' }, // F1
    .{ 0x3B, .none, '\x94' }, // F2
    .{ 0x3C, .none, '\x95' }, // F3
    .{ 0x3D, .none, '\x96' }, // F4
    .{ 0x3E, .none, '\x97' }, // F5
    .{ 0x3F, .none, '\x98' }, // F6
    .{ 0x40, .none, '\x99' }, // F7
    .{ 0x41, .none, '\x9a' }, // F8
    .{ 0x42, .none, '\x9b' }, // F9
    .{ 0x43, .none, '\x9c' }, // F10
    .{ 0x44, .none, '\x9d' }, // F11
    .{ 0x45, .none, '\x9e' }, // F12
    .{ 0x4f, .none, '\xa0' }, // right arrow
    .{ 0x50, .none, '\xa1' }, // left arrow
    .{ 0x51, .none, '\xa2' }, // down arrow
    .{ 0x52, .none, '\xa3' }, // up arrow
    .{ 0x04, .shift, 'A' },
    .{ 0x05, .shift, 'B' },
    .{ 0x06, .shift, 'C' },
    .{ 0x07, .shift, 'D' },
    .{ 0x08, .shift, 'E' },
    .{ 0x09, .shift, 'F' },
    .{ 0x0A, .shift, 'G' },
    .{ 0x0B, .shift, 'H' },
    .{ 0x0C, .shift, 'I' },
    .{ 0x0D, .shift, 'J' },
    .{ 0x0E, .shift, 'K' },
    .{ 0x0F, .shift, 'L' },
    .{ 0x10, .shift, 'M' },
    .{ 0x11, .shift, 'N' },
    .{ 0x12, .shift, 'O' },
    .{ 0x13, .shift, 'P' },
    .{ 0x14, .shift, 'Q' },
    .{ 0x15, .shift, 'R' },
    .{ 0x16, .shift, 'S' },
    .{ 0x17, .shift, 'T' },
    .{ 0x18, .shift, 'U' },
    .{ 0x19, .shift, 'V' },
    .{ 0x1A, .shift, 'W' },
    .{ 0x1B, .shift, 'X' },
    .{ 0x1C, .shift, 'Y' },
    .{ 0x1D, .shift, 'Z' },
    .{ 0x1E, .shift, '!' },
    .{ 0x1F, .shift, '@' },
    .{ 0x20, .shift, '#' },
    .{ 0x21, .shift, '$' },
    .{ 0x22, .shift, '%' },
    .{ 0x23, .shift, '^' },
    .{ 0x24, .shift, '&' },
    .{ 0x25, .shift, '*' },
    .{ 0x26, .shift, '(' },
    .{ 0x27, .shift, ')' },
    .{ 0x28, .shift, '\n' }, // newline
    .{ 0x29, .shift, '\x1b' }, // escape
    .{ 0x2A, .shift, '\x08' }, // backspace
    .{ 0x2B, .shift, '\x09' }, // tab
    .{ 0x2D, .shift, '_' },
    .{ 0x2E, .shift, '+' },
    .{ 0x2F, .shift, '{' },
    .{ 0x30, .shift, '}' },
    .{ 0x31, .shift, '|' },
    .{ 0x33, .shift, ':' },
    .{ 0x34, .shift, '\"' },
    .{ 0x35, .shift, '~' },
    .{ 0x36, .shift, '<' },
    .{ 0x37, .shift, '>' },
    .{ 0x38, .shift, '?' },
};

pub const Usage = struct {
    unshifted_ascii_value: u8 = 0,
    shifted_ascii_value: u8 = 0,
};

pub const usage: [256]Usage = init: {
    var initial_value: [256]Usage = undefined;
    for (0..256) |i| {
        initial_value[i] = .{};
    }
    for (boot_protocol_usage) |u| {
        switch (u[1]) {
            .shift => initial_value[u[0]].shifted_ascii_value = u[2],
            else => initial_value[u[0]].unshifted_ascii_value = u[2],
        }
    }
    break :init initial_value;
};

pub fn decodeKey(buf: [*]u8, index: usize) u8 {
    const modifiers: u8 = @bitCast(buf[0]);
    if (buf[2 + index] != 0) {
        if (modifiers & Modifiers.any_shift != 0) {
            return usage[buf[2 + index]].shifted_ascii_value;
        } else {
            return usage[buf[2 + index]].unshifted_ascii_value;
        }
    }
    return 0;
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

        log.info(@src(), "usbaddr {d} keyboard: selecting interface {d}, endpoint {d}", .{ dev.address, i, in_interrupt_endpoint.?.endpoint_address });

        keyboard_device = dev;
        keyboard_interface = iface;
        keyboard_endpoint = in_interrupt_endpoint;

        const status = usb.controlMessage(
            dev,
            HidClassRequest.set_protocol, // request
            request_interface_class_out, // request type
            0, // value - id of hid boot protocol
            @truncate(i), // index - interface to use
            &.{}, // data (not used for this transfer)
        );

        if (status) |s| {
            if (s != .ok) {
                log.warn(@src(), "cannot set keyboard to use boot protocol: {any}", .{status});
            }
        } else |err| {
            log.err(@src(), "error sending control message to set protocol: {any}", .{err});
        }

        return;
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
