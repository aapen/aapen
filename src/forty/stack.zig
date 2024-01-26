const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

pub fn Stack(comptime T: type) type {
    return struct {
        contents: ArrayList(T),
        // sp: usize,

        const Self = @This();

        pub fn init(allocator: *const Allocator) Self {
            return Self{
                .contents = ArrayList(T).init(allocator.*),
            };
        }

        pub fn deinit(self: *Self) void {
            self.contents.deinit();
        }

        pub fn reset(self: *Self) !void {
            while (!self.isEmpty()) {
                _ = try self.pop();
            }
        }

        pub inline fn push(self: *Self, value: T) !void {
            try self.contents.append(value);
        }

        pub inline fn pop(self: *Self) !T {
            if (self.isEmpty()) {
                return ForthError.UnderFlow;
            }
            return self.contents.pop();
        }

        pub inline fn isEmpty(self: *Self) bool {
            return self.contents.items.len == 0;
        }

        pub inline fn depth(self: *Self) usize {
            return self.contents.items.len;
        }

        pub fn items(self: *Self) []T {
            return self.contents.items;
        }

        pub fn peek(self: *Self) !T {
            if (self.isEmpty()) {
                return ForthError.UnderFlow;
            }
            return self.contents.getLast();
        }
    };
}
