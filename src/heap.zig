const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const HAL = root.HAL;

const MemoryPageAllocator = @import("heap/page_allocator.zig");

pub var page_allocator: Allocator = undefined;

pub fn init() void {
    const real_heap_start: u64 = @intFromPtr(HAL.heap_start);
    const real_heap_end: u64 = HAL.heap_end;

    page_allocator = MemoryPageAllocator.init(real_heap_start, real_heap_end);
}
