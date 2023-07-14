const mailbox = @import("mailbox.zig");
const io = @import("io.zig");
const debug_writer = io.debug_writer;

const SizeMessage = struct {
    const Kind = enum {
        Virtual,
        Physical,
    };

    const Self = @This();
    kind: Kind = undefined,
    xres: u32 = undefined,
    yres: u32 = undefined,

    pub fn physical(xres: u32, yres: u32) Self {
        return Self{
            .kind = .Physical,
            .xres = xres,
            .yres = yres,
        };
    }

    pub fn virtual(xres: u32, yres: u32) Self {
        return Self{
            .kind = .Virtual,
            .xres = xres,
            .yres = yres,
        };
    }

    pub fn message(self: *Self) mailbox.Message {
        var tag = switch (self.kind) {
            .Virtual => mailbox.rpi_firmware_property_tag.RPI_FIRMWARE_FRAMEBUFFER_SET_VIRTUAL_WIDTH_HEIGHT,
            .Physical => mailbox.rpi_firmware_property_tag.RPI_FIRMWARE_FRAMEBUFFER_SET_PHYSICAL_WIDTH_HEIGHT,
        };

        return mailbox.Message.init(self, tag, 2, 2, fill, unfill);
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
        return mailbox.Message.init(self, .RPI_FIRMWARE_FRAMEBUFFER_SET_DEPTH, 1, 1, fill, unfill);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        buf[0] = self.depth;
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.depth = buf[0];
    }
};

const AllocateFrameBufferMessage = struct {
    const Self = @This();
    base: u32 = 16,
    screen_size: u32 = undefined,

    pub fn init() Self {
        return Self{};
    }

    pub fn message(self: *Self) mailbox.Message {
        return mailbox.Message.init(self, .RPI_FIRMWARE_FRAMEBUFFER_ALLOCATE, 1, 2, fill, unfill);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        buf[0] = self.base;
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.base = buf[0];
        self.screen_size = buf[1];
    }

    pub fn get_base_address(self: *Self) [*]u8 {
        return @ptrFromInt(self.base);
    }

    pub fn get_screen_size(self: *Self) usize {
        return @intCast(self.screen_size);
    }
};

const GetPitchMessage = struct {
    const Self = @This();
    pitch: u32 = undefined,

    pub fn init() Self {
        return Self{};
    }

    pub fn message(self: *Self) mailbox.Message {
        return mailbox.Message.init(self, .RPI_FIRMWARE_FRAMEBUFFER_GET_PITCH, 1, 1, fill, unfill);
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

pub const FrameBuffer = struct {
    base: [*]u8 = undefined,
    pitch: usize = undefined,
    xres: usize = undefined,
    yres: usize = undefined,

    pub fn set_resolution(self: *FrameBuffer, xres: u32, yres: u32, bpp: u32) !void {
        var phys = SizeMessage.physical(xres, yres);
        var virt = SizeMessage.virtual(xres, yres);
        var depth = DepthMessage.init(bpp);
        var fb = AllocateFrameBufferMessage.init();
        var pitch = GetPitchMessage.init();
        var messages = [_]mailbox.Message{
            phys.message(),
            virt.message(),
            depth.message(),
            fb.message(),
            pitch.message(),
        };
        var env = mailbox.Envelope.init(&messages);
        _ = try env.call();

        self.base = @ptrFromInt(@intFromPtr(fb.get_base_address()) & 0x3fffffff);
        self.pitch = pitch.get_pitch();
        self.xres = xres;
        self.yres = yres;
    }

    pub fn draw_pixel(self: *FrameBuffer, x: usize, y: usize, color: u8) void {
        if (x < 0) return;
        if (x >= self.xres) return;
        if (y < 0) return;
        if (y >= self.yres) return;

        self.base[x + (y * self.pitch)] = color;
    }
};
