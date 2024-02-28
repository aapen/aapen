const std = @import("std");

const root = @import("root");
const printf = root.printf;
const kernelExit = root.kernelExit;

const arch = @import("architecture.zig");
const cpu = arch.cpu;

const queue = @import("queue.zig");
const Key = queue.Key;
const QID = queue.QID;

const semaphore = @import("semaphore.zig");
const SID = semaphore.SID;

const time = @import("time.zig");

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
pub const THREAD_TIMEOUT: u8 = 7; // timed out waiting for event

// TODO move this to a common "definitions" module
pub const NUM_THREADS = 128;

// TODO move this to a common "definitions" module
pub const INITIAL_STACK_SIZE: u64 = 0x20000;
pub const MIN_STACK_SIZE: u64 = (2 * 8 * CONTEXT_WORDS);

// TODO move this to a common "definitions" module
pub const DEFAULT_PRIORITY: Key = 100;

pub const TID = i16;
pub const NULL_THREAD: TID = 0;
pub const NO_TID: TID = -1;
pub const NAME_LEN = 16;

/// currently executing thread
pub var current: TID = 0;

/// number of live threads
var thread_count: u16 = 0;

/// queue of threads ready to run
var readyq: QID = undefined;

/// queue of sleeping threads
pub var sleepq: QID = undefined;

pub const InterruptMask = u32;

extern fn context_switch(old_context_ptr: *u64, new_context_ptr: *u64) void;

pub const ThreadEntry = struct {
    state: u8,
    priority: Key,
    stack_pointer: u64,
    stack_base: u64,
    stack_length: usize,
    name: [NAME_LEN]u8,
    semaphore: SID,
    irq_mask: InterruptMask,

    pub fn init() ThreadEntry {
        return .{
            .state = THREAD_FREE,
            .priority = 0,
            .stack_pointer = undefined,
            .stack_base = undefined,
            .stack_length = undefined,
            .name = undefined,
            .semaphore = undefined,
            .irq_mask = 0,
        };
    }
};

pub var thread_table: [NUM_THREADS]ThreadEntry = init: {
    var initial_value: [NUM_THREADS]ThreadEntry = undefined;
    for (&initial_value) |*t| {
        t.* = ThreadEntry.init();
    }

    break :init initial_value;
};

pub fn init() !void {
    readyq = try queue.allocate();
    sleepq = try queue.allocate();
    current = NULL_THREAD;
    thread_table[NULL_THREAD].stack_pointer = @intFromPtr(&null_thread_dummy_context);
}

/// Configure the kernel's main thread of execution as thread0 in the
/// table. This should be done exactly once during boot.
pub fn becomeThread0(kernel_stack_top: u64, kernel_stack_size: u64) void {
    const thr0 = thrent(0);
    strncpy(thr0.name[0..NAME_LEN], "null");
    thr0.state = THREAD_RUNNING;
    thr0.priority = queue.MINKEY + 1;
    thr0.stack_base = kernel_stack_top - kernel_stack_size;
    thr0.stack_length = kernel_stack_size;
    // the stack pointer will be overwritten on first context change
    thr0.stack_pointer = 0;

    current = 0;
}

// ----------------------------------------------------------------------
// Thread control
// ----------------------------------------------------------------------

pub const SpawnOptions = struct {
    stack_size: u64 = INITIAL_STACK_SIZE,
    priority: Key = DEFAULT_PRIORITY,
    name: []const u8,
};

pub const ThreadFunction = *const fn (*anyopaque) void;

/// High level function to create and ready a thread in one step.
pub fn spawn(proc: ThreadFunction, name: []const u8, args: *anyopaque) !TID {
    return spawnWithOptions(proc, args, &SpawnOptions{ .name = name });
}

pub fn spawnWithOptions(proc: ThreadFunction, args: *anyopaque, options: *const SpawnOptions) !TID {
    const tid = try create(
        @intFromPtr(proc),
        options.stack_size,
        options.priority,
        options.name,
        @intFromPtr(args),
    );
    try ready(tid, true);
    return tid;
}

