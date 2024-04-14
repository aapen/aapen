const std = @import("std");
const RingBuffer = std.RingBuffer;

const schedule = @import("schedule.zig");

const INPUT_BUFFER_SIZE = 16;
var buffer_storage: [INPUT_BUFFER_SIZE]u8 = undefined;
var buffer: RingBuffer = undefined;

pub fn init() void {
    buffer = RingBuffer{
        .data = &buffer_storage,
        .write_index = 0,
        .read_index = 0,
    };
}

pub fn write(ch: u8) void {
    buffer.writeAssumeCapacity(ch);
}

pub fn isEmpty() bool {
    return buffer.len() == 0;
}

pub fn read() u8 {
    while (isEmpty()) {
        schedule.sleep(20) catch {};
    }

    return buffer.read() orelse 0;
}
