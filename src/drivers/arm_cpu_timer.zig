const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const InterruptController = root.HAL.InterruptController;
const Irq = InterruptController.Irq;
const IrqId = InterruptController.IrqId;
const IrqHandler = InterruptController.IrqHandler;

const arch = @import("../architecture.zig");
const cpu = arch.cpu;

const Forth = @import("../forty/forth.zig").Forth;

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------
pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(@This(), .{});
}

// ----------------------------------------------------------------------
// Private state
// ----------------------------------------------------------------------
const Self = @This();

const IRQ = Irq.ARM_TIMER;

const core_timer_0_interrupt_control: *volatile u32 = @ptrFromInt(0x4000_0040);

interrupt_controller: *InterruptController,
callback: ?*const Callback = null,
irq_handler: IrqHandler = irqHandle,
frequency: u32,

pub fn init(allocator: Allocator, intc: *InterruptController) !*Self {
    const self = try allocator.create(Self);

    self.* = .{
        .interrupt_controller = intc,
        .frequency = readClockFrequency(),
    };

    self.interrupt_controller.connect(Irq.ARM_TIMER, &self.irq_handler, self);

    // route virtual timer 0 interrupt to core 0 IRQ
    // See https://datasheets.raspberrypi.com/bcm2836/bcm2836-peripherals.pdf
    core_timer_0_interrupt_control.* = 0x08;

    return self;
}

inline fn readClockFrequency() u32 {
    return asm (
        \\ mrs %[ret], CNTFRQ_EL0
        : [ret] "=r" (-> u32),
    );
}

fn writeCntvCtlEl0(v: u64) void {
    asm volatile (
        \\ mov x0, %[v]
        \\ msr CNTV_CTL_EL0, x0
        :
        : [v] "r" (v),
        : "x0"
    );
}

inline fn enableCounterAndInterrupts() void {
    // IMASK = 0
    // ENABLE = 1
    writeCntvCtlEl0(0b01);
}

inline fn disableCounterAndInterrupts() void {
    // IMASK = 1
    // ENABLE = 0
    writeCntvCtlEl0(0b10);
}

// ----------------------------------------------------------------------
// Public API
// ----------------------------------------------------------------------
pub const Callback = fn (*Self) void;

pub fn setCallback(self: *Self, cb: ?*const Callback) void {
    const im = cpu.disable();
    defer cpu.restore(im);

    if (cb != null) {
        self.callback = cb;
        self.interrupt_controller.enable(IRQ);
        enableCounterAndInterrupts();
    } else {
        disableCounterAndInterrupts();
        self.callback = null;
        self.interrupt_controller.disable(IRQ);
    }
}

pub fn reset(_: *Self, count: u64) void {
    // CNTV_TVAL_EL0 - interrupt will trigger after this many cycles
    asm volatile (
        \\ msr CNTV_TVAL_EL0, %[count]
        :
        : [count] "r" (count),
        : "x0"
    );
}

pub fn ticks(_: *Self) u64 {
    return asm (
        \\ mrs %[ret], CNTVCT_EL0
        : [ret] "=r" (-> u64),
    );
}

pub fn frequency(self: *Self) u32 {
    return self.frequency;
}

// ----------------------------------------------------------------------
// Interrupt handling
// ----------------------------------------------------------------------
fn irqHandle(_: *InterruptController, _: IrqId, private: ?*anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(private));

    if (self.callback) |cb| {
        cb(self);
    }
}
