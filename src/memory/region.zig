const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;

pub const Region = struct {
    name: ?[]const u8 = null,
    base: usize = undefined,
    size: usize = undefined,
    end: usize = undefined,

    pub fn fromSize(self: *Region, base: usize, size: usize) void {
        assert(size > 0);

        self.base = base;
        self.size = size;
        self.end = (base + size) - 1;
    }

    pub fn fromStartToEnd(self: *Region, start: usize, end: usize) void {
        assert(end > start);

        self.base = start;
        self.size = (end - start) + 1;
        self.end = end;
    }

    pub fn print(self: *const Region, writer: anytype) !void {
        var w = writer;
        if (self.name) |n| {
            w.print("{?s:>20}: 0x{x:0>8} .. 0x{x:0>8}\n", .{ n, self.base, self.end }) catch {};
        } else {
            w.print("{?s:>20}: 0x{x:0>8} .. 0x{x:0>8}\n", .{ "unnamed region", self.base, self.end }) catch {};
        }
    }
};
