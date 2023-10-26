const root = @import("root");
const std = @import("std");
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

pub const Regions = ArrayList(Region);

pub const Region = struct {
    name: ?[]const u8 = null,
    base: usize = undefined,
    size: usize = undefined,
    end: usize = undefined,

    pub fn fromSize(name: []const u8, base: usize, size: usize) Region {
        assert(size > 0);

        return .{
            .name = name,
            .base = base,
            .size = size,
            .end = (base + size) - 1,
        };
    }

    pub fn fromStartToEnd(name: []const u8, start: usize, end: usize) Region {
        assert(end > start);
        return .{
            .name = name,
            .base = start,
            .size = (end - start) + 1,
            .end = end,
        };
    }

    pub fn print(self: *const Region) !void {
        if (self.name) |n| {
            root.kprint("{?s:>20}: 0x{x:0>8} .. 0x{x:0>8}\n", .{ n, self.base, self.end });
        } else {
            root.kprint("{?s:>20}: 0x{x:0>8} .. 0x{x:0>8}\n", .{ "unnamed region", self.base, self.end });
        }
    }

    pub fn allocator(self: *const Region) std.heap.FixedBufferAllocator {
        const base: [*]u8 = @ptrFromInt(self.base);
        return std.heap.FixedBufferAllocator.init(base[0..self.size]);
    }
};
