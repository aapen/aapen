const std = @import("std");
const architecture = @import("architecture.zig");
const cpu = architecture.cpu;
const key = @import("key.zig");
const schedule = @import("schedule.zig");

const INPUT_BUFFER_SIZE = 16;
var buffer: [INPUT_BUFFER_SIZE]key.Keycode = [_]key.Keycode{0} ** INPUT_BUFFER_SIZE;
var write_index: usize = 0;
var read_index: usize = 0;

pub fn init() void {}

pub fn write(ch: key.Keycode) void {
    const im = cpu.disable();
    defer cpu.restore(im);

    buffer[write_index] = ch;
    write_index += 1;
    write_index %= INPUT_BUFFER_SIZE;
}

pub fn isEmpty() bool {
    const im = cpu.disable();
    defer cpu.restore(im);

    return write_index == read_index;
}

pub fn read() key.Keycode {
    while (isEmpty()) {
        schedule.sleep(20) catch {};
    }

    const im = cpu.disable();
    defer cpu.restore(im);

    const ret = buffer[read_index];
    read_index += 1;
    read_index %= INPUT_BUFFER_SIZE;
    return ret;
}
