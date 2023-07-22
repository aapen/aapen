const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;

pub const Region = struct {
    name: ?[]const u8 = null,
    base: usize,
    size: usize,
    end: usize,

    pub fn fromSize(base: usize, size: usize) Region {
        assert(size > 0);

        return Region{
            .base = base,
            .size = size,
            .end = (base + size) - 1,
        };
    }

    pub fn fromStartToEnd(start: usize, end: usize) Region {
        assert(end > start);

        return Region{
            .base = start,
            .size = (end - start) + 1,
            .end = end,
        };
    }

    pub fn print(self: *const Region, writer: anytype) !void {
        if (self.name) |n| {
            writer.print("{?s:>20}: 0x{x:0>8} .. 0x{x:0>8}\n", .{ n, self.base, self.end }) catch {};
        } else {
            writer.print("{?s:>20}: 0x{x:0>8} .. 0x{x:0>8}\n", .{ "unnamed region", self.base, self.end }) catch {};
        }
    }
};

test "equivalence" {
    var r1 = Region.fromSize(0x1000, 0x2000);
    var r2 = Region.fromStartToEnd(0x1000, 0x2fff);

    try expect(std.meta.eql(r1, r2));
}
