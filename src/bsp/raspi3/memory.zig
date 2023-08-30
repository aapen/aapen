const std = @import("std");
const assert = std.debug.assert;
pub const map = @import("memory_map.zig");
const heap = @import("../../heap.zig");
const Heap = heap.Heap;
const Region = heap.Region;

const Self = @This();

pub const linker_heap_start: *u64 = @extern(*u64, .{ .name = "__heap_start" });

pub fn heapStart() u64 {
    return @intFromPtr(linker_heap_start);
}

pub fn heapEnd() u64 {
    return map.device_start - 1;
}

pub fn physicalToBus(physicalAddress: u64) u64 {
    var pa: u64 = physicalAddress;
    var ba: u64 = pa | 0x4000_0000;
    return ba;
}

pub fn busToPhysical(busAddress: u64) u64 {
    var ba: u64 = busAddress;
    var pa: u64 = ba & ~0xc000_0000;
    return pa;
}
