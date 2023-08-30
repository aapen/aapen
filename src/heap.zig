const std = @import("std");
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const Error = Allocator.Error;
const bsp = @import("bsp.zig");
const Region = @import("memory.zig").Region;

const Self = @This();

pub const linker_heap_start: [*]u8 = @extern([*]u8, .{ .name = "__heap_start" });

page_size: u64 = undefined,
memory: Region = Region{},

fba: FixedBufferAllocator = undefined,

pub fn init(self: *Self, page_size: u64) void {
    self.page_size = page_size;

    var heap_start = @intFromPtr(linker_heap_start);
    var heap_end = bsp.memory.map.device_start - 1;
    var heap_len = heap_end - heap_start;

    self.fba = FixedBufferAllocator.init(linker_heap_start[0..heap_len]);
    self.memory.name = "Kernel Heap";
    self.memory.fromStartToEnd(heap_start, heap_end);
}

pub fn allocator(self: *Self) Allocator {
    return self.fba.allocator();
}
