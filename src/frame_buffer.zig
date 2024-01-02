const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const root = @import("root");
const debug = @import("debug.zig");

const auto = @import("forty/auto.zig");
const Forth = @import("forty/forth.zig").Forth;

const DMA = root.HAL.DMA;
const DMAChannel = root.HAL.DMA.Channel;
const DMARequest = root.HAL.DMA.Request;

const Region = @import("memory.zig").Region;

const CharBits = @Vector(8, bool);

const character_rom = @embedFile("data/character_rom.bin");
const character_count = character_rom.len;

// initialized from character_rom when the frame buffer is initialized
const character_rombits: [character_rom.len]CharBits = init: {
    @setEvalBranchQuota(character_rom.len);
    var initial_value: [character_rom.len]CharBits = undefined;
    inline for (0..character_count) |i| {
        initial_value[i] = @bitCast(@bitReverse(character_rom[i]));
    }
    break :init initial_value;
};

pub const Self = @This();

pub fn defineModule(forth: *Forth, fb: *Self) !void {
    try forth.defineConstant("fb", @intFromPtr(fb));
    try auto.defineNamespace(Self, "fb.", forth);
    try forth.defineStruct("FrameBuffer", Self);
}

// Font dimensions

pub const DEFAULT_FONT_WIDTH = 8;
pub const DEFAULT_FONT_HEIGHT = 16;

// These are palette indices
pub const DEFAULT_X_RESOLUTION: u32 = 1024;
pub const DEFAULT_Y_RESOLUTION: u32 = 768;
pub const DEFAULT_DEPTH: u32 = 8;
pub const DEFAULT_PALETTE = [_]u32{
    0x00000000,
    0x00ffffff,
    0x000000ff,
    0x00eeffaa,
    0x00cc44cc,
    0x0055cc00,
    0x00e44140,
    0x0077eeee,
    0x005588dd,
    0x00004466,
    0x007777ff,
    0x00333333,
    0x00777777,
    0x0066ffaa,
    0x00f3afaf,
    0x00bbbbbb,
};

pub const Error = error{
    OutOfBounds,
};

xres: u32 = DEFAULT_X_RESOLUTION,
yres: u32 = DEFAULT_Y_RESOLUTION,
bpp: u32 = DEFAULT_DEPTH,
palette: [DEFAULT_PALETTE.len]u32 = DEFAULT_PALETTE,

font_width_px: u32 = DEFAULT_FONT_WIDTH,
font_height_px: u32 = DEFAULT_FONT_HEIGHT,

dma: *DMA = undefined,
dma_channel: ?DMAChannel = undefined,
base: [*]u8 = undefined,
buffer_size: usize = undefined,
pitch: usize = undefined,
range: Region = undefined,

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------

pub fn demo(iop: auto.InteropCall, fb: *Self, color: u8) void {
    fb.line(0, 0, 1024, 768, color, iop);
}

pub fn init(allocator: Allocator, hal: *root.HAL) !*Self {
    const self = try allocator.create(Self);

    self.* = .{};

    try hal.video_controller.allocFrameBuffer(self);

    return self;
}

pub fn drawPixel(self: *Self, x: usize, y: usize, color: u8) void {
    if (x < 0) return;
    if (x >= self.xres) return;
    if (y < 0) return;
    if (y >= self.yres) return;

    const idx: usize = x + (y * self.pitch);

    assert(idx < self.buffer_size);

    self.base[x + (y * self.pitch)] = color;
}

pub fn clear(self: *Self, color: u8) void {
    self.fill(0, 0, self.xres, self.yres, color);
}

pub fn clearRegion(self: *Self, x: usize, y: usize, w: usize, h: usize, color: u8) void {
    self.fill(x, y, x + w, y + h, color);
}

// Font is fixed height of 16 bits, fixed width of 8 bits
const CharRow = @Vector(DEFAULT_FONT_WIDTH, u8);

pub fn drawChar(self: *Self, x: usize, y: usize, ch: u8, fg: u8, bg: u8, _: auto.InteropCall) void {
    var romidx: usize = @as(usize, ch - 32) * DEFAULT_FONT_HEIGHT;
    if (romidx + self.font_height_px >= character_rom.len)
        return;

    const line_stride = self.pitch;
    var fbidx = x + (y * line_stride);

    const backgv: CharRow = @splat(bg);
    const foregv: CharRow = @splat(fg);

    inline for (0..DEFAULT_FONT_HEIGHT) |_| {
        const rowbits: CharBits = character_rombits[romidx];
        const row = @select(u8, rowbits, foregv, backgv);
        (self.base + fbidx)[0..DEFAULT_FONT_WIDTH].* = row;
        fbidx += line_stride;
        romidx += 1;
    }
}

