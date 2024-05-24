const std = @import("std");

const Self = @This();

ch: u8,
fg: u8,
bg: u8,

pub fn init(ch: u8, fg: u8, bg: u8) Self {
    return .{
        .ch = ch,
        .fg = fg,
        .bg = bg,
    };
}

pub inline fn isWhitespace(self: *const Self) bool {
    return std.ascii.isWhitespace(self.ch);
}
