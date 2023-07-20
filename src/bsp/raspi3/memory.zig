const std = @import("std");
const assert = std.debug.assert;
const memory_map = @import("memory_map.zig");
const mem = @import("../../mem.zig");
const Heap = mem.Heap;
const Region = mem.Region;

pub const linker_heap_start: *u64 = @extern(*u64, .{ .name = "__heap_start" });

fn is_power_of_two(v: u64) bool {
    return (v & (v - 1) == 0);
}

fn align_down(v: u64, alignment: u64) u64 {
    return v & ~(alignment - 1);
}

pub fn create_greedy(page_size: u64) Heap {
    assert(is_power_of_two(page_size));

    var end = align_down(memory_map.device_start - 1, page_size);
    var m = Region.fromStartToEnd(@intFromPtr(linker_heap_start), end);
    m.name = "Kernel heap";

    return Heap{
        .page_size = page_size,
        .memory = m,
    };
}
