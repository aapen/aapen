const std = @import("std");
const root = @import("root");
const debug = root.debug;
const kinfo = root.kinfo;
const kprint = root.kprint;

const frame_buffer = @import("frame_buffer.zig");
const FrameBuffer = frame_buffer.FrameBuffer;

const hal2 = @import("hal2.zig");

const hal = @import("hal.zig");
const VideoController = hal.common.VideoController;
const Serial = hal.interfaces.Serial;
const Allocator = std.mem.Allocator;

const Readline = @import("readline.zig");

/// display console
pub const FrameBufferConsole = struct {
    tab_width: u8 = 8,
    xpos: u64 = 0,
    ypos: u64 = 0,
    width: u64 = undefined,
    height: u64 = undefined,
    fb: *FrameBuffer = undefined,
    serial: *const hal2.Serial,

    pub fn init(self: *FrameBufferConsole) void {
        self.xpos = 0;
        self.ypos = 0;
        self.width = @truncate(self.fb.xres / 8);
        self.height = @truncate(self.fb.yres / 16);
    }

    pub fn clear(self: *FrameBufferConsole) void {
        self.fb.clear();
        self.xpos = 0;
        self.ypos = 0;
    }

    fn next(self: *FrameBufferConsole) void {
        self.xpos += 1;
        if (self.xpos >= self.width) {
            self.nextLine();
        }
    }

    fn nextTab(self: *FrameBufferConsole) void {
        var positions = self.tab_width - (self.xpos % self.tab_width);
        self.xpos += positions;
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
        self.fb.clearRegion(0, self.ypos * 16, self.fb.xres, 16);
    }

    fn nextScreen(self: *FrameBufferConsole) void {
        self.fb.blit(0, 16, self.fb.xres, self.fb.yres - 16, 0, 0);

        self.xpos = 0;
        self.ypos = self.height - 1;
    }

    fn underbar(self: *FrameBufferConsole, color: u8) void {
        var x: u64 = self.xpos * 8;
        var y: u64 = self.ypos * 16 + 15;

        for (0..8) |i| {
            self.fb.drawPixel(x + i, y, color);
        }
    }

    fn eraseCursor(self: *FrameBufferConsole) void {
        self.underbar(self.fb.bg);
    }

    fn drawCursor(self: *FrameBufferConsole) void {
        self.underbar(self.fb.fg);
    }

    fn backspace(self: *FrameBufferConsole) void {
        if (self.xpos > 0) {
            self.xpos -= 1;
        }
        self.fb.eraseChar(self.xpos * 8, self.ypos * 16);
    }

    fn isPrintable(ch: u8) bool {
        return ch >= 32;
    }

    pub fn drawChar(self: *FrameBufferConsole, xpos: u64, ypos: u64, ch: u8) void {
        if (isPrintable(ch)) {
            self.fb.drawChar(xpos * 8, ypos * 16, ch);
        }
    }

    pub fn emit(self: *FrameBufferConsole, ch: u8) void {
        self.eraseCursor();
        defer self.drawCursor();

        switch (ch) {
            0x0c => self.clear(),
            0x7f => self.backspace(),
            '\t' => self.nextTab(),
            '\n' => self.nextLine(),
            else => if (isPrintable(ch)) {
                self.fb.drawChar(self.xpos * 8, self.ypos * 16, ch);
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

    pub fn readLine(self: *FrameBufferConsole, prompt: []const u8, buffer: []u8) usize {
        var i: usize = 0;
        var ch: u8 = 0;
        var echo: bool = true;

        self.emitString(prompt);

        while (i < (buffer.len - 1) and !newline(ch)) {
            echo = true;
            ch = self.getc();

            switch (ch) {
                0x7f => if (i > 0) {
                    i -= 1;
                } else {
                    echo = false;
                },
                else => {
                    buffer[i] = ch;
                    i += 1;
                },
            }
            if (echo) {
                self.putc(ch);
            }
            buffer[i] = 0;
        }
        return i;
    }

    pub fn getc(self: *FrameBufferConsole) u8 {
        var ch = self.serial.getc();
        return if (ch == '\r') '\n' else ch;
    }

    pub fn putc(self: *FrameBufferConsole, ch: u8) void {
        switch (ch) {
            '\n' => {
                _ = self.serial.putc('\r');
                _ = self.serial.putc('\n');
            },
            0x7f => {
                _ = self.serial.putc(0x08);
                _ = self.serial.putc(' ');
                _ = self.serial.putc(0x08);
            },
            else => {
                _ = self.serial.putc(ch);
            },
        }
        self.emit(ch);
    }

    pub fn char_available(self: *FrameBufferConsole) bool {
        return self.serial.hasc();
    }
};

fn newline(ch: u8) bool {
    return ch == '\r' or ch == '\n';
}

fn readLineThunk(ctx: *anyopaque, prompt: []const u8, buffer: []u8) Readline.Error!usize {
    var console: *FrameBufferConsole = @ptrCast(@alignCast(ctx));
    return console.readLine(prompt, buffer);
}

pub fn createReader(allocator: Allocator, console: *FrameBufferConsole) !*Readline {
    return Readline.init(allocator, console, readLineThunk);
}
