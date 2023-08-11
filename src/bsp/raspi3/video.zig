const std = @import("std");
const assert = std.debug.assert;
const mailbox = @import("mailbox.zig");
const Region = @import("../../mem.zig").Region;

const character_rom = @embedFile("../../data/character_rom.bin");

const SizeMessage = struct {
    const Kind = enum {
        virtual,
        physical,
    };

    const Self = @This();
    kind: Kind = undefined,
    xres: u32 = undefined,
    yres: u32 = undefined,

    pub fn physical(xres: u32, yres: u32) Self {
        return Self{
            .kind = .physical,
            .xres = xres,
            .yres = yres,
        };
    }

    pub fn virtual(xres: u32, yres: u32) Self {
        return Self{
            .kind = .virtual,
            .xres = xres,
            .yres = yres,
        };
    }

    pub fn message(self: *Self) mailbox.Message {
        var tag = switch (self.kind) {
            .virtual => mailbox.RpiFirmwarePropertyTag.RPI_FIRMWARE_FRAMEBUFFER_SET_VIRTUAL_WIDTH_HEIGHT,
            .physical => mailbox.RpiFirmwarePropertyTag.RPI_FIRMWARE_FRAMEBUFFER_SET_PHYSICAL_WIDTH_HEIGHT,
        };

        return mailbox.Message.init(self, tag, 2, 2);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        buf[0] = self.xres;
        buf[1] = self.yres;
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.xres = buf[0];
        self.yres = buf[0];
    }
};

const DepthMessage = struct {
    const Self = @This();
    depth: u32 = undefined,

    pub fn init(depth: u32) Self {
        return Self{
            .depth = depth,
        };
    }

    pub fn message(self: *Self) mailbox.Message {
        return mailbox.Message.init(self, .RPI_FIRMWARE_FRAMEBUFFER_SET_DEPTH, 1, 1);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        buf[0] = self.depth;
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.depth = buf[0];
    }

    pub fn get_bpp(self: *Self) u32 {
        return self.depth;
    }
};

const AllocateFrameBufferMessage = struct {
    const Self = @This();
    base: u32 = 16,
    buffer_size: u32 = undefined,

    pub fn init() Self {
        return Self{};
    }

    pub fn message(self: *Self) mailbox.Message {
        return mailbox.Message.init(self, .RPI_FIRMWARE_FRAMEBUFFER_ALLOCATE, 1, 2);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        buf[0] = self.base;
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.base = buf[0] & ~(@as(u32, 0xc0000000));
        self.buffer_size = buf[1];
    }

    pub fn get_base_address(self: *Self) usize {
        return @intCast(self.base);
    }

    pub fn get_buffer_size(self: *Self) usize {
        return @intCast(self.buffer_size);
    }
};

const GetPitchMessage = struct {
    const Self = @This();
    pitch: u32 = undefined,

    pub fn init() Self {
        return Self{};
    }

    pub fn message(self: *Self) mailbox.Message {
        return mailbox.Message.init(self, .RPI_FIRMWARE_FRAMEBUFFER_GET_PITCH, 1, 1);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        _ = self;
        buf[0] = 0;
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.pitch = buf[0];
    }

    pub fn get_pitch(self: *Self) usize {
        return @intCast(self.pitch);
    }
};

const SetPaletteMessage = struct {
    const Self = @This();
    offset: u32 = 0,
    length: u32 = 32,
    entries: [32]u32,
    valid: u32 = undefined,

    pub fn init(pal: []const u32) Self {
        return Self{
            .entries = init: {
                var v: [32]u32 = undefined;
                for (pal, 0..) |p, i| {
                    if (i >= 32)
                        break :init v;
                    v[i] = p;
                }
                break :init v;
            },
        };
    }

    pub fn message(self: *Self) mailbox.Message {
        return mailbox.Message.init(self, .RPI_FIRMWARE_FRAMEBUFFER_SET_PALETTE, 34, 1);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        buf[0] = self.offset;
        buf[1] = self.length;
        for (self.entries, 0..) |e, i| {
            buf[2 + i] = e;
        }
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.valid = buf[0];
    }
};

const SetOverscanMessage = struct {
    const Self = @This();

    left: u32 = 0,
    right: u32 = 0,
    top: u32 = 0,
    bottom: u32 = 0,

    pub fn init() Self {
        return Self{};
    }

    pub fn message(self: *Self) mailbox.Message {
        return mailbox.Message.init(self, .RPI_FIRMWARE_FRAMEBUFFER_SET_OVERSCAN, 4, 4);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        buf[0] = self.top;
        buf[1] = self.bottom;
        buf[2] = self.left;
        buf[3] = self.right;
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.top = buf[0];
        self.bottom = buf[1];
        self.left = buf[2];
        self.right = buf[3];
    }
};

const default_palette = [_]u32{
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
    base: [*]u8 = undefined,
    buffer_size: usize = undefined,
    pitch: usize = undefined,
    xres: usize = undefined,
    yres: usize = undefined,
    bpp: u32 = undefined,
    memory: Region = Region{ .name = "Frame Buffer" },

    pub fn setResolution(self: *FrameBuffer, xres: u32, yres: u32, bpp: u32) !void {
        var phys = SizeMessage.physical(xres, yres);
        var virt = SizeMessage.virtual(xres, yres);
        var depth = DepthMessage.init(bpp);
        var fb = AllocateFrameBufferMessage.init();
        var pitch = GetPitchMessage.init();
        var palette = SetPaletteMessage.init(&default_palette);
        var overscan = SetOverscanMessage.init();
        var messages = [_]mailbox.Message{
            phys.message(),
            virt.message(),
            depth.message(),
            overscan.message(),
            fb.message(),
            pitch.message(),
            palette.message(),
        };
        var env = mailbox.Envelope.init(&messages);
        _ = env.call() catch 0;

        var base_in_arm_address_space = fb.get_base_address() & 0x3fffffff;
        self.base = @ptrFromInt(base_in_arm_address_space);
        self.buffer_size = fb.get_buffer_size();
        self.pitch = pitch.get_pitch();
        self.xres = xres;
        self.yres = yres;
        self.bpp = depth.get_bpp();
        self.memory.fromSize(base_in_arm_address_space, fb.get_buffer_size());
    }

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
        for (0..self.buffer_size) |i| {
            self.base[i] = 0;
        }
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
};
