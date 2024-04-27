/// Protocol definition for USB HID devices
///
/// See USB Device Class Definition for Human Interface Devices
/// Revision 1.1
const std = @import("std");
const Allocator = std.mem.Allocator;
const RingBuffer = std.RingBuffer;

const root = @import("root");
const delayMillis = root.HAL.delayMillis;

const InputBuffer = @import("../input_buffer.zig");

const Forth = @import("../forty/forth.zig").Forth;

const Logger = @import("../logger.zig");
var log: *Logger = undefined;

const p = @import("../printf.zig");
const printf = p.printf;

const schedule = @import("../schedule.zig");

const semaphore = @import("../semaphore.zig");
const SID = semaphore.SID;

const synchronize = @import("../synchronize.zig");
const OneShot = synchronize.OneShot;

const descriptor = @import("descriptor.zig");
const EndpointDescriptor = descriptor.EndpointDescriptor;
const HidDescriptor = descriptor.HidDescriptor;
const InterfaceDescriptor = descriptor.InterfaceDescriptor;

const device = @import("device.zig");
const Device = device.Device;
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
        .{ "startPolling", "kbd-poll-loop" },
        .{ "stopPolling", "kill-kbd-poll-loop" },
    });
}

// ----------------------------------------------------------------------
// Keyboard polling
// ----------------------------------------------------------------------
var driver_initialized: OneShot = .{};
var shutdown_signal: OneShot = .{};

var keyboard_device: ?*Device = null;
var keyboard_interface: ?*InterfaceDescriptor = null;
var keyboard_endpoint: ?*EndpointDescriptor = null;

const REPORT_SIZE = 8;
var report: [REPORT_SIZE]u8 = [_]u8{0} ** REPORT_SIZE;
var last_report: [REPORT_SIZE]u8 = [_]u8{0} ** REPORT_SIZE;

fn keyboardPollCompletion(req: *TransferRequest) void {
    semaphore.signal(req.semaphore.?) catch |err| {
        log.err(@src(), "keyboard poll completion cannot signal {?d}: {any}", .{ req.semaphore, err });
    };
}

fn initializePolling() !TransferRequest {
    shutdown_signal = .{};

    while (!driver_initialized.isSignalled()) {
        try schedule.sleep(1000);
    }

    const interrupt_completion_sem = semaphore.create(0) catch |err| {
        log.err(@src(), "semaphore create error {any}", .{err});
        return Error.BadSemaphoreId;
    };

    return .{
        .device = keyboard_device.?,
        .endpoint_desc = keyboard_endpoint.?,
        .setup_data = undefined,
        .data = &report,
        .size = REPORT_SIZE,
        .completion = keyboardPollCompletion,
        .semaphore = interrupt_completion_sem,
    };
}

fn shutdownPolling(req: *const TransferRequest) void {
    if (req.semaphore) |s| {
        semaphore.free(s) catch |err| {
            log.err(@src(), "semaphore free error {any}", .{err});
        };
    }
}

fn in(ch: u8, rpt: [*]u8) bool {
    for (2..8) |i| {
        if (rpt[i] == ch) {
            return true;
        }
    }
    return false;
}

fn processCurrentReport() void {
    const modifiers: Modifiers = @bitCast(report[0]);

    for (2..8) |idx| {
        if (report[idx] != 0) {
            const u = report[idx];
            const ch = usage[u].value[modifiers.which()];

            if (u != 0 and ch == 0) {
                log.debug(@src(), "unmapped key, usage code {x:0>2}", .{u});
            }

            if (ch != 0 and !in(u, &last_report)) {
                InputBuffer.write(ch);
            }
        }
    }

    @memcpy(last_report[0..8], report[0..8]);
}

