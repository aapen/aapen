const std = @import("std");

const root = @import("root");
const HAL = root.HAL;

const heartbeat = @import("heartbeat.zig");

const task_definitions: []const TaskDefinition = &.{
    .{ 1, "heartbeat", heartbeat.heartbeat },
};

const Task = struct {
    priority: Priority = 0,
    name: []const u8,
    state: State = .ready,
    next_state: State = .ready,
    sleep_until: u64 = 0,
    entry: Proc,

    const Priority = u8;
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

const TaskDefinition = struct { Task.Priority, []const u8, Task.Proc };

const tasks: []Task = tasks: {
    var result: [task_definitions.len]Task = undefined;
    for (task_definitions, 0..) |td, i| {
        result[i] = Task{
            .priority = td[0],
            .name = td[1],
            .entry = td[2],
        };
    }
    break :tasks &result;
};

const quantum = 10_000;

const schedule_handler: HAL.TimerHandler = .{
    .callback = scheduleRun,
};

pub fn init() !void {
    root.hal.system_timer.schedule(quantum, &schedule_handler);
}

// TODO calculate this from reported clock frequency
const ticks_per_milli = 1000;

pub fn sleep(millis: u32) void {
    const now = root.hal.clock.ticks();

    if (currentRunningTask()) |task| {
        task.next_state = .sleeping;
        task.sleep_until = now + (millis * ticks_per_milli);
    }
}

fn currentRunningTask() ?*Task {
    for (tasks) |*t| {
        if (t.state == .running) {
            return t;
        }
    }
    return null;
}

fn scheduleRun(_: *const HAL.TimerHandler, _: *HAL.Timer) u32 {
    awakenSleepingTasks();

    if (nextReadyTask()) |next| {
        next.next_state = .ready;
        next.state = .running;
        if (next.entry()) {
            next.state = next.next_state;
        } else |_| {
            next.state = .failed;
        }
    }

    return quantum;
}

fn awakenSleepingTasks() void {
    const now = root.hal.clock.ticks();

    for (tasks) |*t| {
        if (t.state == .sleeping and t.sleep_until <= now) {
            t.state = .ready;
        }
    }
}

fn nextReadyTask() ?*Task {
    var best_candidate: ?*Task = null;
    var max_pri: Task.Priority = 0;

    for (tasks) |*t| {
        if (t.state == .ready) {
            if (t.priority > max_pri) {
                max_pri = t.priority;
                best_candidate = t;
            }
        }
    }
    return best_candidate;
}
