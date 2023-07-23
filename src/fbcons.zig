const std = @import("std");
const bsp = @import("bsp.zig");

/// display console
pub const FrameBufferConsole = struct {
    xpos: u8 = 0,
    ypos: u8 = 0,
    width: u16 = undefined,
    height: u16 = undefined,
    frame_buffer: *bsp.video.FrameBuffer = undefined,

    pub fn init(frame_buffer: *bsp.video.FrameBuffer, pixel_width: u32, pixel_height: u32) FrameBufferConsole {
        return FrameBufferConsole{
            .frame_buffer = frame_buffer,
            .width = @truncate(pixel_width / 8),
            .height = @truncate(pixel_height / 16),
        };
    }

    fn next(self: *FrameBufferConsole) void {
        self.xpos += 1;
        if (self.xpos >= self.width) {
            self.nextLine();
        }
    }

    fn nextLine(self: *FrameBufferConsole) void {
        self.xpos = 0;
        self.ypos += 1;
        if (self.ypos >= self.height) {
            self.nextScreen();
        }
    }

    fn nextScreen(self: *FrameBufferConsole) void {
        self.xpos = 0;
        self.ypos = 0;
        // TODO: clear screen?
    }

    fn underbar(self: *FrameBufferConsole, color: u8) void {
        var x: u16 = self.xpos;
        x *= 8;
        var y: u16 = self.ypos + 1;
        y *= 16;

        for (0..8) |i| {
            self.frame_buffer.drawPixel(x + i, y, color);
        }
    }

    fn eraseCursor(self: *FrameBufferConsole) void {
        self.underbar(bsp.video.FrameBuffer.COLOR_BACKGROUND);
    }

    fn drawCursor(self: *FrameBufferConsole) void {
        self.underbar(bsp.video.FrameBuffer.COLOR_FOREGROUND);
    }

    fn backspace(self: *FrameBufferConsole) void {
        if (self.xpos > 0) {
            self.xpos -= 1;
        }
        self.frame_buffer.eraseChar(@as(u16, self.xpos) * 8, @as(u16, self.ypos) * 16);
    }

    fn isPrintable(ch: u8) bool {
        return ch >= 32;
    }

    pub fn emit(self: *FrameBufferConsole, ch: u8) void {
        self.eraseCursor();
        defer self.drawCursor();

        switch (ch) {
            0x7f => self.backspace(),
            '\n' => self.nextLine(),
            else => if (isPrintable(ch)) {
                self.frame_buffer.drawChar(@as(u16, self.xpos) * 8, @as(u16, self.ypos) * 16, ch);
                self.next();
            },
        }
    }

    pub fn emitString(self: *FrameBufferConsole, str: []const u8) void {
        self.eraseCursor();
        defer self.drawCursor();

        for (str) |ch| {
            self.emit(ch);
        }
    }

    pub const Writer = std.io.Writer(*FrameBufferConsole, error{}, write);

    pub fn write(self: *FrameBufferConsole, bytes: []const u8) !usize {
        for (bytes) |ch| {
            self.emit(ch);
        }
        return bytes.len;
    }

    pub fn writer(self: *FrameBufferConsole) Writer {
        return .{ .context = self };
    }

    pub fn print(self: *FrameBufferConsole, comptime fmt: []const u8, args: anytype) !void {
        try self.writer().print(fmt, args);
    }
};
