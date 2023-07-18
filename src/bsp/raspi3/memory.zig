const std = @import("std");
const assert = std.debug.assert;
const memory_map = @import("memory_map.zig");

pub const linker_heap_start: *u64 = @extern(*u64, .{ .name = "__heap_start" });

fn is_power_of_two(v: u64) bool {
    return (v & (v - 1) == 0);
}

fn align_down(v: u64, alignment: u64) u64 {
    return v & ~(alignment - 1);
}

pub const Heap = struct {
    page_size: u64,
    start: *u64,
    end: *u64,
};

pub fn create_greedy(page_size: u64) Heap {
    assert(is_power_of_two(page_size));
    return Heap{
        .page_size = page_size,
        .start = linker_heap_start,
        .end = @ptrFromInt(align_down(memory_map.device_start - 1, page_size)),
    };
}
