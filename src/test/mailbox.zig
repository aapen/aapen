const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const printf = root.printf;

const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const atomic = @import("../atomic.zig");
const Mailbox = @import("../mailbox.zig").Mailbox;
const schedule = @import("../schedule.zig");
const time = @import("../time.zig");

var mbox: Mailbox(u32, 5) = undefined;

pub fn testBody() !void {
    try mbox.init();

    try expectCount(0);

    try sendBasicMessages();
    try expectCount(4);

    try receiveBasicMessages();
    try expectCount(0);

    try sendAndReceiveWithBlocking();
    try expectCount(0);

    try destroyIntBox();
}

fn createIntBox(allocator: Allocator) !void {
    try mbox.init(allocator, 5);
}

fn expectCount(ex: u16) !void {
    expectEqual(@src(), ex, mbox.count);
}

fn sendBasicMessages() !void {
    try mbox.send(12345);
    try mbox.send(9999);
    try mbox.send(0);
    try mbox.send(42);
}

fn receiveBasicMessages() !void {
    expectEqual(@src(), @as(u32, 12345), try mbox.receive());
    expectEqual(@src(), @as(u32, 9999), try mbox.receive());
    expectEqual(@src(), @as(u32, 0), try mbox.receive());
    expectEqual(@src(), @as(u32, 42), try mbox.receive());
}

fn sendAndReceiveWithBlocking() !void {
    var state: u64 = 0;

    _ = try schedule.spawn(sendManyMessages, "sender", &state);
    _ = try schedule.spawn(receiveManyMessages, "receiver", &state);

    const deadline = time.deadlineMillis(500);

    while (time.ticks() < deadline and state < 2) {}

    expectEqual(@src(), @as(u64, 2), state);
}

fn sendManyMessages(args: *anyopaque) void {
    const state: *u64 = @alignCast(@ptrCast(args));
    for (0..90) |v| {
        mbox.send(@truncate(v)) catch {
            expect(@src(), false);
        };
    }

    _ = atomic.atomicInc(state);
}

fn receiveManyMessages(args: *anyopaque) void {
    schedule.sleep(10) catch {
        _ = printf("Can't sleep, clown will eat me.\n");
    };

    const state: *u64 = @alignCast(@ptrCast(args));
    for (0..90) |i| {
        const v = mbox.receive() catch 0;
        expectEqual(@src(), @as(u32, @truncate(i)), v);
    }

    _ = atomic.atomicInc(state);
}

fn destroyIntBox() !void {
    try mbox.deinit();
}
