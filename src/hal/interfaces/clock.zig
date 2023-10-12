/// VTable for a common clock interface
pub const Clock = struct {
    ticks: *const fn (clock: *Clock) u64,
};

pub const TimerCallbackFn = *const fn (timer: *anyopaque) u32;

/// VTable for a common timer interface
pub const Timer = struct {
    schedule: *const fn (timer: *Timer, delta: u32, callback: TimerCallbackFn) void,
};
