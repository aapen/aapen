const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const InterruptController = root.HAL.InterruptController;
const IrqId = InterruptController.IrqId;
const IrqHandlerFn = InterruptController.IrqHandlerFn;
const IrqHandler = InterruptController.IrqHandler;

const Forth = @import("../forty/forth.zig").Forth;

const synchronize = @import("../synchronize.zig");
const Spinlock = synchronize.Spinlock;

pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(@This(), .{
        .{ "systemTicks", "ticks", "system clock ticks since boot" },
    });
}

pub fn systemTicks() u64 {
    return root.hal.clock.ticks();
}

pub fn delayMillis(count: u32) void {
    root.hal.clock.delayMillis(count);
}

pub const Clock = struct {
    const Self = @This();

    count_low: *volatile u32,
    count_high: *volatile u32,

    pub fn init(allocator: Allocator, register_base: u64) !*Clock {
        const self = try allocator.create(Self);

        self.* = .{
            .count_low = @ptrFromInt(register_base + 0x04),
            .count_high = @ptrFromInt(register_base + 0x08),
        };

        return self;
    }

    pub fn ticks(self: *const Clock) u64 {
        const low: u32 = self.count_low.*;
        const high: u32 = self.count_high.*;
        return @as(u64, high) << 32 | low;
    }

    pub fn ticksReadLow(self: *const Clock) u32 {
        return self.count_low.*;
    }

    pub fn delayMillis(self: *const Clock, count: u32) void {
        self.delayMicros(count * 1000);
    }

    // spin loop until 'count' ticks elapse
    pub fn delayMicros(self: *const Clock, count: u32) void {
        const start = self.ticks();
        const end = start + count; // assumes clock freq is 1Mhz
        while (self.ticks() <= end) {}
    }
};

pub const TimerHandler = struct {
    callback: *const fn (*const TimerHandler, *Timer) u32,

    fn invoke(self: *const TimerHandler, timer: *Timer) u32 {
        return self.callback(self, timer);
    }
};

fn do_nothing(_: *const TimerHandler, _: *Timer) u32 {
    return 0;
}

const null_handler: TimerHandler = .{
    .callback = do_nothing,
};

pub const Timer = struct {
    const TimerControlStatus = packed struct {
        match: u4,
        _unused_reserved: u28 = 0,
    };

    clock: *Clock,
    intc: *InterruptController,
    irq: IrqId,
    timer_id: u2,
    control: *volatile TimerControlStatus,
    compare: *volatile u32,
    match_reset: u4 = 0,
    schedule_spinlock: Spinlock,
    next_callback: *const TimerHandler,
    irq_handler: IrqHandler = .{
        .callback = irqHandle,
    },

    pub fn init(allocator: Allocator, id: usize, base: u64, clock: *Clock, intc: *InterruptController) !*Timer {
        var self = try allocator.create(Timer);

        const timer_id: u2 = @truncate(id);
        const irq_id: IrqId = @enumFromInt(id);

        self.* = Timer{
            .timer_id = timer_id,
            .irq = irq_id,
            .match_reset = @as(u4, 1) << timer_id,
            .control = @ptrFromInt(base),
            .compare = @ptrFromInt(base + 0x0c + (@as(u64, timer_id) * 4)),
            .next_callback = &null_handler,
            .clock = clock,
            .intc = intc,
            .schedule_spinlock = blk: {
                var lock = Spinlock.init("scheduler", true);
                lock.target_level = .IRQ;
                break :blk lock;
            },
        };

        intc.connect(self.irq, &self.irq_handler);

        return self;
    }

    pub fn deinit(self: *Timer) void {
        self.intc.disconnect(self.intc, self.irq);
    }

    fn clearDetectedFlag(self: *Timer) void {
        // writing to this register clears the detected flag where
        // there is a 1 bit. bit 0 -> timer 0, bit 1 -> timer 1, etc.
        self.control.match |= self.match_reset;
    }

    fn setNextTrigger(self: *Timer, in_ticks: u32) void {
        const tick = self.clock.ticksReadLow();
        // we ignore overflow because the counter will wrap around the
        // same way the compare value does.
        const next_tick = @addWithOverflow(tick, in_ticks)[0];
        self.compare.* = next_tick;
    }

    pub fn schedule(self: *Timer, in_ticks: u32, handler: *const TimerHandler) void {
        self.schedule_spinlock.acquire();
        defer self.schedule_spinlock.release();

        self.clearDetectedFlag();
        self.setNextTrigger(in_ticks);
        self.next_callback = handler;
        self.intc.enable(self.irq);
    }

    fn doCallback(self: *Timer) u32 {
        return self.next_callback.invoke(self);
    }
};

pub fn irqHandle(this: *IrqHandler, _: *InterruptController, _: IrqId) void {
    const timer: *Timer = @fieldParentPtr(Timer, "irq_handler", this);

    // invoke callback
    const next_delta = timer.doCallback();
    timer.clearDetectedFlag();

    if (next_delta >= 0) {
        // repeating, reset the schedule
        const tick = timer.clock.ticksReadLow();
        const next_tick = @addWithOverflow(tick, next_delta)[0];
        timer.compare.* = next_tick;
    } else {
        // else clear the callback and disable
        timer.next_callback = &null_handler;
        timer.disable();
    }
}
