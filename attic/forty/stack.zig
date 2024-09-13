const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

pub fn Stack(comptime T: type) type {
    return struct {
        const A = ArrayList(T);

        contents: A,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .contents = A.init(allocator),
            };
        }

        pub fn initCapacity(allocator: Allocator, capacity: usize) !Self {
            return .{
                .contents = try A.initCapacity(allocator, capacity),
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

        pub fn dropN(self: *Self, count: usize) !void {
            for (0..count) |_| {
                _ = try self.pop();
            }
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
