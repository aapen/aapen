const io = @import("io.zig");
const reg = @import("../mmio_register.zig");
const UniformRegister = reg.UniformRegister;
const interrupts = @import("interrupts.zig");
const peripheral_base = @import("memory_map.zig").peripheral_base;
pub const system_timer_base = peripheral_base + 0x3000;

const debug_write = io.pl011WriteText;

const TimerMatchBit = enum(u1) {
    not_detected = 0b0,
    detected = 0b1,
};

const TimerControlStatusLayout = packed struct {
    m0: TimerMatchBit = .not_detected,
    m1: TimerMatchBit = .not_detected,
    m2: TimerMatchBit = .not_detected,
    m3: TimerMatchBit = .not_detected,
    _unused_reserved: u28 = 0,
};
const timer_control_status = UniformRegister(TimerControlStatusLayout).init(system_timer_base + 0x00);

const TimerCountLowLayout = u32;
const timer_count_low = UniformRegister(TimerCountLowLayout).init(system_timer_base + 0x04);

const TimerCountHighLayout = u32;
const timer_count_high = UniformRegister(TimerCountHighLayout).init(system_timer_base + 0x08);

const TimerCompareLayout = u32;
const timer_compare_0 = UniformRegister(TimerCompareLayout).init(system_timer_base + 0x0c);
const timer_compare_1 = UniformRegister(TimerCompareLayout).init(system_timer_base + 0x10);
const timer_compare_2 = UniformRegister(TimerCompareLayout).init(system_timer_base + 0x14);
const timer_compare_3 = UniformRegister(TimerCompareLayout).init(system_timer_base + 0x18);

// ----------------------------------------------------------------------
// Timer interrupts
// ----------------------------------------------------------------------
pub const TimerIrqs = struct {
    pub const system_timer_irq_0: u32 = 0b0001;
    pub const system_timer_irq_1: u32 = 0b0010;
    pub const system_timer_irq_2: u32 = 0b0100;
    pub const system_timer_irq_3: u32 = 0b1000;
};

pub fn timerIrqEnable(which: u32) void {
    interrupts.irqEnable(which);
}

pub fn timerIrqDisable(which: u32) void {
    interrupts.irqDisable(which);
}

// ----------------------------------------------------------------------
// Repeating timer
// ----------------------------------------------------------------------
const timer_quantum = 200000;
var next_tick: u32 = undefined;

pub fn timerInit() void {
    timerIrqEnable(TimerIrqs.system_timer_irq_1);

    next_tick = timer_count_low.read();
    next_tick += timer_quantum;
    timer_compare_1.write(next_tick);
}

pub fn timerIrqHandle(which_timer: u32) void {
    _ = which_timer;
    next_tick += timer_quantum;
    timer_compare_1.write(next_tick);
    timer_control_status.write(.{ .m1 = .detected });
}
