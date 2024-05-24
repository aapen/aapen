const std = @import("std");

const root = @import("root");
const HAL = root.HAL;

const synchronize = @import("synchronize.zig");
const TicketLock = synchronize.TicketLock;

// ----------------------------------------------------------------------
// Private
// ----------------------------------------------------------------------

var serial_lock: TicketLock("serial output") = .{ .enabled = false };

// ----------------------------------------------------------------------
// Low level interface
// ----------------------------------------------------------------------

pub fn putc(ch: u8) void {
    // TODO wait until there is space to transmit
    if (ch == '\n') {
        root.hal.uart.putc('\r');
    }
    root.hal.uart.putc(ch);
}

pub fn puts(string: []const u8) usize {
    serial_lock.acquire();
    defer serial_lock.release();

    for (string) |ch| {
        putc(ch);
    }
    return string.len;
}

// ----------------------------------------------------------------------
// High level interface
// ----------------------------------------------------------------------
fn stringSendSerial(_: *const anyopaque, str: []const u8) !usize {
    if (root.uart_valid) {
        return puts(str);
    } else {
        return str.len;
    }
}

const SerialWriter = std.io.Writer(*const anyopaque, error{}, stringSendSerial);

pub var writer: SerialWriter = .{ .context = "ignored" };
