const std = @import("std");
const root = @import("root");
const ascii = @import("ascii.zig");
const InputBuffer = @import("input_buffer.zig");
const synchronize = @import("synchronize.zig");

// ----------------------------------------------------------------------
// Private implementation
// ----------------------------------------------------------------------

var serial_lock: synchronize.TicketLock("term") = .{};

// TODO We should probably have a timeout on the ESC1 and CSI
// states. On timeout it would write the chars and return to
// normal state.

// Normal -> keys pass through
// ESC1 -> we've received the initial escape key
// CSI -> we received ESC-[ the "Control Sequence Introducer"
const State = enum { Normal, ESC1, CSI };
var state: State = .Normal;

// "up" from the terminal to the OS
inline fn up(ch: u8) void {
    InputBuffer.write(ch);
}

// "down" from the OS to the terminal
inline fn down(ch: u8) void {
    root.hal.uart.putc(ch);
}

inline fn control(seq: []const u8) void {
    inline for (seq) |c| {
        down(c);
    }
}

pub fn out(ch: u8) void {
    switch (ch) {
        ascii.NL => {
            down(ascii.CR);
            down(ascii.NL);
        },
        ascii.DEL => {
            down(ascii.BS);
            down(ascii.SPACE);
            down(ascii.BS);
        },
        0x80 => control("\x1b[A"),
        0x81 => control("\x1b[B"),
        0x82 => control("\x1b[D"),
        0x83 => control("\x1b[C"),
        0x84 => control("\x1b[1G"),
        // next one is tricky... we don't know
        // how many characters are in the line
        0x85 => control("\x1b[128G"),
        else => down(ch),
    }
}

pub fn in(ch: u8) void {
    switch (state) {
        .ESC1 => {
            switch (ch) {
                '[' => {
                    state = .CSI;
                },
                else => {
                    // we previously swallowed the ESC, send it
                    // now.
                    state = .Normal;
                    up(ascii.ESCAPE);
                    up(ch);
                },
            }
        },
        .CSI => {
            switch (ch) {
                'A' => up(0x80), // phony right-arrow keycode
                'B' => up(0x81), // phony down-arrow keycode
                'C' => up(0x83), // phony right-arrow keycode
                'D' => up(0x82), // phony left-arrow keycode
                'F' => up(0x85), // phony end keycode
                'H' => up(0x84), // phony home keycode
                else => {
                    // we previously swallowed the ESC and [, send
                    // them now
                    up(ascii.ESCAPE);
                    up('[');
                    up(ch);
                },
            }
            state = .Normal;
        },
        else => {
            switch (ch) {
                ascii.ESCAPE => {
                    state = .ESC1;
                },
                else => up(ch),
            }
        },
    }
}

// ----------------------------------------------------------------------
// Public interface
// ----------------------------------------------------------------------
pub fn putch(ch: u8) void {
    out(ch);
}

pub fn puts(str: []const u8) void {
    serial_lock.acquire();
    defer serial_lock.release();

    for (str) |ch| {
        out(ch);
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
