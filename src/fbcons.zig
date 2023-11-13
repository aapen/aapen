const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const debug = root.debug;
const kprint = root.kprint;
const Serial = root.HAL.Serial;

const FrameBuffer = @import("frame_buffer.zig");

const Readline = @import("readline.zig");
const RichChar = @import("rich_char.zig").RichChar;

const Self = @This();

/// Display console.
/// The naming convention is that x and y are pixel coordinates
/// while rows and columns are character coordinates.
tab_width: u8 = 8,
num_cols: u64 = undefined,
num_rows: u64 = undefined,
length: u64 = undefined,
fb: *FrameBuffer = undefined,
serial: *Serial = undefined,
text: [*]RichChar,
current_col: u64 = 0,
current_row: u64 = 0,
current_ignore: u1 = 0,
current_insert: u1 = 0,

pub fn init(allocator: Allocator, fb: *FrameBuffer, serial: *Serial) !*Self {
    var self: *Self = try allocator.create(Self);

    const num_cols = fb.xres / fb.font_width_px;
    const num_rows = fb.yres / fb.font_height_px;
    const length = num_cols * num_rows;
    const text = try allocator.alloc(RichChar, length);

    self.* = .{
        .fb = fb,
        .serial = serial,
        .num_cols = num_cols,
        .num_rows = num_rows,
        .length = length,
        .text = text.ptr,
        .current_col = 0,
        .current_row = 0,
        .current_ignore = 0,
        .current_insert = 0,
    };

    return self;
}

pub fn clear(self: *Self) void {
    self.fb.clear();
    self.current_col = 0;
    self.current_row = 0;
    const space = RichChar.init(' ', self.fb.fg, self.fb.bg, 0);
    @memset(self.text[0..self.length], space);
}

fn next(self: *Self) void {
    self.current_col += 1;
    if (self.current_col >= self.num_cols) {
        self.nextLine();
    }
}

fn nextTab(self: *Self) void {
    var positions = self.tab_width - (self.current_col % self.tab_width);
    self.current_col += positions;
    if (self.current_col >= self.num_cols) {
        self.nextLine();
    }
}

fn nextLine(self: *Self) void {
    self.current_col = 0;
    self.current_row += 1;
    if (self.current_row >= self.num_rows) {
        self.nextScreen();
    }
    self.fb.clearRegion(0, self.fb.rowToY(self.current_row), self.fb.xres, self.fb.font_height_px);
}

fn nextScreen(self: *Self) void {
    //self.fb.blit(0, CharHeight, self.fb.xres, self.fb.yres - CharHeight, 0, 0);
    self.fb.blit(0, self.fb.font_height_px, self.fb.xres, self.fb.yres - self.fb.font_height_px, 0, 0);

    self.current_col = 0;
    self.current_row = self.num_rows - 1;
    const copyLen = self.length - self.num_cols;
    std.mem.copyForwards(RichChar, self.text[0..copyLen], self.text[self.num_cols..self.length]);
    self.setCharRange(0, self.num_rows - 1, self.num_cols, self.num_rows - 1, ' ');
}

fn underbar(self: *Self, color: u8) void {
    var x: u64 = self.fb.colToX(self.current_col);
    var y: u64 = self.fb.rowToY(self.current_row + 1) - 1;

    for (0..self.fb.font_width_px) |i| {
        self.fb.drawPixel(x + i, y, color);
    }
}

fn eraseCursor(self: *Self) void {
    self.underbar(self.fb.bg);
}

fn drawCursor(self: *Self) void {
    self.underbar(self.fb.fg);
}

fn leftCursor(self: *Self) void {
    if (self.current_col > 0) {
        self.current_col -= 1;
        self.drawCursor();
    }
}

fn rightCursor(self: *Self) void {
    if (self.current_col < self.num_cols - 1) {
        self.current_col += 1;
        self.drawCursor();
    }
}

fn upCursor(self: *Self) void {
    if (self.current_row > 0) {
        self.current_row -= 1;
        self.drawCursor();
    }
}

fn downCursor(self: *Self) void {
    if (self.current_row < self.num_cols - 1) {
        self.current_row += 1;
        self.drawCursor();
    }
}

fn bolCursor(self: *Self) void {
    self.current_col = 0;
}

fn eolCursor(self: *Self) void {
    self.current_col = self.num_cols - 1;
}

fn backspace(self: *Self) void {
    if (self.current_col > 0) {
        self.current_col -= 1;
    }
    self.fb.eraseChar(self.fb.colToX(self.current_col), self.fb.rowToY(self.current_row));

    const i_start = self.charIndex(self.current_col + 1, self.current_row);
    const i_end = self.charIndex(self.num_cols, self.current_row);
    for (i_start..i_end) |i| {
        self.text[i - 1] = self.text[i];
    }
    self.text[i_end - 1] = RichChar.init(' ', self.fb.fg, self.fb.bg, 0);
    self.redrawLine(self.current_row);
}

