const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const debug = root.debug;
const kprint = root.kprint;
const Serial = root.HAL.Serial;

const serial = @import("serial.zig");

const FrameBuffer = @import("frame_buffer.zig");
const CharDisplay = @import("char_display.zig");

const Readline = @import("readline.zig");

pub const DEFAULT_FOREGROUND: u8 = 0x01;
pub const DEFAULT_BACKGROUND: u8 = 0x00;

const Self = @This();

/// Display console.
display: *CharDisplay = undefined,

tab_width: u8 = 8,

// The frame buffer and the text behind it.
//fb: *FrameBuffer = undefined,

// The current values of color and ignore, picked up by the characters
// as we add them.
current_ignore: u1 = 0,

// Delay actual drawing and keep track of the rectangle of
// text that has been modified but not yet drawn.
update_depth: u64 = 0,

pub fn init(allocator: Allocator, fb: *FrameBuffer) !*Self {
    var self: *Self = try allocator.create(Self);

    const display = try CharDisplay.init(allocator, fb);

    self.* = .{
        //.fb = fb,
        .display = display,
        .current_ignore = 0,
        .update_depth = 0,
    };

    return self;
}

pub inline fn begin_update(self: *Self) void {
    self.update_depth += 1;
}

pub inline fn end_update(self: *Self) void {
    self.update_depth -= 1;
    if (self.update_depth <= 0) {
        self.display.sync();
        self.update_depth = 0;
    }
}
pub fn emit(self: *Self, ch: u8) void {
    self.begin_update();
    defer self.end_update();

    switch (ch) {
        0x0c => self.display.clearScreen(),
        0x7f => self.backspace(),
        '\t' => self.nextTab(),
        '\n' => self.nextLine(),
        0x80 => self.display.upCursor(),
        0x81 => self.display.downCursor(),
        0x82 => self.display.leftCursor(),
        0x83 => self.display.rightCursor(),
        0x84 => self.display.bolCursor(),
        0x85 => self.display.eolCursor(),
        0x86 => self.display.eraseCursor(self.display.displayed_cursor_col, self.display.displayed_cursor_row),
        0x87 => self.display.drawCursor(self.display.displayed_cursor_col, self.display.displayed_cursor_row),
        0x90...0x9f => self.display.current_fg = (ch - 0x90),
        0xa0...0xaf => self.display.current_bg = (ch - 0xa0),
        0xb0 => self.display.textShiftLeft(self.display.getCursorCol(), self.display.getCursorRow()),
        0xf0 => self.display.infoDump(),
        0xf1 => self.display.textDump(),
        //0xf1 => self.dumpColors(),
        //0xf2 => self.dumpIgnore(),
        //0xfe => self.redrawLine(self.current_row),
        0xff => self.display.invalidate(),
        else => self.addChar(ch),
    }
}

/// Add a character at the current position with the current colors and ignore flag.
pub fn addChar(self: *Self, ch: u8) void {
    self.begin_update();
    defer self.end_update();

    if (isPrintable(ch)) {
        self.display.currentCharSet(ch);
    } else {
        self.display.currentCharSet('?');
    }
    self.next();
}

fn backspace(self: *Self) void {
    if (self.display.current_col <= 0) {
        return;
    }

    self.begin_update();
    defer self.end_update();

    self.display.current_col -= 1;
    self.display.currentCharSet(' ');
    //self.display.shiftLeft(self.display.current_col, self.display.current_row);
    //TBD
    //self.display.sync();
}

fn next(self: *Self) void {
    self.begin_update();
    defer self.end_update();

    self.display.current_col += 1;
    if (self.display.current_col >= self.display.num_cols) {
        self.nextLine();
    }
}

fn nextTab(self: *Self) void {
    self.begin_update();
    defer self.end_update();

    var positions = self.tab_width - (self.display.current_col % self.tab_width);
    self.display.current_col += positions;
    if (self.display.current_col >= self.display.num_cols) {
        self.nextLine();
    }
}

fn nextLine(self: *Self) void {
    self.begin_update();
    defer self.end_update();

    self.display.current_col = 0;
    if (self.display.current_row >= self.display.num_rows - 1) {
        self.display.scrollUp();
    } else {
        self.display.current_row += 1;
    }
}

/// Scroll the screen up. Before we do any scrolling we repaint the screen from
/// self.text thereby ensuring that we are scrolling the latest changes.
//fn scrollUp(self: *Self) void {
//    self.repaint();
//    self.fb.blit(0, self.fb.font_height_px, self.fb.xres, self.fb.yres - self.fb.font_height_px, 0, 0);
//
//    self.current_col = 0;
//    self.current_row = self.num_rows - 1;
//    const copy_len = self.length - self.num_cols;
//    std.mem.copyForwards(RichChar, self.text[0..copy_len], self.text[self.num_cols..self.length]);
//    self.setCharRange(0, self.num_rows - 1, self.num_cols, self.num_rows - 1, ' ');
//}
//
///// Set a range of chars in self.text, does not update the modified_area rect.
//inline fn setCharRange(self: *Self, col1: usize, row1: usize, col2: usize, row2: usize, ch: u8) void {
//    const i = self.charIndex(col1, row1);
//    const j = self.charIndex(col2, row2);
//    for (i..j) |k| {
//        self.text[k] = RichChar.init(ch, self.current_fg, self.current_bg, 0);
//    }
//}

/// Sync up the cursor on the screen with our internal
/// idea of where the cursor is.
fn isPrintable(ch: u8) bool {
    return ch >= 32 and ch <= 128;
}

//pub fn lineShiftRight(self: *Self) void {
//    self.begin_update();
//    const i = self.charIndex(self.current_col, self.current_row);
//    const len = self.num_cols - self.current_col - 1;
//    //std.mem.copyBackwards(RichChar, self.text[i + 1 .. i + 1 + len], self.text[i .. i + len]);
//    self.modified_area.expand(self.current_col, self.current_row);
//    self.modified_area.expand(self.num_cols - 1, self.current_row);
//    self.end_update();
//}
//
pub fn emitString(self: *Self, str: []const u8) void {
    self.begin_update();
    defer self.end_update();
    for (str) |ch| {
        self.emit(ch);
    }
}

pub const Writer = std.io.Writer(*Self, error{}, write);

pub fn write(self: *Self, bytes: []const u8) !usize {
    self.begin_update();
    for (bytes) |ch| {
        self.emit(ch);
    }
    self.end_update();
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
    _ = self;
    var ch = serial.getc();
    return if (ch == '\r') '\n' else ch;
}

pub fn putc(self: *Self, ch: u8) void {
    switch (ch) {
        '\n' => {
            _ = serial.putc('\r');
            _ = serial.putc('\n');
        },
        0x7f => {
            _ = serial.putc(0x08);
            _ = serial.putc(' ');
            _ = serial.putc(0x08);
        },
        else => {
            _ = serial.putc(ch);
        },
    }
    self.emit(ch);
}

pub fn char_available(self: *Self) bool {
    _ = self;
    return serial.hasc();
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
