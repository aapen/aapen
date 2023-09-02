const std = @import("std");
const assert = std.debug.assert;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const bigToNative = std.mem.bigToNative;

const root = @import("root");
const kprint = root.kprint;
const kwarn = root.kwarn;
const kinfo = root.kinfo;

const register = @import("../bsp/mmio_register.zig");
const UniformRegister = register.UniformRegister;

const common = @import("common.zig");
const Driver = common.Driver;
const Device = common.Device;

const devicetree = @import("../devicetree.zig");
const Node = devicetree.Fdt.Node;
const Property = devicetree.Fdt.Property;

const architecture = @import("../../architecture.zig");
const cache = architecture.cache;
const barriers = architecture.barriers;

const memory = @import("../memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;
const toChild = memory.toChild;
const toParent = memory.toParent;

const MailboxPeekLayout = u32;

const MailboxReadLayout = u32;

const MailboxSenderLayout = u32;

const MailboxStatusLayout = packed struct {
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

const MailboxWriteLayout = u32;

const BroadcomMailbox = struct {
    mailbox_base: u64,
    mailbox_0_read: UniformRegister(MailboxReadLayout),
    mailbox_0_peek: UniformRegister(MailboxPeekLayout),
    mailbox_0_sender: UniformRegister(MailboxSenderLayout),
    mailbox_0_status: UniformRegister(MailboxStatusLayout),
    mailbox_0_configuration: UniformRegister(MailboxConfigurationLayout),
    mailbox_0_write: UniformRegister(MailboxWriteLayout),
    translations: *AddressTranslations,

    pub fn init(self: *BroadcomMailbox, register_base: u64, translations: *AddressTranslations) void {
        self.translations = translations;

        var register_cpu_addr = toChild(translations, register_base);
        kprint("Mailbox register base {x} -> {x}\n", .{ register_base, register_cpu_addr });

        self.mailbox_base = register_base + 0xB880;
        self.mailbox_0_read.init(register_base + 0x00);
        self.mailbox_0_peek.init(register_base + 0x10);
        self.mailbox_0_sender.init(register_base + 0x14);
        self.mailbox_0_status.init(register_base + 0x18);
        self.mailbox_0_configuration.init(register_base + 0x1c);
        self.mailbox_0_write.init(register_base + 0x20);
    }

    // ----------------------------------------------------------------------
    // Send and receive messages
    // ----------------------------------------------------------------------
    fn mailFull(self: *BroadcomMailbox) bool {
        barriers.barrierMemoryDevice();
        return self.mailbox_0_status.read().mail_full == 1;
    }

    fn mailEmpty(self: *BroadcomMailbox) bool {
        barriers.barrierMemoryDevice();
        return self.mailbox_0_status.read().mail_empty == 1;
    }

    pub fn mailboxWrite(self: *BroadcomMailbox, channel: MailboxChannel, data: u32) void {
        while (self.mailFull()) {}

        var val = (data & 0xfffffff0) | @intFromEnum(channel);
        self.mailbox_0_write.write(val);
    }

    // TODO: Use peek instead of read so we don't lose messages meant for
    // other channels.
    // TODO: Use an interrupt to read this and put it into a data structure
    pub fn mailboxRead(self: *BroadcomMailbox, channel_expected: MailboxChannel) u32 {
        while (true) {
            while (self.mailEmpty()) {}

            var data: u32 = self.mailbox_0_read.read();
            var channel_read: MailboxChannel = @enumFromInt(data & 0xf);

            if (channel_read == channel_expected) {
                return data & 0xfffffff0;
            }
        }
    }
};

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

        cache.flushDCache(u32, &self.buffer);
        var bus_address = memory.physicalToBus(@intFromPtr(&self.buffer));
        _ = bus_address;
        // mbox.mailboxWrite(self.channel, @truncate(bus_address));
        // var data = mailboxRead(self.channel);

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

        if (ptr_info != .Pointer) @compileError("argument `pointer` must be an actual pointer");
        if (ptr_info.Pointer.size != .One) @compileError("argument `pointer` must be a single-item pointer");
        if (@typeInfo(ptr_info.Pointer.child) != .Struct) @compileError("argument `pointer` must be a pointer to a struct");

        const closure = struct {
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
            .fillFn = closure.fill,
            .unfillFn = closure.unfill,
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

fn Attach(_: *Device) !void {
    return common.Error.NotImplemented;
}

fn Detach(_: *Device) !void {
    return common.Error.NotImplemented;
}

fn Query(_: *Device) !void {
    return common.Error.NotImplemented;
}

fn Detect(allocator: *Allocator, devicenode: *Node) !*common.Driver {
    var device: *MailboxDevice = try allocator.create(MailboxDevice);
    const mbox_cells = devicenode.mboxCells();
    const address_cells = devicenode.parent.addressCells();
    const reg = devicenode.propertyValueAs(u32, "reg") catch return common.Error.InitializationError;
    const register_base = devicetree.cellsAs(reg[0..address_cells]);
    const register_len = devicetree.cellsAs(reg[address_cells .. address_cells + 1]);

    const interrupt_parent = devicenode.interruptParent() catch return common.Error.InitializationError;
    const interrupt_cells = interrupt_parent.interruptCells();
    const interrupts = devicenode.propertyValueAs(u32, "interrupts") catch return common.Error.InitializationError;

    for (interrupts, 0..) |intc, i| {
        kprint("Device '{s}' interrupt[{d}] = {x}\n", .{ devicenode.name, i, intc });
    }

    device.* = MailboxDevice{
        .driver = common.Driver{
            .attach = Attach,
            .detach = Detach,
            .query = Query,
            .name = "bcm2835-mbox",
        },
        .devicenode = devicenode,
        .mbox_bits = 32 * mbox_cells,
        .register_base = register_base,
        .register_len = register_len,
        .interrupt_cells = interrupt_cells,
        .interrupts = interrupts,
    };

    return &device.driver;
}

const MailboxDevice = struct {
    driver: common.Driver,
    devicenode: *Node,
    mbox_bits: usize,
    register_base: usize,
    register_len: usize,
    interrupts: []u32,
    interrupt_cells: usize,
};

pub const ident = common.DriverIdent{
    .compatible = "brcm,bcm2835-mbox",
    .detect = &Detect,
};
