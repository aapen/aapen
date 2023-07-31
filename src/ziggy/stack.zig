const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

pub fn Stack(comptime T: type) type {
    return struct {
        contents: ArrayList(T),
        sp: usize,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return Self{
                .contents = ArrayList(T).init(allocator),
                .sp = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.contents.deinit();
            self.sp = 0;
        }

        pub fn push(self: *Self, value: T) !void {
            try self.contents.append(value);
            self.sp += 1;
        }

        pub fn pop(self: *Self) !T {
            if (self.isEmpty()) {
                return ForthError.UnderFlow;
            }
            var result = self.contents.items[self.sp - 1];
            self.sp -= 1;
            return result;
        }

        pub fn isEmpty(self: *Self) bool {
            return self.sp == 0;
        }

        pub fn items(self: *Self) []T {
            return self.contents.items[0..self.sp];
        }

        pub fn peek(self: *Self) !T {
            if (self.isEmpty()) {
                return ForthError.UnderFlow;
            }
            return self.contents.items[self.sp - 1];
        }
    };
}

test "Basic stack operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.testing.expect(gpa.deinit() == .ok) catch @panic("leak");
    var allocator = gpa.allocator();

    const print = std.debug.print;

    const DStack = Stack(i32);
    var dstack = DStack.init(allocator);
    defer dstack.deinit();

    const RStack = Stack(u16);
    var rstack = RStack.init(allocator);
    defer rstack.deinit();

    for (0..7) |i| {
        try dstack.push(@as(i32, @intCast(i)) * 10);
        try rstack.push(@as(u16, @intCast(i)));
    }

    while (!dstack.isEmpty()) {
        var v = try dstack.pop();
        print("pop: {}\n", .{v});
    }

    while (!rstack.isEmpty()) {
        var v = try rstack.pop();
        print("rop: {}\n", .{v});
    }
}