pub fn text(self: *Self, str: [*:0]u8, x_start: usize, y_start: usize, fg: u8, bg: u8, iop: auto.InteropCall) void {
    const y = y_start;
    var x = x_start;
    var i: usize = 0;
    while (str[i] != 0) : (i += 1) {
        self.drawChar(x, y, str[i], fg, bg, iop);
        x += 8;
    }
}

pub fn eraseChar(self: *Self, x: usize, y: usize, color: u8) void {
    const line_stride = self.pitch;
    var fbidx = x + (y * line_stride);

    inline for (0..DEFAULT_FONT_HEIGHT) |_| {
        inline for (0..DEFAULT_FONT_WIDTH) |_| {
            self.base[fbidx] = color;
            fbidx += 1;
        }
        fbidx -= self.font_width_px;
        fbidx += line_stride;
    }
}

pub inline fn yToRow(self: *Self, y: usize) usize {
    return @truncate(y / self.font_height_px);
}

pub inline fn xToCol(self: *Self, x: usize) usize {
    return @truncate(x / self.font_width_px);
}

pub inline fn rowToY(self: *Self, row: usize) usize {
    return row * self.font_height_px;
}

pub inline fn colToX(self: *Self, col: usize) usize {
    return col * self.font_width_px;
}

pub fn blit(fb: *Self, src_x: usize, src_y: usize, src_w: usize, src_h: usize, dest_x: usize, dest_y: usize, _: auto.InteropCall) void {
    const sx = clamp(usize, 0, src_x, fb.xres);
    const sy = clamp(usize, 0, src_y, fb.yres);
    const w = clamp(usize, 0, src_w, fb.xres);
    const h = clamp(usize, 0, src_h, fb.yres);
    const dx = clamp(usize, 0, dest_x, fb.xres);
    const dy = clamp(usize, 0, dest_y, fb.yres);

    if (fb.dma_channel) |ch| {
        const fb_base: usize = @intFromPtr(fb.base);
        const fb_pitch = fb.pitch;
        const stride_2d = fb.xres - w;
        const xfer_y_len = h;
        const xfer_x_len = w;

        const len = if (stride_2d > 0) ((xfer_y_len << 16) + xfer_x_len) else (h * fb.xres);

        var req = DMARequest{
            .source = @truncate(fb_base + (sy * fb_pitch) + sx),
            .destination = @truncate(fb_base + (dy * fb_pitch) + dx),
            .length = len,
            .stride = (stride_2d << 16) | stride_2d,
        };
        fb.dma.initiate(ch, &req) catch {};
        _ = fb.dma.awaitChannel(ch);
    }
}

inline fn clamp(comptime T: type, min: T, val: T, max: T) T {
    return @max(min, @min(val, max));
}

inline fn boundsCheck(comptime T: type, min: T, val: T, max: T) !T {
    if (val < min or val > max) {
        return Error.OutOfBounds;
    }
    return val;
}

inline fn abs(comptime T: type, val: T) T {
    return if (val > 0) val else -val;
}

pub fn fill(fb: *Self, left: usize, top: usize, right: usize, bottom: usize, color: u8, _: auto.InteropCall) void {
    const l = clamp(usize, 0, left, fb.xres);
    const r = clamp(usize, 0, right, fb.xres);
    const t = clamp(usize, 0, top, fb.yres);
    const b = clamp(usize, 0, bottom, fb.yres);

    if (fb.dma_channel) |ch| {
        if (fb.dma.createRequest()) |req| {
            // DMA fill
            defer fb.dma.destroyRequest(req);
            fb.fillDMA(ch, req, l, t, r, b, color);
            return;
        } else |_| {
            // will use fallback
        }
    }

    // fallback to CPU driven fill
    fb.fillPixels(l, t, r, b, color);
}

