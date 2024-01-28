const std = @import("std");
const Allocator = std.mem.Allocator;

const Forth = @import("../forty/forth.zig").Forth;

const root = @import("root");
const InterruptController = root.HAL.InterruptController;
const IrqHandler = InterruptController.IrqHandler;
const IrqId = InterruptController.IrqId;

const GPIO_0 = InterruptController.IrqId.GPIO_0;
const GPIO_1 = InterruptController.IrqId.GPIO_1;
const GPIO_2 = InterruptController.IrqId.GPIO_2;
const GPIO_3 = InterruptController.IrqId.GPIO_3;

const Event = @import("../event.zig");

const Self = @This();
pub fn defineModule(forth: *Forth) !void {
    try forth.defineStruct("gpio.pull", PullUpDownSelect, .{
        .declarations = true,
    });
    try forth.defineStruct("gpio.function", FunctionSelect, .{
        .declarations = true,
    });
    try forth.defineStruct("gpio.event", EventSelect, .{
        .declarations = true,
    });
    try forth.defineNamespace(Self, .{
        .{ "enable", "gpio-pin-enable" },
        .{ "set", "gpio-pin-set" },
        .{ "get", "gpio-pin-get" },
        .{ "selectFunction", "gpio-pin-func" },
        .{ "selectPull", "gpio-pin-pull" },
        .{ "eventListen", "gpio-listen" },
    });
}

extern fn spinDelay(cpu_cycles: u32) void;

pub const FunctionSelect = struct {
    pub const Input: u3 = 0b000;
    pub const Output: u3 = 0b001;
    pub const Alt0: u3 = 0b100;
    pub const Alt1: u3 = 0b101;
    pub const Alt2: u3 = 0b110;
    pub const Alt3: u3 = 0b111;
    pub const Alt4: u3 = 0b011;
    pub const Alt5: u3 = 0b010;
};

pub const PullUpDownSelect = struct {
    pub const Float: u32 = 0x00;
    pub const Down: u32 = 0b01;
    pub const Up: u32 = 0b10;
};

pub const EventSelect = struct {
    pub const None: u32 = 0x00;
    pub const Falling: u32 = 0x01;
    pub const Rising: u32 = 0x02;
};

const Registers = extern struct {
    function_select: [6]u32,
    reserved_1: u32,
    output_set: [2]u32,
    reserved_2: u32,
    output_clear: [2]u32,
    reserved_3: u32,
    level: [2]u32,
    reserved_4: u32,
    event_detect_status: [2]u32,
    reserved_5: u32,
    rising_edge_detect_enable: [2]u32,
    reserved_6: u32,
    falling_edge_detect_enable: [2]u32,
    reserved_7: u32,
    pin_high_detect_enable: [2]u32,
    reserved_8: u32,
    pin_low_detect_enable: [2]u32,
    reserved_9: u32,
    pin_async_rising_detect_enable: [2]u32,
    reserved_10: u32,
    pin_async_falling_detect_enable: [2]u32,
    reserved_11: u32,
    pull_up_pull_down_enable: u32,
    pull_up_pull_down_enable_clock: [2]u32,
};

const Pin = struct {
    physical_id: u8,
    broadcom_id: u8,
    function_select_register_index: u8,
    function_select_register_shift: u5,
    data_register_index: u8,
    data_register_shift: u5,
    getset_mask: u32,
};

fn pin(physical_id: u8, broadcom_id: u8) Pin {
    const data_register_shift: u5 = @truncate(@mod(broadcom_id, 32));
    const getset_mask: u32 = @as(u32, 1) << data_register_shift;

    return .{
        .physical_id = physical_id,
        .broadcom_id = broadcom_id,
        .function_select_register_index = broadcom_id / 10,
        .function_select_register_shift = @truncate(@mod(broadcom_id * 3, 30)),
        .data_register_index = broadcom_id / 32,
        .data_register_shift = data_register_shift,
        .getset_mask = getset_mask,
    };
}

pins: [28]Pin = init: {
    var initial_value: [28]Pin = undefined;
    initial_value[2] = pin(3, 2);
    initial_value[3] = pin(5, 3);
    initial_value[4] = pin(7, 4);
    initial_value[5] = pin(29, 5);
    initial_value[6] = pin(31, 6);
    initial_value[7] = pin(26, 7);
    initial_value[8] = pin(24, 8);
    initial_value[9] = pin(21, 9);
    initial_value[10] = pin(19, 10);
    initial_value[11] = pin(23, 11);
    initial_value[12] = pin(32, 12);
    initial_value[13] = pin(33, 13);
    initial_value[14] = pin(8, 14);
    initial_value[15] = pin(10, 15);
    initial_value[16] = pin(36, 16);
    initial_value[17] = pin(11, 17);
    initial_value[18] = pin(12, 18);
    initial_value[19] = pin(35, 19);
    initial_value[20] = pin(38, 20);
    initial_value[21] = pin(40, 21);
    initial_value[22] = pin(15, 22);
    initial_value[23] = pin(16, 23);
    initial_value[24] = pin(18, 24);
    initial_value[25] = pin(22, 25);
    initial_value[26] = pin(37, 26);
    initial_value[27] = pin(13, 27);
    break :init initial_value;
},

