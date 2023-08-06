const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

const readFn = *const fn (ctx: *anyopaque, prompt: []const u8, buffer: []u8) usize;

ptr: *anyopaque,
rf: readFn,

pub fn init(allocator: Allocator, ptr: *anyopaque, rf: readFn) !*Self {
    var s = try allocator.create(Self);
    s.ptr = ptr;
    s.rf = rf;
    return s;
}

pub fn read(self: *Self, prompt: []const u8, buffer: []u8) usize {
    return self.rf(self.ptr, prompt, buffer);
}
