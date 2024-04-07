const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const InterruptController = root.HAL.InterruptController;
const IrqId = InterruptController.IrqId;
const IrqHandlerFn = InterruptController.IrqHandlerFn;
const IrqHandler = InterruptController.IrqHandler;

const arch = @import("../architecture.zig");
const cpu = arch.cpu;

const Forth = @import("../forty/forth.zig").Forth;

pub fn defineModule(forth: *Forth) !void {
    _ = forth;
}

pub const Clock = struct {
    const Self = @This();

    count_low: *volatile u32,
    count_high: *volatile u32,
    ticks_per_micro: u32,

    pub fn init(allocator: Allocator, register_base: u64, clock_frequency_hz: u32) !*Clock {
        const self = try allocator.create(Self);

        self.* = .{
            .count_low = @ptrFromInt(register_base + 0x04),
            .count_high = @ptrFromInt(register_base + 0x08),
            .ticks_per_micro = clock_frequency_hz / 1_000_000,
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

    pub fn delayMillis(self: *const Clock, millis: u32) void {
        self.delayMicros(millis * 1000);
    }

    // spin loop until 'count' ticks elapse
    pub fn delayMicros(self: *const Clock, micros: u32) void {
        const deadline = self.deadlineMicros(micros);
        while (self.ticks() <= deadline) {}
    }

    pub fn deadlineMillis(self: *const Clock, millis: u32) u64 {
        return self.deadlineMicros(millis * 1000);
    }

    pub fn deadlineMicros(self: *const Clock, micros: u32) u64 {
        return self.ticks() + (micros * self.ticks_per_micro);
    }
};

pub const TimerHandler = fn (*Timer) void;

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
    next_callback: ?*const TimerHandler,
    repeat_cycles: u32 = 0,
    irq_handle: IrqHandler = irqHandle,

    pub fn init(allocator: Allocator, id: usize, base: u64, clock: *Clock, intc: *InterruptController) !*Timer {
        var self = try allocator.create(Timer);

        const timer_id: u2 = @truncate(id);
        const irq_id: IrqId = @as(IrqId, @truncate(id));

        self.* = Timer{
            .timer_id = timer_id,
            .irq = irq_id,
            .match_reset = @as(u4, 1) << timer_id,
            .control = @ptrFromInt(base),
            .compare = @ptrFromInt(base + 0x0c + (@as(u64, timer_id) * 4)),
            .next_callback = null,
            .clock = clock,
            .intc = intc,
        };

        intc.connect(self.irq, &self.irq_handle, self);

        return self;
    }

    pub fn deinit(self: *Timer) void {
        self.intc.disconnect(self.intc, self.irq);
    }

    pub fn reset(self: *Timer, interval: u32) void {
        const im = cpu.disable();
        defer cpu.restore(im);

        // writing to this register clears the detected flag where
        // there is a 1 bit. bit 0 -> timer 0, bit 1 -> timer 1, etc.
        self.control.match |= self.match_reset;

        const tick = self.clock.ticksReadLow();
        // we ignore overflow because the counter will wrap around the
        // same way the compare value does.
        const next_tick = @addWithOverflow(tick, interval)[0];
        self.compare.* = next_tick;
    }

    pub fn setCallback(self: *Timer, handler: *const TimerHandler) void {
        self.next_callback = handler;
        self.intc.enable(self.irq);
    }
};

pub fn irqHandle(_: *InterruptController, _: IrqId, private: ?*anyopaque) void {
    const timer: *Timer = @ptrCast(@alignCast(private));

    // invoke callback
    if (timer.next_callback) |cb| {
        cb(timer);
    }
}