pub fn create(proc: u64, ssize: u64, priority: Key, name: []const u8, args_ptr: u64) !TID {
    // _ = printf("create: current is %d, thread_count is %d\n", current, thread_count);

    const im = cpu.disable();
    defer cpu.restore(im);

    const stack_size = @max(ssize, MIN_STACK_SIZE);
    const stack_addr = try stackCreate(stack_size);
    errdefer stackFree(stack_addr, stack_size);

    const tid = try allocate();

    thread_count += 1;

    // _ = printf("thread_count now %d\n", thread_count);

    const thr = thrent(tid);

    thr.state = THREAD_SUSPEND;
    thr.priority = priority;
    thr.stack_base = stack_addr;
    thr.stack_length = stack_size;
    strncpy(thr.name[0..NAME_LEN], name);
    thr.stack_pointer = stackSetup(stack_addr, stack_size, proc, @intFromPtr(&threadExit), args_ptr);

    return tid;
}

pub fn ready(tid: TID, resched: bool) !void {
    // _ = printf("ready: tid is %d, reschedule? %b\n", tid, resched);

    if (isBadTid(tid)) {
        return error.BadThreadId;
    }

    const thr = thrent(tid);
    thr.state = THREAD_READY;

    try queue.insert(tid, thr.priority, readyq);

    // _ = printf("ready: readylist after insert");
    // queue.dumpQ(readylist);

    if (resched) {
        reschedule();
    }
}

fn kill(tid: TID) void {
    // _ = printf("kill tid %d, current is %d\n", tid, current);

    const im = cpu.disable();
    defer cpu.restore(im);

    if (isBadTid(tid) or tid == NULL_THREAD) return;

    const thr: *ThreadEntry = thrent(tid);

    thread_count -= 1;

    // _ = printf("thread_count now %d\n", thread_count);

    if (thread_count < 1) {
        // _ = printf("last thread finished, time to exit\n");
        kernelExit();
    }

    // signal parent thread? do we need a concept of parent thread?
    stackFree(thr.stack_base, thr.stack_length);

    // depending on the thread's state, we have some bookkeeping to do
    switch (thr.state) {
        THREAD_SLEEP => {
            // TODO remove from sleep queue
            unsleep(tid) catch {};
        },
        THREAD_RUNNING => {
            thr.state = THREAD_FREE;
            reschedule();
        },
        THREAD_WAIT => {
            semaphore.sement(thr.semaphore).count += 1;
            _ = queue.getItem(tid); // remove thread from all queues
        },
        THREAD_READY => {
            _ = queue.getItem(tid); // remove thread from all queues
        },
        else => {},
    }

    thr.state = THREAD_FREE;
}

pub fn sleep(millis: u32) !void {
    const ticks: u32 = @truncate(@min(millis * time.QUANTA_PER_MILLI, std.math.maxInt(u32)));

    const im = cpu.disable();
    defer cpu.restore(im);

    try queue.insertDelta(current, ticks, sleepq);
    thrent(current).state = THREAD_SLEEP;
    reschedule();
}

pub fn unsleep(tid: TID) !void {
    if (isBadTid(tid)) return error.BadThreadId;

    const im = cpu.disable();
    defer cpu.restore(im);

    const thr = thrent(tid);
    if (thr.state != THREAD_SLEEP and thr.state != THREAD_TIMEOUT) {
        return error.NotSleeping;
    }
    const next = queue.quetab(tid).next;
    if (next < NUM_THREADS) {
        queue.quetab(next).key += queue.quetab(tid).key;
    }
    _ = queue.getItem(tid); // removes thread from its queue
}

/// Ready all threads that should be done sleeping
pub fn wakeup() void {
    while (queue.nonEmpty(sleepq) and queue.firstKey(sleepq) <= 0) {
        if (queue.dequeue(sleepq)) |tid| {
            _ = ready(tid, false) catch {};
        } else |_| {
            // complain?
        }
    }
    reschedule();
}

