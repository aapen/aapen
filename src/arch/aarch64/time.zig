const std = @import("std");
const registers = @import("registers.zig");
const barrier = @import("barrier.zig");

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
    return @truncate(registers.CNTFRQ_EL0.read());
}

fn read_cntpct() u32 {
    barrier.isb();
    return registers.CNTPCT_EL0.read();
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
    registers.CNTP_TVAL_EL0.write(@as(u64, target_ticks));

    // Start the ticks
    registers.CNTP_CTL_EL0.modify(.{ .enable = .enable, .istatus = .not_met });

    // Check status. It will be 1 when the timer is done.
    while (registers.CNTP_CTL_EL0.read().istatus == .not_met) {}

    // Turn the timer back off
    registers.CNTP_CTL_EL0.modify(.{ .enable = .disable });
}
