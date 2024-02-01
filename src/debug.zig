const std = @import("std");
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const RingBuffer = std.RingBuffer;

const root = @import("root");
const printf = root.printf;

const Forth = @import("forty/forth.zig").Forth;
const auto = @import("forty/auto.zig");

const serial = @import("serial.zig");

const synchronize = @import("synchronize.zig");
const TicketLock = synchronize.TicketLock;

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

pub fn sliceDumpAsWords(buf: []const u8) void {
    const buf_words = std.mem.bytesAsSlice(u32, buf);
    const len = buf_words.len;
    var offset: usize = 0;

    while (offset < len) {
        _ = printf("%016x  %08x\n", @intFromPtr(buf_words.ptr) + offset, buf_words[offset]);
        offset += 1;
    }
}

pub fn sliceDump(buf: []const u8) void {
    const len = buf.len;
    var offset: usize = 0;

    while (offset < len) {
        _ = printf("%016x  ", @intFromPtr(buf.ptr) + offset);

        for (0..16) |iByte| {
            if (offset + iByte < len) {
                _ = printf("%02x ", buf[offset + iByte]);
            } else {
                _ = printf("   ");
            }
            if (iByte == 7) {
                _ = printf("  ");
            }
        }
        printf("  |");
        for (0..16) |iByte| {
            if (offset + iByte < len) {
                _ = printf("%c", string.toPrintable(buf[offset + iByte]));
            } else {
                _ = printf(" ");
            }
        }
        printf("|\n");
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
var mring_spinlock: TicketLock = TicketLock.init("kernel_message_ring", true);
var ring: RingBuffer = undefined;

// implementation variables... not for use outside of init()
var fba: FixedBufferAllocator = undefined;
var allocator: Allocator = undefined;

pub fn init() !void {
    fba = FixedBufferAllocator.init(&mring_storage);
    allocator = fba.allocator();
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
    _ = printf("%s: %s\n", msg.ptr, @errorName(err).ptr);
}
