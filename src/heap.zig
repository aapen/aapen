const std = @import("std");
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const memory = @import("memory.zig");
const Region = memory.Region;

pub var range: Region = undefined;
var fba: FixedBufferAllocator = undefined;
pub var allocator: Allocator = undefined;

pub fn init(lower_bound: usize, upper_bound: usize) void {
    range = Region.fromStartToEnd("kernel heap", lower_bound, upper_bound);
    fba = range.allocator();
    allocator = fba.allocator();
}
