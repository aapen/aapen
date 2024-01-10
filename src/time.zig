const std = @import("std");
const builtin = @import("builtin");

const root = @import("root");

pub fn deadlineMillis(count: u32) u64 {
    const TICKS_PER_MILLI = 1000;
    return ticks() + (count * TICKS_PER_MILLI);
}

pub fn delayMillis(count: u32) void {
    const NANOS_PER_MILLI = 1000 * 1000;
    if (builtin.is_test) {
        std.time.sleep(count * NANOS_PER_MILLI);
    } else {
        root.hal.clock.delayMillis(count);
    }
}

pub fn ticks() u64 {
    if (builtin.is_test) {
        return std.time.microTimestamp();
    } else {
        return root.hal.clock.ticks();
    }
}
