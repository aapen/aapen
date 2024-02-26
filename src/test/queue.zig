const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const root = @import("root");
const printf = root.printf;

const queue = @import("../queue.zig");
const MAXKEY = queue.MAXKEY;
const MINKEY = queue.MINKEY;
const QEMPTY = queue.QEMPTY;
const QNULL = @as(queue.QID, QEMPTY);
const quetab = queue.quetab;
const quehead = queue.quehead;
const quetail = queue.quetail;

const schedule2 = @import("../schedule2.zig");
const TID = schedule2.TID;

pub fn testBody() !void {
    try allocate();
    try enqueueAndDequeue();
    try priorityQueueing();
}

fn setupQueue() void {
    queue.reinit();
}

fn setupThreads() void {
    for (0..10) |i| {
        schedule2.threads[i].state = schedule2.THREAD_READY;
    }
    schedule2.threads[0].state = schedule2.THREAD_RUNNING;
}

fn allocate() !void {
    const qid = try queue.allocate();

    expect(qid >= schedule2.NUM_THREADS);

    const qhead = quehead(qid);
    const qtail = quetail(qid);

    // queue head should:
    // - have maximum priority
    expectEqual(MAXKEY, quetab(qhead).key);
    // - have no prev
    expectEqual(QNULL, quetab(qhead).prev);
    // - next points to queue tail
    expectEqual(qtail, quetab(qhead).next);

    // queue tail should:
    // - have minimum priority
    expectEqual(MINKEY, quetab(qtail).key);
    // - previous points to queue head
    expectEqual(qhead, quetab(qtail).prev);
    // - have no next
    expectEqual(QNULL, quetab(qtail).next);
}

fn enqueueAndDequeue() !void {
    setupQueue();
    setupThreads();

    const qid = try queue.allocate();

    // enqueue some threads, but not in numeric order
    const threads_to_queue = [_]TID{ 2, 7, 9, 1, 3, 4, 5, 8, 6 };
    for (threads_to_queue) |t| {
        expectEqual(t, try queue.enqueue(t, qid));
    }

    // dequeue order should be FIFO
    const threads_expected = threads_to_queue;
    for (threads_expected) |t| {
        expectEqual(t, try queue.dequeue(qid));
    }

    // queue is empty, so next dequeue should return -1
    expectEqual(@as(TID, schedule2.NO_TID), try queue.dequeue(qid));
}

fn priorityQueueing() !void {
    setupQueue();
    setupThreads();

    const readyq = try queue.allocate();

    // enqueue some threads, but not in numeric order
    const ThreadPriority = struct { TID, queue.Key };
    const threads_with_priority = [_]ThreadPriority{
        .{ 7, 100 },
        .{ 8, 600 },
        .{ 2, 400 },
        .{ 5, 900 },
    };
    for (threads_with_priority) |tp| {
        expectEqual(tp[0], try queue.insert(tp[0], tp[1], readyq));
    }

    _ = printf("readyQ ");
    queue.dumpQ(readyq);

    // dequeue order should be from highest priority to lowest
    const threads_expected = [_]TID{ 5, 8, 2, 7 };
    for (threads_expected) |t| {
        expectEqual(t, try queue.dequeue(readyq));
    }
}
