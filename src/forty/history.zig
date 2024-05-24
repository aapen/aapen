const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const History = @This();

allocator: Allocator,
max_size: usize = 10,
contents: ArrayList([]u8),

pub fn init(allocator: Allocator, max_size: usize) History {
    return .{
        .allocator = allocator,
        .max_size = max_size,
        .contents = ArrayList([]u8).init(allocator),
    };
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

pub fn items(self: *const History) [][]u8 {
    return self.contents.items;
}
