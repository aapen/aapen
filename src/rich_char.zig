const std = @import("std");

const FrameBuffer = @import("frame_buffer.zig");

pub const RichChar = struct {
    ch: u8,
    fg: u8,
    bg: u8,
    ignore: u1,

    pub fn init(ch: u8, fg: u8, bg: u8, ignore: u1, x: usize, y: usize) RichChar {
        return RichChar{
            .ch = ch,
            .fg = fg,
            .bg = bg,
            .ignore = ignore,
            .x = x,
            .y = y,
        };
    }

    pub inline fn isIgnorable(self: *const RichChar) bool {
        return (self.ignore == 1);
    }

    pub inline fn isWhitespace(self: *const RichChar) bool {
        return std.ascii.isWhitespace(self.ch);
    }

    pub inline fn isSignificant(self: *const RichChar) bool {
        return !self.isWhitespace() and !self.isIgnorable();
    }
};