registers: *volatile Registers,
interrupt_controller: *InterruptController,
interrupts_enabled: bool,

irq_handler: IrqHandler = .{
    .callback = irqHandle,
},

pub fn init(allocator: Allocator, register_base: u64, interrupt_controller: *InterruptController) !*Self {
    const self = try allocator.create(Self);

    self.* = .{
        .registers = @ptrFromInt(register_base),
        .interrupt_controller = interrupt_controller,
        .interrupts_enabled = false,
    };

    self.interrupt_controller.connect(.GPIO_0, &self.irq_handler);
    self.interrupt_controller.connect(.GPIO_1, &self.irq_handler);
    self.interrupt_controller.connect(.GPIO_2, &self.irq_handler);
    self.interrupt_controller.connect(.GPIO_3, &self.irq_handler);
    return self;
}

fn enable_interrupts(self: *Self) void {
    if (!self.interrupts_enabled) {
        self.interrupt_controller.enable(GPIO_3);
        self.interrupt_controller.enable(GPIO_2);
        self.interrupt_controller.enable(GPIO_1);
        self.interrupt_controller.enable(GPIO_0);
    }
    self.interrupts_enabled = true;
}

pub fn enable(self: *Self, bc_id: u64) void {
    self.enable_interrupts();
    self.selectFunction(bc_id, FunctionSelect.Output);
    self.selectPull(bc_id, PullUpDownSelect.Float);
}

pub fn selectFunction(self: *Self, bc_id: u64, fsel: u3) void {
    const p = &self.pins[bc_id];
    var val = self.registers.function_select[p.function_select_register_index];
    val &= ~(@as(u32, 7) << p.function_select_register_shift);
    val |= (@as(u32, fsel) << p.function_select_register_shift);
    self.registers.function_select[p.function_select_register_index] = val;
}

pub fn selectPull(self: *Self, bc_id: u64, pull: u32) void {
    const p = &self.pins[bc_id];

    self.registers.pull_up_pull_down_enable = 0;
    spinDelay(150);

    self.registers.pull_up_pull_down_enable = pull;
    spinDelay(150);

    // En/disable PU/PD for this pin
    self.registers.pull_up_pull_down_enable_clock[p.data_register_index] = p.getset_mask;
    spinDelay(150);

    // Clock in a zero
    self.registers.pull_up_pull_down_enable = 0;
    self.registers.pull_up_pull_down_enable_clock[p.data_register_index] = 0;
}

pub fn eventListen(self: *Self, bc_id: u64, edge: u32) void {
    const p = &self.pins[bc_id];

    switch (edge) {
        EventSelect.None => {
            self.registers.rising_edge_detect_enable[p.data_register_index] &= (~p.getset_mask);
            self.registers.falling_edge_detect_enable[p.data_register_index] &= (~p.getset_mask);
        },
        EventSelect.Rising => {
            var val = self.registers.rising_edge_detect_enable[p.data_register_index];
            val |= @as(u32, 1) << p.data_register_shift;
            self.registers.rising_edge_detect_enable[p.data_register_index] = val;
            self.registers.event_detect_status[p.data_register_index] = @as(u32, 1) << p.data_register_shift;
        },
        EventSelect.Falling => {
            var val = self.registers.falling_edge_detect_enable[p.data_register_index];
            val |= @as(u32, 1) << p.data_register_shift;
            self.registers.falling_edge_detect_enable[p.data_register_index] = val;
            self.registers.event_detect_status[p.data_register_index] = @as(u32, 1) << p.data_register_shift;
        },
        else => {
            _ = root.printf("Bad event enable type %d\n", edge);
        },
    }
}

pub fn set(self: *Self, bc_id: u64, pin_on: bool) void {
    const p = &self.pins[bc_id];
    if (pin_on) {
        self.registers.output_set[p.data_register_index] = p.getset_mask;
    } else {
        self.registers.output_clear[p.data_register_index] = p.getset_mask;
    }
}

pub fn get(self: *Self, bc_id: u64) bool {
    const p = &self.pins[bc_id];
    const levels = self.registers.level[p.data_register_index];
    return (levels & p.getset_mask) != 0;
}

pub fn irqHandle(this: *IrqHandler, _: *InterruptController, _: IrqId) void {
    var self: *Self = @fieldParentPtr(Self, "irq_handler", this);

    // Make sure we have some status to report.
    if ((self.registers.event_detect_status[0] == 0) and
        (self.registers.event_detect_status[1] == 0))
    {
        return;
    }

    for (self.pins) |p| {
        const p_status = self.registers.event_detect_status[p.data_register_index] & p.getset_mask;
        if (p_status != 0) {
            Event.enqueue(.{ .type = Event.EventType.GPIO, .subtype = 0x66, .value = p.broadcom_id, .extra = @truncate(root.hal.clock.ticks()) });
        }
    }
    self.registers.event_detect_status[0] = @as(u32, 0xffffffff);
    self.registers.event_detect_status[1] = @as(u32, 0xffffffff);
}
