const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const root = @import("root");

const Forth = @import("../forty/forth.zig").Forth;

const architecture = @import("../architecture.zig");
const barriers = architecture.barriers;

const memory = @import("../memory.zig");
const AddressTranslations = memory.AddressTranslations;
const toChild = memory.toChild;

const synchronize = @import("../synchronize.zig");

extern fn spinDelay(delay: u32) void;

const Self = @This();

pub fn defineModule(forth: *Forth) !void {
    _ = forth;
}

pub const PropertyTag = extern struct {
    tag_id: u32,
    value_buffer_size: u32,
    value_length: u32,

    pub fn init(tag_type: u32, request_words: u29, buffer_words: u29) PropertyTag {
        const request_size_bytes: u32 = request_words * 4;
        const value_buffer_size_bytes: u32 = buffer_words * 4;
        return .{
            .tag_id = tag_type,
            .value_length = request_size_bytes,
            .value_buffer_size = value_buffer_size_bytes,
        };
    }

    pub fn asU32Slice(tag: anytype) []u32 {
        const TagPtr = @TypeOf(tag);
        assert(@typeInfo(TagPtr) == .Pointer);
        assert(@typeInfo(TagPtr).Pointer.size == .One);

        const Tag = @typeInfo(TagPtr).Pointer.child;
        const size = @sizeOf(Tag);

        if (size % 4 != 0) @compileError("tag structure size must be a multiple of 4 bytes, but it is " ++ size);

        const byte_ptr: [*]u8 = @ptrCast(@constCast(tag));
        const u32_ptr: [*]u32 = @ptrCast(@alignCast(byte_ptr));

        return u32_ptr[0 .. size / 4];
    }
};

const MailboxStatusRegister = packed struct {
    _unused_reserved: u30,
    mail_empty: u1,
    mail_full: u1,
};

pub const IRQ_DISABLE: u1 = 0;
pub const IRQ_ENABLE: u1 = 1;

pub const IRQ_IDLE: u1 = 0;
pub const IRQ_PENDING: u1 = 1;

const MailboxConfigurationRegister = packed struct {
    data_available_irq_enable: u1 = IRQ_DISABLE,
    space_available_irq_enable: u1 = IRQ_DISABLE,
    opp_empty_irq_enable: u1 = IRQ_DISABLE,
    mail_clear: u1 = 0,
    data_available_irq_pending: u1 = IRQ_IDLE,
    space_available_irq_pending: u1 = IRQ_IDLE,
    opp_empty_irq_pending: u1 = IRQ_IDLE,
    _unused_reserved_0: u1 = 0,
    error_non_owner_read: u1 = 0,
    error_overflow: u1 = 0,
    error_underflow: u1 = 0,
    _unused_reserved_1: u21 = 0,
};

const Registers = extern struct {
    mailbox_0_read: u32, // 0x00
    _reserved_0: u32, // 0x04
    _reserved_1: u32, // 0x08
    _reserved_2: u32, // 0x0c
    mailbox_0_peek: u32, // 0x10
    mailbox_0_sender: u32, // 0x14
    mailbox_0_status: MailboxStatusRegister, // 0x18
    mailbox_0_configuration: MailboxConfigurationRegister, // 0x1c
    mailbox_0_write: u32, // 0x20
};

allocator: Allocator,
registers: *volatile Registers,
translations: *const AddressTranslations,

// ----------------------------------------------------------------------
// Setup
// ----------------------------------------------------------------------
pub fn init(allocator: Allocator, register_base: u64, translations: *AddressTranslations) Self {
    return .{
        .allocator = allocator,
        .registers = @ptrFromInt(register_base),
        .translations = translations,
    };
}

// ----------------------------------------------------------------------
// Register-level interface
// ----------------------------------------------------------------------
inline fn mailFull(self: *Self) bool {
    return self.registers.mailbox_0_status.mail_full == 1;
}

inline fn mailEmpty(self: *Self) bool {
    return self.registers.mailbox_0_status.mail_empty == 1;
}

fn flush(self: *Self) void {
    while (!self.mailEmpty()) {
        _ = self.registers.mailbox_0_read;
        spinDelay(20);
    }
}

fn write(self: *Self, channel: u4, data: u32) void {
    while (self.mailFull()) {}

    const val = (data & 0xfffffff0) | channel;
    self.registers.mailbox_0_write = val;
}

// TODO: Use peek instead of read so we don't lose messages meant for
// other channels.
// TODO: Use an interrupt to read this and put it into a data structure
fn read(self: *Self, channel_expected: u4) u32 {
    while (true) {
        while (self.mailEmpty()) {}

        const data: u32 = self.registers.mailbox_0_read;
        const channel_read: u4 = @truncate(data & 0xf);

        if (channel_read == channel_expected) {
            return data & 0xfffffff0;
        }
    }
}

