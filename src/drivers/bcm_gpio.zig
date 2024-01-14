const Forth = @import("../forty/forth.zig").Forth;
const auto = @import("../forty/auto.zig");

const Self = @This();

pub fn defineModule(forth: *Forth) !void {
    try auto.defineNamespace(Self, .{
        .{ "enable", "gpio-pin-enable" },
        .{ "set", "gpio-pin-set" },
        .{ "clear", "gpio-pin-clear" },
        .{ "get", "gpio-pin-get" },
        .{ "selectFunction", "gpio-pin-func" },
    }, forth);
}

extern fn spinDelay(cpu_cycles: u32) void;

pub const FunctionSelect = enum(u3) {
    input = 0b000,
    output = 0b001,
    alt0 = 0b100,
    alt1 = 0b101,
    alt2 = 0b110,
    alt3 = 0b111,
    alt4 = 0b011,
    alt5 = 0b010,
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
    pull_up_pull_down_enable: [1]u32,
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

pub fn init(register_base: u64) Self {
    return .{
        .registers = @ptrFromInt(register_base),
    };
}

pub fn selectFunction(self: *Self, bc_id: u64, fsel: FunctionSelect) void {
    const p = &self.pins[bc_id];
    var val = self.registers.function_select[p.function_select_register_index];
    val &= ~(@as(u32, 7) << p.function_select_register_shift);
    val |= (@as(u32, @intFromEnum(fsel)) << p.function_select_register_shift);
    self.registers.function_select[p.function_select_register_index] = val;
}

pub fn enable(self: *Self, bc_id: u64) void {
    const p = &self.pins[bc_id];

    self.registers.pull_up_pull_down_enable[0] = 0;
    spinDelay(150);

    // enable PU/PD for this pin
    self.registers.pull_up_pull_down_enable_clock[p.data_register_index] = p.getset_mask;
    spinDelay(150);

    // clock in a zero
    self.registers.pull_up_pull_down_enable[0] = 0;
    self.registers.pull_up_pull_down_enable_clock[p.data_register_index] = 0;
}

const Serial = @import("../serial.zig");

pub fn set(self: *Self, bc_id: u64, pin_on: bool) void {
    try Serial.writer.print("set: id: {} pin_on: {}\n", .{ bc_id, pin_on });
    const p = &self.pins[bc_id];
    if (pin_on) {
        self.registers.output_set[p.data_register_index] = p.getset_mask;
    } else {
        self.registers.output_clear[p.data_register_index] = p.getset_mask;
    }
}

pub fn xset(self: *Self, bc_id: u64) void {
    const p = &self.pins[bc_id];
    self.registers.output_set[p.data_register_index] = p.getset_mask;
}

pub fn clear(self: *Self, bc_id: u64) void {
    const p = &self.pins[bc_id];
    self.registers.output_clear[p.data_register_index] = p.getset_mask;
}

pub fn get(self: *Self, bc_id: u64) bool {
    const p = &self.pins[bc_id];
    const levels = self.registers.level[p.data_register_index];
    return (levels & p.getset_mask) != 0;
}
