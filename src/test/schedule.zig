const root = @import("root");
const printf = root.printf;

const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const atomic = @import("../atomic.zig");
const queue = @import("../queue.zig");
const schedule = @import("../schedule.zig");
const time = @import("../time.zig");

pub fn testBody() !void {
    try stackManagement();
    try threadCreate();
    try threadSleep();
}

fn stackManagement() !void {
    const stack_size = 1024;
    const stack_addr = try schedule.stackCreate(stack_size);

    // Aarch64 stack must be 8-byte aligned.
    const stack_alignment = stack_addr & 0x07;
    expectEqual(@as(u64, 0), stack_alignment);

    const stack_top = schedule.stackSetup(stack_addr, stack_size, 0x12345678, 0xdeadbeef, 0x00abacab);
    _ = stack_top;

    // schedule.dumpContextRecord(stack_top);

    schedule.stackFree(stack_addr, stack_size);
}

fn threadCreate() !void {
    var counter: u64 = 0;
    var rendezvous: TArgs = .{&counter};

    const thread_id = try schedule.create(@intFromPtr(&exitImmediately), schedule.INITIAL_STACK_SIZE, 2 * schedule.DEFAULT_PRIORITY, "test", @intFromPtr(&rendezvous));

    // _ = printf("threadCreate: tid = %d\n", thread_id);

    const end_ticks = time.deadlineMillis(100);

    try schedule.ready(thread_id, true);

    // _ = printf("threadCreate: after call to ready\n");

    while (atomic.atomicFetch(&counter) == 0) {
        if (time.ticks() > end_ticks) {
            _ = printf("timeout waiting for thread to start\n");
            expect(false);
            return;
        }
    }
}

const TArgs = struct { *u64 };

fn exitImmediately(args: *TArgs) void {
    _ = atomic.atomicInc(args[0]);
    return;
}

fn threadSleep() !void {
    const start_sleep = (time.seconds_since_boot * time.QUANTA_PER_SECOND + time.quanta_since_boot);

    try schedule.sleep(1000);

    const end_sleep = (time.seconds_since_boot * time.QUANTA_PER_SECOND + time.quanta_since_boot);

    _ = printf("threadSleep: start = %d, end = %d (slept for %d)", start_sleep, end_sleep, (end_sleep - start_sleep));

    expect(end_sleep >= (start_sleep + 995) and end_sleep <= (start_sleep + 1005));
}
