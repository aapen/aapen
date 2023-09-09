const bsp = @import("../bsp.zig");
const InterruptController = bsp.common.InterruptController;
const IrqId = bsp.common.IrqId;

/// Returns a number of ticks to schedule the next invocation. A zero
/// return means don't schedule.
//pub const TimerCallbackFn = *const fn (timer: *Timer, context: ?*anyopaque) u32;

// fn rawTicks(_: *bsp.common.Timer) u64 {
//     return counter.ticks();
// }

// fn rawSchedule(_: *bsp.common.Timer, delta: u32, callback: *bsp.common.TimerCallbackFn, context: ?*anyopaque) void {
//     timers[1].schedule(delta, callback, context);
// }

const FreeRunningCounter = struct {
    count_low: *volatile u32,
    count_high: *volatile u32,

    pub fn init(self: *FreeRunningCounter, timer_base: u64) void {
        self.count_low = @ptrFromInt(timer_base + 0x04);
        self.count_high = @ptrFromInt(timer_base + 0x08);
    }

    pub fn clock(self: *FreeRunningCounter) bsp.common.Clock {
        return bsp.common.Clock.init(self, ticks);
    }

    pub fn ticks(self: *FreeRunningCounter) u64 {
        // TODO Probably should disable interrupts during this.
        const low: u32 = self.count_low.*;
        const high: u32 = self.count_high.*;
        return @as(u64, high) << 32 | low;
    }

    pub fn ticksReadLow(self: *FreeRunningCounter) u32 {
        return self.count_low.*;
    }
};

pub const Timer = struct {
    const CallbackThunk = struct {
        callback: bsp.common.TimerCallbackFn,
        context: ?*anyopaque,
    };

    fn noAction(_: ?*anyopaque) u32 {
        return 0;
    }

    const null_callback = CallbackThunk{ .callback = noAction, .context = null };

    const TimerControlStatus = packed struct {
        match: u4,
        _unused_reserved: u28 = 0,
    };

    intc: *InterruptController,
    irq: IrqId,
    timer_id: u2,
    control: *volatile TimerControlStatus,
    compare: *volatile u32,
    match_reset: u4 = 0,
    next_callback: CallbackThunk = null_callback,

    pub fn init(
        self: *Timer,
        timer_base: u64,
        intc: *InterruptController,
        timer_id: u2,
    ) void {
        self.match_reset = @as(u4, 1) << timer_id;
        self.control = @ptrFromInt(timer_base);
        self.compare = @ptrFromInt(timer_base + 0x0c + (@as(u64, timer_id) * 4));
        self.next_callback = null_callback;
        self.irq = IrqId{ 1, timer_id };
        self.intc = intc;

        self.intc.connect(self.irq, timerIrqHandle, self);
    }

    pub fn timer(self: *Timer) bsp.common.Timer {
        return bsp.common.Timer.init(self, schedule);
    }

    pub fn deinit(self: *Timer) void {
        self.intc.disconnect(self.irq);
    }

    pub fn enable(self: *Timer) void {
        self.intc.enable(self.irq);
    }

    pub fn disable(self: *Timer) void {
        self.intc.disable(self.irq);
    }

    fn clearDetectedFlag(self: *Timer) void {
        // writing to this register clears the detected flag where
        // there is a 1 bit. bit 0 -> timer 0, bit 1 -> timer 1, etc.
        self.control.match = self.match_reset;
    }

    pub fn schedule(self: *Timer, in_ticks: u32, cb: bsp.common.TimerCallbackFn, context: ?*anyopaque) void {
        self.disable();
        const tick = counter.ticksReadLow();

        // we ignore overflow because the counter will wrap around the
        // same way the compare value does.
        const next_tick = @addWithOverflow(tick, in_ticks)[0];
        self.compare.* = next_tick;
        self.next_callback = CallbackThunk{ .callback = cb, .context = context };
        self.enable();
    }

    pub fn irqHandle(self: *Timer) void {
        // invoke callback
        const next_delta = self.next_callback.callback(self.next_callback.context);
        self.clearDetectedFlag();

        if (next_delta >= 0) {
            // repeating, reset the schedule
            const tick = counter.ticksReadLow();
            const next_tick = @addWithOverflow(tick, next_delta)[0];
            self.compare.* = next_tick;
        } else {
            // else clear the callback and disable
            self.next_callback = null_callback;
            self.disable();
        }
    }
};

pub var counter: FreeRunningCounter = undefined;
pub var timers: [4]Timer = undefined;

pub fn init(system_timer_base: u64, intc: *InterruptController) void {
    // TODO externalize this constant
    counter.init(system_timer_base);
    inline for (0..3) |i| {
        timers[i].init(system_timer_base, intc, i);
    }
}

// ----------------------------------------------------------------------
// Trampoline function
// ----------------------------------------------------------------------

pub fn timerIrqHandle(_: IrqId, context: ?*anyopaque) void {
    if (null == context) {
        return;
    }

    var which: *Timer = @ptrCast(@alignCast(context));
    which.irqHandle();
}
