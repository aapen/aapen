const std = @import("std");
const cpu = @import("../cortex-a.zig");
const registers = @import("registers.zig");

// TODO: is there a way to integrate this with std.time?

pub const TimeError = error{ DurationTooShort, DurationTooLong };

pub const Seconds = u64;
pub const Nanos = u32;

pub const nanos_per_second: u32 = 1000000000;

pub const Duration = struct {
    seconds: Seconds = 0,
    nanos: Nanos = 0,

    pub fn from_u64_nanos(nanos: u64) Duration {
        return Duration{
            .seconds = nanos / nanos_per_second,
            .nanos = nanos % nanos_per_second,
        };
    }

    pub fn as_u64_nanos(self: Duration) u64 {
        return self.seconds * nanos_per_second + self.nanos;
    }
};

fn frequency() u32 {
    return @truncate(registers.cntfrq_el0.read());
}

fn read_cntpct() u32 {
    cpu.barrierInstruction();
    return registers.cntpct_el0.read();
}

pub fn uptime() Duration {
    var current_count = read_cntpct();

    // TODO: seems like overflow is possible?
    return Duration.from_u64_nanos((current_count * nanos_per_second) / frequency());
}

pub fn spin(duration: Duration) !void {
    var freq = frequency(); // hertz
    var target_nanos = duration.as_u64_nanos(); // seconds * nanos_per_second

    var target_ticks = (target_nanos * freq) / nanos_per_second;

    if (target_ticks == 0)
        return;

    if (target_ticks >= std.math.maxInt(u32))
        return TimeError.DurationTooLong;

    // Set the countdown register
    registers.cntp_tval_el0.write(@as(u64, target_ticks));

    // Start the ticks
    registers.cntp_ctl_el0.modify(.{ .enable = .enable, .istatus = .not_met });

    // Check status. It will be 1 when the timer is done.
    while (registers.cntp_ctl_el0.read().istatus == .not_met) {}

    // Turn the timer back off
    registers.cntp_ctl_el0.modify(.{ .enable = .disable });
}
