const std = @import("std");
const assert = std.debug.assert;

const hal = @import("hal.zig");
const DMA = hal.DMA;

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

pub const default_palette = [_]u32{
    0x00000000,
    0x00ffffff,
    0x00000088,
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

pub const FrameBuffer = struct {
    //    pub const Self = @This();
    pub const VTable = struct {
        line: *const fn (fb: *FrameBuffer, x0: usize, y0: usize, x1: usize, x2: usize, color: u8) Error!void,
    };

    // These are palette indices
    pub const DEFAULT_FOREGROUND: u8 = 0x01;
    pub const DEFAULT_BACKGROUND: u8 = 0x00;

    pub const Error = error{
        OutOfBounds,
    };

    dma: *const hal.DMA = undefined,
    dma_channel: ?hal.DMAChannel = undefined,
    base: [*]u8 = undefined,
    buffer_size: usize = undefined,
    pitch: usize = undefined,
    xres: usize = undefined,
    yres: usize = undefined,
    bpp: u32 = undefined,
    range: Region = undefined,
    fg: u8 = DEFAULT_FOREGROUND,
    bg: u8 = DEFAULT_BACKGROUND,
    vtable: VTable = .{ .line = line },

    pub fn drawPixel(self: *FrameBuffer, x: usize, y: usize, color: u8) void {
        if (x < 0) return;
        if (x >= self.xres) return;
        if (y < 0) return;
        if (y >= self.yres) return;

        var idx: usize = x + (y * self.pitch);

        assert(idx < self.buffer_size);

        self.base[x + (y * self.pitch)] = color;
    }

    pub fn clear(self: *FrameBuffer) void {
        self.fill(0, 0, self.xres, self.yres, self.bg) catch {};
    }

    pub fn clearRegion(self: *FrameBuffer, x: usize, y: usize, w: usize, h: usize) void {
        self.fill(x, y, x + w, y + h, self.bg) catch {};
    }

    // Font is fixed height of 16 bits, fixed width of 8 bits
    const CharRow = @Vector(8, u8);

    pub fn drawChar(self: *FrameBuffer, x: usize, y: usize, ch: u8) void {
        var romidx: usize = @as(usize, ch - 32) * 16;
        if (romidx + 16 >= character_rom.len)
            return;

        var line_stride = self.pitch;
        var fbidx = x + (y * line_stride);

        const backgv: CharRow = @splat(self.bg);
        const foregv: CharRow = @splat(self.fg);

        inline for (0..16) |_| {
            const rowbits: CharBits = character_rombits[romidx];
            const row = @select(u8, rowbits, foregv, backgv);
            (self.base + fbidx)[0..8].* = row;
            fbidx += line_stride;
            romidx += 1;
        }
    }

    pub fn drawString(self: *FrameBuffer, str: [*:0]u8, x_start: usize, y_start: usize) void {
        var x = x_start;
        var y = y_start;
        var i: usize = 0;
        while (str[i] != 0) : (i += 1) {
            self.drawChar(x, y, str[i]);
            x += 8;
        }
    }

    pub fn eraseChar(self: *FrameBuffer, x: usize, y: usize) void {
        var line_stride = self.pitch;
        var fbidx = x + (y * line_stride);

        inline for (0..16) |_| {
            inline for (0..8) |_| {
                self.base[fbidx] = self.bg;
                fbidx += 1;
            }
            fbidx -= 8;
            fbidx += line_stride;
        }
    }

    pub fn blit(fb: *FrameBuffer, src_x: usize, src_y: usize, src_w: usize, src_h: usize, dest_x: usize, dest_y: usize) void {
        var sx = clamp(usize, 0, src_x, fb.xres);
        var sy = clamp(usize, 0, src_y, fb.yres);
        var w = clamp(usize, 0, src_w, fb.xres);
        var h = clamp(usize, 0, src_h, fb.yres);
        var dx = clamp(usize, 0, dest_x, fb.xres);
        var dy = clamp(usize, 0, dest_y, fb.yres);

        if (fb.dma_channel) |ch| {
            const fb_base: usize = @intFromPtr(fb.base);
            const fb_pitch = fb.pitch;
            const stride_2d = fb.xres - w;
            const xfer_y_len = h;
            const xfer_x_len = w;

            const len = if (stride_2d > 0) ((xfer_y_len << 16) + xfer_x_len) else (h * fb.xres);

            var req = hal.DMARequest{
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

    pub fn fill(fb: *FrameBuffer, left: usize, top: usize, right: usize, bottom: usize, color: u8) !void {
        var c: @Vector(16, u8) = @splat(color);

        var l = clamp(usize, 0, left, fb.xres);
        var r = clamp(usize, 0, right, fb.xres);
        var t = clamp(usize, 0, top, fb.yres);
        var b = clamp(usize, 0, bottom, fb.yres);

        if (fb.dma_channel) |ch| {
            const fb_base: usize = @intFromPtr(fb.base);
            const fb_pitch = fb.pitch;

            const src = @intFromPtr(&c);
            const src_stride = 0;

            const dest = fb_base + (t * fb_pitch) + l;
            const dest_stride = fb.xres - r + l;

            const xfer_y_len = b - t;
            const xfer_x_len = r - l;

            const xfer_count = if (dest_stride > 0)
                ((xfer_y_len << 16) + xfer_x_len)
            else
                ((b - t) * fb.xres);

            var req = try fb.dma.createRequest();
            defer fb.dma.destroyRequest(req);

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
    }

    pub fn line(fb: *FrameBuffer, x0: usize, y0: usize, x1: usize, y1: usize, color: u8) !void {
        var x_start = try boundsCheck(usize, 0, x0, fb.xres);
        var y_start = try boundsCheck(usize, 0, y0, fb.yres);
        var x_end = try boundsCheck(usize, 0, x1, fb.xres);
        var y_end = try boundsCheck(usize, 0, y1, fb.yres);

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

            var steep = abs(isize, iy1 - iy0) > abs(isize, ix1 - ix0);

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

            var dx = ix1 - ix0;
            var dy = abs(isize, iy1 - iy0);
            var err: isize = 0;
            var ystep: isize = if (iy0 < iy1) 1 else -1;
            var y_cur = iy0;
            var x_cur = ix0;
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

    fn lineHorizontal(fb: *FrameBuffer, y: usize, x0: usize, x1: usize, color: u8) void {
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

    fn lineVertical(fb: *FrameBuffer, x: usize, y0: usize, y1: usize, color: u8) void {
        var start: usize = 0;
        var end: usize = 0;

        if (y0 > y1) {
            start = y1;
            end = y0;
        } else {
            start = y0;
            end = y1;
        }

        var step = fb.pitch;
        var pixel: [*]u8 = fb.base;
        pixel += start * step + x;
        pixel[0] = color;
        for (start..end) |_| {
            pixel += step;
            pixel[0] = color;
        }
    }
};
