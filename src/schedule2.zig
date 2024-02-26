const std = @import("std");
const root = @import("root");

const arch = @import("architecture.zig");
const cpu = arch.cpu;

pub const THREAD_FREE: u8 = 0; // thread table entry unused
pub const THREAD_RUNNING: u8 = 1; // thread currently running
pub const THREAD_READY: u8 = 2; // thread runnable
pub const THREAD_RECEIVING: u8 = 3; // thread waiting for message
pub const THREAD_SLEEP: u8 = 4; // thread sleeping
pub const THREAD_SUSPEND: u8 = 5; // thread suspended
pub const THREAD_WAIT: u8 = 6; // waiting on a semaphore

// TODO move this to a common "definitions" module
pub const NUM_THREADS = 128;

pub const TID = i16;
pub const NO_TID = -1;

pub const InterruptMask = u64;

pub const Thread = struct {
    state: u8,
    priority: u16,
    stack_pointer: u64,
    stack_base: u64,
    stack_length: usize,
    name: [16]u8,
    irq_mask: InterruptMask,

    pub fn init() Thread {
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

pub var threads: [NUM_THREADS]Thread = init: {
    var initial_value: [NUM_THREADS]Thread = undefined;
    for (&initial_value) |*t| {
        t.* = Thread.init();
    }
    break :init initial_value;
};

// currently executing thread
var current: TID = NO_TID;
pub inline fn isBadTid(t: TID) bool {
    return (t >= NUM_THREADS or t < 0 or THREAD_FREE == threads[@intCast(t)].state);
}

// pub fn reschedule() void {
//     const old = &threads[current];
//     old.irq_mask = cpu.disable();
// }
