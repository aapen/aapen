/// One shot signals
const atomic = @import("../atomic.zig");

const Self = @This();

value: u64 = 0,

pub fn signal(self: *Self) void {
    _ = atomic.atomicInc(&self.value);
}

pub fn isSignalled(self: *Self) bool {
    const v = atomic.atomicFetch(&self.value);
    return v != 0;
}