const MailboxError = error{
    UnexpectedResponse,
};

pub fn sendReceive(self: *Self, data_location: u32, channel: u4) !void {
    // discard any old pending messages
    self.flush();

    self.write(channel, data_location);

    const result = self.read(channel);

    if (result != data_location) {
        return MailboxError.UnexpectedResponse;
    }
}

// ----------------------------------------------------------------------
// ARM <-> Videocore protocol
// ----------------------------------------------------------------------

// Channel numbers
pub const CHANNEL_POWER: u4 = 0;
pub const CHANNEL_FRAMEBUFFER: u4 = 1;
pub const CHANNEL_VIRTUAL_UART: u4 = 2;
pub const CHANNEL_VCHIQ: u4 = 3;
pub const CHANNEL_LEDS: u4 = 4;
pub const CHANNEL_BUTTONS: u4 = 5;
pub const CHANNEL_TOUCH_SCREEN: u4 = 6;
pub const CHANNEL_PROPERTY_ARM_TO_VC: u4 = 8;
pub const CHANNEL_PROPERTY_VC_TO_ARM: u4 = 9;

// Tag numbers
pub const RPI_FIRMWARE_PROPERTY_END: u32 = 0x00000000;
pub const RPI_FIRMWARE_GET_FIRMWARE_REVISION: u32 = 0x00000001;

pub const RPI_FIRMWARE_SET_CURSOR_INFO: u32 = 0x00008010;
pub const RPI_FIRMWARE_SET_CURSOR_STATE: u32 = 0x00008011;

pub const RPI_FIRMWARE_GET_BOARD_MODEL: u32 = 0x00010001;
pub const RPI_FIRMWARE_GET_BOARD_REVISION: u32 = 0x00010002;
pub const RPI_FIRMWARE_GET_BOARD_MAC_ADDRESS: u32 = 0x00010003;
pub const RPI_FIRMWARE_GET_BOARD_SERIAL: u32 = 0x00010004;
pub const RPI_FIRMWARE_GET_ARM_MEMORY: u32 = 0x00010005;
pub const RPI_FIRMWARE_GET_VC_MEMORY: u32 = 0x00010006;
pub const RPI_FIRMWARE_GET_CLOCKS: u32 = 0x00010007;
pub const RPI_FIRMWARE_GET_POWER_STATE: u32 = 0x00020001;
pub const RPI_FIRMWARE_GET_TIMING: u32 = 0x00020002;
pub const RPI_FIRMWARE_SET_POWER_STATE: u32 = 0x00028001;
pub const RPI_FIRMWARE_GET_CLOCK_STATE: u32 = 0x00030001;
pub const RPI_FIRMWARE_GET_CLOCK_RATE: u32 = 0x00030002;
pub const RPI_FIRMWARE_GET_VOLTAGE: u32 = 0x00030003;
pub const RPI_FIRMWARE_GET_MAX_CLOCK_RATE: u32 = 0x00030004;
pub const RPI_FIRMWARE_GET_MAX_VOLTAGE: u32 = 0x00030005;
pub const RPI_FIRMWARE_GET_TEMPERATURE: u32 = 0x00030006;
pub const RPI_FIRMWARE_GET_MIN_CLOCK_RATE: u32 = 0x00030007;
pub const RPI_FIRMWARE_GET_MIN_VOLTAGE: u32 = 0x00030008;
pub const RPI_FIRMWARE_GET_TURBO: u32 = 0x00030009;
pub const RPI_FIRMWARE_GET_MAX_TEMPERATURE: u32 = 0x0003000a;
pub const RPI_FIRMWARE_GET_STC: u32 = 0x0003000b;
pub const RPI_FIRMWARE_ALLOCATE_MEMORY: u32 = 0x0003000c;
pub const RPI_FIRMWARE_LOCK_MEMORY: u32 = 0x0003000d;
pub const RPI_FIRMWARE_UNLOCK_MEMORY: u32 = 0x0003000e;
pub const RPI_FIRMWARE_RELEASE_MEMORY: u32 = 0x0003000f;
pub const RPI_FIRMWARE_EXECUTE_CODE: u32 = 0x00030010;
pub const RPI_FIRMWARE_EXECUTE_QPU: u32 = 0x00030011;
pub const RPI_FIRMWARE_SET_ENABLE_QPU: u32 = 0x00030012;
pub const RPI_FIRMWARE_GET_DISPMANX_RESOURCE_MEM_HANDLE: u32 = 0x00030014;
pub const RPI_FIRMWARE_GET_EDID_BLOCK: u32 = 0x00030020;
pub const RPI_FIRMWARE_GET_CUSTOMER_OTP: u32 = 0x00030021;
pub const RPI_FIRMWARE_GET_DOMAIN_STATE: u32 = 0x00030030;
pub const RPI_FIRMWARE_SET_CLOCK_STATE: u32 = 0x00038001;
pub const RPI_FIRMWARE_SET_CLOCK_RATE: u32 = 0x00038002;
pub const RPI_FIRMWARE_SET_VOLTAGE: u32 = 0x00038003;
pub const RPI_FIRMWARE_SET_TURBO: u32 = 0x00038009;
pub const RPI_FIRMWARE_SET_CUSTOMER_OTP: u32 = 0x00038021;
pub const RPI_FIRMWARE_SET_DOMAIN_STATE: u32 = 0x00038030;
pub const RPI_FIRMWARE_GET_GPIO_STATE: u32 = 0x00030041;
pub const RPI_FIRMWARE_SET_GPIO_STATE: u32 = 0x00038041;
pub const RPI_FIRMWARE_SET_SDHOST_CLOCK: u32 = 0x00038042;
pub const RPI_FIRMWARE_GET_GPIO_CONFIG: u32 = 0x00030043;
pub const RPI_FIRMWARE_SET_GPIO_CONFIG: u32 = 0x00038043;
pub const RPI_FIRMWARE_GET_PERIPH_REG: u32 = 0x00030045;
pub const RPI_FIRMWARE_SET_PERIPH_REG: u32 = 0x00038045;

