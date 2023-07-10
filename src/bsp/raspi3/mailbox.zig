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

    // var val = (@as(u28, @truncate(data)) << 4) | @intFromEnum(channel);
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
// Serializers for several message types
// ----------------------------------------------------------------------

// request_size and max_response_size are the number of u32 words needed
pub fn MailboxMessageType(comptime tag: rpi_firmware_property_tag, comptime request_size: u32, comptime max_response_size: u32) type {
    return struct {
        const Error = error{
            InsufficientBufferSpace,
            Overflow,
            Underflow,
        };
        const Self = @This();
        // the request and response share memory, so the content is
        // the larger of the two.
        const content_size: u32 = @max(request_size, max_response_size);
        // total size includes the content size plus 6 extra u32's for
        // the header and terminator
        const total_size: u32 = content_size + 6;

        buffer: [total_size]u32 = undefined,

        fn fill(self: *Self, request: []u32) !void {
            if (self.buffer.len < total_size) {
                return Error.InsufficientBufferSpace;
            }

            try debug_writer.print("request type {s}, content_size {}\r\n", .{ @tagName(tag), content_size });

            self.buffer[0] = self.buffer.len * @sizeOf(u32);
            self.buffer[1] = RPI_FIRMWARE_STATUS_REQUEST;
            self.buffer[2] = @intFromEnum(tag);
            self.buffer[3] = content_size * @sizeOf(u32);
            self.buffer[4] = request_size * @sizeOf(u32);
            for (request, 0..) |w, idx| {
                self.buffer[5 + idx] = w;
            }
            self.buffer[self.buffer.len - 1] = @intFromEnum(rpi_firmware_property_tag.RPI_FIRMWARE_PROPERTY_END);
        }

        fn has_response(self: *Self) bool {
            return (self.buffer[1] == RPI_FIRMWARE_STATUS_SUCCESS) or (self.buffer[1] == RPI_FIRMWARE_STATUS_ERROR);
        }

        fn is_successful(self: *Self) bool {
            return self.buffer[1] == RPI_FIRMWARE_STATUS_SUCCESS;
        }

        fn get_response_body(self: *Self) []u32 {
            return self.buffer[5..];
        }

        fn call(self: *Self, channel: MailboxChannel, request: []u32) !u32 {
            try self.fill(request);

            // TODO: do we need to translate this address?
            mailbox_write(channel, @as(u32, @truncate(@intFromPtr(&self.buffer))));
            // _ = debug_writer.print("mailbox_status: {any}\r\n", .{mailbox_0_status.read()}) catch 0;
            return mailbox_read(channel);
        }
    };
}

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

pub const MailboxPower = MailboxMessageType(.RPI_FIRMWARE_GET_DOMAIN_STATE, 1, 2);

pub const PowerStatus = packed struct {
    domain_id: u32,
    power_state: u32,
};

pub fn get_power_status(domain: PowerDomain) !struct { bool, PowerStatus } {
    var power_message = MailboxPower{};
    var request_body: [1]u32 = undefined;
    request_body[0] = @intFromEnum(domain);
    var ret = try power_message.call(.property_arm_to_vc, &request_body);
    _ = ret;
    // TODO: check if actual return value
    // TODO: check if error response
    var body = power_message.get_response_body();
    return .{ power_message.is_successful(), PowerStatus{
        .domain_id = body[0],
        .power_state = body[1],
    } };
}

pub const ClockType = enum(u32) {
    emmc = 1,
    uart = 2,
    arm = 3,
    core = 4,
};

pub const MailboxClock = MailboxMessageType(.RPI_FIRMWARE_GET_CLOCK_RATE, 1, 1);

pub const ClockRate = struct {
    clock_type: ClockType,
    rate: u32,
};

pub fn get_clock_rate(clock_type: ClockType) !struct { bool, ClockRate } {
    var clock_message = MailboxClock{};
    var request_body: [1]u32 = undefined;
    request_body[0] = @intFromEnum(clock_type);
    var ret = try clock_message.call(.property_arm_to_vc, &request_body);
    _ = ret;
    var body = clock_message.get_response_body();
    return .{ clock_message.is_successful(), ClockRate{
        .clock_type = @enumFromInt(body[0]),
        .rate = body[1],
    } };
}
