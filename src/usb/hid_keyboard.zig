/// Protocol definition for USB HID devices
///
/// See USB Device Class Definition for Human Interface Devices
/// Revision 1.1
const std = @import("std");
const Allocator = std.mem.Allocator;
const RingBuffer = std.RingBuffer;

const root = @import("root");
const DMA = root.HAL.USBHCI.DMA_ALIGNMENT;

const key = @import("../key.zig");
const InputBuffer = @import("../input_buffer.zig");

const Forth = @import("../forty/forth.zig");

const Logger = @import("../logger.zig");
var log: *Logger = undefined;

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
        .{ "startPolling", "kbd-poll-loop" },
        .{ "stopPolling", "kill-kbd-poll-loop" },
    });
}

// ----------------------------------------------------------------------
// Keyboard polling
// ----------------------------------------------------------------------
var driver_initialized: synchronize.OneShot = .{};
var shutdown_signal: synchronize.OneShot = .{};

var keyboard_port: ?*hub.HubPort = null;
var keyboard_endpoint: ?*hub.Endpoint = null;
var keyboard_int_urb: core.URB = undefined;
var keyboard_interval: u8 = 1;

const REPORT_SIZE = 8;
var report: [REPORT_SIZE]u8 align(DMA) = [_]u8{0} ** REPORT_SIZE;
var last_report: [REPORT_SIZE]u8 = [_]u8{0} ** REPORT_SIZE;

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

pub fn pollKeyboard(_: *anyopaque) void {
    while (!driver_initialized.isSignalled()) {
        schedule.sleep(1000) catch |err| {
            log.err(@src(), "schedule sleep error {any}", .{err});
            return;
        };
    }

    keyboard_int_urb.fillInterrupt(keyboard_port.?, keyboard_endpoint.?, &report, REPORT_SIZE, 0, null);

    while (!shutdown_signal.isSignalled()) {
        const ret = usb.interruptTransfer(&keyboard_int_urb) catch 0;
        _ = ret;

        if (keyboard_int_urb.status == .OK) {
            processCurrentReport();
        } else if (keyboard_int_urb.status_detail == .Nak) {
            // no data available. wait a while
        } else {
            // probably an error
            log.err(@src(), "interrupt transfer status {any}:{any}", .{ keyboard_int_urb.status, keyboard_int_urb.status_detail });
        }

        schedule.sleep(keyboard_interval) catch |err| {
            log.err(@src(), "sleep keyboard interval error {any}", .{err});
            return;
        };
    }
}

