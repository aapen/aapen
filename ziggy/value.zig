const std = @import("std");
const mem = std.mem;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

pub const ValueType = enum {
    f,
    i,
    u,
    l,
    s,
    w,
    fp,
    addr,
    sz,
    call,
};

pub const Value = union(ValueType) {
    f: f32,
    i: i32,
    u: u32,
    l: u64,
    s: []const u8,
    w: []const u8,
    fp: usize,
    addr: usize,
    sz: usize,
    call: i32,

    pub fn fromString(token: []const u8) ForthError!Value {
        if (token[0] == '"') {
            return Value{ .s = token[1..(token.len - 1)] };
        }
        else if (token[0] == '#') {
            var sNumber = token[1..(token.len-1)];
            const address: usize = std.fmt.parseInt(usize, sNumber, 16) catch {
                return ForthError.ParseError;
            };
            return Value{ .addr = address};
        }

        var iValue = std.fmt.parseInt(i32, token, 10) catch {
            var fValue = std.fmt.parseFloat(f32, token) catch {
                return Value{ .w = token };
            };
            return Value{ .f = fValue };
        };
        return Value{ .i = iValue };
    }

    pub fn pr(this: *const Value, comptime printf: anytype) void {
        switch (this.*) {
            .f => |v| printf("{}", .{v}),
            .i => |v| printf("{}", .{v}),
            .u => |v| printf("{}", .{v}),
            .l => |v| printf("{}", .{v}),
            .s => |v| printf("{s}", .{v}),
            .w => |v| printf("word: {s}", .{v}),
            .fp => |v| printf("fp: {x}", .{v}),
            .sz => |v| printf("sz: {}", .{v}),
            .addr => |v| printf("addr: {x}", .{v}),
            .call => |v| printf("call: {}", .{v}),
        }
    }

    pub fn add(this: *const Value, other: *const Value) !Value {
        var vt: ValueType = this.*;
        var ot: ValueType = other.*;

        if (vt != ot) {
            return ForthError.BadOperation;
        }

        switch (this.*) {
            .f => |v| return Value{
                .f = (v + other.*.f),
            },
            .i => |v| return Value{
                .i = (v + other.*.i),
            },
            else => return ForthError.BadOperation,
        }
    }
};

//pub fn main() !void {
//    const stdout = std.io.getStdOut().writer();
//
//    //var i = splitAny(u8, "hello out there", " ");
//    var i = tokenizer("here is \"string abc\" zzz empty \"\"");
//
//    while (i.next()) |token| {
//        _ = try stdout.print("token: [{s}]\n", .{token});
//        var v = toValue(token);
//        _ = try stdout.print("value: [{any}]\n", .{v});
//
//    }
//}
