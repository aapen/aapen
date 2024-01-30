const helpers = @import("helpers.zig");
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const atomic = @import("../atomic.zig");

pub fn testBody() !void {
    try atomicAdd();
    try atomicAddFetch();
    try atomicSubtract();
    try atomicSubtractFetch();
}

// Note that this doesn't verify atomicity, just that the return value
// and side effect are as expected.
fn atomicAdd() !void {
    var add_value: u64 = 42;
    const r = atomic.atomicInc(&add_value);
    expectEqual(@as(u64, 42), r);
    expectEqual(@as(u64, 43), add_value);
}

fn atomicAddFetch() !void {
    var add_value_2: u64 = 123;
    const r2 = atomic.atomicAddFetch(&add_value_2, 321);
    expectEqual(@as(u64, 444), r2);
    expectEqual(r2, add_value_2);
}

fn atomicSubtract() !void {
    var dec_value: u64 = 99;
    const r = atomic.atomicDec(&dec_value);
    expectEqual(@as(u64, 99), r);
    expectEqual(@as(u64, 98), dec_value);
}

fn atomicSubtractFetch() !void {
    var dec_value: u64 = 789;
    const r = atomic.atomicSubFetch(&dec_value, 564);
    expectEqual(@as(u64, 225), r);
    expectEqual(r, dec_value);
}
