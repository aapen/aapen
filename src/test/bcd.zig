// expected_output
// Hello, world!
// end_expected_output

const helpers = @import("helpers.zig");
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const bcd = @import("../bcd.zig");

pub fn testBody() !void {
    try testSmallNumbers();
    try testMiddleyNumbers();
    try testLargeNumbers();

    var buf1: [512]u16 = undefined;
    var buf2: [512]u16 = undefined;

    for (0..16) |i| {
        buf1[i] = @truncate(i);
    }

    for (0..22) |i| {
        buf2[i] = @truncate(i);
    }

    helpers.expectEqualSlices(u16, &buf1, &buf2);
}

fn testSmallNumbers() !void {
    expectEqual(@as(u8, 1), try bcd.decode(u8, 0b0001));
    expectEqual(@as(u8, 2), try bcd.decode(u8, 0b0010));
    expectEqual(@as(u8, 4), try bcd.decode(u8, 0b0100));
    expectEqual(@as(u8, 7), try bcd.decode(u8, 0b0111));
    expectEqual(@as(u8, 9), try bcd.decode(u8, 0b1001));

    expectError(error.Overflow, bcd.decode(u8, 0b1010));
    expectError(error.Overflow, bcd.decode(u8, 0b1111));
}

fn testMiddleyNumbers() !void {
    expectEqual(@as(u8, 1), try bcd.decode(u8, 0b0000_0001));
    expectEqual(@as(u8, 10), try bcd.decode(u8, 0b0001_0000));
    expectEqual(@as(u8, 19), try bcd.decode(u8, 0b0001_1001));
    expectEqual(@as(u8, 42), try bcd.decode(u8, 0b0100_0010));

    expectError(error.Overflow, bcd.decode(u8, 0b1010_0000));
}

fn testLargeNumbers() !void {
    expectEqual(@as(u16, 1000), try bcd.decode(u16, 0b0001_0000_0000_0000));
    expectEqual(@as(u16, 9000), try bcd.decode(u16, 0b1001_0000_0000_0000));
    expectEqual(@as(u16, 9001), try bcd.decode(u16, 0b1001_0000_0000_0001));

    expectError(error.Overflow, bcd.decode(u16, 0b1010_0000_0000_0000));
    expectError(error.Overflow, bcd.decode(u16, 0b1111_1111_1111_1111));
}
