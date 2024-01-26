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
    range = Region.fromStartToEnd("kernel heap", @intFromPtr(HAL.heap_start), HAL.heap_end);
    fba = range.allocator();
    allocator = fba.allocator();
}