// ----------------------------------------------------------------------
// Internals
// ----------------------------------------------------------------------

pub fn reschedule() void {
    const old: *ThreadEntry = thrent(current);
    var new: *ThreadEntry = undefined;

    old.irq_mask = cpu.disable();

    //    _ = printf("reschedule: old tid is %d, old state is %d\n", current, old.state);

    if (THREAD_RUNNING == old.state) {
        if (queue.nonEmpty(readyq) and old.priority > queue.firstKey(readyq)) {
            // the current thread is still the highest priority, keep
            // running it
            cpu.restore(old.irq_mask);
            return;
        }

        old.state = THREAD_READY;

        //        _ = printf("reschedule: old thread is still runnable. inserting %d to readylist\n", current);

        queue.insert(current, old.priority, readyq) catch {};
    }

    var next_tid: TID = NO_TID;

    //    _ = printf("reschedule: readylist ");
    // queue.dumpQ(readylist);

    while (isBadTid(next_tid)) {
        next_tid = queue.dequeue(readyq) catch NO_TID;

        if (next_tid == NO_TID) {
            cpu.wfe();
        } else {
            //            _ = printf("reschedule: selected %d\n", next_tid);
        }
    }

    current = next_tid;
    new = thrent(current);
    new.state = THREAD_RUNNING;

    //    _ = printf("reschedule: current is now %d, current state is now %d\n", current, new.state);
    //    _ = printf("reschedule: &old.stack_pointer = 0x%08x, &new.stack_pointer = 0x%08x\n", &old.stack_pointer, &new.stack_pointer);
    // _ = printf("reschedule: old.stack_pointer = 0x%08x, new.stack_pointer = 0x%08x\n", old.stack_pointer, new.stack_pointer);

    context_switch(&old.stack_pointer, &new.stack_pointer);

    // IMPORTANT: contextSwitch returns here once the _old_ thread
    // resumes. When it switches to the _new_ thread, it returns with
    // _that_ thread's stack (and therefore, _that_ thread's value of
    // `old` and `new`)

    cpu.restore(old.irq_mask);
}

fn threadExit() void {
    kill(current);
}

var nexttid: TID = 0;

pub fn allocate() !TID {
    for (0..NUM_THREADS) |t| {
        _ = t;
        nexttid = @mod((nexttid + 1), NUM_THREADS);
        if (THREAD_FREE == thrent(nexttid).state) {
            return nexttid;
        }
    }
    return Error.NoMoreThreads;
}

fn strncpy(dst: []u8, src: []const u8) void {
    const l = @min(dst.len, src.len);
    for (0..l) |i| {
        dst[i] = src[i];
    }
}

// ----------------------------------------------------------------------
// Table manipulation
// ----------------------------------------------------------------------

/// Convenience for indexing into the table with an i16
/// Caller MUST verify the value is non-negative
pub inline fn thrent(x: TID) *ThreadEntry {
    return &thread_table[@intCast(x)];
}

pub inline fn isBadTid(tid: TID) bool {
    return (tid >= NUM_THREADS or tid < 0 or THREAD_FREE == thrent(tid).state);
}

// ----------------------------------------------------------------------
// Stack management
// ----------------------------------------------------------------------

// A thread's stack starts with the thread's context record, used when
// switching to the thread. Below that is the first activation frame
// that represents invocation of the thread's main function.
//
// Register state when the thread starts:
//
// x0 - pointer to struct of launch arguments. (Zig is bad with
//      varargs, so we allow only a single struct pointer as launch
//      arguments for the new thread. Those go in x0 when the thread
//      starts
// fp - points to low address of the context record
// lr - points to address of thread exit routine
// sp - points to low address of the context record

pub fn stackCreate(stack_size: usize) !u64 {
    const stack_slice = try root.kernel_allocator.alloc(u8, stack_size);
    return @intFromPtr(stack_slice.ptr);
}

