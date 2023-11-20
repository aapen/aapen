const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const debug = root.debug;
const kprint = root.kprint;
const Serial = root.HAL.Serial;

const serial = @import("serial.zig");

const FrameBuffer = @import("frame_buffer.zig");
const clamp = FrameBuffer.clamp;

const Readline = @import("readline.zig");
const RichChar = @import("rich_char.zig").RichChar;

const Rectangle = @import("rectangle.zig").Rectangle;

pub const DEFAULT_FOREGROUND: u8 = 0x01;
pub const DEFAULT_BACKGROUND: u8 = 0x00;

const Self = @This();

/// Character mode display.
/// The naming convention is that x and y are pixel coordinates
/// while rows and columns are character coordinates.
num_cols: u64 = undefined,
num_rows: u64 = undefined,
length: u64 = undefined,

/// The frame buffer, which is what is actually displayed.
fb: *FrameBuffer = undefined,

/// The text that should be on the screen. The idea is that
/// we update .text and then sync it with the screen.
text: [*]RichChar,

/// The top row is the row of text that gets displayed at the top
/// of the framebuffer.
top_row: u64 = 0,

/// The section of .text (in col/row units) that is out of sync
/// with what is currently displayed.
modified_area: Rectangle = undefined,

/// Current colors.
current_fg: u8,
current_bg: u8,

/// Where we want the cursor to display.
current_col: u64 = 0,
current_row: u64 = 0,

/// The position of the cursor as currently drawn on the fb.
displayed_cursor_col: u64 = 0,
displayed_cursor_row: u64 = 0,

pub fn init(allocator: Allocator, fb: *FrameBuffer) !*Self {
    var self: *Self = try allocator.create(Self);

    const num_cols = fb.xres / fb.font_width_px;
    const num_rows = fb.yres / fb.font_height_px;
    const length = num_cols * num_rows;
    const text = try allocator.alloc(RichChar, length);

    self.* = .{
        .fb = fb,
        .num_cols = num_cols,
        .num_rows = num_rows,
        .length = length,
        .text = text.ptr,
        .top_row = 0,
        .modified_area = Rectangle.invalid(),
        .current_fg = DEFAULT_FOREGROUND,
        .current_bg = DEFAULT_BACKGROUND,
        .current_col = 0,
        .current_row = 0,
        .displayed_cursor_col = 0,
        .displayed_cursor_row = 0,
    };

    for (0..num_rows) |row| {
        for (0..num_cols) |col| {
            const i = self.charIndex(col, row);
            self.text[i].ch = ' ';
            self.text[i].fg = DEFAULT_FOREGROUND;
            self.text[i].bg = DEFAULT_BACKGROUND;
            self.text[i].ignore = 0;
            self.text[i].x = fb.colToX(col);
            self.text[i].y = fb.rowToY(row);
        }
    }

    return self;
}

pub fn sync(self: *Self) void {
    self.syncText();
    self.syncCursor();
}

pub fn syncText(self: *Self) void {
    if (self.modified_area.valid) {
        try serial.writer.print("Syncing screen, rect is {any}\n", .{self.modified_area});
        self.renderRect(self.modified_area);
        self.modified_area.valid = false;
    }
}

pub fn syncCursor(self: *Self) void {
    if ((self.current_row != self.displayed_cursor_row) or (self.current_col != self.displayed_cursor_col)) {
        self.eraseCursor(self.displayed_cursor_col, self.displayed_cursor_row);
        self.drawCursor(self.current_col, self.current_row);
        self.displayed_cursor_row = self.current_row;
        self.displayed_cursor_col = self.current_col;
    }
}

pub fn drawCursor(self: *Self, col: usize, row: usize) void {
    const ch = self.getChar(col, row);
    self.renderCursor(ch.x, ch.y, ch.fg);
}

pub fn eraseCursor(self: *Self, col: usize, row: usize) void {
    const ch = self.getChar(col, row);
    self.renderCursor(ch.x, ch.y, ch.bg);
}

fn renderCursor(self: *Self, x: u64, y: u64, color: u8) void {
    for (0..self.fb.font_width_px) |i| {
        self.fb.drawPixel(x + i, y + self.fb.font_height_px, color);
    }
}

fn renderRect(self: *Self, rect: Rectangle) void {
    if (!rect.valid) {
        return;
    }

    for (rect.top..rect.bottom) |row| {
        try serial.writer.print("rendering row {}, left: {} right {}\n", .{ row, rect.left, rect.right });
        for (rect.left..rect.right) |col| {
            const i_char = self.charIndex(col, row);
            self.text[i_char].render(self.fb);
        }
    }
}

/// Invalidate the whole screen, which will eventually trigger a complete repaint.
pub fn invalidate(self: *Self) void {
    self.modified_area.expand(0, 0);
    self.modified_area.expand(self.num_cols - 1, self.num_rows - 1);
}

// Move the cursor.
pub inline fn cursorMoveTo(self: *Self, col: u64, row: u64) void {
    self.current_col = col;
    self.current_row = row;
}

// Get the current (internal) cursor position.
pub inline fn getCursorCol(self: *Self) u64 {
    return self.current_col;
}

pub inline fn getCursorRow(self: *Self) u64 {
    return self.current_row;
}

pub fn leftCursor(self: *Self) void {
    if (self.current_col > 0) {
        self.current_col -= 1;
    }
}

