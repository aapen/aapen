const std = @import("std");
const root = @import("root");
const HalUart = root.HAL.Uart;
const ascii = @import("ascii.zig");
const InputBuffer = @import("input_buffer.zig");
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

const HalfAnsi = struct {
    const Self = @This();

    // TODO We should probably have a timeout on the ESC1 and CSI
    // states. On timeout it would write the chars and return to
    // normal state.

    // Normal -> keys pass through
    // ESC1 -> we've received the initial escape key
    // CSI -> we received ESC-[ the "Control Sequence Introducer"
    const State = enum { Normal, ESC1, CSI };

    uart: Uart,
    state: State = .Normal,

    pub fn out(self: *Self, ch: u8) void {
        switch (ch) {
            ascii.NL => {
                self.uart.out(ascii.CR);
                self.uart.out(ascii.NL);
            },
            ascii.DEL => {
                self.uart.out(ascii.BS);
                self.uart.out(ascii.SPACE);
                self.uart.out(ascii.BS);
            },
            else => self.uart.out(ch),
        }
    }

    pub fn in(self: *Self, ch: u8) void {
        switch (self.state) {
            .ESC1 => {
                switch (ch) {
                    '[' => {
                        self.state = .CSI;
                    },
                    else => {
                        // we previously swallowed the ESC, send it
                        // now.
                        self.state = .Normal;
                        write(ascii.ESCAPE);
                        write(ch);
                    },
                }
            },
            .CSI => {
                switch (ch) {
                    'A' => {
                        // cursor up
                        write(0x80); // phony right-arrow keycode
                        self.state = .Normal;
                    },
                    'B' => {
                        // cursor down
                        write(0x81); // phony down-arrow keycode
                        self.state = .Normal;
                    },
                    'C' => {
                        // cursor right
                        write(0x83); // phony right-arrow keycode
                        self.state = .Normal;
                    },
                    'D' => {
                        // cursor left
                        write(0x82); // phony left-arrow keycode
                        self.state = .Normal;
                    },
                    'F' => {
                        // end
                        write(0x85); // phony end keycode
                        self.state = .Normal;
                    },
                    'H' => {
                        // home
                        write(0x84); // phony home keycode
                        self.state = .Normal;
                    },
                    else => {
                        // we previously swallowed the ESC and [, send
                        // them now
                        self.state = .Normal;
                        write(ascii.ESCAPE);
                        write('[');
                        write(ch);
                    },
                }
            },
            else => {
                switch (ch) {
                    ascii.ESCAPE => {
                        self.state = .ESC1;
                    },
                    else => write(ch),
                }
            },
        }
    }

    inline fn write(ch: u8) void {
        InputBuffer.write(ch);
    }
};

var term: HalfAnsi = undefined;

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

// ----------------------------------------------------------------------
// Input up from hardware
// ----------------------------------------------------------------------
pub fn recv(ch: u8) void {
    term.in(ch);
}
