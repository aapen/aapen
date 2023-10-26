const std = @import("std");
const assert = std.debug.assert;

const root = @import("root");
const kinfo = root.kinfo;

const hal2 = @import("../hal2.zig");
const hal = @import("../hal.zig");

const local_interrupt_controller = @import("arm_local_interrupt_controller.zig");

const architecture = @import("../architecture.zig");
const cache = architecture.cache;
const barriers = architecture.barriers;

const memory = @import("../memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;
const toChild = memory.toChild;
const toParent = memory.toParent;

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

pub const BroadcomMailbox = struct {
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

    registers: *volatile Registers = undefined,
    intc: *hal.interfaces.InterruptController = undefined,
    intc2: *const local_interrupt_controller.LocalInterruptController = undefined,
    translations: *const AddressTranslations = undefined,

    pub fn init(self: *BroadcomMailbox, base: u64, interrupt_controller: *hal.interfaces.InterruptController, translations: *AddressTranslations) void {
        self.registers = @ptrFromInt(base);
        self.intc = interrupt_controller;
        self.translations = translations;
    }

    // ----------------------------------------------------------------------
    // Send and receive messages
    // ----------------------------------------------------------------------
    fn mailFull(self: *const BroadcomMailbox) bool {
        barriers.barrierMemoryDevice();
        return self.registers.mailbox_0_status.mail_full == 1;
    }

    fn mailEmpty(self: *const BroadcomMailbox) bool {
        barriers.barrierMemoryDevice();
        return self.registers.mailbox_0_status.mail_empty == 1;
    }

    pub fn mailboxWrite(self: *const BroadcomMailbox, channel: MailboxChannel, data: u32) void {
        while (self.mailFull()) {}

        var val = (data & 0xfffffff0) | @intFromEnum(channel);
        self.registers.mailbox_0_write = val;
    }

    // TODO: Use peek instead of read so we don't lose messages meant for
    // other channels.
    // TODO: Use an interrupt to read this and put it into a data structure
    pub fn mailboxRead(self: *const BroadcomMailbox, channel_expected: MailboxChannel) u32 {
        while (true) {
            while (self.mailEmpty()) {}

            var data: u32 = self.registers.mailbox_0_read;
            var channel_read: MailboxChannel = @enumFromInt(data & 0xf);

            if (channel_read == channel_expected) {
                return data & 0xfffffff0;
            }
        }
    }

    // ----------------------------------------------------------------------
    // Peripheral Registers
    // ----------------------------------------------------------------------
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
    // Support for marshalling / unmarshalling
    // ----------------------------------------------------------------------

    pub const Envelope = struct {
        const Error = error{
            StatusError,
            NoResponse,
        };

        const max_buffer_length = 128;

        owner: *const BroadcomMailbox = undefined,
        channel: MailboxChannel = .property_arm_to_vc,
        messages: []Message,
        buffer: [max_buffer_length]u32 align(16),
        total_size: u32,

        pub fn init(owner: *const BroadcomMailbox, messages: []Message) Envelope {
            var content_size: u32 = 0;
            for (messages) |m| {
                content_size += m.total_size;
            }

            var total_size = content_size + 3;

            assert(total_size < max_buffer_length);

            return .{
                .owner = owner,
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

            self.buffer[idx] = @intFromEnum(RpiFirmwarePropertyTag.rpi_firmware_property_end);

            self.buffer[0] = @intCast(idx * @sizeOf(u32));
            self.buffer[1] = rpi_firmware_status_request;

            cache.flushDCache(u32, &self.buffer);

            var cpu_address = @intFromPtr(&self.buffer);
            var bus_address = toChild(self.owner.translations, cpu_address);

            self.owner.mailboxWrite(self.channel, @truncate(bus_address));
            _ = self.owner.mailboxRead(self.channel);

            cache.invalidateDCache(u32, &self.buffer);

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

            // return data;
            return 0;
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

        pub fn init(pointer: anytype, tag: RpiFirmwarePropertyTag, request_size: u32, response_size: u32) Message {
            const Ptr = @TypeOf(pointer);
            const ptr_info = @typeInfo(Ptr);

            assert(@typeInfo(Ptr) == .Pointer);
            assert(@typeInfo(Ptr).Pointer.size == .One);
            assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

            const generic = struct {
                fn fill(ptr: *anyopaque, buf: []u32) void {
                    const self: Ptr = @ptrCast(@alignCast(ptr));
                    return @call(.always_inline, ptr_info.Pointer.child.fill, .{ self, buf });
                }

                fn unfill(ptr: *anyopaque, buf: []u32) void {
                    const self: Ptr = @ptrCast(@alignCast(ptr));
                    return @call(.always_inline, ptr_info.Pointer.child.unfill, .{ self, buf });
                }
            };

            const content_size = @max(request_size, response_size);

            return .{
                .ptr = pointer,
                .fillFn = generic.fill,
                .unfillFn = generic.unfill,
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
            if (buf[1] & message_value_length_response == 0) {
                root.kinfo(@src(), "expected bit 31 to be set, but it wasn't\n", .{});
            } else {
                buf[1] &= ~message_value_length_response;
            }
            self.unfillFn(self.ptr, buf[3..]);
        }
    };
};
