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

pub inline fn enable_irq(irqset: u64) void {
    var low_irqs: u32 = @truncate(irqset);
    var high_irqs: u32 = @truncate(irqset >> 32);

    enable_irqs_1.write(low_irqs);
    enable_irqs_2.write(high_irqs);
}

pub inline fn disable_irq(irqset: u64) void {
    var low_irqs: u32 = @truncate(irqset);
    var high_irqs: u32 = @truncate(irqset >> 32);

    disable_irqs_1.write(low_irqs);
    disable_irqs_2.write(high_irqs);
}

inline fn raised(value: u32, bitset: u32) bool {
    return (value & bitset) != 0;
}

pub fn handle_irq() void {
    var basic_interrupts = irq_basic_pending.read();
    var irq_1_received = (basic_interrupts & @as(u32, (1 << 8))) != 0;
    var irq_2_received = (basic_interrupts & @as(u32, (1 << 9))) != 0;

    // Check low 32 IRQs first
    if (irq_1_received) {
        var low_irqs = irq_pending_1.read();
        if (raised(low_irqs, timer.TimerIRQs.SystemTimerIRQ1)) {
            timer.handle_timer_irq(1);
        }
    }

    if (irq_2_received) {
        var high_irqs = irq_pending_2.read();
        if (raised(high_irqs, (io.PL011Interrupts.UARTInterrupt >> 32) & 0xffffffff)) {
            io.handle_pl011_interrupt();
        }
    }
}