fn fillDMA(fb: *Self, ch: DMAChannel, req: *DMARequest, l: usize, t: usize, r: usize, b: usize, color: u8) void {
    var cvec: @Vector(16, u8) = @splat(color);

    const fb_base: usize = @intFromPtr(fb.base);
    const fb_pitch = fb.pitch;

    const src = @intFromPtr(&cvec);
    const src_stride = 0;

    const dest = fb_base + (t * fb_pitch) + l;
    const dest_stride = fb.xres - r + l;

    const xfer_y_len = b - t;
    const xfer_x_len = r - l;

    const xfer_count = if (dest_stride > 0)
        ((xfer_y_len << 16) + xfer_x_len)
    else
        ((b - t) * fb.xres);

    req.* = .{
        .source = @truncate(src),
        .source_increment = false,
        .destination = @truncate(dest),
        .destination_increment = true,
        .length = xfer_count,
        .stride = (dest_stride << 16) | src_stride,
    };
    fb.dma.initiate(ch, req) catch {};
    _ = fb.dma.awaitChannel(ch);
}

fn fillPixels(fb: *Self, l: usize, t: usize, r: usize, b: usize, color: u8) void {
    const cvec: @Vector(16, u8) = @splat(color);
    const line_stride = fb.pitch;
    const gap = line_stride - (r - l);
    const row_vecs = (r - l) / 16;
    const row_leftover = (r - l) % 16;
    const rows = (b - t);

    var fbidx = l + (t * line_stride);

    for (0..rows) |_| {
        for (0..row_vecs) |_| {
            (fb.base + fbidx)[0..16].* = cvec;
            fbidx += 16;
        }
        for (0..row_leftover) |_| {
            (fb.base + fbidx)[0] = color;
        }
        fbidx += gap;
    }
}

pub fn line(fb: *Self, x0: usize, y0: usize, x1: usize, y1: usize, color: u8, _: auto.InteropCall) void {
    const x_start = boundsCheck(usize, 0, x0, fb.xres) catch {
        return;
    };
    const y_start = boundsCheck(usize, 0, y0, fb.yres) catch {
        return;
    };
    const x_end = boundsCheck(usize, 0, x1, fb.xres) catch {
        return;
    };
    const y_end = boundsCheck(usize, 0, y1, fb.yres) catch {
        return;
    };

    if (x_start == x_end) {
        // special case for vertical lines (infinite slope!)
        fb.lineVertical(x_start, y_start, y_end, color);
    } else if (y_start == y_end) {
        // special case for horizontal lines (very fast)
        fb.lineHorizontal(y_start, x_start, x_end, color);
    } else {
        // full Bresenham
        var ix0: isize = @bitCast(x_start);
        var ix1: isize = @bitCast(x_end);
        var iy0: isize = @bitCast(y_start);
        var iy1: isize = @bitCast(y_end);

        const steep = abs(isize, iy1 - iy0) > abs(isize, ix1 - ix0);

        if (steep) {
            var t = ix0;
            ix0 = iy0;
            iy0 = ix0;

            t = ix1;
            ix1 = iy1;
            iy1 = t;
        }

        if (ix0 > ix1) {
            var t = ix0;
            ix0 = ix1;
            ix1 = t;

            t = iy0;
            iy0 = iy1;
            iy1 = t;
        }

        const ystep: isize = if (iy0 < iy1) 1 else -1;
        const dx = ix1 - ix0;
        const dy = abs(isize, iy1 - iy0);
        var y_cur = iy0;
        var x_cur = ix0;
        var err: isize = 0;

        while (x_cur <= ix1) {
            if (steep) {
                fb.base[@as(usize, @intCast(y_cur)) + @as(usize, @intCast(x_cur)) * fb.pitch] = color;
            } else {
                fb.base[@as(usize, @intCast(x_cur)) + @as(usize, @intCast(y_cur)) * fb.pitch] = color;
            }
            err += dy;
            if (2 * err >= dx) {
                y_cur += ystep;
                err -= dx;
            }
            x_cur += 1;
        }
    }
}

fn lineHorizontal(fb: *Self, y: usize, x0: usize, x1: usize, color: u8) void {
    var start: usize = 0;
    var end: usize = 0;
    if (x0 > x1) {
        start = x1;
        end = x0;
    } else {
        start = x0;
        end = x1;
    }

    var pixel: [*]u8 = fb.base;
    pixel += y * fb.pitch + start;
    pixel[0] = color;
    for (start..end) |_| {
        pixel += 1;
        pixel[0] = color;
    }
}

fn lineVertical(fb: *Self, x: usize, y0: usize, y1: usize, color: u8) void {
    var start: usize = 0;
    var end: usize = 0;

    if (y0 > y1) {
        start = y1;
        end = y0;
    } else {
        start = y0;
        end = y1;
    }

    const step = fb.pitch;
    var pixel: [*]u8 = fb.base;
    pixel += start * step + x;
    pixel[0] = color;
    for (start..end) |_| {
        pixel += step;
        pixel[0] = color;
    }
}
