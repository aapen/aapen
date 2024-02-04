const std = @import("std");

const arch = @import("architecture.zig");
const cpu = arch.cpu;

const queue = @import("queue.zig");
const Key = queue.Key;
const QID = queue.QID;

pub const Error = error{
    NoMoreThreads,
};

pub const THREAD_FREE: u8 = 0; // thread table entry unused
pub const THREAD_RUNNING: u8 = 1; // thread currently running
pub const THREAD_READY: u8 = 2; // thread runnable
pub const THREAD_RECEIVING: u8 = 3; // thread waiting for message
pub const THREAD_SLEEP: u8 = 4; // thread sleeping
pub const THREAD_SUSPEND: u8 = 5; // thread suspended
pub const THREAD_WAIT: u8 = 6; // waiting on a semaphore

// TODO move this to a common "definitions" module
pub const NUM_THREAD_ENTRIES = 128;

// TODO move this to a common "definitions" module
pub const INITIAL_STACK_SIZE: u64 = 0x20000;
pub const MIN_STACK_SIZE: u64 = 0x80;
pub const INITIAL_PRIORITY: Key = 0x20;

pub const TID = i16;
pub const NO_TID = -1;

// currently executing thread
var current: TID = NO_TID;
var thread_count: u16 = 0;

// queue of threads ready to run
var readylist: QID = undefined;

pub const InterruptMask = u64;

pub const ThreadEntry = struct {
    state: u8,
    priority: u16,
    stack_pointer: u64,
    stack_base: u64,
    stack_length: usize,
    name: [16]u8,
    irq_mask: InterruptMask,

    pub fn init() ThreadEntry {
        return .{
            .state = THREAD_FREE,
            .priority = 0,
            .stack_pointer = undefined,
            .stack_base = undefined,
            .stack_length = undefined,
            .name = undefined,
            .irq_mask = 0,
        };
    }
};

pub var thread_table: [NUM_THREAD_ENTRIES]ThreadEntry = init: {
    var initial_value: [NUM_THREAD_ENTRIES]ThreadEntry = undefined;
    for (&initial_value) |*t| {
        t.* = ThreadEntry.init();
    }
    break :init initial_value;
};

pub fn init() void {
    readylist = queue.allocate();
    current = NO_TID;
    nexttid = 0;
}

pub fn create(proc: u64, ssize: u64, priority: Key, name: []const u8, args_ptr: u64) !void {
    _ = args_ptr;
    _ = proc;
    const im = cpu.disable();
    defer cpu.restore(im);

    const stack_size = @max(ssize, MIN_STACK_SIZE);
    const stack_addr: u64 = 0;
    //    const stack_addr = try stackCreate(stack_size);
    // errdefer stackFree(stack_addr, stack_size);

    const tid = try allocate();

    thread_count += 1;
    const thr = thrent(tid);

    thr.state = THREAD_SUSPEND;
    thr.priority = priority;
    thr.stack_base = stack_addr;
    thr.stack_length = stack_size;
    @memcpy(thr.name, name);
    //    thr.stack_pointer = stackSetup(stack_addr, proc, args_ptr);
}

pub fn reschedule() void {
    const old: *ThreadEntry = thrent(current);
    var new: *ThreadEntry = undefined;

    old.irq_mask = cpu.disable();

    if (THREAD_RUNNING == old.state) {
        if (queue.nonEmpty(readylist) and old.priority > queue.firstKey(readylist)) {
            // the current thread is still the highest priority
            cpu.restore(old.irq_mask);
            return;
        }

        old.state = THREAD_READY;
        queue.insert(current, readylist, old.priority);
    }

    current = queue.dequeue(readylist);
    new = thrent(current);
    new.state = THREAD_RUNNING;

    cpu.contextSwitch(old.stack_pointer, new.stack_pointer);

    // IMPORTANT: contextSwitch returns here once the _old_ thread
    // resumes. When it switches to the _new_ thread, it returns with
    // _that_ thread's stack (and therefore, _that_ thread's value of
    // `old` and `new`)

    cpu.restore(old.irq_mask);
}

// ----------------------------------------------------------------------
// Low level functions
// ----------------------------------------------------------------------

var nexttid: TID = 0;

pub fn allocate() !TID {
    for (0..NUM_THREAD_ENTRIES) |t| {
        _ = t;
        nexttid = (nexttid + 1) % NUM_THREAD_ENTRIES;
        if (THREAD_FREE == thrent(nexttid).state) {
            return nexttid;
        }
    }
    return Error.NoMoreThreads;
}

/// Convenience for indexing into the table with an i16
/// Caller MUST verify the value is non-negative
pub inline fn thrent(x: TID) *ThreadEntry {
    return &thread_table[@intCast(x)];
}

// ----------------------------------------------------------------------
// Table manipulation
// ----------------------------------------------------------------------
pub inline fn isBadTid(tid: TID) bool {
    return (tid >= NUM_THREAD_ENTRIES or tid < 0 or THREAD_FREE == thrent(tid).state);
}

// ----------------------------------------------------------------------
// Test and debug support
// ----------------------------------------------------------------------
pub fn reinit() void {
    // reinitialize between test cases
    for (&thread_table) |*thr| {
        thr.* = ThreadEntry.init();
    }

    nexttid = 0;
}

pub fn dumpThread(tid: TID) void {
    const root = @import("root");
    const printf = root.printf;

    if (tid >= NUM_THREAD_ENTRIES or tid < 0) {
        _ = printf("bad thread id: %d\n", tid);
        return;
    }

    if (thrent(tid).state == THREAD_FREE) {
        _ = printf("thread free: %d\n", tid);
        return;
    }
}
