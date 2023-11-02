const std = @import("std");

const bcm_mailbox = @import("bcm_mailbox.zig");
const BroadcomMailbox = bcm_mailbox.BroadcomMailbox;
const PropertyTag = bcm_mailbox.PropertyTag;

const bcm_dma = @import("bcm_dma.zig");
const BroadcomDMAController = bcm_dma.BroadcomDMAController;

const frame_buffer = @import("../frame_buffer.zig");
const FrameBuffer = frame_buffer.FrameBuffer;

const memory = @import("../memory.zig");
const Region = memory.Region;

pub const BroadcomVideoController = struct {
    mailbox: *const BroadcomMailbox = undefined,
    dma: *const BroadcomDMAController = undefined,

    pub fn allocFrameBuffer(self: *const BroadcomVideoController, fb: *FrameBuffer, xres: u32, yres: u32, depth: u32, palette: []const u32) !void {
        var setup = PropertyVideoSetup.init(xres, yres, depth, palette);
        try self.mailbox.getTags(&setup, @sizeOf(PropertyVideoSetup) / 4);

        var base_in_arm_address_space = setup.allocate.base & 0x3fffffff;
        fb.base = @ptrFromInt(base_in_arm_address_space);
        fb.buffer_size = setup.allocate.buffer_size;
        fb.pitch = setup.pitch.pitch;
        fb.xres = xres;
        fb.yres = yres;
        fb.bpp = setup.depth.depth;
        fb.range = Region.fromSize("Frame buffer", base_in_arm_address_space, setup.allocate.buffer_size);
        fb.dma = self.dma;
        fb.dma_channel = self.dma.reserveChannel() catch null;
    }
};

const PropertySize = extern struct {
    tag: PropertyTag,
    xres: u32,
    yres: u32,

    pub fn initPhysical(xres: u32, yres: u32) @This() {
        return .{
            .tag = PropertyTag.init(.rpi_firmware_framebuffer_set_physical_width_height, 2, 2),
            .xres = xres,
            .yres = yres,
        };
    }

    pub fn initVirtual(xres: u32, yres: u32) @This() {
        return .{
            .tag = PropertyTag.init(.rpi_firmware_framebuffer_set_virtual_width_height, 2, 2),
            .xres = xres,
            .yres = yres,
        };
    }
};

const PropertyDepth = extern struct {
    tag: PropertyTag,
    depth: u32,

    pub fn init(depth: u32) @This() {
        return .{
            .tag = PropertyTag.init(.rpi_firmware_framebuffer_set_depth, 1, 1),
            .depth = depth,
        };
    }
};

const PropertyAllocateFrameBuffer = extern struct {
    tag: PropertyTag = PropertyTag.init(.rpi_firmware_framebuffer_allocate, 1, 2),
    base: u32 = 16,
    buffer_size: u32 = undefined,

    pub fn init() @This() {
        return .{};
    }
};

const PropertyPitch = extern struct {
    tag: PropertyTag = PropertyTag.init(.rpi_firmware_framebuffer_get_pitch, 1, 1),
    pitch: u32 = undefined,

    pub fn init() @This() {
        return .{};
    }
};

const PropertySetPalette = extern struct {
    tag: PropertyTag = PropertyTag.init(.rpi_firmware_framebuffer_set_palette, 34, 34),
    param1: extern union {
        offset: u32,
        valid: u32,
    },
    length: u32,
    entries: [32]u32,

    pub fn init(pal: []const u32) @This() {
        return .{
            .param1 = .{
                .offset = 0,
            },
            .length = 32,
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
};

const PropertyOverscan = extern struct {
    tag: PropertyTag = PropertyTag.init(.rpi_firmware_framebuffer_set_overscan, 4, 4),
    top: u32 = 0,
    bottom: u32 = 0,
    left: u32 = 0,
    right: u32 = 0,

    pub fn init() @This() {
        return .{};
    }
};

const PropertyVideoSetup = extern struct {
    physical: PropertySize,
    virtual: PropertySize,
    depth: PropertyDepth,
    overscan: PropertyOverscan,
    allocate: PropertyAllocateFrameBuffer,
    pitch: PropertyPitch,
    palette: PropertySetPalette,

    pub fn init(xres: u32, yres: u32, depth: u32, palette: []const u32) @This() {
        return .{
            .physical = PropertySize.initPhysical(xres, yres),
            .virtual = PropertySize.initVirtual(xres, yres),
            .depth = PropertyDepth.init(depth),
            .overscan = PropertyOverscan.init(),
            .allocate = PropertyAllocateFrameBuffer.init(),
            .pitch = PropertyPitch.init(),
            .palette = PropertySetPalette.init(palette),
        };
    }
};
