const bcm_mailbox = @import("bcm_mailbox.zig");
const BroadcomMailbox = bcm_mailbox.BroadcomMailbox;
const Message = BroadcomMailbox.Message;
const Envelope = BroadcomMailbox.Envelope;

const bcm_dma = @import("bcm_dma.zig");
const BroadcomDMAController = bcm_dma.BroadcomDMAController;

const frame_buffer = @import("../frame_buffer.zig");
const FrameBuffer = frame_buffer.FrameBuffer;

const memory = @import("../memory.zig");
const Regions = memory.Regions;
const Region = memory.Region;

pub const BroadcomVideoController = struct {
    mailbox: *const BroadcomMailbox = undefined,
    dma: *const BroadcomDMAController = undefined,

    pub fn allocFrameBuffer(self: *const BroadcomVideoController, fb: *FrameBuffer, xres: u32, yres: u32, depth: u32, default_palette: []const u32) void {
        var phys = SizeMessage.physical(xres, yres);
        var virt = SizeMessage.virtual(xres, yres);
        var bpp = DepthMessage.init(depth);
        var alloc = AllocateFrameBufferMessage.init();
        var pitch = GetPitchMessage.init();
        var palette = SetPaletteMessage.init(default_palette);
        var overscan = SetOverscanMessage.init();
        var messages = [_]Message{
            phys.message(),
            virt.message(),
            bpp.message(),
            overscan.message(),
            alloc.message(),
            pitch.message(),
            palette.message(),
        };
        var env = Envelope.init(self.mailbox, &messages);
        _ = env.call() catch 0;

        // TODO pass in translations from the BSP
        var base_in_arm_address_space = alloc.get_base_address() & 0x3fffffff;
        fb.base = @ptrFromInt(base_in_arm_address_space);
        fb.buffer_size = alloc.get_buffer_size();
        fb.pitch = pitch.get_pitch();
        fb.xres = xres;
        fb.yres = yres;
        fb.bpp = bpp.get_bpp();
        fb.range = Region.fromSize("Frame buffer", base_in_arm_address_space, alloc.get_buffer_size());
        fb.dma = self.dma;
        fb.dma_channel = self.dma.reserveChannel() catch null;
    }
};

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

    pub fn message(self: *Self) Message {
        var tag = switch (self.kind) {
            .virtual => BroadcomMailbox.RpiFirmwarePropertyTag.rpi_firmware_framebuffer_set_virtual_width_height,
            .physical => BroadcomMailbox.RpiFirmwarePropertyTag.rpi_firmware_framebuffer_set_physical_width_height,
        };

        return Message.init(self, tag, 2, 2);
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

    pub fn message(self: *Self) Message {
        return Message.init(self, .rpi_firmware_framebuffer_set_depth, 1, 1);
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

    pub fn message(self: *Self) Message {
        return Message.init(self, .rpi_firmware_framebuffer_allocate, 1, 2);
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

    pub fn message(self: *Self) Message {
        return Message.init(self, .rpi_firmware_framebuffer_get_pitch, 1, 1);
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

    pub fn message(self: *Self) Message {
        return Message.init(self, .rpi_firmware_framebuffer_set_palette, 34, 1);
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

    pub fn message(self: *Self) Message {
        return Message.init(self, .rpi_firmware_framebuffer_set_overscan, 4, 4);
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
