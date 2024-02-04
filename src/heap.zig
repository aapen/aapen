const std = @import("std");
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const root = @import("root");

const memory = @import("memory.zig");
const Region = memory.Region;

const Self = @This();

var range: Region = undefined;
var fba: FixedBufferAllocator = undefined;
pub var allocator: Allocator = undefined;

const HAL = root.HAL;

pub fn init() !void {
    // while testing the new allocator, make sure we push this way up
    // out of the way
    const heap_start: u64 = @intFromPtr(HAL.heap_start) + 10_000_000;

    range = Region.fromStartToEnd("kernel heap", heap_start, HAL.heap_end);
    fba = range.allocator();
    allocator = fba.allocator();
}