// Dispmanx TAGS
pub const RPI_FIRMWARE_FRAMEBUFFER_ALLOCATE: u32 = 0x00040001;
pub const RPI_FIRMWARE_FRAMEBUFFER_BLANK: u32 = 0x00040002;
pub const RPI_FIRMWARE_FRAMEBUFFER_GET_PHYSICAL_WIDTH_HEIGHT: u32 = 0x00040003;
pub const RPI_FIRMWARE_FRAMEBUFFER_GET_VIRTUAL_WIDTH_HEIGHT: u32 = 0x00040004;
pub const RPI_FIRMWARE_FRAMEBUFFER_GET_DEPTH: u32 = 0x00040005;
pub const RPI_FIRMWARE_FRAMEBUFFER_GET_PIXEL_ORDER: u32 = 0x00040006;
pub const RPI_FIRMWARE_FRAMEBUFFER_GET_ALPHA_MODE: u32 = 0x00040007;
pub const RPI_FIRMWARE_FRAMEBUFFER_GET_PITCH: u32 = 0x00040008;
pub const RPI_FIRMWARE_FRAMEBUFFER_GET_VIRTUAL_OFFSET: u32 = 0x00040009;
pub const RPI_FIRMWARE_FRAMEBUFFER_GET_OVERSCAN: u32 = 0x0004000a;
pub const RPI_FIRMWARE_FRAMEBUFFER_GET_PALETTE: u32 = 0x0004000b;
pub const RPI_FIRMWARE_FRAMEBUFFER_GET_TOUCHBUF: u32 = 0x0004000f;
pub const RPI_FIRMWARE_FRAMEBUFFER_GET_GPIOVIRTBUF: u32 = 0x00040010;
pub const RPI_FIRMWARE_FRAMEBUFFER_RELEASE: u32 = 0x00048001;
pub const RPI_FIRMWARE_FRAMEBUFFER_TEST_PHYSICAL_WIDTH_HEIGHT: u32 = 0x00044003;
pub const RPI_FIRMWARE_FRAMEBUFFER_TEST_VIRTUAL_WIDTH_HEIGHT: u32 = 0x00044004;
pub const RPI_FIRMWARE_FRAMEBUFFER_TEST_DEPTH: u32 = 0x00044005;
pub const RPI_FIRMWARE_FRAMEBUFFER_TEST_PIXEL_ORDER: u32 = 0x00044006;
pub const RPI_FIRMWARE_FRAMEBUFFER_TEST_ALPHA_MODE: u32 = 0x00044007;
pub const RPI_FIRMWARE_FRAMEBUFFER_TEST_VIRTUAL_OFFSET: u32 = 0x00044009;
pub const RPI_FIRMWARE_FRAMEBUFFER_TEST_OVERSCAN: u32 = 0x0004400a;
pub const RPI_FIRMWARE_FRAMEBUFFER_TEST_PALETTE: u32 = 0x0004400b;
pub const RPI_FIRMWARE_FRAMEBUFFER_TEST_VSYNC: u32 = 0x0004400e;
pub const RPI_FIRMWARE_FRAMEBUFFER_SET_PHYSICAL_WIDTH_HEIGHT: u32 = 0x00048003;
pub const RPI_FIRMWARE_FRAMEBUFFER_SET_VIRTUAL_WIDTH_HEIGHT: u32 = 0x00048004;
pub const RPI_FIRMWARE_FRAMEBUFFER_SET_DEPTH: u32 = 0x00048005;
pub const RPI_FIRMWARE_FRAMEBUFFER_SET_PIXEL_ORDER: u32 = 0x00048006;
pub const RPI_FIRMWARE_FRAMEBUFFER_SET_ALPHA_MODE: u32 = 0x00048007;
pub const RPI_FIRMWARE_FRAMEBUFFER_SET_VIRTUAL_OFFSET: u32 = 0x00048009;
pub const RPI_FIRMWARE_FRAMEBUFFER_SET_OVERSCAN: u32 = 0x0004800a;
pub const RPI_FIRMWARE_FRAMEBUFFER_SET_PALETTE: u32 = 0x0004800b;
pub const RPI_FIRMWARE_FRAMEBUFFER_SET_TOUCHBUF: u32 = 0x0004801f;
pub const RPI_FIRMWARE_FRAMEBUFFER_SET_GPIOVIRTBUF: u32 = 0x00048020;
pub const RPI_FIRMWARE_FRAMEBUFFER_SET_VSYNC: u32 = 0x0004800e;
pub const RPI_FIRMWARE_FRAMEBUFFER_SET_BACKLIGHT: u32 = 0x0004800f;

