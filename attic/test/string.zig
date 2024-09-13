const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const string = @import("../forty/string.zig");

pub fn testBody() !void {
    assertToPrintable();
    assertStreq();
    assertStrlen();
}

fn assertToPrintable() void {
    expectEqual(@src(), @as(u8, ' '), string.toPrintable(' '));
    expectEqual(@src(), @as(u8, 'a'), string.toPrintable('a'));
    expectEqual(@src(), @as(u8, '.'), string.toPrintable(4));
}

fn assertStreq() void {
    expect(@src(), string.streql("abc", "abc"));
    expect(@src(), string.streql("a", "a"));
    expect(@src(), string.streql("", ""));
    expect(@src(), !string.streql("x", ""));
    expect(@src(), !string.streql("", "x"));
    expect(@src(), !string.streql("ab", "qq"));
    expect(@src(), !string.streql("abc", "abx"));
}

fn assertStrlen() void {
    expect(@src(), string.strlen("abc") == 3);
    expect(@src(), string.strlen("ab") == 2);
    expect(@src(), string.strlen("a") == 1);
    expect(@src(), string.strlen("") == 0);
}
