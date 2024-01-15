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

const event = @import("event.zig");
const heartbeat = @import("heartbeat.zig");

const TaskDefinition = struct { []const u8, Task.Proc };

const task_definitions: []const TaskDefinition = &.{
    .{ "usb_poll", HAL.USBHCI.poll },
    .{ "heartbeat", heartbeat.heartbeat },
    .{ "kev_send", event.timerSignal },
    //    .{ "hb2", heartbeat.heartbeat2 },
};

const TID = u32;
pub var current_task: ?TID = null;

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

const quantum = 50_000;

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
    taskRun(roundRobin());
    return quantum;
}

fn taskRun(next_tid: ?TID) void {
    if (next_tid) |tid| {
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

fn roundRobin() ?TID {
    const first_considered = current_task orelse 0;
    var next: TID = first_considered + 1;
    if (next >= tasks.len) {
        next -= @truncate(tasks.len);
    }

    while (next != first_considered) {
        if (tasks[next].state == .ready) {
            return next;
        }
        next += 1;
        if (next >= tasks.len) {
            next -= @truncate(tasks.len);
        }
    }
    return null;
}
