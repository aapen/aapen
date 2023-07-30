const io = @import("io.zig");
const reg = @import("../mmio_register.zig");
const UniformRegister = reg.UniformRegister;
const timer = @import("timer.zig");
const peripheral_base = @import("memory_map.zig").peripheral_base;

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

pub inline fn irqEnable(irqset: u64) void {
    var low_irqs: u32 = @truncate(irqset);
    var high_irqs: u32 = @truncate(irqset >> 32);

    enable_irqs_1.write(low_irqs);
    enable_irqs_2.write(high_irqs);
}

pub inline fn irqDisable(irqset: u64) void {
    var low_irqs: u32 = @truncate(irqset);
    var high_irqs: u32 = @truncate(irqset >> 32);

    disable_irqs_1.write(low_irqs);
    disable_irqs_2.write(high_irqs);
}

inline fn raised(value: u32, bitset: u32) bool {
    return (value & bitset) != 0;
}

pub fn irqHandle() void {
    var basic_interrupts = irq_basic_pending.read();
    var pending_1_received = (basic_interrupts & @as(u32, (1 << 8))) != 0;
    var pending_2_received = (basic_interrupts & @as(u32, (1 << 9))) != 0;

    // process basic interrupts before anything else
    if (raised(basic_interrupts, io.Pl011Irqs.UartBaseRegisterIrqBit)) {
        io.pl011IrqHandle();
    } else if (pending_1_received) {
        // Check low 32 pending IRQs first
        var low_irqs = irq_pending_1.read();
        if (raised(low_irqs, timer.TimerIrqs.SystemTimerIrq1)) {
            timer.timerIrqHandle(1);
        }
    } else if (pending_2_received) {
        var high_irqs = irq_pending_2.read();
        if (raised(high_irqs, (io.Pl011Irqs.UartIrq >> 32) & 0xffffffff)) {
            io.pl011IrqHandle();
        }
    }
}
