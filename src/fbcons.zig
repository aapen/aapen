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
nCols: u64 = undefined,
nRows: u64 = undefined,
length: u64 = undefined,
fb: *FrameBuffer = undefined,
serial: *Serial = undefined,
text: [*]RichChar,
currentCol: u64 = 0,
currentRow: u64 = 0,
currentIgnore: u1 = 0,
currentInsert: u1 = 0,

pub fn init(allocator: Allocator, fb: *FrameBuffer, serial: *Serial) !*Self {
    var self: *Self = try allocator.create(Self);

    const nCols = fb.xres / fb.font_width_px;
    const nRows = fb.yres / fb.font_height_px;
    const length = nCols * nRows;
    const text = try allocator.alloc(RichChar, length);

    self.* = .{
        .fb = fb,
        .serial = serial,
        .nCols = nCols,
        .nRows = nRows,
        .length = length,
        .text = text.ptr,
        .currentCol = 0,
        .currentRow = 0,
        .currentIgnore = 0,
        .currentInsert = 0,
    };

    return self;
}

pub fn clear(self: *Self) void {
    self.fb.clear();
    self.currentCol = 0;
    self.currentRow = 0;
    const space = RichChar.init(' ', self.fb.fg, self.fb.bg, 0);
    @memset(self.text[0..self.length], space);
}

fn next(self: *Self) void {
    self.currentCol += 1;
    if (self.currentCol >= self.nCols) {
        self.nextLine();
    }
}

fn nextTab(self: *Self) void {
    var positions = self.tab_width - (self.currentCol % self.tab_width);
    self.currentCol += positions;
    if (self.currentCol >= self.nCols) {
        self.nextLine();
    }
}

fn nextLine(self: *Self) void {
    self.currentCol = 0;
    self.currentRow += 1;
    if (self.currentRow >= self.nRows) {
        self.nextScreen();
    }
    self.fb.clearRegion(0, self.fb.rowToY(self.currentRow), self.fb.xres, self.fb.font_height_px);
}

fn nextScreen(self: *Self) void {
    //self.fb.blit(0, CharHeight, self.fb.xres, self.fb.yres - CharHeight, 0, 0);
    self.fb.blit(0, self.fb.font_height_px, self.fb.xres, self.fb.yres - self.fb.font_height_px, 0, 0);

    self.currentCol = 0;
    self.currentRow = self.nRows - 1;
    const copyLen = self.length - self.nCols;
    std.mem.copyForwards(RichChar, self.text[0..copyLen], self.text[self.nCols..self.length]);
    self.setCharRange(0, self.nRows - 1, self.nCols, self.nRows - 1, ' ');
}

fn underbar(self: *Self, color: u8) void {
    var x: u64 = self.fb.colToX(self.currentCol);
    var y: u64 = self.fb.rowToY(self.currentRow + 1) - 1;

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
    if (self.currentCol > 0) {
        self.currentCol -= 1;
        self.drawCursor();
    }
}

fn rightCursor(self: *Self) void {
    if (self.currentCol < self.nCols - 1) {
        self.currentCol += 1;
        self.drawCursor();
    }
}

fn upCursor(self: *Self) void {
    if (self.currentRow > 0) {
        self.currentRow -= 1;
        self.drawCursor();
    }
}

fn downCursor(self: *Self) void {
    if (self.currentRow < self.nCols - 1) {
        self.currentRow += 1;
        self.drawCursor();
    }
}

fn bolCursor(self: *Self) void {
    self.currentCol = 0;
}

fn eolCursor(self: *Self) void {
    self.currentCol = self.nCols - 1;
}

fn backspace(self: *Self) void {
    if (self.currentCol > 0) {
        self.currentCol -= 1;
    }
    self.fb.eraseChar(self.fb.colToX(self.currentCol), self.fb.rowToY(self.currentRow));

    const iStart = self.charIndex(self.currentCol + 1, self.currentRow);
    const iEnd = self.charIndex(self.nCols, self.currentRow);
    for (iStart..iEnd) |i| {
        self.text[i - 1] = self.text[i];
    }
    self.text[iEnd - 1] = RichChar.init(' ', self.fb.fg, self.fb.bg, 0);
    self.redrawLine(self.currentRow);
}

fn isPrintable(ch: u8) bool {
    return ch >= 32 and ch <= 128;
}

pub fn getLineText(self: *Self, line_no: usize, filter: bool, result: [*]u8) void {
    const i = self.charIndex(0, line_no);
    const j = self.charIndex(0, line_no + 1);
    @memset(result[0..self.nCols], ' ');

    var iDst: usize = 0;
    for (i..j) |iSrc| {
        const rc = self.text[iSrc];
        if (filter and (rc.ignore == 1)) {
            continue;
        }
        result[iDst] = rc.ch;
        iDst += 1;
    }
}

pub fn redrawLine(self: *Self, row: usize) void {
    for (0..self.nCols) |col| {
        self.text[self.charIndex(col, row)].draw(self.fb, col, row);
    }
    if (row == self.currentRow) {
        self.drawCursor();
    }
}

pub fn redraw(self: *Self) void {
    for (0..self.nRows) |row| {
        self.redrawLine(row);
    }
}

pub fn addChar(self: *Self, ch: u8) void {
    if (isPrintable(ch)) {
        const rc = RichChar.init(ch, self.fb.fg, self.fb.bg, self.currentIgnore);
        self.setChar(self.currentCol, self.currentRow, rc);
        rc.draw(self.fb, self.currentCol, self.currentRow);
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
        0x86 => self.currentInsert = 1, // Currently ignored.
        0x87 => self.currentInsert = 0,
        0x8a => self.currentIgnore = 1,
        0x8b => self.currentIgnore = 0,
        0x90...0x9f => self.fb.fg = (ch - 0x90),
        0xa0...0xaf => self.fb.bg = (ch - 0xa0),
        0xf0 => self.dump_text(),
        0xf1 => self.dump_colors(),
        0xf2 => self.dump_ignore(),
        0xfe => self.redrawLine(self.currentRow),
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
    return y * self.nCols + x;
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

pub fn dump_text(self: *Self) void {
    _ = self.serial.puts("===Text ===\r\n");
    for (0..self.nRows) |row| {
        self.serial.putc('|');
        for (0..self.nCols) |col| {
            const ch = self.getChar(col, row);
            self.serial.putc(ch.ch);
        }
        _ = self.serial.puts("$\r\n");
    }
    _ = self.serial.puts("------\r\n");
}

pub fn dump_ignore(self: *Self) void {
    _ = self.serial.puts("=== ignore ===\r\n");
    for (0..self.nRows) |row| {
        self.serial.putc('|');
        for (0..self.nCols) |col| {
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

pub fn dump_colors(self: *Self) void {
    _ = self.serial.puts("=== fg ===\r\n");
    for (0..self.nRows) |row| {
        self.serial.putc('|');
        for (0..self.nCols) |col| {
            const rc = self.getChar(col, row);
            self.serial.putc('A' + rc.fg);
        }
        _ = self.serial.puts("$\r\n");
    }

    _ = self.serial.puts("=== bg ===\r\n");
    for (0..self.nRows) |row| {
        self.serial.putc('|');
        for (0..self.nCols) |col| {
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
