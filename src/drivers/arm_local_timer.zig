const interrupts = @import("arm_local_interrupt_controller.zig");

pub const IrqId = interrupts.IrqId;
pub const LocalInterruptController = interrupts.LocalInterruptController;

pub const TimerCallbackFn = *const fn (timer: *anyopaque) u32;

pub const Clock = struct {
    count_low: *volatile u32,
    count_high: *volatile u32,

    pub fn init(register_base: u64) Clock {
        return .{
            .count_low = @ptrFromInt(register_base + 0x04),
            .count_high = @ptrFromInt(register_base + 0x08),
        };
    }

    pub fn ticks(self: *const Clock) u64 {
        const low: u32 = self.count_low.*;
        const high: u32 = self.count_high.*;
        return @as(u64, high) << 32 | low;
    }

    pub fn ticksReadLow(self: *const Clock) u32 {
        return self.count_low.*;
    }
};

pub const Timer = struct {
    pub fn init(id: usize, base: u64, clock: *Clock, intc: *LocalInterruptController) Timer {
        var timer_id: u2 = @truncate(id);
        return .{
            .timer_id = timer_id,
            .irq = .{ .index = id },
            .match_reset = @as(u4, 1) << timer_id,
            .control = @ptrFromInt(base),
            .compare = @ptrFromInt(base + 0x0c + (@as(u64, timer_id) * 4)),
            .next_callback = Timer.noAction,
            .clock = clock,
            .intc = intc,
        };
    }

    fn noAction(intf: *const anyopaque) u32 {
        _ = intf;
        return 0;
    }

    const TimerControlStatus = packed struct {
        match: u4,
        _unused_reserved: u28 = 0,
    };

    clock: *Clock,
    intc: *LocalInterruptController,
    irq: IrqId,
    timer_id: u2,
    control: *volatile TimerControlStatus,
    compare: *volatile u32,
    match_reset: u4 = 0,
    next_callback: TimerCallbackFn = noAction,

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

    fn schedule(self: *const Timer, in_ticks: u32, cb: TimerCallbackFn) void {
        self.disable();
        const tick = self.clock.ticksReadLow();

        // we ignore overflow because the counter will wrap around the
        // same way the compare value does.
        const next_tick = @addWithOverflow(tick, in_ticks)[0];
        self.compare.* = next_tick;
        self.next_callback = cb;
        self.enable();
    }

    pub fn irqHandle(context: *anyopaque, _: IrqId) void {
        const self: *const Timer = @ptrCast(@alignCast(context));

        // invoke callback
        const next_delta = self.next_callback(&self.interface);
        self.clearDetectedFlag();

        if (next_delta >= 0) {
            // repeating, reset the schedule
            const tick = self.clock.ticksReadLow();
            const next_tick = @addWithOverflow(tick, next_delta)[0];
            self.compare.* = next_tick;
        } else {
            // else clear the callback and disable
            self.next_callback = noAction;
            self.disable();
        }
    }
};
