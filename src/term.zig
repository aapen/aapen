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

// TODO We should probably have a timeout on the ESC1 and CSI
// states. On timeout it would write the chars and return to
// normal state.

// Normal -> keys pass through
// ESC1 -> we've received the initial escape key
// CSI -> we received ESC-[ the "Control Sequence Introducer"
// FN1_4 -> we received ESC-O which starts F1 - F4
// FN_ALL -> we received ESC-[1 or ESC-[2 which indicates F5 - F12
// ExpectTilde -> we think the command is complete but need to see ~
const State = enum { Normal, ESC1, CSI, FN1_4, FN_ALL, ExpectTilde };
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

pub fn in(ch: u8) void {
    switch (state) {
        .ESC1 => {
            switch (ch) {
                '[' => {
                    state = .CSI;
                },
                'O' => {
                    state = .FN1_4;
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
                'A' => {
                    up(key.UP_ARROW);
                    state = .Normal;
                },
                'B' => {
                    up(key.DOWN_ARROW);
                    state = .Normal;
                },
                'C' => {
                    up(key.RIGHT_ARROW);
                    state = .Normal;
                },
                'D' => {
                    up(key.LEFT_ARROW);
                    state = .Normal;
                },
                'F' => {
                    up(key.END);
                    state = .Normal;
                },
                'H' => {
                    up(key.HOME);
                    state = .Normal;
                },
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
                0x50 => up(key.F1),
                0x51 => up(key.F2),
                0x52 => up(key.F3),
                0x53 => up(key.F4),
                else => {
                    // we previously swallowed the ESC and O, send
                    // them now
                    up(key.ESCAPE);
                    up('O');
                    up(ch);
                },
            }
            state = .Normal;
        },
        .FN_ALL => {
            if (pending == '1') {
                switch (ch) {
                    '5' => {
                        pending = key.F5;
                        state = .ExpectTilde;
                    },
                    '7' => {
                        pending = key.F6;
                        state = .ExpectTilde;
                    },
                    '8' => {
                        pending = key.F7;
                        state = .ExpectTilde;
                    },
                    '9' => {
                        pending = key.F8;
                        state = .ExpectTilde;
                    },
                    else => resetPending(),
                }
            } else if (pending == '2') {
                switch (ch) {
                    '0' => {
                        pending = key.F9;
                        state = .ExpectTilde;
                    },
                    '1' => {
                        pending = key.F10;
                        state = .ExpectTilde;
                    },
                    '3' => {
                        pending = key.F11;
                        state = .ExpectTilde;
                    },
                    '4' => {
                        pending = key.F12;
                        state = .ExpectTilde;
                    },
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
                ascii.ESCAPE => {
                    state = .ESC1;
                },
                else => up(ch),
            }
        },
    }
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
