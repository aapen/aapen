const std = @import("std");
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const root = @import("root");

const memory = @import("memory.zig");
const Region = memory.Region;

const Self = @This();

range: Region = undefined,
fba: FixedBufferAllocator = undefined,
allocator: Allocator = undefined,

const HAL = root.HAL;

var the_heap: Self = Self{};

pub fn init() !*Self {
    the_heap.range = Region.fromStartToEnd("kernel heap", @intFromPtr(HAL.heap_start), HAL.heap_end);
    the_heap.fba = the_heap.range.allocator();
    the_heap.allocator = the_heap.fba.allocator();
    return &the_heap;
}
