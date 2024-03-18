const std = @import("std");

const root = @import("root");
const printf = root.printf;

const arch = @import("architecture.zig");
const cpu = arch.cpu;

const queue = @import("queue.zig");
const Key = queue.Key;
const QID = queue.QID;

const schedule = @import("schedule.zig");

pub const Error = error{
    NoMoreSemaphores,
    BadSemaphoreId,
    BadCount,
};

pub const NUM_SEMAPHORES = 128;

pub const SID = i16;
pub const NO_SEM: SID = -1;

pub const SEMAPHORE_FREE: u8 = 0x01;
pub const SEMAPHORE_USED: u8 = 0x02;

pub const SemaphoreState = u8;
pub const SemaphoreCount = i16;

pub const SemaphoreEntry = struct {
    state: SemaphoreState,
    queue: QID,
    count: SemaphoreCount,

    pub fn init() SemaphoreEntry {
        return .{
            .state = SEMAPHORE_FREE,
            .queue = queue.QEMPTY,
            .count = 0,
        };
    }
};

pub var semaphore_table: [NUM_SEMAPHORES]SemaphoreEntry = init: {
    var initial_value: [NUM_SEMAPHORES]SemaphoreEntry = undefined;
    for (&initial_value) |*s| {
        s.* = SemaphoreEntry.init();
    }
    break :init initial_value;
};

pub fn init() !void {
    for (&semaphore_table) |*s| {
        s.state = SEMAPHORE_FREE;
        s.queue = try queue.allocate();
    }
    nextsem = 0;
}

// ----------------------------------------------------------------------
// Public API
// ----------------------------------------------------------------------

pub fn create(cnt: SemaphoreCount) !SID {
    const im = cpu.disable();
    defer cpu.restore(im);

    const sid = try allocate();
    const sem = sement(sid);
    sem.count = cnt;
    return sid;
}

pub fn free(sid: SID) !void {
    if (isBadSid(sid)) return error.BadSemaphoreId;

    const im = cpu.disable();
    defer cpu.restore(im);

    const sem = sement(sid);
    while (queue.nonEmpty(sem.queue)) {
        const tid = try queue.dequeue(sem.queue);
        try schedule.ready(tid, false);
    }
    sem.count = 0;
    sem.state = SEMAPHORE_FREE;
}

pub fn count(sid: SID) !SemaphoreCount {
    if (isBadSid(sid)) return error.BadSemaphoreId;
    return sement(sid).count;
}

pub fn wait(sid: SID) !void {
    if (isBadSid(sid)) return error.BadSemaphoreId;

    const im = cpu.disable();
    defer cpu.restore(im);

    const thr = schedule.thrent(schedule.current);
    const sem = sement(sid);
    sem.count -= 1;
    if (sem.count < 0) {
        thr.state = schedule.THREAD_WAIT;
        thr.semaphore = sid;
        _ = try queue.enqueue(schedule.current, sem.queue);
        schedule.reschedule();
    }
}

pub fn signal(sid: SID) !void {
    if (isBadSid(sid)) return error.BadSemaphoreId;

    const im = cpu.disable();
    defer cpu.restore(im);

    const sem = sement(sid);

    const old = sem.count;
    sem.count += 1;
    if (old < 0) {
        const waiting_tid = try queue.dequeue(sem.queue);
        try schedule.ready(waiting_tid, true);
    }
}

pub fn signalN(sid: SID, cnt: SemaphoreCount) !void {
    if (isBadSid(sid)) return error.BadSemaphoreId;
    if (cnt == 0) return error.BadCount;

    const im = cpu.disable();
    defer cpu.restore(im);

    const sem = sement(sid);
    for (0..cnt) |_| {
        sem.count += 1;
        if (sem.count <= 0) {
            schedule.ready(queue.dequeue(sem.queue), false);
        }
    }

    schedule.reschedule();
}

// ----------------------------------------------------------------------
// Internals
// ----------------------------------------------------------------------

var nextsem: SID = 0;

pub fn allocate() !SID {
    for (0..NUM_SEMAPHORES) |s| {
        _ = s;
        nextsem = @mod((nextsem + 1), NUM_SEMAPHORES);
        if (SEMAPHORE_FREE == sement(nextsem).state) {
            sement(nextsem).state = SEMAPHORE_USED;
            return nextsem;
        }
    }
    return Error.NoMoreSemaphores;
}

// ----------------------------------------------------------------------
// Table manipulation
// ----------------------------------------------------------------------

/// Convenience for indexing into the table with an i16
/// Caller MUST verify the value is non-negative
pub inline fn sement(x: SID) *SemaphoreEntry {
    return &semaphore_table[@intCast(x)];
}

pub inline fn isBadSid(x: SID) bool {
    return (x >= NUM_SEMAPHORES or SEMAPHORE_FREE == sement(x).state);
}
