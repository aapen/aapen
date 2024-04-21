const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const root = @import("root");
const printf = root.printf;

const schedule = @import("../schedule.zig");

const semaphore = @import("../semaphore.zig");
const SID = semaphore.SID;

pub fn testBody() !void {
    const sid = try semaphoreCreate();
    try semaphoreDownNoWait(sid);
    try semaphoreDownWithWait(sid);
}

fn expectCount(cnt: semaphore.SemaphoreCount, s: SID) !void {
    expectEqual(cnt, try semaphore.count(s));
}

fn semaphoreCreate() !SID {
    const s = try semaphore.create(1);
    expect(@src(), s > 0);
    try expectCount(1, s);
    return s;
}

fn semaphoreDownNoWait(s: SID) !void {
    try expectCount(1, s);
    try semaphore.wait(s);
    try expectCount(0, s);
}

const SIGNAL_DELAY = 100;

fn semaphoreDownWithWait(s: SID) !void {
    // after previous tests, sem should have count 0, which means a
    // `wait` will block
    try expectCount(0, s);

    var args: TArgs = .{ .s = s };

    _ = try schedule.spawn(downTheSemaphore, "down it", &args);
    _ = try schedule.spawn(upTheSemaphore, "up it", &args);

    schedule.sleep(2 * SIGNAL_DELAY) catch |err| {
        _ = printf("semaphoreDownWithWait(%d): sleep error %s\n", s, @errorName(err).ptr);
    };
}

const TArgs = struct {
    s: SID,
};

fn downTheSemaphore(args_o: *anyopaque) void {
    const args: *TArgs = @alignCast(@ptrCast(args_o));

    // const count_before: semaphore.SemaphoreCount = semaphore.count(args.s) catch -1;
    // _ = printf("downTheSemaphore(%d): count is %d\n", args.s, count_before);
    // _ = printf("downTheSemaphore(%d): wait\n", args.s);

    semaphore.wait(args.s) catch |err| {
        _ = printf("downTheSemaphore(%d): wait error %s\n", args.s, @errorName(err).ptr);
    };

    expectCount(0, args.s) catch |err| {
        _ = printf("downTheSemaphore(%d): count error %s\n", args.s, @errorName(err).ptr);
    };

    // const count_after: semaphore.SemaphoreCount = semaphore.count(args.s) catch -1;
    // _ = printf("downTheSemaphore(%d): count is %d\n", args.s, count_after);
}

fn upTheSemaphore(args_o: *anyopaque) void {
    const args: *TArgs = @alignCast(@ptrCast(args_o));

    // const count_before: semaphore.SemaphoreCount = semaphore.count(args.s) catch -1;
    // _ = printf("upTheSemaphore(%d): count is %d\n", args.s, count_before);
    // _ = printf("upTheSemaphore(%d): sleep(%d)\n", args.s, @as(u16, SIGNAL_DELAY));

    schedule.sleep(SIGNAL_DELAY) catch |err| {
        _ = printf("upTheSemaphore(%d): sleep error %s\n", args.s, @errorName(err).ptr);
    };

    semaphore.signal(args.s) catch |err| {
        _ = printf("upTheSemaphore(%d): signal error %s\n", args.s, @errorName(err).ptr);
    };

    // const count_after: semaphore.SemaphoreCount = semaphore.count(args.s) catch -1;
    // _ = printf("upTheSemaphore(%d): count is %d\n", args.s, count_after);
}
