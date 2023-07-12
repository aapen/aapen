const std = @import("std");
const assert = std.debug.assert;
const io = @import("io.zig");
const debug_writer = io.debug_writer;
const reg = @import("../mmio_register.zig");
const UniformRegister = reg.UniformRegister;
const peripheral_base = @import("peripheral.zig").peripheral_base;

// ----------------------------------------------------------------------
// Peripheral Registers
// ----------------------------------------------------------------------
pub const mailbox_base = peripheral_base + 0xB880;

const mailbox_read_layout = u32;
const mailbox_0_read = UniformRegister(mailbox_read_layout).init(mailbox_base + 0x00);

const mailbox_peek_layout = u32;
const mailbox_0_peek = UniformRegister(mailbox_peek_layout).init(mailbox_base + 0x10);

const mailbox_sender_layout = u32;
const mailbox_0_sender = UniformRegister(mailbox_sender_layout).init(mailbox_base + 0x14);

const mailbox_status_layout = packed struct {
    _unused_reserved: u30,
    mail_empty: u1,
    mail_full: u1,
};
pub const mailbox_0_status = UniformRegister(mailbox_status_layout).init(mailbox_base + 0x18);

const IrqEnableBit = enum(u1) {
    disabled = 0b0,
    enabled = 0b1,
};

const IrqPendingBit = enum(u1) {
    not_raised = 0b0,
    raised = 0b1,
};

