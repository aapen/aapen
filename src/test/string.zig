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
    expectEqual(@as(u8, ' '), string.toPrintable(' '));
    expectEqual(@as(u8, 'a'), string.toPrintable('a'));
    expectEqual(@as(u8, '.'), string.toPrintable(4));
}

fn assertStreq() void {
    expect(string.streql("abc", "abc"));
    expect(string.streql("a", "a"));
    expect(string.streql("", ""));

    expect(!string.streql("x", ""));
    expect(!string.streql("", "x"));
    expect(!string.streql("ab", "qq"));
    expect(!string.streql("abc", "abx"));
}

fn assertStrlen() void {
    expect(string.strlen("abc") == 3);
    expect(string.strlen("ab") == 2);
    expect(string.strlen("a") == 1);
    expect(string.strlen("") == 0);
}
