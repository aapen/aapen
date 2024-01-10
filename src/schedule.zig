/// Schedule tasks to run on a recurring basis
///
/// This is not a "real" scheduler, in the sense of tasks and threads
/// with different CPU contexts. It's more like a timer interrupt that
/// mulitplexes out to different Zig function calls. It relies on the
/// function calls to return quickly.
///
/// The task definitions are comptime so the table of tasks to execute
/// cannot be changed while the system is running.
///
/// This has an advantage of simplicity at this point, since we don't
/// need to deal with multiple stacks, register contexts, etc.
///
/// The "main thread" continues to execute normally and is
/// periodically interrupted by the timer. The selected task's `entry`
/// function is called in an interrupt context.
const std = @import("std");

const root = @import("root");
const HAL = root.HAL;

const heartbeat = @import("heartbeat.zig");

const TaskDefinition = struct { []const u8, Task.Proc };

const task_definitions: []const TaskDefinition = &.{
    .{ "heartbeat", heartbeat.heartbeat },
    //    .{ "hb2", heartbeat.heartbeat2 },
};

const TID = usize;
pub var current_task: ?TID = 0;

const Task = struct {
    name: []const u8,
    state: State = .ready,
    next_state: State = .ready,
    sleep_until: u64 = 0,
    entry: Proc,

    const State = enum {
        ready,
        running,
        sleeping,
        //        running,
        suspended,
        failed,
    };
    const Proc = *const fn () Error!void;
    const Error = error{
        Fatal,
    };
};

pub const tasks: []Task = tasks: {
    var result: [task_definitions.len]Task = undefined;
    for (task_definitions, 0..) |td, i| {
        result[i] = Task{
            .name = td[0],
            .entry = td[1],
        };
    }
    break :tasks &result;
};

const quantum = 20_000;

const schedule_handler: HAL.TimerHandler = .{
    .callback = scheduleRun,
};

pub fn init() !void {
    root.hal.system_timer.schedule(quantum, &schedule_handler);
}

// TODO calculate this from reported clock frequency
const ticks_per_milli = 1000;

/// Pause a background task for some time. Note that this _only_ works
/// when called from a background task in `task_definitions` that was
/// invoked from this scheduler
pub fn sleep(millis: u32) void {
    const now = root.hal.clock.ticks();

    if (current_task) |tid| {
        tasks[tid].next_state = .sleeping;
        tasks[tid].sleep_until = now + (millis * ticks_per_milli);
    }
}

fn scheduleRun(_: *const HAL.TimerHandler, _: *HAL.Timer) u32 {
    awakenSleepingTasks();
    taskRun(firstReadyTask());
    return quantum;
}

fn taskRun(maybe_tid: ?TID) void {
    if (maybe_tid) |tid| {
        var task_to_run: *Task = &tasks[tid];
        task_to_run.next_state = .ready;
        task_to_run.state = .running;
        current_task = tid;
        if (task_to_run.entry()) {
            task_to_run.state = task_to_run.next_state;
        } else |_| {
            task_to_run.state = .failed;
        }
    }
}

fn awakenSleepingTasks() void {
    const now = root.hal.clock.ticks();

    for (tasks) |*t| {
        if (t.state == .sleeping and t.sleep_until <= now) {
            t.state = .ready;
        }
    }
}

fn firstReadyTask() ?TID {
    for (0..tasks.len) |next| {
        if (tasks[next].state == .ready) {
            return next;
        }
    }
    return null;
}
