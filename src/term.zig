const std = @import("std");
const root = @import("root");
const HalUart = root.HAL.Uart;
const synchronize = @import("synchronize.zig");

// ----------------------------------------------------------------------
// Private implementation
// ----------------------------------------------------------------------

const Uart = struct {
    const Self = @This();

    pub fn out(_: *Self, ch: u8) void {
        root.hal.uart.putc(ch);
    }
};

const Vt220 = struct {
    const Self = @This();

    uart: Uart,

    pub fn out(self: *Self, ch: u8) void {
        if (ch == '\n') {
            self.uart.out('\r');
        }

        self.uart.out(ch);
    }
};

var term: Vt220 = undefined;

pub fn init() void {
    term = .{
        .uart = .{},
    };
}

var serial_lock: synchronize.TicketLock("term") = .{};

// ----------------------------------------------------------------------
// Public interface
// ----------------------------------------------------------------------
pub fn putch(ch: u8) void {
    term.out(ch);
}

pub fn puts(str: []const u8) void {
    serial_lock.acquire();
    defer serial_lock.release();

    for (str) |ch| {
        putch(ch);
    }
}

// ----------------------------------------------------------------------
// Writer interface
// ----------------------------------------------------------------------
fn termStringSend(_: *const anyopaque, str: []const u8) !usize {
    puts(str);
    return str.len;
}

const TermWriter = std.io.Writer(*const anyopaque, error{}, termStringSend);

pub var writer: TermWriter = .{ .context = "ignored" };
