const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

pub const History = struct {
    allocator: Allocator = undefined,
    max_size: usize = 10,
    contents: ArrayList([]u8) = undefined,

    pub fn init(allocator: Allocator, max_size: usize) History {
        var result = History{};
        result.setUp(allocator, max_size);
        return result;
    }

    pub fn setUp(self: *History, allocator: Allocator, max_size: usize) void {
        self.allocator = allocator;
        self.max_size = max_size;
        self.contents = ArrayList([]u8).init(allocator);
    }

    pub fn deinit(self: *History) void {
        while (self.contents.popOrNull()) |s| {
            self.allocator.free(s);
        }
        self.contents.deinit();
    }

    pub fn add(self: *History, cmd: []u8) !void {
        self.make_room();
        const s_copy = try self.allocator.dupe(u8, cmd);
        try self.contents.append(s_copy);
    }

    fn make_room(self: *History) void {
        if (self.contents.items.len >= self.max_size) {
            const s = self.contents.orderedRemove(0);
            self.allocator.free(s);
        }
    }

    pub fn items(self: *History) [][]u8 {
        return self.contents.items;
    }
};

pub fn main() !void {
    const print = std.debug.print;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }
    var allocator = gpa.allocator();

    var h = History.init(&allocator, 10);

    for (0..15) |i| {
        var s: [3]u8 = undefined;
        s[0] = 'C';
        s[1] = 'A' + @as(u8, @intCast(i));
        s[2] = 0;
        try h.add(&s);
        const items = h.items();
        print("\n======== {} =========\n", .{i});
        for (items) |item| {
            print("item {s}\n", .{item});
        }
    }
    h.deinit();
}