pub fn pollKeyboard(args: *anyopaque) void {
    _ = args;

    const interrupt_request_template = initializePolling() catch |err| {
        log.err(@src(), "initialize polling error {any}", .{err});
        return;
    };

    defer shutdownPolling(&interrupt_request_template);

    while (!shutdown_signal.isSignalled()) {
        var interrupt_request = interrupt_request_template;

        usb.transferSubmit(&interrupt_request) catch |err| {
            log.err(@src(), "transfer submit error {any}", .{err});
            return;
        };

        semaphore.wait(interrupt_request.semaphore.?) catch |err| {
            log.err(@src(), "semaphore wait error {any}", .{err});
            return;
        };

        if (interrupt_request.status == .ok) {
            processCurrentReport();
        }
    }
}

pub fn startPolling() !void {
    _ = try schedule.spawn(pollKeyboard, "usb-kbd", &.{});
}

pub fn stopPolling() void {
    shutdown_signal.signal();
}

// ----------------------------------------------------------------------
// Translation
// ----------------------------------------------------------------------

// The bitfields in this strut are defined by the USB keyboard boot protocol
const Modifiers = packed struct {
    fn which(mod: *const Modifiers) u2 {
        var w: u2 = 0;
        w |= if (mod.left_shift != 0 or mod.right_shift != 0) 0b01 else 0b00;
        w |= if (mod.left_control != 0 or mod.right_control != 0) 0b10 else 0b00;
        return w;
    }

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

// column 1 - unshifted
// column 2 - shifted
// column 3 - control
// column 4 - control + shift
const boot_protocol_usage = .{
    .{ 0x04, 'a', 'A', '\x01', '\x01' },
    .{ 0x05, 'b', 'B', '\x02', '\x02' },
    .{ 0x06, 'c', 'C', '\x03', '\x03' },
    .{ 0x07, 'd', 'D', '\x04', '\x04' },
    .{ 0x08, 'e', 'E', '\x05', '\x05' },
    .{ 0x09, 'f', 'F', '\x06', '\x06' },
    .{ 0x0A, 'g', 'G', '\x07', '\x07' },
    .{ 0x0B, 'h', 'H', '\x08', '\x08' },
    .{ 0x0C, 'i', 'I', '\x09', '\x09' },
    .{ 0x0D, 'j', 'J', '\x0A', '\x0A' },
    .{ 0x0E, 'k', 'K', '\x0B', '\x0B' },
    .{ 0x0F, 'l', 'L', '\x0C', '\x0C' },
    .{ 0x10, 'm', 'M', '\x0D', '\x0D' },
    .{ 0x11, 'n', 'N', '\x0E', '\x0E' },
    .{ 0x12, 'o', 'O', '\x0F', '\x0F' },
    .{ 0x13, 'p', 'P', '\x10', '\x10' },
    .{ 0x14, 'q', 'Q', '\x11', '\x11' },
    .{ 0x15, 'r', 'R', '\x12', '\x12' },
    .{ 0x16, 's', 'S', '\x13', '\x13' },
    .{ 0x17, 't', 'T', '\x14', '\x14' },
    .{ 0x18, 'u', 'U', '\x15', '\x15' },
    .{ 0x19, 'v', 'V', '\x16', '\x16' },
    .{ 0x1A, 'w', 'W', '\x17', '\x17' },
    .{ 0x1B, 'x', 'X', '\x18', '\x18' },
    .{ 0x1C, 'y', 'Y', '\x19', '\x19' },
    .{ 0x1D, 'z', 'Z', '\x1A', '\x1A' },
    .{ 0x1E, '1', '!', '\x00', '\x00' },
    .{ 0x1F, '2', '@', '\x00', '\x00' },
    .{ 0x20, '3', '#', '\x00', '\x00' },
    .{ 0x21, '4', '$', '\x00', '\x00' },
    .{ 0x22, '5', '%', '\x00', '\x00' },
    .{ 0x23, '6', '^', '\x00', '\x00' },
    .{ 0x24, '7', '&', '\x00', '\x00' },
    .{ 0x25, '8', '*', '\x00', '\x00' },
    .{ 0x26, '9', '(', '\x00', '\x00' },
    .{ 0x27, '0', ')', '\x00', '\x00' },
    .{ 0x28, '\x0a', '\x0A', '\x0A', '\x0A' }, // Enter
    .{ 0x29, '\x1B', '\x1B', '\x1B', '\x1B' }, // Escape
    .{ 0x2A, '\x7F', '\x7F', '\x7F', '\x7F' }, // Backspace
    .{ 0x2B, '\x09', '\x09', '\x09', '\x09' }, // Tab
    .{ 0x2C, ' ', ' ', '\x00', '\x00' }, // Space
    .{ 0x2D, '-', '_', '\x00', '\x00' },
    .{ 0x2E, '=', '+', '\x00', '\x00' },
    .{ 0x2F, '[', '{', '\x00', '\x00' },
    .{ 0x30, ']', '}', '\x00', '\x00' },
    .{ 0x31, '\\', '|', '\x00', '\x00' },
    .{ 0x32, '#', '~', '\x00', '\x00' },
    .{ 0x33, ';', ':', '\x00', '\x00' },
    .{ 0x34, '\'', '\"', '\x00', '\x00' },
    .{ 0x35, '`', '~', '\x00', '\x00' },
    .{ 0x36, ',', '<', '\x00', '\x00' },
    .{ 0x37, '.', '>', '\x00', '\x00' },
    .{ 0x38, '/', '?', '\x00', '\x00' },
    .{ 0x39, '\x00', '\x00', '\x00', '\x00' }, // Caps Lock
    .{ 0x3A, '\x90', '\xA0', '\x90', '\xA0' }, // F1
    .{ 0x3B, '\x91', '\xA1', '\x91', '\xA1' }, // F2
    .{ 0x3C, '\x92', '\xA2', '\x92', '\xA2' }, // F3
    .{ 0x3D, '\x93', '\xA3', '\x93', '\xA3' }, // F4
    .{ 0x3E, '\x94', '\xA4', '\x94', '\xA4' }, // F5
    .{ 0x3F, '\x95', '\xA5', '\x95', '\xA5' }, // F6
    .{ 0x40, '\x96', '\xA6', '\x96', '\xA6' }, // F7
    .{ 0x41, '\x97', '\xA7', '\x97', '\xA7' }, // F8
    .{ 0x42, '\x98', '\xA8', '\x98', '\xA8' }, // F9
    .{ 0x43, '\x99', '\xA9', '\x99', '\xA9' }, // F10
    .{ 0x44, '\x9A', '\xAA', '\x9A', '\xAA' }, // F11
    .{ 0x45, '\x9B', '\xAB', '\x9B', '\xAB' }, // F12
    .{ 0x4A, '\x84', '\x84', '\x00', '\x00' }, // home
    .{ 0x4D, '\x85', '\x85', '\x00', '\x00' }, // end
    .{ 0x4F, '\x83', '\x81', '\x00', '\x00' }, // right arrow
    .{ 0x50, '\x82', '\x82', '\x00', '\x00' }, // left arrow
    .{ 0x51, '\x81', '\x81', '\x00', '\x00' }, // down arrow
    .{ 0x52, '\x80', '\x80', '\x00', '\x00' }, // up arrow
};

pub const Usage = struct {
    value: [4]u8,

    fn fromSpec(tuple: struct { u8, u8, u8, u8, u8 }) Usage {
        return .{
            .value = .{ tuple[1], tuple[2], tuple[3], tuple[4] },
        };
    }
};

pub const usage: [256]Usage = init: {
    var initial_value: [256]Usage = undefined;
    for (0..256) |i| {
        initial_value[i] = .{ .value = .{ 0, 0, 0, 0 } };
    }
    for (boot_protocol_usage) |u| {
        initial_value[u[0]] = Usage.fromSpec(u);
    }
    break :init initial_value;
};

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
            if (s == .ok) {
                driver_initialized.signal();
            } else {
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