pub fn stackFree(stack_addr: u64, stack_size: usize) void {
    const stack_ptr: [*]u8 = @ptrFromInt(stack_addr);
    const stack_slice: []u8 = stack_ptr[0..stack_size];
    const stack_align = @typeInfo(*u8).Pointer.alignment;
    root.kernel_allocator.rawFree(stack_slice, stack_align, @returnAddress());
}

const CONTEXT_WORDS: usize = 24;
const FIQ_MASKED: u64 = 1 << 6;
const IRQ_MASKED: u64 = 1 << 7;
const NEW_THREAD_FRAME_POINTER: u64 = 0;
const NEW_THREAD_DAIF: u64 = FIQ_MASKED;
const NEW_THREAD_NZCV: u64 = 0;

const null_thread_dummy_context: [CONTEXT_WORDS]u64 = undefined;

pub fn stackSetup(stack_addr: u64, stack_size: usize, proc_addr: u64, return_addr: u64, args_ptr: u64) u64 {
    const stack_lowest_addr: [*]u8 = @ptrFromInt(stack_addr);
    const stack_highest_addr: [*]u8 = stack_lowest_addr + stack_size;

    const stack_highest_addr_words: [*]u64 = @alignCast(@ptrCast(stack_highest_addr));

    const frame_bottom: [*]u64 = stack_highest_addr_words - CONTEXT_WORDS;

    // context frame is laid out from high addr to low addr, but when
    // accessing as an array we index from the lowest word. So there's
    // a kind of double-negative happening here. E.g., we want the
    // address of the target proc to be the first entry in the stack,
    // which means it goes at the highest address.
    //
    // this layout must match that expected by context_switch.S

    for (3..CONTEXT_WORDS - 4) |i| {
        frame_bottom[i] = 0;
    }

    // place proc_addr where the pc will be loaded from
    frame_bottom[CONTEXT_WORDS - 2] = proc_addr;
    frame_bottom[CONTEXT_WORDS - 3] = return_addr;
    frame_bottom[CONTEXT_WORDS - 4] = NEW_THREAD_FRAME_POINTER;

    frame_bottom[2] = args_ptr; // place args_ptr where x0 will be pulled from
    frame_bottom[1] = NEW_THREAD_NZCV;
    frame_bottom[0] = NEW_THREAD_DAIF;

    return @intFromPtr(frame_bottom);
}

// ----------------------------------------------------------------------
// Test and debug support
// ----------------------------------------------------------------------
pub fn reinit() !void {
    // reinitialize between test cases
    for (&thread_table) |*thr| {
        thr.* = ThreadEntry.init();
    }

    try init();
}

pub fn dumpThread(tid: TID) void {
    if (tid >= NUM_THREADS or tid < 0) {
        _ = printf("bad thread id: %d\n", tid);
        return;
    }

    if (thrent(tid).state == THREAD_FREE) {
        _ = printf("thread free: %d\n", tid);
        return;
    }
}

const context_record_field_names = [_][]const u8{
    "daif",
    "nzcv",
    "lr (x30)",
    "fp (x29)",
    "x17",
    "x16",
    "x15",
    "x14",
    "x13",
    "x12",
    "x11",
    "x10",
    "x9",
    "x8",
    "x7",
    "x6",
    "x5",
    "x4",
    "x3",
    "x2",
    "x1",
    "x0",
    "fp",
    "lr",
    "saved pc",
    "zero fill",
};

pub fn dumpContextRecord(stack_bottom: u64) void {
    _ = printf("Thread context at 0x%08x\n", stack_bottom);
    const stack_ptr: [*]u64 = @ptrFromInt(stack_bottom);
    for (0..CONTEXT_WORDS) |i| {
        _ = printf("[0x%08x] (%02d): 0x%08x    %s\n", @intFromPtr(&stack_ptr[i]), i, stack_ptr[i], context_record_field_names[i].ptr);
    }
}
