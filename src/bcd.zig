const std = @import("std");

pub fn decode(comptime T: type, val: T) !T {
    var ret: T = 0;
    const nibbles = @bitSizeOf(T) / 4;
    inline for (0..nibbles) |i| {
        var nibble = (val >> (4 * i)) & 0xf;
        if (nibble > 0b1001) {
            return error.Overflow;
        }

        ret += (nibble * std.math.pow(T, 10, i));
    }
    return ret;
}

test "small numbers" {
    std.debug.print("\n", .{});

    const expect = std.testing.expect;
    const expectError = std.testing.expectError;

    try expect(1 == try decode(u8, 0b0001));
    try expect(2 == try decode(u8, 0b0010));
    try expect(4 == try decode(u8, 0b0100));
    try expect(7 == try decode(u8, 0b0111));
    try expect(9 == try decode(u8, 0b1001));

    try expectError(error.Overflow, decode(u8, 0b1010));
    try expectError(error.Overflow, decode(u8, 0b1111));
}

test "middley numbers" {
    std.debug.print("\n", .{});

    const expect = std.testing.expect;
    const expectError = std.testing.expectError;

    try expect(1 == try decode(u8, 0b0000_0001));
    try expect(10 == try decode(u8, 0b0001_0000));
    try expect(19 == try decode(u8, 0b0001_1001));
    try expect(42 == try decode(u8, 0b0100_0010));

    try expectError(error.Overflow, decode(u8, 0b1010_0000));
}

test "larger numbers" {
    std.debug.print("\n", .{});

    const expect = std.testing.expect;
    const expectError = std.testing.expectError;

    try expect(1000 == try decode(u16, 0b0001_0000_0000_0000));
    try expect(9000 == try decode(u16, 0b1001_0000_0000_0000));
    try expect(9001 == try decode(u16, 0b1001_0000_0000_0001));

    try expectError(error.Overflow, decode(u16, 0b1010_0000_0000_0000));
    try expectError(error.Overflow, decode(u16, 0b1111_1111_1111_1111));
}
