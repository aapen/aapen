const std = @import("std");
const assert = std.debug.assert;

const hal = @import("hal.zig");
const DMAController = hal.interfaces.DMAController;
const DMAChannel = hal.interfaces.DMAChannel;
const DMARequest = hal.interfaces.DMARequest;

const Region = @import("memory.zig").Region;

const character_rom = @embedFile("data/character_rom.bin");

pub const default_palette = [_]u32{
    0x00000000,
    0xFFBB5500,
    0xFFFFFFFF,
    0xFFFF0000,
    0xFF00FF00,
    0xFF0000FF,
    0x55555555,
    0xCCCCCCCC,
};

pub const FrameBuffer = struct {
    pub const Error = error{
        OutOfBounds,
    };

    dma: *DMAController = undefined,
    dma_channel: ?DMAChannel = undefined,
    base: [*]u8 = undefined,
    buffer_size: usize = undefined,
    pitch: usize = undefined,
    xres: usize = undefined,
    yres: usize = undefined,
    bpp: u32 = undefined,
    range: Region = Region{ .name = "Frame Buffer" },

    pub fn drawPixel(self: *FrameBuffer, x: usize, y: usize, color: u8) void {
        if (x < 0) return;
        if (x >= self.xres) return;
        if (y < 0) return;
        if (y >= self.yres) return;

        var idx: usize = x + (y * self.pitch);

        assert(idx < self.buffer_size);

        self.base[x + (y * self.pitch)] = color;
    }

    // These are palette indices
    pub const COLOR_FOREGROUND: u8 = 0x02;
    pub const COLOR_BACKGROUND: u8 = 0x00;

    pub fn clear(self: *FrameBuffer) void {
        self.fill(0, 0, self.xres, self.yres, COLOR_BACKGROUND) catch {};
    }

    pub fn clearRegion(self: *FrameBuffer, x: usize, y: usize, w: usize, h: usize) void {
        self.fill(x, y, x + w, y + h, COLOR_BACKGROUND) catch {};
    }

    // Font is fixed height of 16 bits, fixed width of 8 bits
    pub fn drawChar(self: *FrameBuffer, x: usize, y: usize, ch: u8) void {
        var romidx: usize = @as(usize, ch - 32) * 16;
        if (romidx + 16 >= character_rom.len)
            return;

        var line_stride = self.pitch;
        var fbidx = x + (y * line_stride);

        for (0..16) |_| {
            var charbits: u8 = character_rom[romidx];
            for (0..8) |_| {
                self.base[fbidx] = if ((charbits & 0x80) != 0) COLOR_FOREGROUND else COLOR_BACKGROUND;
                fbidx += 1;
                charbits <<= 1;
            }
            fbidx -= 8;
            fbidx += line_stride;
            romidx += 1;
        }
    }

    pub fn eraseChar(self: *FrameBuffer, x: usize, y: usize) void {
        var line_stride = self.pitch;
        var fbidx = x + (y * line_stride);

        for (0..16) |_| {
            for (0..8) |_| {
                self.base[fbidx] = COLOR_BACKGROUND;
                fbidx += 1;
            }
            fbidx -= 8;
            fbidx += line_stride;
        }
    }

    pub fn blit(fb: *FrameBuffer, src_x: usize, src_y: usize, src_w: usize, src_h: usize, dest_x: usize, dest_y: usize) void {
        if (fb.dma_channel) |ch| {
            // TODO: probably ought to clip some of these values to
            // make sure they're all inside the framebuffer!
            const fb_base: usize = @intFromPtr(fb.base);
            const fb_pitch = fb.pitch;
            const stride_2d = fb.xres - src_w;
            const xfer_y_len = src_h;
            const xfer_x_len = src_w;

            const len = if (stride_2d > 0) ((xfer_y_len << 16) + xfer_x_len) else (src_h * fb.xres);

            var req = DMARequest{
                .source = fb_base + (src_y * fb_pitch) + src_x,
                .destination = fb_base + (dest_y * fb_pitch) + dest_x,
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

            var req = try fb.dma.createRequest(fb.dma);
            defer fb.dma.destroyRequest(fb.dma, req);

            req.* = .{
                .source = @truncate(src),
                .source_increment = false,
                .destination = @truncate(dest),
                .destination_increment = true,
                .length = xfer_count,
                .stride = (dest_stride << 16) | src_stride,
            };
            fb.dma.initiate(fb.dma, ch, req) catch {};
            _ = fb.dma.awaitChannel(fb.dma, ch);
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
            const dx: i64 = @bitCast(@subWithOverflow(x_end, x_start)[0]);
            var dy: i64 = @bitCast(@subWithOverflow(y_end, y_start)[0]);

            if (abs(i64, dx) > abs(i64, dy)) {
                if (x_end < x_start) {
                    x_start = x1;
                    x_end = x0;
                    y_start = y1;
                    y_end = y0;
                }

                var step_add = true;
                const y_step = fb.pitch;
                if (dy < 0) {
                    step_add = false;
                    dy = -dy;
                }

                var delta: i64 = 2 * dy - dx;
                var err: i64 = 2 * dy;
                var err_decrement: i64 = 2 * (dy - dx);

                var x = x_start;
                var y = y_start;
                var pixel: [*]u8 = fb.base;
                //                const y_step = fb.pitch;
                const x_step = 1;
                pixel += y * fb.pitch + x;
                for (x_start..x_end) |_| {
                    pixel[0] = color;
                    pixel += x_step;
                    if (delta <= 0) {
                        delta += err;
                    } else {
                        delta += err_decrement;

                        // TODO Zig can add or subtract a usize to a pointer but
                        // cannot add an isize?
                        if (step_add) {
                            pixel += y_step;
                        } else {
                            pixel -= y_step;
                        }
                    }
                }
            } else {
                if (y_end < y_start) {
                    x_start = x1;
                    x_end = x0;
                    y_start = y1;
                    y_end = y0;
                }

                var step_add = true;
                const x_step = 1;

                if (dy < 0) {
                    step_add = false;
                    dy = -dy;
                }

                var delta: i64 = 2 * dx - dy;
                var err: i64 = 2 * dx;
                var err_decrement: i64 = 2 * (dx - dy);

                var x = x_start;
                var y = y_start;
                var pixel: [*]u8 = fb.base;
                const y_step = fb.pitch;

                pixel += y * y_step + x;
                for (y_start..y_end) |_| {
                    pixel[0] = color;
                    pixel += y_step;
                    if (delta <= 0) {
                        delta += err;
                    } else {
                        delta += err_decrement;

                        if (step_add) {
                            pixel += x_step;
                        } else {
                            pixel -= x_step;
                        }
                    }
                }
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
