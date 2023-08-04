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
        } else if (token[0] == '#') {
            var sNumber = token[1..(token.len - 1)];
            const address: usize = std.fmt.parseInt(usize, sNumber, 16) catch {
                return ForthError.ParseError;
            };
            return Value{ .addr = address };
        }

        var iValue = std.fmt.parseInt(i32, token, 10) catch {
            var fValue = std.fmt.parseFloat(f32, token) catch {
                return Value{ .w = token };
            };
            return Value{ .f = fValue };
        };
        return Value{ .i = iValue };
    }

    pub fn pr(this: *const Value, writer: anytype, hex: bool) !void {
        var base: u8 = if (hex) 16 else 10;
        try switch (this.*) {
            .f => |v| writer.print("{}", .{v}),
            .i => |v| std.fmt.formatInt(v, base, .lower, .{}, writer.writer()),
            .u => |v| std.fmt.formatInt(v, base, .lower, .{}, writer.writer()),
            .l => |v| std.fmt.formatInt(v, base, .lower, .{}, writer.writer()),
            .s => |v| writer.print("{s}", .{v}),
            .w => |v| writer.print("word: {s}", .{v}),
            .fp => |v| writer.print("fp: {x}", .{v}),
            .sz => |v| std.fmt.formatInt(v, base, .lower, .{}, writer.writer()),
            .addr => |v| writer.print("addr: {x}", .{v}),
            .call => |v| writer.print("call: {}", .{v}),
        };
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
            .u => |v| return Value{
                .u = (v + other.*.u),
            },
            .addr => |v| return Value{
                .addr = (v + other.*.addr),
            },
            else => return ForthError.BadOperation,
        }
    }

    pub fn asChar(this: *const Value) !u8 {
        return switch (this.*) {
            .i => |v| @truncate(@as(u32, @bitCast(v))),
            .l => |v| @truncate(v),
            .u => |v| @truncate(v),
            else => ForthError.BadOperation,
        };
    }
};

fn expectEqualString(a: []const u8, b: []const u8) !void {
    try std.testing.expect(std.mem.eql(u8, a, b));
}

test "parsing" {
    const expectEqual = std.testing.expectEqual;

    var i = try Value.fromString("12345");
    try expectEqual(i.i, 12345);

    var f = try Value.fromString("12.345");
    try expectEqual(f.f, 12.345);

    var s = try Value.fromString("\"cake\"");
    try expectEqualString(s.s, "cake");

    var addr = try Value.fromString("#cafebabe#");
    try expectEqual(addr.addr, 0xcafebabe);

    var word = try Value.fromString("an-atom");
    try expectEqualString(word.w, "an-atom");

    var badA = Value.fromString("#123FGHIJKL99#");
    try std.testing.expectError(ForthError.ParseError, badA);
}
