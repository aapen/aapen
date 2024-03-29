const std = @import("std");
const Allocator = std.mem.Allocator;

const atomic = @import("atomic.zig");
const FrameBuffer = @import("frame_buffer.zig");
const CharBuffer = @import("char_buffer.zig");

pub const DEFAULT_FOREGROUND: u8 = 0x01;
pub const DEFAULT_BACKGROUND: u8 = 0x00;

const Self = @This();

/// Character buffer backing.
char_buffer: *CharBuffer = undefined,

/// Count of update batch nesting.
update_depth: u64 = 0,

/// Tabs.
tab_width: u8 = 8,

pub fn init(allocator: Allocator, char_buffer: *CharBuffer) !*Self {
    const self: *Self = try allocator.create(Self);

    self.* = .{
        .char_buffer = char_buffer,
        .update_depth = 0,
    };

    return self;
}

/// Start a batch up updates. With the exception of scrolling
/// this will prevent any output until end_update() is called.
pub inline fn begin_update(self: *Self) void {
    _ = atomic.atomicInc(&self.update_depth);
}

/// End a batch of updates and, if this is the outter update,
/// update the screen.
pub inline fn end_update(self: *Self) void {
    const prior = atomic.atomicDec(&self.update_depth);

    if (prior == 1) {
        self.char_buffer.sync();
    }
}

/// Emit a string of chars to the console.
pub fn emitString(self: *Self, str: []const u8) void {
    self.begin_update();
    defer self.end_update();

    for (str) |ch| {
        self.emit(ch);
    }
}

/// Emit a single character to the console. Chars <= 128 have their usual
/// meanings. > 128 there are a selection of control codes that do things
/// like change color and move the cursor.
pub fn emit(self: *Self, ch: u8) void {
    self.begin_update();
    defer self.end_update();

    switch (ch) {
        0x0c => self.char_buffer.clearScreen(),
        0x7f => self.backspace(),
        '\t' => self.nextTab(),
        '\n' => self.nextLine(),
        0x80 => self.char_buffer.upCursor(),
        0x81 => self.char_buffer.downCursor(),
        0x82 => self.char_buffer.leftCursor(),
        0x83 => self.char_buffer.rightCursor(),
        0x84 => self.char_buffer.bolCursor(),
        0x85 => self.char_buffer.eolCursor(),
        0x90...0x9f => self.char_buffer.current_fg = (ch - 0x90),
        0xa0...0xaf => self.char_buffer.current_bg = (ch - 0xa0),
        0xb0 => self.char_buffer.textShiftLeft(self.char_buffer.current_col, self.char_buffer.current_row),
        0xb1 => self.char_buffer.textShiftRight(self.char_buffer.current_col, self.char_buffer.current_row),
        0xf0 => self.char_buffer.infoDump(),
        0xf1 => self.char_buffer.textDump(),
        0xff => self.char_buffer.invalidate(),
        else => self.addChar(ch),
    }
}

/// Add a character at the current position with the current colors.
fn addChar(self: *Self, ch: u8) void {
    self.begin_update();
    defer self.end_update();

    self.char_buffer.currentCharSet(if (isPrintable(ch)) ch else '?');
    self.next();
}

/// Do a traditional backspace.
fn backspace(self: *Self) void {
    if (self.char_buffer.current_col <= 0) {
        return;
    }

    self.begin_update();
    defer self.end_update();

    self.char_buffer.current_col -= 1;
    self.char_buffer.textShiftLeft(self.char_buffer.current_col, self.char_buffer.current_row);
}

/// Move to the next char position.
fn next(self: *Self) void {
    self.begin_update();
    defer self.end_update();

    self.char_buffer.current_col += 1;
    if (self.char_buffer.current_col >= self.char_buffer.num_cols) {
        self.nextLine();
    }
}

/// Move to the next tab position.
fn nextTab(self: *Self) void {
    self.begin_update();
    defer self.end_update();

    const positions = self.tab_width - (self.char_buffer.current_col % self.tab_width);
    self.char_buffer.current_col += positions;
    if (self.char_buffer.current_col >= self.char_buffer.num_cols) {
        self.nextLine();
    }
}

/// Move to the next line, scrolling as needed.
fn nextLine(self: *Self) void {
    self.begin_update();
    defer self.end_update();

    self.char_buffer.current_col = 0;
    if (self.char_buffer.current_row >= self.char_buffer.num_rows - 1) {
        self.char_buffer.scrollUp();
    } else {
        self.char_buffer.current_row += 1;
        self.char_buffer.rowTextSet(self.char_buffer.current_row, ' ');
    }
}

fn isPrintable(ch: u8) bool {
    return ch >= 32 and ch <= 128;
}
