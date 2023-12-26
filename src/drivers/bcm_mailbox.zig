const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const root = @import("root");

const architecture = @import("../architecture.zig");
const barriers = architecture.barriers;

const memory = @import("../memory.zig");
const AddressTranslations = memory.AddressTranslations;
const toChild = memory.toChild;

const synchronize = @import("../synchronize.zig");

extern fn spinDelay(delay: u32) void;

const Self = @This();

pub const PropertyTag = extern struct {
    tag_id: u32,
    value_buffer_size: u32,
    value_length: u32,

    pub fn init(tag_type: RpiFirmwarePropertyTag, request_words: u29, buffer_words: u29) PropertyTag {
        const request_size_bytes: u32 = request_words * 4;
        const value_buffer_size_bytes: u32 = buffer_words * 4;
        return .{
            .tag_id = @intFromEnum(tag_type),
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

const IrqEnableBit = enum(u1) {
    disabled = 0b0,
    enabled = 0b1,
};

const IrqPendingBit = enum(u1) {
    not_raised = 0b0,
    raised = 0b1,
};

const MailboxConfigurationRegister = packed struct {
    data_available_irq_enable: IrqEnableBit = .disabled,
    space_available_irq_enable: IrqEnableBit = .disabled,
    opp_empty_irq_enable: IrqEnableBit = .disabled,
    mail_clear: u1 = 0,
    data_available_irq_pending: IrqPendingBit = .not_raised,
    space_available_irq_pending: IrqPendingBit = .not_raised,
    opp_empty_irq_pending: IrqPendingBit = .not_raised,
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

fn write(self: *Self, channel: MailboxChannel, data: u32) void {
    while (self.mailFull()) {}

    const val = (data & 0xfffffff0) | @intFromEnum(channel);
    self.registers.mailbox_0_write = val;
}

// TODO: Use peek instead of read so we don't lose messages meant for
// other channels.
// TODO: Use an interrupt to read this and put it into a data structure
fn read(self: *Self, channel_expected: MailboxChannel) u32 {
    while (true) {
        while (self.mailEmpty()) {}

        const data: u32 = self.registers.mailbox_0_read;
        const channel_read: MailboxChannel = @enumFromInt(data & 0xf);

        if (channel_read == channel_expected) {
            return data & 0xfffffff0;
        }
    }
}

const MailboxError = error{
    UnexpectedResponse,
};

pub fn sendReceive(self: *Self, data_location: u32, channel: MailboxChannel) !void {
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

const MailboxChannel = enum(u4) {
    power = 0,
    framebuffer = 1,
    virtual_uart = 2,
    vchiq = 3,
    leds = 4,
    buttons = 5,
    touch_screen = 6,
    property_arm_to_vc = 8,
    property_vc_to_arm = 9,
};

pub const RpiFirmwarePropertyTag = enum(u32) {
    rpi_firmware_property_end = 0x00000000,
    rpi_firmware_get_firmware_revision = 0x00000001,

    rpi_firmware_set_cursor_info = 0x00008010,
    rpi_firmware_set_cursor_state = 0x00008011,

    rpi_firmware_get_board_model = 0x00010001,
    rpi_firmware_get_board_revision = 0x00010002,
    rpi_firmware_get_board_mac_address = 0x00010003,
    rpi_firmware_get_board_serial = 0x00010004,
    rpi_firmware_get_arm_memory = 0x00010005,
    rpi_firmware_get_vc_memory = 0x00010006,
    rpi_firmware_get_clocks = 0x00010007,
    rpi_firmware_get_power_state = 0x00020001,
    rpi_firmware_get_timing = 0x00020002,
    rpi_firmware_set_power_state = 0x00028001,
    rpi_firmware_get_clock_state = 0x00030001,
    rpi_firmware_get_clock_rate = 0x00030002,
    rpi_firmware_get_voltage = 0x00030003,
    rpi_firmware_get_max_clock_rate = 0x00030004,
    rpi_firmware_get_max_voltage = 0x00030005,
    rpi_firmware_get_temperature = 0x00030006,
    rpi_firmware_get_min_clock_rate = 0x00030007,
    rpi_firmware_get_min_voltage = 0x00030008,
    rpi_firmware_get_turbo = 0x00030009,
    rpi_firmware_get_max_temperature = 0x0003000a,
    rpi_firmware_get_stc = 0x0003000b,
    rpi_firmware_allocate_memory = 0x0003000c,
    rpi_firmware_lock_memory = 0x0003000d,
    rpi_firmware_unlock_memory = 0x0003000e,
    rpi_firmware_release_memory = 0x0003000f,
    rpi_firmware_execute_code = 0x00030010,
    rpi_firmware_execute_qpu = 0x00030011,
    rpi_firmware_set_enable_qpu = 0x00030012,
    rpi_firmware_get_dispmanx_resource_mem_handle = 0x00030014,
    rpi_firmware_get_edid_block = 0x00030020,
    rpi_firmware_get_customer_otp = 0x00030021,
    rpi_firmware_get_domain_state = 0x00030030,
    rpi_firmware_set_clock_state = 0x00038001,
    rpi_firmware_set_clock_rate = 0x00038002,
    rpi_firmware_set_voltage = 0x00038003,
    rpi_firmware_set_turbo = 0x00038009,
    rpi_firmware_set_customer_otp = 0x00038021,
    rpi_firmware_set_domain_state = 0x00038030,
    rpi_firmware_get_gpio_state = 0x00030041,
    rpi_firmware_set_gpio_state = 0x00038041,
    rpi_firmware_set_sdhost_clock = 0x00038042,
    rpi_firmware_get_gpio_config = 0x00030043,
    rpi_firmware_set_gpio_config = 0x00038043,
    rpi_firmware_get_periph_reg = 0x00030045,
    rpi_firmware_set_periph_reg = 0x00038045,

    // Dispmanx TAGS
    rpi_firmware_framebuffer_allocate = 0x00040001,
    rpi_firmware_framebuffer_blank = 0x00040002,
    rpi_firmware_framebuffer_get_physical_width_height = 0x00040003,
    rpi_firmware_framebuffer_get_virtual_width_height = 0x00040004,
    rpi_firmware_framebuffer_get_depth = 0x00040005,
    rpi_firmware_framebuffer_get_pixel_order = 0x00040006,
    rpi_firmware_framebuffer_get_alpha_mode = 0x00040007,
    rpi_firmware_framebuffer_get_pitch = 0x00040008,
    rpi_firmware_framebuffer_get_virtual_offset = 0x00040009,
    rpi_firmware_framebuffer_get_overscan = 0x0004000a,
    rpi_firmware_framebuffer_get_palette = 0x0004000b,
    rpi_firmware_framebuffer_get_touchbuf = 0x0004000f,
    rpi_firmware_framebuffer_get_gpiovirtbuf = 0x00040010,
    rpi_firmware_framebuffer_release = 0x00048001,
    rpi_firmware_framebuffer_test_physical_width_height = 0x00044003,
    rpi_firmware_framebuffer_test_virtual_width_height = 0x00044004,
    rpi_firmware_framebuffer_test_depth = 0x00044005,
    rpi_firmware_framebuffer_test_pixel_order = 0x00044006,
    rpi_firmware_framebuffer_test_alpha_mode = 0x00044007,
    rpi_firmware_framebuffer_test_virtual_offset = 0x00044009,
    rpi_firmware_framebuffer_test_overscan = 0x0004400a,
    rpi_firmware_framebuffer_test_palette = 0x0004400b,
    rpi_firmware_framebuffer_test_vsync = 0x0004400e,
    rpi_firmware_framebuffer_set_physical_width_height = 0x00048003,
    rpi_firmware_framebuffer_set_virtual_width_height = 0x00048004,
    rpi_firmware_framebuffer_set_depth = 0x00048005,
    rpi_firmware_framebuffer_set_pixel_order = 0x00048006,
    rpi_firmware_framebuffer_set_alpha_mode = 0x00048007,
    rpi_firmware_framebuffer_set_virtual_offset = 0x00048009,
    rpi_firmware_framebuffer_set_overscan = 0x0004800a,
    rpi_firmware_framebuffer_set_palette = 0x0004800b,
    rpi_firmware_framebuffer_set_touchbuf = 0x0004801f,
    rpi_firmware_framebuffer_set_gpiovirtbuf = 0x00048020,
    rpi_firmware_framebuffer_set_vsync = 0x0004800e,
    rpi_firmware_framebuffer_set_backlight = 0x0004800f,

    rpi_firmware_vchiq_init = 0x00048010,

    rpi_firmware_get_command_line = 0x00050001,
    rpi_firmware_get_dma_channels = 0x00060001,
};

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

const VALUE_LENGTH_RESPONSE: u32 = 1 << 31;
const PROPERTY_TAG_REQUIRED_ALIGNMENT = 16;

pub fn getTag(self: *Self, tag: anytype) !void {
    const TagPtr = @TypeOf(tag);
    assert(@typeInfo(TagPtr) == .Pointer);
    assert(@typeInfo(TagPtr).Pointer.size == .One);

    const Tag = @typeInfo(TagPtr).Pointer.child;
    if (!@hasField(Tag, "tag")) @compileError("tag field missing, expected: tag: PropertyTag");
    if (@TypeOf(tag.tag) != PropertyTag) @compileError("tag expected type PropertyTag, found: " ++ @typeName(@TypeOf(tag.tag)));

    var u32slice = PropertyTag.asU32Slice(tag);
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
    try self.sendReceive(buffer_address_mailbox, MailboxChannel.property_arm_to_vc);

    // Make sure changes from the GPU are visible to us
    synchronize.dataCacheRangeInvalidate(@intFromPtr(message.ptr), payload_size);
    barriers.barrierMemory();

    if (message[1] == CODE_RESPONSE_SUCCESS) {
        @memcpy(buffer, message[2 .. message.len - 1]);
    }
}
