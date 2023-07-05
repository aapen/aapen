const io = @import("io.zig");
const reg = @import("../mmio_register.zig");
const UniformRegister = reg.UniformRegister;
const timer = @import("timer.zig");
const peripheral_base = @import("peripheral.zig").peripheral_base;

const debug_write = io.pl011_uart_write_text;

// ----------------------------------------------------------------------
// Interrupt controller
// ----------------------------------------------------------------------
pub const irq_base = peripheral_base + 0xb200;

pub const irq_basic_pending = UniformRegister(u32).init(irq_base + 0x00);
pub const irq_pending_1 = UniformRegister(u32).init(irq_base + 0x04);
pub const irq_pending_2 = UniformRegister(u32).init(irq_base + 0x08);
pub const fiq_control = UniformRegister(u32).init(irq_base + 0x0c);
pub const enable_irqs_1 = UniformRegister(u32).init(irq_base + 0x10);
pub const enable_irqs_2 = UniformRegister(u32).init(irq_base + 0x14);
pub const enable_basic_irqs = UniformRegister(u32).init(irq_base + 0x18);
pub const disable_irqs_1 = UniformRegister(u32).init(irq_base + 0x1c);
pub const disable_irqs_2 = UniformRegister(u32).init(irq_base + 0x20);
pub const disable_basic_irqs = UniformRegister(u32).init(irq_base + 0x24);

inline fn enable_irq(irqset: u32) void {
    enable_irqs_1.write(irqset);
}

inline fn disable_irq(irqset: u32) void {
    disable_irqs_1.write(irqset);
}

inline fn raised(value: u32, bitset: u32) bool {
    return (value & bitset) != 0;
}

pub fn handle_irq() void {
    var irqs = irq_pending_1.read();

    if (raised(irqs, TimerIRQs.SystemTimerIRQ1)) {
        timer.handle_timer_irq(1);
    } else {
        debug_write("Unknown pending irq\n");
    }
}

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
    enable_irq(which);
}

pub fn disable_timer_irq(which: u32) void {
    disable_irq(which);
}
