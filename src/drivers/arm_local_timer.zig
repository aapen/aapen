const hal2 = @import("../hal2.zig");

const hal = @import("../hal.zig");
const InterruptController = hal.interfaces.InterruptController;
const IrqId = hal.interfaces.IrqId;

const interrupts = @import("arm_local_interrupt_controller.zig");

pub const FreeRunningCounter = struct {
    count_low: *volatile u32,
    count_high: *volatile u32,

    pub fn ticks(self: *const FreeRunningCounter) u64 {
        const low: u32 = self.count_low.*;
        const high: u32 = self.count_high.*;
        return @as(u64, high) << 32 | low;
    }

    pub fn ticksReadLow(self: *const FreeRunningCounter) u32 {
        return self.count_low.*;
    }
};

pub const Timer = struct {
    fn noAction(intf: *const anyopaque) u32 {
        _ = intf;
        return 0;
    }

    const TimerControlStatus = packed struct {
        match: u4,
        _unused_reserved: u28 = 0,
    };

    interface: hal.interfaces.Timer = undefined,

    intc: *InterruptController,
    irq: IrqId,
    timer_id: u2,
    control: *volatile TimerControlStatus,
    compare: *volatile u32,
    match_reset: u4 = 0,
    next_callback: hal.interfaces.TimerCallbackFn = noAction,

    pub fn init(
        self: *Timer,
        timer_base: u64,
        intc: *InterruptController,
        timer_id: u2,
        irq: IrqId,
    ) void {
        self.interface = .{
            .schedule = schedule,
        };

        self.timer_id = timer_id;
        self.irq = irq;
        self.match_reset = @as(u4, 1) << self.timer_id;
        self.control = @ptrFromInt(timer_base);
        self.compare = @ptrFromInt(timer_base + 0x0c + (@as(u64, self.timer_id) * 4));
        self.next_callback = noAction;
        self.intc = intc;
        self.intc.connect(self.intc, self.irq, irqHandle);
    }

    pub fn timer(self: *Timer) *hal.interfaces.Timer {
        return &self.interface;
    }

    pub fn deinit(self: *Timer) void {
        self.intc.disconnect(self.intc, self.irq);
    }

    pub fn enable(self: *Timer) void {
        self.intc.enable(self.intc, self.irq);
    }

    pub fn disable(self: *Timer) void {
        self.intc.disable(self.intc, self.irq);
    }

    fn clearDetectedFlag(self: *Timer) void {
        // writing to this register clears the detected flag where
        // there is a 1 bit. bit 0 -> timer 0, bit 1 -> timer 1, etc.
        self.control.match = self.match_reset;
    }

    fn schedule(intf: *hal.interfaces.Timer, in_ticks: u32, cb: hal.interfaces.TimerCallbackFn) void {
        const self = @fieldParentPtr(@This(), "interface", intf);

        self.disable();
        const tick = hal2.clock.ticksReadLow();

        // we ignore overflow because the counter will wrap around the
        // same way the compare value does.
        const next_tick = @addWithOverflow(tick, in_ticks)[0];
        self.compare.* = next_tick;
        self.next_callback = cb;
        self.enable();
    }

    pub fn irqHandle(_: *anyopaque, id: IrqId) void {
        const which_timer = id.index & 0x3;
        var self = timers[which_timer];

        // invoke callback
        const next_delta = self.next_callback(&self.interface);
        self.clearDetectedFlag();

        if (next_delta >= 0) {
            // repeating, reset the schedule
            const tick = hal2.clock.ticksReadLow();
            const next_tick = @addWithOverflow(tick, next_delta)[0];
            self.compare.* = next_tick;
        } else {
            // else clear the callback and disable
            self.next_callback = noAction;
            self.disable();
        }
    }
};

pub var timers: [4]Timer = undefined;

pub fn init(system_timer_base: u64, intc: *InterruptController) void {
    // TODO externalize this constant
    inline for (0..3) |timer_id| {
        timers[timer_id].init(system_timer_base, intc, timer_id, interrupts.mkid(0, timer_id));
    }
}
