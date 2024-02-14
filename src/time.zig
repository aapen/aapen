const std = @import("std");
const builtin = @import("builtin");

const root = @import("root");
const HAL = root.HAL;
const Forth = @import("forty/forth.zig").Forth;

const atomic = @import("atomic.zig");
const queue = @import("queue.zig");
const schedule = @import("schedule2.zig");

pub const TICKS_PER_SECOND = root.HAL.timer_frequency_hz;
pub const QUANTA_PER_SECOND = 1000;
pub const QUANTA_PER_MILLI = 1;

pub var quanta_since_boot: u64 = 0;
pub var seconds_since_boot: u64 = 0;

// ----------------------------------------------------------------------
// Define forty interface
// ----------------------------------------------------------------------
pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(@This(), .{
        .{ "uptime", "uptime", "seconds since boot" },
        .{ "quantaSinceBoot", "quptime", "interrupt quanta since boot" },
    });
}

// ----------------------------------------------------------------------
// Public functions
// ----------------------------------------------------------------------
pub fn init() void {
    quanta_since_boot = 0;
    seconds_since_boot = 0;

    root.hal.system_timer.schedule(quantum, clockHandle);
}

pub fn secondsSinceBoot() u64 {
    return atomic.atomicFetch(&seconds_since_boot);
}

pub fn quantaSinceBoot() u64 {
    return atomic.atomicFetch(&quanta_since_boot);
}

pub fn uptime() u64 {
    return atomic.atomicFetch(&seconds_since_boot);
}

pub fn ticks() u64 {
    return root.hal.clock.ticks();
}

// ----------------------------------------------------------------------
// Time calculations
// ----------------------------------------------------------------------

pub fn deadlineMillis(millis: u32) u64 {
    return ticks() + (millis * QUANTA_PER_MILLI);
}

pub fn delayMillis(millis: u32) void {
    root.hal.clock.delayMillis(millis);
}

// ----------------------------------------------------------------------
// Timer interrupts
// ----------------------------------------------------------------------
const quantum: u32 = TICKS_PER_SECOND / QUANTA_PER_SECOND;

fn clockHandle(_: *HAL.Timer) u32 {
    const now = atomic.atomicInc(&quanta_since_boot);

    if (now == QUANTA_PER_SECOND) {
        _ = atomic.atomicInc(&seconds_since_boot);
        _ = atomic.atomicReset(&quanta_since_boot, 0);
    }

    // Check for sleeping threads that have reached their wakeup time
    if (queue.nonEmpty(schedule.sleepq) and queue.decrementFirstKey(schedule.sleepq) <= 0) {
        schedule.wakeup();
    } else {
        schedule.reschedule();
    }

    return quantum;
}
