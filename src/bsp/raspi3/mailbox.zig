const std = @import("std");
const assert = std.debug.assert;
const cpu = @import("../../architecture.zig").cpu;
const reg = @import("../mmio_register.zig");
const UniformRegister = reg.UniformRegister;
const peripheral_base = @import("memory_map.zig").peripheral_base;
const memory = @import("memory.zig");

const clock = @import("mailbox/clock.zig");
pub const Clock = clock.Clock;
pub const getClockRate = clock.getClockRate;

const power = @import("mailbox/power.zig");
pub const PowerDevice = power.PowerDevice;
pub const isPowered = power.isPowered;
pub const powerOn = power.powerOn;

const board_info = @import("mailbox/board_info.zig");
pub const BoardInfo = board_info.BoardInfo;

// ----------------------------------------------------------------------
// Peripheral Registers
// ----------------------------------------------------------------------
pub const mailbox_base = peripheral_base + 0xB880;

const MailboxReadLayout = u32;
const mailbox_0_read = UniformRegister(MailboxReadLayout).init(mailbox_base + 0x00);

const MailboxPeekLayout = u32;
const mailbox_0_peek = UniformRegister(MailboxPeekLayout).init(mailbox_base + 0x10);

const MailboxSenderLayout = u32;
const mailbox_0_sender = UniformRegister(MailboxSenderLayout).init(mailbox_base + 0x14);

const MailboxStatusLayout = packed struct {
    _unused_reserved: u30,
    mail_empty: u1,
    mail_full: u1,
};
pub const mailbox_0_status = UniformRegister(MailboxStatusLayout).init(mailbox_base + 0x18);

const IrqEnableBit = enum(u1) {
    disabled = 0b0,
    enabled = 0b1,
};

const IrqPendingBit = enum(u1) {
    not_raised = 0b0,
    raised = 0b1,
};

