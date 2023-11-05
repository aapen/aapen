const std = @import("std");
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const RingBuffer = std.RingBuffer;

const root = @import("root");

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (comptime !std.log.logEnabled(level, scope)) return;

    const prefix = "[" ++ comptime level.asText() ++ "] (" ++ @tagName(scope) ++ "): ";

    // TODO acquire spinlock
    // TODO defer release spinlock
    if (root.uart_valid) {
        root.HAL.serial_writer.print(prefix ++ format ++ "\n", args) catch {};
    }

    if (root.console_valid) {
        root.frame_buffer_console.print(prefix ++ format ++ "\n", args) catch {};
    }
}

pub fn kprint(comptime fmt: []const u8, args: anytype) void {
    if (root.uart_valid) {
        root.HAL.serial_writer.print(fmt, args) catch {};
    }

    if (root.console_valid) {
        root.frame_buffer_console.print(fmt, args) catch {};
    }
}

// ------------------------------------------------------------------------------
// Kernel message buffer
// ------------------------------------------------------------------------------

pub const MessageBuffer = struct {
    const Self = @This();

    ring: RingBuffer,

    pub fn init(raw_space: []u8) Allocator.Error!Self {
        var fba = FixedBufferAllocator.init(raw_space);
        var allocator = fba.allocator();
        var ring = try RingBuffer.init(allocator, raw_space.len);
        return .{
            .ring = ring,
        };
    }

    pub fn append(message_buffer: *Self, msg: []const u8) void {
        message_buffer.ring.writeSliceAssumeCapacity(msg);
        message_buffer.ring.writeAssumeCapacity(@as(u8, 0));
    }
};
