const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const term = @import("term.zig");

const Forth = @import("forty/forth.zig");

const CharBufferConsole = @import("char_buffer_console.zig");
const InputBuffer = @import("input_buffer.zig");

const Self = @This();

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------

pub fn defineModule(forth: *Forth, console: *Self) !void {
    try forth.defineStruct("MainConsole", Self, .{});
    try forth.defineConstant("console", @intFromPtr(console));
}

// ----------------------------------------------------------------------
// Zig affordances
// ----------------------------------------------------------------------
pub const Writer = std.io.Writer(*Self, error{}, write);

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
        term.putch(ch);
    }
    return bytes.len;
}

pub fn writer(self: *Self) Writer {
    return .{ .context = self };
}

pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
    try self.writer().print(fmt, args);
}

pub fn getc(self: *Self) u8 {
    _ = self;
    const ch = InputBuffer.read();
    return if (ch == '\r') '\n' else ch;
}

pub fn putc(self: *Self, ch: u8) void {
    term.putch(ch);
    self.char_buffer_console.emit(ch);
}

pub fn char_available(self: *Self) bool {
    _ = self;
    return !InputBuffer.isEmpty();
}

fn newline(ch: u8) bool {
    return ch == '\r' or ch == '\n';
}
