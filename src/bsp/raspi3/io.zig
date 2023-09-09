const std = @import("std");
const reg = @import("../mmio_register.zig");
const UniformRegister = reg.UniformRegister;

const bsp = @import("../../bsp.zig");
const interrupts = bsp.interrupts;
const IrqId = bsp.common.IrqId;

const ring = @import("../../ring.zig");
const cpu = @import("../../architecture.zig").cpu;
const peripheral_base = @import("memory_map.zig").peripheral_base;

extern fn spinDelay(cpu_cycles: u32) void;

// GPIO registers and their structures
// Note: this is incomplete... at the moment, it only contains enough
// to get a serial connection
const gpio_base = peripheral_base + 0x200000;

pub const GPIOFunctionSelect = enum(u3) {
    input = 0b000,
    output = 0b001,
    alt0 = 0b100,
    alt1 = 0b101,
    alt2 = 0b110,
    alt3 = 0b111,
    alt4 = 0b011,
    alt5 = 0b010,
};

const gpio_function_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x00),
    UniformRegister(u32).init(gpio_base + 0x04),
    UniformRegister(u32).init(gpio_base + 0x08),
    UniformRegister(u32).init(gpio_base + 0x0c),
    UniformRegister(u32).init(gpio_base + 0x10),
    UniformRegister(u32).init(gpio_base + 0x14),
};

const gpio_output_set_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x1c),
    UniformRegister(u32).init(gpio_base + 0x20),
};

const gpio_output_clear_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x28),
    UniformRegister(u32).init(gpio_base + 0x2c),
};

const gpio_level_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x34),
    UniformRegister(u32).init(gpio_base + 0x38),
};

const gpio_event_detect_status_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x40),
    UniformRegister(u32).init(gpio_base + 0x44),
};

const gpio_rising_edge_detect_enable_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x4c),
    UniformRegister(u32).init(gpio_base + 0x50),
};

const gpio_falling_edge_detect_enable_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x58),
    UniformRegister(u32).init(gpio_base + 0x5c),
};

const gpio_pin_high_detect_enable_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x64),
    UniformRegister(u32).init(gpio_base + 0x68),
};

const gpio_pin_low_detect_enable_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x70),
    UniformRegister(u32).init(gpio_base + 0x74),
};

const gpio_pull_up_pull_down_enable_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x94),
};

const gpio_pull_up_pull_down_enable_clock_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x98),
    UniformRegister(u32).init(gpio_base + 0x9c),
};

const GPIOPin = struct {
    const Self = @This();

    physical_id: u8,
    broadcom_id: u8,
    function_select_register_index: u8,
    function_select_register_shift: u5,
    data_register_index: u8,
    data_register_shift: u5,
    getset_mask: u32,

    fn define(physical_id: u8, broadcom_id: u8) Self {
        var fsel_bitstart: u5 = @truncate(@mod(broadcom_id * 3, 30));
        var fsel_register_index: u8 = broadcom_id / 10;
        var data_register_index: u8 = broadcom_id / 32;
        var data_register_shift: u5 = @truncate(@mod(broadcom_id, 32));
        var getset_mask: u32 = @as(u32, 1) << data_register_shift;

        return .{
            .physical_id = physical_id,
            .broadcom_id = broadcom_id,
            .function_select_register_index = fsel_register_index,
            .function_select_register_shift = fsel_bitstart,
            .data_register_index = data_register_index,
            .data_register_shift = data_register_shift,
            .getset_mask = getset_mask,
        };
    }

    pub fn selectFunction(self: *const Self, fsel: GPIOFunctionSelect) void {
        var val = gpio_function_registers[self.function_select_register_index].read_raw();
        val &= ~(@as(u32, 7) << self.function_select_register_shift);
        val |= (@as(u32, @intFromEnum(fsel)) << self.function_select_register_shift);
        gpio_function_registers[self.function_select_register_index].write_raw(val);
    }

    pub fn enable(self: *const Self) void {
        gpio_pull_up_pull_down_enable_registers[0].write_raw(0);
        spinDelay(150);
        gpio_pull_up_pull_down_enable_clock_registers[self.data_register_index].write_raw(self.getset_mask);
        spinDelay(150);
        gpio_pull_up_pull_down_enable_registers[0].write_raw(0);
        gpio_pull_up_pull_down_enable_clock_registers[self.data_register_index].write_raw(0);
    }

    pub fn set(self: *const Self) void {
        gpio_output_set_registers[self.data_register_index].write_raw(self.getset_mask);
    }

    pub fn clear(self: *const Self) void {
        gpio_output_clear_registers[self.data_register_index].write_raw(self.getset_mask);
    }

    pub fn get(self: *const Self) bool {
        var levels = gpio_level_registers[self.data_register_index].read_raw();
        return (levels & self.getset_mask) != 0;
    }
};

pub const pins = struct {
    pub const Pin2 = GPIOPin.define(3, 2);
    pub const Pin3 = GPIOPin.define(5, 3);
    pub const Pin4 = GPIOPin.define(7, 4);
    pub const Pin5 = GPIOPin.define(29, 5);
    pub const Pin6 = GPIOPin.define(31, 6);
    pub const Pin7 = GPIOPin.define(26, 7);
    pub const Pin8 = GPIOPin.define(24, 8);
    pub const Pin9 = GPIOPin.define(21, 9);
    pub const Pin10 = GPIOPin.define(19, 10);
    pub const Pin11 = GPIOPin.define(23, 11);
    pub const Pin12 = GPIOPin.define(32, 12);
    pub const Pin13 = GPIOPin.define(33, 13);
    pub const Pin14 = GPIOPin.define(8, 14);
    pub const Pin15 = GPIOPin.define(10, 15);
    pub const Pin16 = GPIOPin.define(36, 16);
    pub const Pin17 = GPIOPin.define(11, 17);
    pub const Pin18 = GPIOPin.define(12, 18);
    pub const Pin19 = GPIOPin.define(35, 19);
    pub const Pin20 = GPIOPin.define(38, 20);
    pub const Pin21 = GPIOPin.define(40, 21);
    pub const Pin22 = GPIOPin.define(15, 22);
    pub const Pin23 = GPIOPin.define(16, 23);
    pub const Pin24 = GPIOPin.define(18, 24);
    pub const Pin25 = GPIOPin.define(22, 25);
    pub const Pin26 = GPIOPin.define(37, 26);
    pub const Pin27 = GPIOPin.define(13, 27);
};
