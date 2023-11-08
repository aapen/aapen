const std = @import("std");
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const memory = @import("memory.zig");
const Region = memory.Region;

const Self = @This();

range: Region,
fba: FixedBufferAllocator,

pub fn init(lower_bound: usize, upper_bound: usize) Self {
    const region = Region.fromStartToEnd("kernel heap", lower_bound, upper_bound);
    return .{
        .range = region,
        .fba = region.allocator(),
    };
}

pub fn allocator(self: *Self) Allocator {
    return self.fba.allocator();
}
