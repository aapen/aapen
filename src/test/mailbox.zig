const root = @import("root");
const printf = root.printf;

const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const atomic = @import("../atomic.zig");
const mailbox = @import("../mailbox.zig");
const schedule = @import("../schedule.zig");
const time = @import("../time.zig");

const IntBox = mailbox.Mailbox(u32);
var mbox: IntBox = undefined;

pub fn testBody() !void {
    try createIntBox();
    try expectCount(0);

    try sendBasicMessages();
    try expectCount(4);

    try receiveBasicMessages();
    try expectCount(0);

    try sendAndReceiveWithBlocking();
    try expectCount(0);

    try destroyIntBox();
}

fn createIntBox() !void {
    try mbox.init(5);
}

fn expectCount(ex: IntBox.MailboxCapacity) !void {
    expectEqual(ex, mbox.count);
}

fn sendBasicMessages() !void {
    try mbox.send(12345);
    try mbox.send(9999);
    try mbox.send(0);
    try mbox.send(42);
}

fn receiveBasicMessages() !void {
    expectEqual(@as(u32, 12345), try mbox.receive());
    expectEqual(@as(u32, 9999), try mbox.receive());
    expectEqual(@as(u32, 0), try mbox.receive());
    expectEqual(@as(u32, 42), try mbox.receive());
}

fn sendAndReceiveWithBlocking() !void {
    var state: u64 = 0;

    _ = try schedule.spawn(sendManyMessages, "sender", &state);
    _ = try schedule.spawn(receiveManyMessages, "receiver", &state);

    const deadline = time.deadlineMillis(500);

    while (time.ticks() < deadline and state < 2) {}

    expectEqual(@as(u64, 2), state);
}

fn sendManyMessages(args: *anyopaque) void {
    const state: *u64 = @alignCast(@ptrCast(args));
    for (0..90) |v| {
        mbox.send(@truncate(v)) catch {
            expect(false);
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
        expectEqual(@as(u32, @truncate(i)), v);
    }

    _ = atomic.atomicInc(state);
}

fn destroyIntBox() !void {
    try mbox.deinit();
}