pub fn startPolling() !void {
    _ = try schedule.spawn(pollKeyboard, "usb-kbd", schedule.no_args);
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
// zig fmt: off
const boot_protocol_usage = .{
    .{ 0x04, 'a',             'A',             '\x01',          '\x41' },
    .{ 0x05, 'b',             'B',             '\x02',          '\x42' },
    .{ 0x06, 'c',             'C',             '\x03',          '\x43' },
    .{ 0x07, 'd',             'D',             '\x04',          '\x44' },
    .{ 0x08, 'e',             'E',             '\x05',          '\x45' },
    .{ 0x09, 'f',             'F',             '\x06',          '\x46' },
    .{ 0x0A, 'g',             'G',             '\x07',          '\x47' },
    .{ 0x0B, 'h',             'H',             '\x08',          '\x48' },
    .{ 0x0C, 'i',             'I',             '\x09',          '\x49' },
    .{ 0x0D, 'j',             'J',             '\x0A',          '\x4A' },
    .{ 0x0E, 'k',             'K',             '\x0B',          '\x4B' },
    .{ 0x0F, 'l',             'L',             '\x0C',          '\x4C' },
    .{ 0x10, 'm',             'M',             '\x0D',          '\x4D' },
    .{ 0x11, 'n',             'N',             '\x0E',          '\x4E' },
    .{ 0x12, 'o',             'O',             '\x0F',          '\x4F' },
    .{ 0x13, 'p',             'P',             '\x10',          '\x50' },
    .{ 0x14, 'q',             'Q',             '\x11',          '\x51' },
    .{ 0x15, 'r',             'R',             '\x12',          '\x52' },
    .{ 0x16, 's',             'S',             '\x13',          '\x53' },
    .{ 0x17, 't',             'T',             '\x14',          '\x54' },
    .{ 0x18, 'u',             'U',             '\x15',          '\x55' },
    .{ 0x19, 'v',             'V',             '\x16',          '\x56' },
    .{ 0x1A, 'w',             'W',             '\x17',          '\x57' },
    .{ 0x1B, 'x',             'X',             '\x18',          '\x58' },
    .{ 0x1C, 'y',             'Y',             '\x19',          '\x59' },
    .{ 0x1D, 'z',             'Z',             '\x1A',          '\x5A' },
    .{ 0x1E, '1',             '!',             '1',             '!' },
    .{ 0x1F, '2',             '@',             '2',             '@' },
    .{ 0x20, '3',             '#',             '3',             '#' },
    .{ 0x21, '4',             '$',             '4',             '$' },
    .{ 0x22, '5',             '%',             '5',             '%' },
    .{ 0x23, '6',             '^',             '6',             '^' },
    .{ 0x24, '7',             '&',             '7',             '&' },
    .{ 0x25, '8',             '*',             '8',             '*' },
    .{ 0x26, '9',             '(',             '9',             '(' },
    .{ 0x27, '0',             ')',             '0',             ')' },
    .{ 0x28, '\x0A',          '\x0A',          '\x0A',          '\x0A' },
    .{ 0x29, '\x1B',          '\x1B',          '\x1B',          '\x1B' },
    .{ 0x2A, '\x7F',          '\x7F',          '\x7F',          '\x7F' },
    .{ 0x2B, '\x09',          '\x09',          '\x09',          '\x09' },
    .{ 0x2C, ' ',             ' ',             ' ',             ' ' },
    .{ 0x2D, '-',             '_',             '-',             '_' },
    .{ 0x2E, '=',             '+',             '=',             '+' },
    .{ 0x2F, '[',             '{',             '[',             '{' },
    .{ 0x30, ']',             '}',             ']',             '}' },
    .{ 0x31, '\\',            '|',             '\\',            '|' },
    .{ 0x32, '#',             '~',             '#',             '~' },
    .{ 0x33, ';',             ':',             ';',             ':' },
    .{ 0x34, '\'',            '\"',            '\'',            '\"' },
    .{ 0x35, '`',             '~',             '`',             '~' },
    .{ 0x36, ',',             '<',             ',',             '<' },
    .{ 0x37, '.',             '>',             '.',             '>' },
    .{ 0x38, '/',             '?',             '/',             '?' },
    .{ 0x39, 0x00,            0x00,            0x00,            0x00 },            // Caps Lock
    .{ 0x3A, key.F1,          key.SHIFT_F1,    0x00,            0x00 },
    .{ 0x3B, key.F2,          key.SHIFT_F2,    0x00,            0x00 },
    .{ 0x3C, key.F3,          key.SHIFT_F3,    0x00,            0x00 },
    .{ 0x3D, key.F4,          key.SHIFT_F4,    0x00,            0x00 },
    .{ 0x3E, key.F5,          key.SHIFT_F5,    0x00,            0x00 },
    .{ 0x3F, key.F6,          key.SHIFT_F6,    0x00,            0x00 },
    .{ 0x40, key.F7,          key.SHIFT_F7,    0x00,            0x00 },
    .{ 0x41, key.F8,          key.SHIFT_F8,    0x00,            0x00 },
    .{ 0x42, key.F9,          key.SHIFT_F9,    0x00,            0x00 },
    .{ 0x43, key.F10,         key.SHIFT_F10,   0x00,            0x00 },
    .{ 0x44, key.F11,         key.SHIFT_F11,   0x00,            0x00 },
    .{ 0x45, key.F12,         key.SHIFT_F12,   0x00,            0x00 },
    .{ 0x4A, key.HOME,        key.HOME,        key.HOME,        key.HOME },
    .{ 0x4D, key.END,         key.END,         key.END,         key.END },
    .{ 0x4F, key.RIGHT_ARROW, key.RIGHT_ARROW, key.RIGHT_ARROW, key.RIGHT_ARROW },
    .{ 0x50, key.LEFT_ARROW,  key.LEFT_ARROW,  key.LEFT_ARROW,  key.LEFT_ARROW },
    .{ 0x51, key.DOWN_ARROW,  key.DOWN_ARROW,  key.DOWN_ARROW,  key.DOWN_ARROW },
    .{ 0x52, key.UP_ARROW,    key.UP_ARROW,    key.UP_ARROW,    key.UP_ARROW },
};
// zig fmt: on

pub const Usage = struct {
    value: [4]key.Keycode,

    fn fromSpec(tuple: struct { u8, key.Keycode, key.Keycode, key.Keycode, key.Keycode }) Usage {
        return .{
            .value = .{
                tuple[1],
                tuple[2] | key.MOD_SHIFT,
                tuple[3] | key.MOD_CONTROL,
                tuple[4] | key.MOD_CONTROL | key.MOD_SHIFT,
            },
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

pub fn hidkbdClassDriverBind(port: *hub.HubPort, interface: u8) core.Error!void {
    const iface = &port.interfaces[interface];
    const ep_int_in = selectInterruptEndpoint(iface) orelse return core.Error.ConfigurationError;

    keyboard_port = port;
    keyboard_endpoint = &iface.alternate[0].ep[ep_int_in];
    keyboard_interval = iface.alternate[0].ep[ep_int_in].ep_desc.interval;

    port.setup = .{
        .request_type = usb.USB_REQUEST_TYPE_INTERFACE_CLASS_OUT,
        .request = usb.HID_REQUEST_SET_PROTOCOL,
        .value = 0,
        .index = interface,
        .data_size = 0,
    };

    _ = usb.controlTransfer(port, &port.setup, null) catch |err| {
        log.warn(@src(), "cannot set keyboard to use boot protocol {any}", .{err});
        return err;
    };

    driver_initialized.signal();
}

pub fn hidkbdClassDriverUnbind(port: *hub.HubPort, interface: u8) !void {
    _ = interface;
    _ = port;
}

pub fn hidkbdDriverInitialize(allocator: Allocator) !void {
    _ = allocator;
    log = Logger.init("usb_hid_keyboard", .info);
}

pub const class_driver: class.Driver = .{
    .name = "USB Keyboard",
    .initialize = hidkbdDriverInitialize,
    .bind = hidkbdClassDriverBind,
    .unbind = hidkbdClassDriverUnbind,
};