pub const RPI_FIRMWARE_VCHIQ_INIT: u32 = 0x00048010;

pub const RPI_FIRMWARE_GET_COMMAND_LINE: u32 = 0x00050001;
pub const RPI_FIRMWARE_GET_DMA_CHANNELS: u32 = 0x00060001;

// ----------------------------------------------------------------------
// High level "tags" interface
// ----------------------------------------------------------------------

const TagError = error{
    StatusError,
    NoResponse,
    Unsuccessful,
};

const CODE_REQUEST = 0x0;
const CODE_RESPONSE_SUCCESS = 0x80000000;

const VALUE_LENGTH_RESPONSE: u32 = 0x80000000;
const PROPERTY_TAG_REQUIRED_ALIGNMENT = 16;

pub fn getTag(self: *Self, tag: anytype) !void {
    const TagPtr = @TypeOf(tag);
    assert(@typeInfo(TagPtr) == .Pointer);
    assert(@typeInfo(TagPtr).Pointer.size == .One);

    const Tag = @typeInfo(TagPtr).Pointer.child;
    if (!@hasField(Tag, "tag")) @compileError("tag field missing, expected: tag: PropertyTag");
    if (@TypeOf(tag.tag) != PropertyTag) @compileError("tag expected type PropertyTag, found: " ++ @typeName(@TypeOf(tag.tag)));

    const u32slice = PropertyTag.asU32Slice(tag);
    try self.getTags(u32slice);

    // a valid response should have the high bit set on the "value
    // length" field.
    if (u32slice[2] & VALUE_LENGTH_RESPONSE == 0) {
        return TagError.NoResponse;
    }
}

pub fn getTags(self: *Self, buffer: []u32) !void {
    const data_words: u32 = @truncate(buffer.len);
    const payload_size: u32 = (data_words + 3) * @as(u32, 4);
    const message: []u32 = try self.allocator.alignedAlloc(u32, PROPERTY_TAG_REQUIRED_ALIGNMENT, data_words + 3);
    defer self.allocator.free(message);

    message[0] = payload_size;
    message[1] = CODE_REQUEST;
    @memcpy(message[2..(2 + data_words)], buffer);
    message[data_words + 2] = 0;

    barriers.barrierMemoryWrite();
    synchronize.dataCacheRangeClean(@intFromPtr(message.ptr), payload_size);

    const buffer_address_mailbox: u32 = @truncate(@intFromPtr(message.ptr));
    try self.sendReceive(buffer_address_mailbox, CHANNEL_PROPERTY_ARM_TO_VC);

    // Make sure changes from the GPU are visible to us
    synchronize.dataCacheRangeInvalidate(@intFromPtr(message.ptr), payload_size);
    barriers.barrierMemory();

    if (message[1] == CODE_RESPONSE_SUCCESS) {
        @memcpy(buffer, message[2 .. message.len - 1]);
    }
}
