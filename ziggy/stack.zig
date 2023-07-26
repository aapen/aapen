const std = @import("std");
const print = std.debug.print;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

pub fn Stack(comptime T: type, comptime len: usize) type {
    return struct {
        contents: [len]T,
        sp: usize,

        const Self = @This();

        pub fn init() Self {
            return Self{
                .contents = undefined,
                .sp = 0,
            };
        }

        pub fn push(self: *Self, value: T) !void {
            //print("pushing {any} onto stack\n", .{value});
            if (self.sp >= self.contents.len) {
                print("stack overflow {any}\n", .{self});
                return ForthError.OverFlow;
            }
            self.contents[self.sp] = value;
            self.sp += 1;
        }

        pub fn pop(self: *Self) !T {
            if (self.isEmpty()) {
                print("stack underflow {any}\n", .{self});
                return ForthError.UnderFlow;
            }
            var result = self.contents[self.sp - 1];
            //print("poping {any} from stack\n", .{result});
            self.sp -= 1;
            return result;
        }

        pub fn isEmpty(self: *Self) bool {
            return self.sp == 0;
        }

        pub fn items(self: *Self) []T {
            return self.contents[0..self.sp];
        }

        pub fn peek(self: *Self) !T {
            if (self.isEmpty()) {
                return ForthError.UnderFlow;
            }
            return self.contents[self.sp - 1];
        }
    };
}

//pub fn main() !void {
//    const DStack = Stack(i32, 100);
//    const RStack = Stack(u16, 50);
//
//    var stack = DStack.init();
//    var rstack = RStack.init();
//
//    for (0..7) |i| {
//        try stack.push(@intCast(i32, i) * 10);
//        try rstack.push(@intCast(u16, i));
//    }
//
//    while (!stack.isEmpty()) {
//        var v = try stack.pop();
//        std.debug.print("pop: {}\n", .{v});
//    }
//    while (!rstack.isEmpty()) {
//        var v = try rstack.pop();
//        std.debug.print("rop: {}\n", .{v});
//    }
//}