const MailboxConfigurationLayout = packed struct {
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
const mailbox_0_configuration = UniformRegister(MailboxConfigurationLayout).init(mailbox_base + 0x1c);

const MailboxWriteLayout = u32;
const mailbox_0_write = UniformRegister(MailboxWriteLayout).init(mailbox_base + 0x20);

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

const rpi_firmware_status_request: u32 = 0;
const rpi_firmware_status_success: u32 = 0x80000000;
const rpi_firmware_status_error: u32 = 0x80000001;

pub const RpiFirmwarePropertyTag = enum(u32) {
    RPI_FIRMWARE_PROPERTY_END = 0x00000000,
    RPI_FIRMWARE_GET_FIRMWARE_REVISION = 0x00000001,

    RPI_FIRMWARE_SET_CURSOR_INFO = 0x00008010,
    RPI_FIRMWARE_SET_CURSOR_STATE = 0x00008011,

    RPI_FIRMWARE_GET_BOARD_MODEL = 0x00010001,
    RPI_FIRMWARE_GET_BOARD_REVISION = 0x00010002,
    RPI_FIRMWARE_GET_BOARD_MAC_ADDRESS = 0x00010003,
    RPI_FIRMWARE_GET_BOARD_SERIAL = 0x00010004,
    RPI_FIRMWARE_GET_ARM_MEMORY = 0x00010005,
    RPI_FIRMWARE_GET_VC_MEMORY = 0x00010006,
    RPI_FIRMWARE_GET_CLOCKS = 0x00010007,
    RPI_FIRMWARE_GET_POWER_STATE = 0x00020001,
    RPI_FIRMWARE_GET_TIMING = 0x00020002,
    RPI_FIRMWARE_SET_POWER_STATE = 0x00028001,
    RPI_FIRMWARE_GET_CLOCK_STATE = 0x00030001,
    RPI_FIRMWARE_GET_CLOCK_RATE = 0x00030002,
    RPI_FIRMWARE_GET_VOLTAGE = 0x00030003,
    RPI_FIRMWARE_GET_MAX_CLOCK_RATE = 0x00030004,
    RPI_FIRMWARE_GET_MAX_VOLTAGE = 0x00030005,
    RPI_FIRMWARE_GET_TEMPERATURE = 0x00030006,
    RPI_FIRMWARE_GET_MIN_CLOCK_RATE = 0x00030007,
    RPI_FIRMWARE_GET_MIN_VOLTAGE = 0x00030008,
    RPI_FIRMWARE_GET_TURBO = 0x00030009,
    RPI_FIRMWARE_GET_MAX_TEMPERATURE = 0x0003000a,
    RPI_FIRMWARE_GET_STC = 0x0003000b,
    RPI_FIRMWARE_ALLOCATE_MEMORY = 0x0003000c,
    RPI_FIRMWARE_LOCK_MEMORY = 0x0003000d,
    RPI_FIRMWARE_UNLOCK_MEMORY = 0x0003000e,
    RPI_FIRMWARE_RELEASE_MEMORY = 0x0003000f,
    RPI_FIRMWARE_EXECUTE_CODE = 0x00030010,
    RPI_FIRMWARE_EXECUTE_QPU = 0x00030011,
    RPI_FIRMWARE_SET_ENABLE_QPU = 0x00030012,
    RPI_FIRMWARE_GET_DISPMANX_RESOURCE_MEM_HANDLE = 0x00030014,
    RPI_FIRMWARE_GET_EDID_BLOCK = 0x00030020,
    RPI_FIRMWARE_GET_CUSTOMER_OTP = 0x00030021,
    RPI_FIRMWARE_GET_DOMAIN_STATE = 0x00030030,
    RPI_FIRMWARE_SET_CLOCK_STATE = 0x00038001,
    RPI_FIRMWARE_SET_CLOCK_RATE = 0x00038002,
    RPI_FIRMWARE_SET_VOLTAGE = 0x00038003,
    RPI_FIRMWARE_SET_TURBO = 0x00038009,
    RPI_FIRMWARE_SET_CUSTOMER_OTP = 0x00038021,
    RPI_FIRMWARE_SET_DOMAIN_STATE = 0x00038030,
    RPI_FIRMWARE_GET_GPIO_STATE = 0x00030041,
    RPI_FIRMWARE_SET_GPIO_STATE = 0x00038041,
    RPI_FIRMWARE_SET_SDHOST_CLOCK = 0x00038042,
    RPI_FIRMWARE_GET_GPIO_CONFIG = 0x00030043,
    RPI_FIRMWARE_SET_GPIO_CONFIG = 0x00038043,
    RPI_FIRMWARE_GET_PERIPH_REG = 0x00030045,
    RPI_FIRMWARE_SET_PERIPH_REG = 0x00038045,

    // Dispmanx TAGS
    RPI_FIRMWARE_FRAMEBUFFER_ALLOCATE = 0x00040001,
    RPI_FIRMWARE_FRAMEBUFFER_BLANK = 0x00040002,
    RPI_FIRMWARE_FRAMEBUFFER_GET_PHYSICAL_WIDTH_HEIGHT = 0x00040003,
    RPI_FIRMWARE_FRAMEBUFFER_GET_VIRTUAL_WIDTH_HEIGHT = 0x00040004,
    RPI_FIRMWARE_FRAMEBUFFER_GET_DEPTH = 0x00040005,
    RPI_FIRMWARE_FRAMEBUFFER_GET_PIXEL_ORDER = 0x00040006,
    RPI_FIRMWARE_FRAMEBUFFER_GET_ALPHA_MODE = 0x00040007,
    RPI_FIRMWARE_FRAMEBUFFER_GET_PITCH = 0x00040008,
    RPI_FIRMWARE_FRAMEBUFFER_GET_VIRTUAL_OFFSET = 0x00040009,
    RPI_FIRMWARE_FRAMEBUFFER_GET_OVERSCAN = 0x0004000a,
    RPI_FIRMWARE_FRAMEBUFFER_GET_PALETTE = 0x0004000b,
    RPI_FIRMWARE_FRAMEBUFFER_GET_TOUCHBUF = 0x0004000f,
    RPI_FIRMWARE_FRAMEBUFFER_GET_GPIOVIRTBUF = 0x00040010,
    RPI_FIRMWARE_FRAMEBUFFER_RELEASE = 0x00048001,
    RPI_FIRMWARE_FRAMEBUFFER_TEST_PHYSICAL_WIDTH_HEIGHT = 0x00044003,
    RPI_FIRMWARE_FRAMEBUFFER_TEST_VIRTUAL_WIDTH_HEIGHT = 0x00044004,
    RPI_FIRMWARE_FRAMEBUFFER_TEST_DEPTH = 0x00044005,
    RPI_FIRMWARE_FRAMEBUFFER_TEST_PIXEL_ORDER = 0x00044006,
    RPI_FIRMWARE_FRAMEBUFFER_TEST_ALPHA_MODE = 0x00044007,
    RPI_FIRMWARE_FRAMEBUFFER_TEST_VIRTUAL_OFFSET = 0x00044009,
    RPI_FIRMWARE_FRAMEBUFFER_TEST_OVERSCAN = 0x0004400a,
    RPI_FIRMWARE_FRAMEBUFFER_TEST_PALETTE = 0x0004400b,
    RPI_FIRMWARE_FRAMEBUFFER_TEST_VSYNC = 0x0004400e,
    RPI_FIRMWARE_FRAMEBUFFER_SET_PHYSICAL_WIDTH_HEIGHT = 0x00048003,
    RPI_FIRMWARE_FRAMEBUFFER_SET_VIRTUAL_WIDTH_HEIGHT = 0x00048004,
    RPI_FIRMWARE_FRAMEBUFFER_SET_DEPTH = 0x00048005,
    RPI_FIRMWARE_FRAMEBUFFER_SET_PIXEL_ORDER = 0x00048006,
    RPI_FIRMWARE_FRAMEBUFFER_SET_ALPHA_MODE = 0x00048007,
    RPI_FIRMWARE_FRAMEBUFFER_SET_VIRTUAL_OFFSET = 0x00048009,
    RPI_FIRMWARE_FRAMEBUFFER_SET_OVERSCAN = 0x0004800a,
    RPI_FIRMWARE_FRAMEBUFFER_SET_PALETTE = 0x0004800b,
    RPI_FIRMWARE_FRAMEBUFFER_SET_TOUCHBUF = 0x0004801f,
    RPI_FIRMWARE_FRAMEBUFFER_SET_GPIOVIRTBUF = 0x00048020,
    RPI_FIRMWARE_FRAMEBUFFER_SET_VSYNC = 0x0004800e,
    RPI_FIRMWARE_FRAMEBUFFER_SET_BACKLIGHT = 0x0004800f,

    RPI_FIRMWARE_VCHIQ_INIT = 0x00048010,

    RPI_FIRMWARE_GET_COMMAND_LINE = 0x00050001,
    RPI_FIRMWARE_GET_DMA_CHANNELS = 0x00060001,
};

// ----------------------------------------------------------------------
// Send and receive messages
// ----------------------------------------------------------------------
fn mailFull() bool {
    cpu.barrierMemoryDevice();
    return mailbox_0_status.read().mail_full == 1;
}

fn mailEmpty() bool {
    cpu.barrierMemoryDevice();
    return mailbox_0_status.read().mail_empty == 1;
}

pub fn mailboxWrite(channel: MailboxChannel, data: u32) void {
    while (mailFull()) {}

    var val = (data & 0xfffffff0) | @intFromEnum(channel);
    mailbox_0_write.write(val);
}

// TODO: Use peek instead of read so we don't lose messages meant for
// other channels.
// TODO: Use an interrupt to read this and put it into a data structure
pub fn mailboxRead(channel_expected: MailboxChannel) u32 {
    while (true) {
        while (mailEmpty()) {}

        var data: u32 = mailbox_0_read.read();
        var channel_read: MailboxChannel = @enumFromInt(data & 0xf);

        if (channel_read == channel_expected) {
            return data & 0xfffffff0;
        }
    }
}

// ----------------------------------------------------------------------
// Support for marshalling / unmarshalling
// ----------------------------------------------------------------------

pub const Envelope = struct {
    const Error = error{
        StatusError,
        NoResponse,
    };

    const max_buffer_length = 128;

    channel: MailboxChannel = .property_arm_to_vc,
    messages: []Message,
    buffer: [max_buffer_length]u32 align(16),
    total_size: u32,

    pub fn init(messages: []Message) Envelope {
        var content_size: u32 = 0;
        for (messages) |m| {
            content_size += m.total_size;
        }

        var total_size = content_size + 3;

        assert(total_size < max_buffer_length);

        return .{
            .buffer = [_]u32{0} ** max_buffer_length,
            .total_size = total_size,
            .messages = messages,
        };
    }

    pub fn call(self: *Envelope) !u32 {
        var idx: usize = 2;

        for (self.messages) |m| {
            m.fill(self.buffer[idx..]);
            idx += m.total_size;
        }

        self.buffer[idx] = @intFromEnum(RpiFirmwarePropertyTag.RPI_FIRMWARE_PROPERTY_END);

        self.buffer[0] = @intCast(idx * @sizeOf(u32));
        self.buffer[1] = rpi_firmware_status_request;

        cpu.memory.flushDCache(u32, &self.buffer);
        var bus_address = memory.physicalToBus(@intFromPtr(&self.buffer));
        mailboxWrite(self.channel, @truncate(bus_address));
        var data = mailboxRead(self.channel);

        cpu.memory.invalidateDCache(u32, &self.buffer);

        idx = 2;

        for (self.messages) |m| {
            m.unfill(self.buffer[idx..]);
            idx += m.total_size;
        }

        if (self.buffer[1] == rpi_firmware_status_error) {
            return Error.StatusError;
        }

        if (self.buffer[1] != rpi_firmware_status_success) {
            return Error.NoResponse;
        }

        return data;
    }
};

pub const Message = struct {
    // Should be set in the message response to indicate the word now
    // holds the length of the response body
    const message_value_length_response = @as(u32, 1) << 31;

    fillFn: *const fn (ptr: *anyopaque, buf: []u32) void,
    unfillFn: *const fn (ptr: *anyopaque, buf: []u32) void,

    ptr: *anyopaque,
    tag: u32,
    request_size: u32,
    content_size: u32,
    total_size: u32,

    pub fn init(pointer: anytype, tag: RpiFirmwarePropertyTag, request_size: u32, response_size: u32, comptime fillFn: fn (ptr: @TypeOf(pointer), buf: []u32) void, comptime unfillFn: fn (ptr: @TypeOf(pointer), buf: []u32) void) Message {
        const Ptr = @TypeOf(pointer);
        assert(@typeInfo(Ptr) == .Pointer); // Must be a pointer
        assert(@typeInfo(Ptr).Pointer.size == .One); // Must be a single-item pointer
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct); // Must point to a struct
        const gen = struct {
            fn fill(ptr: *anyopaque, buf: []u32) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                fillFn(self, buf);
            }
            fn unfill(ptr: *anyopaque, buf: []u32) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                unfillFn(self, buf);
            }
        };

        const content_size = @max(request_size, response_size);

        return .{
            .ptr = pointer,
            .fillFn = gen.fill,
            .unfillFn = gen.unfill,
            .tag = @intFromEnum(tag),
            .request_size = request_size,
            .content_size = content_size,
            .total_size = content_size + 3,
        };
    }

    pub fn fill(self: Message, buf: []u32) void {
        buf[0] = self.tag;
        buf[1] = self.content_size * @sizeOf(u32);
        buf[2] = self.request_size * @sizeOf(u32);
        self.fillFn(self.ptr, buf[3..]);
    }

    pub fn unfill(self: Message, buf: []u32) void {
        // TODO warn if the response length bit is not set
        buf[1] &= ~message_value_length_response;
        self.unfillFn(self.ptr, buf[3..]);
    }
};