pub fn rightCursor(self: *Self) void {
    if (self.current_col < self.num_cols - 1) {
        self.current_col += 1;
    }
}

pub fn upCursor(self: *Self) void {
    if (self.current_row > 0) {
        self.current_row -= 1;
    }
}

pub fn downCursor(self: *Self) void {
    if (self.current_row < self.num_rows - 1) {
        self.current_row += 1;
    }
}

pub fn bolCursor(self: *Self) void {
    // Find the first non-whitespace char in the current line.
    var first_non_whitespace: usize = 0;
    for (0..self.num_cols) |i| {
        if (!self.getChar(i, self.current_row).isWhitespace()) {
            first_non_whitespace = i;
            break;
        }
    }

    self.current_col = first_non_whitespace;
}

pub fn eolCursor(self: *Self) void {
    // Find the last non-whitespace, non-irnorable char in the line.
    var i = self.num_cols - 1;
    while (i > 0) {
        if (self.getChar(i, self.current_row).isSignificant()) {
            self.current_col = i;
            break;
        }
        i -= 1;
    }
}

// Clear the screen, move the cursor to 0, 0.
pub fn clearScreen(self: *Self) void {
    for (0..self.length) |i| {
        self.text[i].ch = ' ';
        self.text[i].fg = self.current_fg;
        self.text[i].bg = self.current_bg;
    }
    self.cursorMoveTo(0, 0);
    self.modified_area.expand(0, 0);
    self.modified_area.expand(self.num_cols - 1, self.num_rows - 1);
}

pub fn textShiftLeft(self: *Self, col: usize, row: usize) void {
    var start_i = self.charIndex(col, row);
    var end_i = self.charIndex(self.num_cols - 1, row);
    try serial.writer.print("start_i {} end {}\n", .{ start_i, end_i });

    for (start_i..end_i) |i| {
        self.text[i] = self.text[i + 1];
    }
    self.text[start_i].ch = 'Q';
    self.modified_area.expand(col, row);
    self.modified_area.expand(self.num_cols - 1, row);
}

pub fn shiftRight(self: *Self, col: usize, row: usize) void {
    var len = self.num_cols - col - 1;
    var i_start = self.charIndex(self.num_cols - 1, row);

    var i = i_start;
    for (0..len) |_| {
        self.text[i - 1] = self.text[i];
        i = i - 1;
    }
    self.text[i_start].ch = ' ';
    self.modified_area.expand(col, row);
    self.modified_area.expand(self.num_cols - 1, row);
}

pub fn setRow(self: *Self, row: usize, ch: u8) void {
    var i = self.charIndex(0, row);

    for (0..self.num_cols) |_| {
        self.text[i].ch = ch;
        self.text[i].fg = self.current_fg;
        self.text[i].bg = self.current_bg;
        i += 1;
    }
    self.modified_area.expand(0, row);
    self.modified_area.expand(self.num_cols - 1, row);
}

/// Get the text from the given line. Assumes that result is big enough to hold
/// a lines worth of characters.
pub fn getRowText(self: *Self, row: usize, result: [*]u8) void {
    @memset(result[0..self.num_cols], ' ');
    self.getText(self.charIndex(0, row), self.num_cols, result);
}

pub fn getText(self: *Self, i_start: usize, len: usize, result: [*]u8) void {
    try serial.writer.print("getText: istart {} len {} result {*}\n", .{ i_start, len, result });
    var i_dst: usize = 0;
    for (i_start..(i_start + len)) |i| {
        result[i_dst] = self.text[i].ch;
        i_dst += 1;
    }
}

inline fn charIndex(self: *Self, x: u64, y: u64) u64 {
    return y * self.num_cols + x;
}

pub inline fn setCurrentChar(self: *Self, ch: u8) void {
    const i = self.charIndex(self.current_col, self.current_row);
    self.text[i].ch = ch;
    self.text[i].fg = self.current_fg;
    self.text[i].bg = self.current_bg;
    self.modified_area.expand(self.current_col, self.current_row);
    if (self.current_col > 400 or self.current_row > 400) {
        try serial.writer.print("bad row/col {} {} ????\n", .{ self.current_col, self.current_row });
    }
}

pub inline fn getChar(self: *Self, col: u64, row: u64) RichChar {
    const i = self.charIndex(col, row);
    return self.text[i];
}

pub fn dumpText(self: *Self) void {
    _ = serial.puts("===Text ===\r\n");
    for (0..self.num_rows) |row| {
        serial.putc('|');
        for (0..self.num_cols) |col| {
            const ch = self.getChar(col, row);
            serial.putc(ch.ch);
        }
        _ = serial.puts("$\r\n");
    }
    _ = serial.puts("------\r\n");
}
pub fn dumpInfo(self: *Self) void {
    const w = serial.writer;
    try w.print("CharDisplay: num_rows: {} num_cols: {} length {}\n", .{ self.num_rows, self.num_cols, self.length });

    for (0..self.num_rows) |row| {
        const i_start = self.charIndex(0, row);
        var count: usize = 0;
        for (0..self.num_cols) |col| {
            const ch = self.getChar(col, row);
            if (ch.ch != ' ') {
                count += 1;
            }
        }
        try w.print("Row {} starts at index {}, address {*} and contains {} non-blanks\n", .{ row, i_start, self.text + i_start, count });
    }
}
