const std = @import("std");
const builtin = @import("builtin");

const root = @import("root");
const HAL = root.HAL;
const Forth = @import("forty/forth.zig");

const Logger = @import("logger.zig");
var log: *Logger = undefined;

const atomic = @import("atomic.zig");
const queue = @import("queue.zig");
const schedule = @import("schedule.zig");

pub const quanta_per_second: u32 = 1000;

pub var ticks_per_second: u32 = 0;
pub var ticks_per_milli: u32 = 0;
pub var quantum: u32 = 0;

pub var quanta_since_boot: u64 = 0;
pub var seconds_since_boot: u64 = 0;

// ----------------------------------------------------------------------
// Define forty interface
// ----------------------------------------------------------------------
pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(@This(), .{
        .{ "uptime", "uptime", "seconds since boot" },
        .{ "quantaInSecond", "quptime", "interrupt quanta, range is 0 to 999" },
        .{ "ticks", "ticks", "system clock ticks since boot" },
    });
}

// ----------------------------------------------------------------------
// Public functions
// ----------------------------------------------------------------------
pub fn init() void {
    ticks_per_second = root.hal.system_timer.frequency;
    ticks_per_milli = ticks_per_second / 1000;

    quantum = ticks_per_second / quanta_per_second;

    log = Logger.init("time", .info);
    log.debug(@src(), "clock frequency = {d} Hz\tquantum = {d}", .{ ticks_per_second, quantum });

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
    return root.hal.system_timer.ticks();
}

// ----------------------------------------------------------------------
// Time calculations
// ----------------------------------------------------------------------

pub fn deadlineMillis(millis: u32) u64 {
    return ticks() + (millis * ticks_per_milli);
}

pub fn delayMillis(millis: u32) void {
    const deadline = deadlineMillis(millis);

    while (root.hal.system_timer.ticks() <= deadline) {}
}

// ----------------------------------------------------------------------
// Timer interrupts
// ----------------------------------------------------------------------

fn clockHandle(timer: *HAL.Timer) void {
    timer.reset(quantum);

    const now = atomic.atomicInc(&quanta_since_boot);

    if (now >= quanta_per_second) {
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
