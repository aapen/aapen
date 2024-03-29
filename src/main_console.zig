const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const debug = root.debug;

const Forth = @import("forty/forth.zig").Forth;
const auto = @import("forty/auto.zig");

const CharBufferConsole = @import("char_buffer_console.zig");
const Serial = @import("serial.zig");
const Readline = @import("readline.zig");

const Self = @This();

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------

pub fn defineModule(forth: *Forth, console: *Self) !void {
    try forth.defineStruct("MainConsole", Self, .{});
    try forth.defineConstant("console", @intFromPtr(console));
    try forth.defineNamespace(Self, .{.{"chello"}});
}

// ----------------------------------------------------------------------
// Zig affordances
// ----------------------------------------------------------------------
pub const Writer = std.io.Writer(*Self, error{}, write);

// ----------------------------------------------------------------------
// C interop
// ----------------------------------------------------------------------

export fn _putchar(ch: u8) callconv(.C) c_int {
    root.main_console.putc(ch);
    return ch;
}

const cstub = @cImport({
    @cInclude("printf.h");
});

pub const printf = cstub.printf;

pub fn chello() void {
    _ = printf("Hello, %s!\nmain_console.init = 0x%08x\n", "world", &init);
}

// ----------------------------------------------------------------------
// Implementation
// ----------------------------------------------------------------------

char_buffer_console: *CharBufferConsole = undefined,

pub fn init(allocator: Allocator, fbc: *CharBufferConsole) !*Self {
    const self: *Self = try allocator.create(Self);

    self.* = .{
        .char_buffer_console = fbc,
    };

    return self;
}

pub fn write(self: *Self, bytes: []const u8) !usize {
    for (bytes) |ch| {
        self.char_buffer_console.emit(ch);
        Serial.putc(ch);
    }
    return bytes.len;
}

pub fn writer(self: *Self) Writer {
    return .{ .context = self };
}

pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
    try self.writer().print(fmt, args);
}

pub fn readLine(self: *Self, prompt: []const u8, buffer: []u8) usize {
    var i: usize = 0;
    var ch: u8 = 0;
    var echo: bool = true;

    self.char_buffer_console.emitString(prompt);

    while (i < (buffer.len - 1) and !newline(ch)) {
        echo = true;
        ch = self.getc();

        switch (ch) {
            0x7f => if (i > 0) {
                i -= 1;
            } else {
                echo = false;
            },
            else => {
                buffer[i] = ch;
                i += 1;
            },
        }
        if (echo) {
            self.putc(ch);
        }
        buffer[i] = 0;
    }
    return i;
}

pub fn getc(self: *Self) u8 {
    _ = self;
    const ch = Serial.getc();
    return if (ch == '\r') '\n' else ch;
}

pub fn putc(self: *Self, ch: u8) void {
    switch (ch) {
        '\n' => {
            _ = Serial.putc('\r');
            _ = Serial.putc('\n');
        },
        0x7f => {
            _ = Serial.putc(0x08);
            _ = Serial.putc(' ');
            _ = Serial.putc(0x08);
        },
        else => {
            if (std.ascii.isPrint(ch)) {
                _ = Serial.putc(ch);
            }
        },
    }
    self.char_buffer_console.emit(ch);
}

pub fn char_available(self: *Self) bool {
    _ = self;
    return Serial.hasc();
}

fn newline(ch: u8) bool {
    return ch == '\r' or ch == '\n';
}

fn readLineThunk(ctx: *anyopaque, prompt: []const u8, buffer: []u8) Readline.Error!usize {
    var console: *Self = @ptrCast(@alignCast(ctx));
    return console.readLine(prompt, buffer);
}

pub fn createReader(allocator: Allocator, console: *Self) !*Readline {
    return Readline.init(allocator, console, readLineThunk);
}
