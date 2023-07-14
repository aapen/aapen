const io = @import("io.zig");
const reg = @import("../mmio_register.zig");
const UniformRegister = reg.UniformRegister;
const interrupts = @import("interrupts.zig");
const peripheral_base = @import("memory_map.zig").peripheral_base;
pub const system_timer_base = peripheral_base + 0x3000;

const debug_write = io.pl011_uart_write_text;

const TimerMatchBit = enum(u1) {
    not_detected = 0b0,
    detected = 0b1,
};

const timer_control_status_layout = packed struct {
    m0: TimerMatchBit = .not_detected,
    m1: TimerMatchBit = .not_detected,
    m2: TimerMatchBit = .not_detected,
    m3: TimerMatchBit = .not_detected,
    _unused_reserved: u28 = 0,
};
const timer_control_status = UniformRegister(timer_control_status_layout).init(system_timer_base + 0x00);

const timer_count_low_layout = u32;
const timer_count_low = UniformRegister(timer_count_low_layout).init(system_timer_base + 0x04);

const timer_count_high_layout = u32;
const timer_count_high = UniformRegister(timer_count_high_layout).init(system_timer_base + 0x08);

const timer_compare = u32;
const timer_compare_0 = UniformRegister(timer_compare).init(system_timer_base + 0x0c);
const timer_compare_1 = UniformRegister(timer_compare).init(system_timer_base + 0x10);
const timer_compare_2 = UniformRegister(timer_compare).init(system_timer_base + 0x14);
const timer_compare_3 = UniformRegister(timer_compare).init(system_timer_base + 0x18);

// ----------------------------------------------------------------------
// Timer interrupts
// ----------------------------------------------------------------------
pub const TimerIRQs = struct {
    pub const SystemTimerIRQ0: u32 = 0b0001;
    pub const SystemTimerIRQ1: u32 = 0b0010;
    pub const SystemTimerIRQ2: u32 = 0b0100;
    pub const SystemTimerIRQ3: u32 = 0b1000;
};

pub fn enable_timer_irq(which: u32) void {
    interrupts.enable_irq(which);
}

pub fn disable_timer_irq(which: u32) void {
    interrupts.disable_irq(which);
}

// ----------------------------------------------------------------------
// Repeating timer
// ----------------------------------------------------------------------
const timer_quantum = 200000;
var next_tick: u32 = undefined;

pub fn timer_init() void {
    enable_timer_irq(TimerIRQs.SystemTimerIRQ1);

    next_tick = timer_count_low.read();
    next_tick += timer_quantum;
    timer_compare_1.write(next_tick);
}

pub fn handle_timer_irq(which_timer: u32) void {
    _ = which_timer;
    next_tick += timer_quantum;
    timer_compare_1.write(next_tick);
    timer_control_status.write(.{ .m1 = .detected });
}
