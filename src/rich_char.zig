const std = @import("std");

const FrameBuffer = @import("frame_buffer.zig");

pub const RichChar = struct {
    ch: u8,
    fg: u8,
    bg: u8,

    pub fn init(ch: u8, fg: u8, bg: u8) RichChar {
        return RichChar{
            .ch = ch,
            .fg = fg,
            .bg = bg,
        };
    }

    pub inline fn isWhitespace(self: *const RichChar) bool {
        return std.ascii.isWhitespace(self.ch);
    }
};