fn isPrintable(ch: u8) bool {
    return ch >= 32 and ch <= 128;
}

pub fn getLineText(self: *Self, line_no: usize, filter: bool, result: [*]u8) void {
    const i = self.charIndex(0, line_no);
    const j = self.charIndex(0, line_no + 1);
    @memset(result[0..self.num_cols], ' ');

    var i_dest: usize = 0;
    for (i..j) |i_source| {
        const rc = self.text[i_source];
        if (filter and (rc.ignore == 1)) {
            continue;
        }
        result[i_dest] = rc.ch;
        i_dest += 1;
    }
}

pub fn redrawLine(self: *Self, row: usize) void {
    for (0..self.num_cols) |col| {
        self.text[self.charIndex(col, row)].draw(self.fb, col, row);
    }
    if (row == self.current_row) {
        self.drawCursor();
    }
}

pub fn redraw(self: *Self) void {
    for (0..self.num_rows) |row| {
        self.redrawLine(row);
    }
}

pub fn addChar(self: *Self, ch: u8) void {
    if (isPrintable(ch)) {
        const rc = RichChar.init(ch, self.fb.fg, self.fb.bg, self.current_ignore);
        self.setChar(self.current_col, self.current_row, rc);
        rc.draw(self.fb, self.current_col, self.current_row);
    }
    self.next();
}

pub fn emit(self: *Self, ch: u8) void {
    self.eraseCursor();
    defer self.drawCursor();

    switch (ch) {
        0x0c => self.clear(),
        0x7f => self.backspace(),
        '\t' => self.nextTab(),
        '\n' => self.nextLine(),
        0x80 => self.upCursor(),
        0x81 => self.downCursor(),
        0x82 => self.leftCursor(),
        0x83 => self.rightCursor(),
        0x84 => self.bolCursor(),
        0x85 => self.eolCursor(),
        0x86 => self.current_insert = 1, // Currently ignored.
        0x87 => self.current_insert = 0,
        0x8a => self.current_ignore = 1,
        0x8b => self.current_ignore = 0,
        0x90...0x9f => self.fb.fg = (ch - 0x90),
        0xa0...0xaf => self.fb.bg = (ch - 0xa0),
        0xf0 => self.dumpText(),
        0xf1 => self.dumpColors(),
        0xf2 => self.dumpIgnore(),
        0xfe => self.redrawLine(self.current_row),
        0xff => self.redraw(),
        else => self.addChar(ch),
    }
}

pub fn emitString(self: *Self, str: []const u8) void {
    self.eraseCursor();
    defer self.drawCursor();

    for (str) |ch| {
        self.emit(ch);
    }
}

inline fn charIndex(self: *Self, x: u64, y: u64) u64 {
    return y * self.num_cols + x;
}

pub inline fn setChar(self: *Self, xpos: u64, ypos: u64, rc: RichChar) void {
    self.text[self.charIndex(xpos, ypos)] = rc;
}

pub inline fn getChar(self: *Self, xpos: u64, ypos: u64) RichChar {
    const i = self.charIndex(xpos, ypos);
    return self.text[i];
}

pub inline fn setCharRange(self: *Self, x1: usize, y1: usize, x2: usize, y2: usize, ch: u8) void {
    const i = self.charIndex(x1, y1);
    const j = self.charIndex(x2, y2);
    for (i..j) |k| {
        self.text[k] = RichChar.init(ch, self.fb.fg, self.fb.bg, 0);
    }
}

pub fn dumpText(self: *Self) void {
    _ = self.serial.puts("===Text ===\r\n");
    for (0..self.num_rows) |row| {
        self.serial.putc('|');
        for (0..self.num_cols) |col| {
            const ch = self.getChar(col, row);
            self.serial.putc(ch.ch);
        }
        _ = self.serial.puts("$\r\n");
    }
    _ = self.serial.puts("------\r\n");
}

pub fn dumpIgnore(self: *Self) void {
    _ = self.serial.puts("=== ignore ===\r\n");
    for (0..self.num_rows) |row| {
        self.serial.putc('|');
        for (0..self.num_cols) |col| {
            const rc = self.getChar(col, row);
            if (rc.ignore == 1) {
                self.serial.putc('Y');
            } else {
                self.serial.putc('.');
            }
        }
        _ = self.serial.puts("$\r\n");
    }
}

pub fn dumpColors(self: *Self) void {
    _ = self.serial.puts("=== fg ===\r\n");
    for (0..self.num_rows) |row| {
        self.serial.putc('|');
        for (0..self.num_cols) |col| {
            const rc = self.getChar(col, row);
            self.serial.putc('A' + rc.fg);
        }
        _ = self.serial.puts("$\r\n");
    }

    _ = self.serial.puts("=== bg ===\r\n");
    for (0..self.num_rows) |row| {
        self.serial.putc('|');
        for (0..self.num_cols) |col| {
            const rc = self.getChar(col, row);
            self.serial.putc('A' + rc.bg);
        }
        _ = self.serial.puts("$\r\n");
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
