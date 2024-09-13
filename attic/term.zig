const std = @import("std");
const root = @import("root");
const ascii = @import("ascii.zig");
const key = @import("key.zig");
const InputBuffer = @import("input_buffer.zig");
const synchronize = @import("synchronize.zig");

// ----------------------------------------------------------------------
// Private implementation
// ----------------------------------------------------------------------

var serial_lock: synchronize.TicketLock("term") = .{};

// TODO We should probably have a timeout on the ESC and CSI
// states. On timeout it would send up whatever held chars and return
// to normal state.

// Normal      -> keys pass through
// ESC         -> we've received the initial escape key
// CSI         -> we received ESC-[ the "Control Sequence Introducer"
// FN1_4       -> we received ESC-O which starts F1 - F4
// FN_ALL      -> we received ESC-[1 or ESC-[2 which indicates F5 - F12
// ExpectTilde -> we think the command is complete but need to see ~
const State = enum { Normal, ESC, CSI, FN1_4, FN_ALL, ExpectTilde };
var state: State = .Normal;

// "up" from the terminal to the OS. Keycodes go up.
inline fn up(ch: key.Keycode) void {
    InputBuffer.write(ch);
}

// "down" from the OS to the terminal. Bytes go down.
inline fn down(ch: u8) void {
    root.hal.uart.putc(ch);
}

inline fn control(seq: []const u8) void {
    inline for (seq) |c| {
        down(c);
    }
}

/// Send an outbound keycode. Translates some keycodes into a subset
/// of ANSI escape sequences.
pub fn out(ch: key.Keycode) void {
    switch (ch) {
        key.NL => {
            down(ascii.CR);
            down(ascii.NL);
        },
        key.DEL => {
            down(ascii.BS);
            down(ascii.SPACE);
            down(ascii.BS);
        },
        key.UP_ARROW => control("\x1b[A"),
        key.DOWN_ARROW => control("\x1b[B"),
        key.LEFT_ARROW => control("\x1b[D"),
        key.RIGHT_ARROW => control("\x1b[C"),
        key.HOME => control("\x1b[1G"),
        // next one is tricky... we don't know
        // how many characters are in the line
        key.END => control("\x1b[128G"),

        key.F1...key.F12,
        key.FIRST_UNASSIGNED_KEY...key.KEYCODE_MAX,
        => {
            // ignore
        },
        else => down(@truncate(ch & 0xff)),
    }
}

/// Process an incoming serial byte. This uses a subset of ANSI escape
/// sequences that seems to be common across several terminals on Linux
/// and macOS. May or may not work on Putty.
pub fn in(ch: u8) void {
    switch (state) {
        .ESC => {
            switch (ch) {
                '[' => state = .CSI,
                'O' => state = .FN1_4,
                else => {
                    // we previously swallowed the ESC, send it
                    // now.
                    up(ascii.ESCAPE);
                    upAndReset(ch);
                },
            }
        },
        .CSI => {
            switch (ch) {
                'A' => upAndReset(key.UP_ARROW),
                'B' => upAndReset(key.DOWN_ARROW),
                'C' => upAndReset(key.RIGHT_ARROW),
                'D' => upAndReset(key.LEFT_ARROW),
                'F' => upAndReset(key.END),
                'H' => upAndReset(key.HOME),
                '1', '2' => {
                    pending = ch;
                    state = .FN_ALL;
                },
                else => {
                    // we previously swallowed the ESC and [, send
                    // them now
                    up(key.ESCAPE);
                    up('[');
                    up(ch);
                    state = .Normal;
                },
            }
        },
        .FN1_4 => {
            switch (ch) {
                0x50 => upAndReset(key.F1),
                0x51 => upAndReset(key.F2),
                0x52 => upAndReset(key.F3),
                0x53 => upAndReset(key.F4),
                else => {
                    // we previously swallowed the ESC and O, send
                    // them now
                    up(key.ESCAPE);
                    up('O');
                    upAndReset(ch);
                },
            }
        },
        .FN_ALL => {
            if (pending == '1') {
                switch (ch) {
                    '5' => expectTildeThenUp(key.F5),
                    '7' => expectTildeThenUp(key.F6),
                    '8' => expectTildeThenUp(key.F7),
                    '9' => expectTildeThenUp(key.F8),
                    else => resetPending(),
                }
            } else if (pending == '2') {
                switch (ch) {
                    '0' => expectTildeThenUp(key.F9),
                    '1' => expectTildeThenUp(key.F10),
                    '3' => expectTildeThenUp(key.F11),
                    '4' => expectTildeThenUp(key.F12),
                    else => resetPending(),
                }
            } else {
                resetPending();
            }
        },
        .ExpectTilde => {
            switch (ch) {
                '~' => deliverPending(),
                else => {},
            }
            resetPending();
        },
        else => {
            switch (ch) {
                ascii.ESCAPE => state = .ESC,
                else => up(ch),
            }
        },
    }
}

inline fn upAndReset(k: key.Keycode) void {
    up(k);
    state = .Normal;
}

inline fn expectTildeThenUp(k: key.Keycode) void {
    pending = k;
    state = .ExpectTilde;
}

var pending: key.Keycode = 0;

inline fn deliverPending() void {
    up(pending);
}

inline fn resetPending() void {
    pending = 0;
    state = .Normal;
}

// ----------------------------------------------------------------------
// Public interface
// ----------------------------------------------------------------------
pub fn putch(ch: key.Keycode) void {
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
