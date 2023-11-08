const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const debug = root.debug;
const kprint = root.kprint;
const Serial = root.HAL.Serial;

const FrameBuffer = @import("frame_buffer.zig");

const Readline = @import("readline.zig");

const Self = @This();

/// display console
tab_width: u8 = 8,
xpos: u64 = 0,
ypos: u64 = 0,
width: u64 = undefined,
height: u64 = undefined,
fb: *FrameBuffer = undefined,
serial: *Serial = undefined,

pub fn init(allocator: Allocator, fb: *FrameBuffer, serial: *Serial) !*Self {
    var self: *Self = try allocator.create(Self);

    self.* = .{
        .fb = fb,
        .serial = serial,
        .xpos = 0,
        .ypos = 0,
        .width = fb.xres / 8,
        .height = fb.yres / 16,
    };

    return self;
}

pub fn clear(self: *Self) void {
    self.fb.clear();
    self.xpos = 0;
    self.ypos = 0;
}

fn next(self: *Self) void {
    self.xpos += 1;
    if (self.xpos >= self.width) {
        self.nextLine();
    }
}

fn nextTab(self: *Self) void {
    var positions = self.tab_width - (self.xpos % self.tab_width);
    self.xpos += positions;
    if (self.xpos >= self.width) {
        self.nextLine();
    }
}

fn nextLine(self: *Self) void {
    self.xpos = 0;
    self.ypos += 1;
    if (self.ypos >= self.height) {
        self.nextScreen();
    }
    self.fb.clearRegion(0, self.ypos * 16, self.fb.xres, 16);
}

fn nextScreen(self: *Self) void {
    self.fb.blit(0, 16, self.fb.xres, self.fb.yres - 16, 0, 0);

    self.xpos = 0;
    self.ypos = self.height - 1;
}

fn underbar(self: *Self, color: u8) void {
    var x: u64 = self.xpos * 8;
    var y: u64 = self.ypos * 16 + 15;

    for (0..8) |i| {
        self.fb.drawPixel(x + i, y, color);
    }
}

fn eraseCursor(self: *Self) void {
    self.underbar(self.fb.bg);
}

fn drawCursor(self: *Self) void {
    self.underbar(self.fb.fg);
}

fn backspace(self: *Self) void {
    if (self.xpos > 0) {
        self.xpos -= 1;
    }
    self.fb.eraseChar(self.xpos * 8, self.ypos * 16);
}

fn isPrintable(ch: u8) bool {
    return ch >= 32;
}

pub fn drawChar(self: *Self, xpos: u64, ypos: u64, ch: u8) void {
    if (isPrintable(ch)) {
        self.fb.drawChar(xpos * 8, ypos * 16, ch);
    }
}

pub fn emit(self: *Self, ch: u8) void {
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

pub fn emitString(self: *Self, str: []const u8) void {
    self.eraseCursor();
    defer self.drawCursor();

    for (str) |ch| {
        self.emit(ch);
    }
}

pub const Writer = std.io.Writer(*Self, error{}, write);

pub fn write(self: *Self, bytes: []const u8) !usize {
    for (bytes) |ch| {
        self.emit(ch);
    }
    return bytes.len;
}

pub fn writer(self: *Self) Writer {
    return .{ .context = self };
}

pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
    try self.writer().print(fmt, args);
}

pub fn readLine(self: *Self, prompt: []const u8, buffer: []u8) usize {
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

pub fn getc(self: *Self) u8 {
    var ch = self.serial.getc();
    return if (ch == '\r') '\n' else ch;
}

pub fn putc(self: *Self, ch: u8) void {
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

pub fn char_available(self: *Self) bool {
    return self.serial.hasc();
}

fn newline(ch: u8) bool {
    return ch == '\r' or ch == '\n';
}

fn readLineThunk(ctx: *anyopaque, prompt: []const u8, buffer: []u8) Readline.Error!usize {
    var console: *Self = @ptrCast(@alignCast(ctx));
    return console.readLine(prompt, buffer);
}

pub fn createReader(allocator: Allocator, console: *Self) !*Readline {
    return Readline.init(allocator, console, readLineThunk);
}
