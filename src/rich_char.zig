const std = @import("std");

const FrameBuffer = @import("frame_buffer.zig");

pub const RichChar = packed struct {
    ch: u8,
    fg: u8,
    bg: u8,
    ignore: u1,

    pub fn init(ch: u8, fg: u8, bg: u8, ignore: u1) RichChar {
        return RichChar{
            .ch = ch,
            .fg = fg,
            .bg = bg,
            .ignore = ignore,
        };
    }

    pub fn plain(ch: u8) RichChar {
        return RichChar{
            .ch = ch,
            .fg = 0,
            .bg = 1,
            .colors = 0,
            .ignore = 0,
        };
    }

    pub inline fn draw(self: *const RichChar, fb: *FrameBuffer, col: u64, row: u64) void {
        const fg = fb.fg;
        const bg = fb.bg;
        defer {
            fb.fg = fg;
            fb.bg = bg;
        }
        fb.fg = self.fg;
        fb.bg = self.bg;
        fb.drawChar(fb.colToX(col), fb.rowToY(row), self.ch);
    }
};
