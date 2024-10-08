const helpers = @import("helpers.zig");
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const bcd = @import("../bcd.zig");

pub fn testBody() !void {
    try testSmallNumbers();
    try testMiddleyNumbers();
    try testLargeNumbers();
}

fn testSmallNumbers() !void {
    expectEqual(@src(), @as(u8, 1), try bcd.decode(u8, 0b0001));
    expectEqual(@src(), @as(u8, 2), try bcd.decode(u8, 0b0010));
    expectEqual(@src(), @as(u8, 4), try bcd.decode(u8, 0b0100));
    expectEqual(@src(), @as(u8, 7), try bcd.decode(u8, 0b0111));
    expectEqual(@src(), @as(u8, 9), try bcd.decode(u8, 0b1001));

    expectError(@src(), error.Overflow, bcd.decode(u8, 0b1010));
    expectError(@src(), error.Overflow, bcd.decode(u8, 0b1111));
}

fn testMiddleyNumbers() !void {
    expectEqual(@src(), @as(u8, 1), try bcd.decode(u8, 0b0000_0001));
    expectEqual(@src(), @as(u8, 10), try bcd.decode(u8, 0b0001_0000));
    expectEqual(@src(), @as(u8, 19), try bcd.decode(u8, 0b0001_1001));
    expectEqual(@src(), @as(u8, 42), try bcd.decode(u8, 0b0100_0010));

    expectError(@src(), error.Overflow, bcd.decode(u8, 0b1010_0000));
}

fn testLargeNumbers() !void {
    expectEqual(@src(), @as(u16, 1000), try bcd.decode(u16, 0b0001_0000_0000_0000));
    expectEqual(@src(), @as(u16, 9000), try bcd.decode(u16, 0b1001_0000_0000_0000));
    expectEqual(@src(), @as(u16, 9001), try bcd.decode(u16, 0b1001_0000_0000_0001));

    expectError(@src(), error.Overflow, bcd.decode(u16, 0b1010_0000_0000_0000));
    expectError(@src(), error.Overflow, bcd.decode(u16, 0b1111_1111_1111_1111));
}
