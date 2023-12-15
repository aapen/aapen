const std = @import("std");
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const RingBuffer = std.RingBuffer;

const root = @import("root");

const serial = @import("serial.zig");

const synchronize = @import("synchronize.zig");
const Spinlock = synchronize.Spinlock;

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (comptime !std.log.logEnabled(level, scope)) return;

    const prefix = switch (scope) {
        std.log.default_log_scope => "",
        else => @tagName(scope) ++ " ",
    } ++ "[" ++ comptime level.asText() ++ "]: ";

    if (root.main_console_valid) {
        root.main_console.print(prefix ++ format ++ "\n", args) catch {};
    } else {
        serial.writer.print(prefix ++ format ++ "\n", args) catch {};
    }
}

pub fn kprint(comptime fmt: []const u8, args: anytype) void {
    if (root.main_console_valid) {
        root.main_console.print(fmt, args) catch {};
    } else {
        serial.writer.print(fmt, args) catch {};
    }
}

// ------------------------------------------------------------------------------
// Kernel message buffer
// ------------------------------------------------------------------------------

const mring_space_bytes = 1024 * 1024;
pub var mring_storage: [mring_space_bytes]u8 = undefined;
var mring_spinlock: Spinlock = Spinlock.init("kernel_message_ring", true);
var ring: RingBuffer = undefined;

pub fn init() !void {
    var fba = FixedBufferAllocator.init(&mring_storage);
    const allocator = fba.allocator();
    ring = try RingBuffer.init(allocator, mring_storage.len);
}

/// Use this to report low-level errors. It bypasses the serial
/// interface, the frame buffer, and even Zig's formatting. (This does
/// mean you don't get formatted messages, but it also has no chance
/// of panicking.)
pub fn kernelMessage(msg: []const u8) void {
    mring_spinlock.acquire();
    defer mring_spinlock.release();

    ring.writeSliceAssumeCapacity(msg);
    ring.writeAssumeCapacity(@as(u8, 0));
}

pub fn kernelError(msg: []const u8, err: anyerror) void {
    kernelMessage(msg);
    kernelMessage(@errorName(err));
    kprint("{s}: {any}\n", .{ msg, err });
}
