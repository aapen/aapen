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
};
