const std = @import("std");
const builtin = @import("builtin");

const root = @import("root");
const HAL = root.HAL;
const Forth = @import("forty/forth.zig").Forth;

const atomic = @import("atomic.zig");
const queue = @import("queue.zig");
const schedule = @import("schedule.zig");

pub const TICKS_PER_SECOND = root.HAL.timer_frequency_hz;
pub const TICKS_PER_MILLI = TICKS_PER_SECOND / 1_000;
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
        .{ "quantaInSecond", "quptime", "interrupt quanta, range is 0 to 999" },
        .{ "restartTimer", "restart-timer", "force restart timer interrupts" },
        .{ "ticks", "ticks", "system clock ticks since boot" },
    });
}

// ----------------------------------------------------------------------
// Public functions
// ----------------------------------------------------------------------
pub fn init() void {
    quanta_since_boot = 0;
    seconds_since_boot = 0;

    root.hal.system_timer.setCallback(clockHandle);
    root.hal.system_timer.reset(quantum);
}

pub fn secondsSinceBoot() u64 {
    return atomic.atomicFetch(&seconds_since_boot);
}

pub fn quantaInSecond() u64 {
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
    return ticks() + (millis * TICKS_PER_MILLI);
}

pub fn delayMillis(millis: u32) void {
    root.hal.clock.delayMillis(millis);
}

// ----------------------------------------------------------------------
// Timer interrupts
// ----------------------------------------------------------------------
const quantum: u32 = TICKS_PER_SECOND / QUANTA_PER_SECOND;

fn clockHandle(timer: *HAL.Timer) void {
    timer.reset(quantum);

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
}

pub fn restartTimer() void {
    // THIS IS A HACK
    //
    // for some reason, I keep losing the timer interrupts. something
    // is happening that prevents the timer from being reset for the
    // next quantum. Until I can figure out why that happens, this
    // acts like shock paddles to restart the regular rhythm.
    root.hal.system_timer.reset(quantum);
}