const mailbox_configuration_layout = packed struct {
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
const mailbox_0_configuration = UniformRegister(mailbox_configuration_layout).init(mailbox_base + 0x1c);

const mailbox_write_layout = u32;
const mailbox_0_write = UniformRegister(mailbox_write_layout).init(mailbox_base + 0x20);

// const mailbox = packed struct {
//     read_write: mailbox_read_write_layout,
//     _unused_reserved_0: u32,
//     _unused_reserved_1: u32,
//     _unused_reserved_2: u32,
//     peek: mailbox_peek_layout,
//     sender: mailbox_sender_layout,
//     status: mailbox_status_layout,
//     configuration: mailbox_configuration_layout,
// };

// const mailbox_0: *volatile mailbox = @ptrFromInt(mailbox_base);
// const mailbox_1: *volatile mailbox = @ptrFromInt(mailbox_base + 0x20);

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

const RPI_FIRMWARE_STATUS_REQUEST: u32 = 0;
const RPI_FIRMWARE_STATUS_SUCCESS: u32 = 0x80000000;
const RPI_FIRMWARE_STATUS_ERROR: u32 = 0x80000001;

const rpi_firmware_property_tag = enum(u32) {
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
fn mail_full() bool {
    reg.memory_barrier();
    return mailbox_0_status.read().mail_full == 1;
}

pub fn mailbox_write(channel: MailboxChannel, data: u32) void {
    while (mail_full()) {}

    var val = (data & 0xfffffff0) | @intFromEnum(channel);
    mailbox_0_write.write(val);
}

fn mail_empty() bool {
    reg.memory_barrier();
    return mailbox_0_status.read().mail_empty == 1;
}

// TODO: Use peek instead of read so we don't lose messages meant for
// other channels.
// TODO: Use an interrupt to read this and put it into a data structure
pub fn mailbox_read(channel_expected: MailboxChannel) u32 {
    while (true) {
        while (mail_empty()) {}

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

    channel: MailboxChannel = .property_arm_to_vc,
    messages: []Message,
    buffer: [64]u32 align(16),
    total_size: u32,

    pub fn init(messages: []Message) Envelope {
        var content_size: u32 = 0;
        for (messages) |m| {
            content_size += m.total_size;
        }

        var total_size = content_size + 3;

        assert(total_size < 64);

        return .{
            .buffer = [_]u32{0} ** 64,
            .total_size = total_size,
            .messages = messages,
        };
    }

    pub fn call(self: *Envelope) !u32 {
        self.buffer[1] = RPI_FIRMWARE_STATUS_REQUEST;

        var idx: usize = 2;

        for (self.messages) |m| {
            m.fill(self.buffer[idx..]);
            idx += m.total_size;
        }

        self.buffer[idx] = @intFromEnum(rpi_firmware_property_tag.RPI_FIRMWARE_PROPERTY_END);

        self.buffer[0] = @intCast(idx * @sizeOf(u32));

        mailbox_write(self.channel, @as(u32, @truncate(@intFromPtr(&self.buffer))));
        var data = mailbox_read(self.channel);

        if (self.buffer[1] == RPI_FIRMWARE_STATUS_ERROR) {
            return Error.StatusError;
        }

        if (self.buffer[1] != RPI_FIRMWARE_STATUS_SUCCESS) {
            return Error.NoResponse;
        }

        idx = 2;

        for (self.messages) |m| {
            m.unfill(self.buffer[idx..]);
            idx += m.total_size;
        }
        return data;
    }
};

pub const Message = struct {
    ptr: *anyopaque,
    fillFn: *const fn (ptr: *anyopaque, buf: []u32) void,
    unfillFn: *const fn (ptr: *anyopaque, buf: []u32) void,
    tag: u32,
    request_size: u32,
    content_size: u32,
    total_size: u32,

    pub fn init(pointer: anytype, tag: rpi_firmware_property_tag, request_size: u32, response_size: u32, comptime fillFn: fn (ptr: @TypeOf(pointer), buf: []u32) void, comptime unfillFn: fn (ptr: @TypeOf(pointer), buf: []u32) void) Message {
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
        self.unfillFn(self.ptr, buf[3..]);
    }
};

// ----------------------------------------------------------------------
// Serializers for several message types
// ----------------------------------------------------------------------

pub const PowerDomain = enum(u32) {
    I2C0 = 0,
    I2C1 = 1,
    I2C2 = 2,
    VIDEO_SCALER = 3,
    VPU1 = 4,
    HDMI = 5,
    USB = 6,
    VEC = 7,
    JPEG = 8,
    H264 = 9,
    V3D = 10,
    ISP = 11,
    UNICAM0 = 12,
    UNICAM1 = 13,
    CCP2RX = 14,
    CSI2 = 15,
    CPI = 16,
    DSI0 = 17,
    DSI1 = 18,
    TRANSPOSER = 19,
    CCP2TX = 20,
    CDP = 21,
    ARM = 22,
};

const PowerMessage = struct {
    const Self = @This();
    domain: PowerDomain,
    state: u32 = 0,

    pub fn init(domain: PowerDomain) Self {
        return Self{
            .domain = domain,
        };
    }

    pub fn message(self: *Self) Message {
        return Message.init(self, .RPI_FIRMWARE_GET_DOMAIN_STATE, 1, 2, fill, unfill);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        buf[0] = @intFromEnum(self.domain);
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.domain = @enumFromInt(buf[0]);
        self.rate = buf[1];
    }
};

pub fn get_power_status(domain: PowerDomain) !struct { bool, u32 } {
    var powermsg = PowerMessage.init(domain);
    var messages = [_]Message{powermsg.message()};
    var env = Envelope.init(&messages);
    _ = try env.call();

    return .{ true, powermsg.state };
}

const ClockMessage = struct {
    const Self = @This();
    clock_type: ClockRate.Clock,
    rate: u32 = 0,

    pub fn init(clock_type: ClockRate.Clock) Self {
        return Self{
            .clock_type = clock_type,
        };
    }

    pub fn message(self: *Self) Message {
        return Message.init(self, .RPI_FIRMWARE_GET_CLOCK_RATE, 1, 2, fill, unfill);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        buf[0] = @intFromEnum(self.clock_type);
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.clock_type = @enumFromInt(buf[0]);
        self.rate = buf[1];
    }
};

pub const ClockRate = packed struct {
    pub const Clock = enum(u32) {
        emmc = 1,
        uart = 2,
        arm = 3,
        core = 4,
    };

    clock_type: Clock,
    rate: u32,
};

pub fn get_clock_rate(clock_type: ClockRate.Clock) !struct { bool, u32 } {
    var clockmsg = ClockMessage.init(clock_type);
    var messages = [_]Message{clockmsg.message()};
    var env = Envelope.init(&messages);

    _ = try env.call();

    return .{ true, clockmsg.rate };
}
