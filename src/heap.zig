const std = @import("std");
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const memory = @import("memory.zig");
const Region = memory.Region;

pub const Heap = struct {
    range: Region,
    fba: FixedBufferAllocator,

    pub fn init(lower_bound: usize, upper_bound: usize) Heap {
        const region = Region.fromStartToEnd("kernel heap", lower_bound, upper_bound);
        return .{
            .range = region,
            .fba = region.allocator(),
        };
    }

    pub fn allocator(self: *Heap) Allocator {
        return self.fba.allocator();
    }
};
