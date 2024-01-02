const std = @import("std");
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const RingBuffer = std.RingBuffer;

const root = @import("root");

const Forth = @import("forty/forth.zig").Forth;
const auto = @import("forty/auto.zig");

const serial = @import("serial.zig");

const synchronize = @import("synchronize.zig");
const Spinlock = synchronize.Spinlock;

const string = @import("forty/string.zig");

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

pub fn sliceDumpAsWords(buf: []const u8) void {
    const buf_words = std.mem.bytesAsSlice(u32, buf);
    const len = buf_words.len;
    var offset: usize = 0;

    while (offset < len) {
        kprint("{x:16}  {x:0>8}\n", .{ @intFromPtr(buf_words.ptr) + offset, buf_words[offset] });
        offset += 1;
    }
}

pub fn sliceDump(buf: []const u8) void {
    const len = buf.len;
    var offset: usize = 0;

    while (offset < len) {
        kprint("{x:16}  ", .{@intFromPtr(buf.ptr) + offset});

        for (0..16) |iByte| {
            if (offset + iByte < len) {
                kprint("{x:0>2} ", .{buf[offset + iByte]});
            } else {
                kprint("   ", .{});
            }
            if (iByte == 7) {
                kprint("  ", .{});
            }
        }
        kprint("  |", .{});
        for (0..16) |iByte| {
            if (offset + iByte < len) {
                kprint("{c}", .{string.toPrintable(buf[offset + iByte])});
            } else {
                kprint(" ", .{});
            }
        }
        kprint("|\n", .{});
        offset += 16;
    }
}

// ------------------------------------------------------------------------------
// Kernel message buffer
// ------------------------------------------------------------------------------

pub fn defineModule(forth: *Forth) !void {
    try forth.defineConstant("mring", @intFromPtr(&mring_storage));
}

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
