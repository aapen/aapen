const root = @import("root");
const printf = root.printf;

const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const atomic = @import("../atomic.zig");
const queue = @import("../queue.zig");
const schedule = @import("../schedule2.zig");
const time = @import("../time.zig");

pub fn testBody() !void {
    try stackManagement();
    try threadCreate();
    //    try threadSleep();
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
    var end_sleep: u64 = 0;
    var rendezvous: TArgs = .{&end_sleep};

    const thread_id = try schedule.create(@intFromPtr(&exitImmediately), schedule.INITIAL_STACK_SIZE, 2 * schedule.DEFAULT_PRIORITY, "test", @intFromPtr(&rendezvous));

    // _ = printf("threadCreate: tid = %d\n", thread_id);

    const thread_finish_deadline = time.deadlineMillis(100);

    const q = time.quanta_since_boot;
    const s = time.seconds_since_boot;
    const start_sleep = (s * time.QUANTA_PER_SECOND + q);

    try schedule.ready(thread_id, true);

    // _ = printf("threadCreate: after call to ready\n");

    while (atomic.atomicFetch(&end_sleep) == 0) {
        if (time.ticks() > thread_finish_deadline) {
            _ = printf("timeout waiting for thread to start\n");
            expect(false);
            return;
        }
    }

    if (end_sleep >= (start_sleep + 2500)) {
        expect(true);
    } else {
        _ = printf("threadSleep: start = %d, end = %d (slept for %d?)\n", start_sleep, end_sleep, (end_sleep - start_sleep));
        expect(false);
    }
}

fn sleepTwoSeconds(args: *TArgs) void {
    try schedule.sleep(2500);

    const end_time = (time.seconds_since_boot * time.QUANTA_PER_SECOND + time.quanta_since_boot);
    atomic.atomicReset(args[0], end_time);
}
