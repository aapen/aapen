/// Thread queueing system. Uses a static array with fixed size to
/// provide a priority queue without dynamic memory allocation.
///
/// Each entry acts like a doubly-linked list, using array indices as
/// "pointers" in the table.
///
/// Entries 0..NUM_THREADS are reserved to hold thread IDs. When we
/// add a thread to a queue, we update the `next` and `prev` pointers
/// in that thread's entry in the queue. This way, a thread implicitly
/// exists in at most one queue.
///
/// Note that we will, at times, use some punning: a QID identifies an
/// entry in the queue table. When it indexes the first entry in a
/// queue, then the QID doubles as the queue identifier itself as well
/// as the identifier of the first item in the queue.
const std = @import("std");

const schedule2 = @import("schedule2.zig");
const TID = schedule2.TID;
const NO_TID = schedule2.NO_TID;
const isBadTid = schedule2.isBadTid;

// TODO move this to a common "definitions" module
pub const Error = error{
    NoMoreQueues,
    BadThreadId,
    BadQueueId,
    QueueEmpty,
};

// TODO move this to a common "definitions" module
pub const NUM_THREADS = 128;

// TODO move this to a common "definitions" module
pub const NUM_SEMAPHORES = 128;

/// Number of queue entries allowed in the entire system, across all queues.
const NUM_QUEUE_ENTRIES = NUM_THREADS + 4 + (2 * NUM_SEMAPHORES);

/// "Pointer" to a queue entry. Must be big enough to hold QEMPTY..NUM_QUEUE_ENTRIES
pub const QID = i16;
pub const QEMPTY = -1; // Placeholder for a "pointer" to null

/// Value of a queue entry's priority key.
pub const Key = i16;
pub const MINKEY: Key = std.math.minInt(Key);
pub const MAXKEY: Key = std.math.maxInt(Key);

const QueueEntry = packed struct {
    key: Key,
    prev: QID,
    next: QID,

    pub fn init() QueueEntry {
        return .{
            .key = 0,
            .prev = 0,
            .next = 0,
        };
    }
};

var queue_table: [NUM_QUEUE_ENTRIES]QueueEntry = init: {
    var initial_value: [NUM_QUEUE_ENTRIES]QueueEntry = undefined;
    for (&initial_value) |*q| {
        q.* = QueueEntry.init();
    }
    break :init initial_value;
};

// ----------------------------------------------------------------------
// Public API
// ----------------------------------------------------------------------

/// Next available queue_table entry
var nextQid: QID = NUM_THREADS;

/// Allocate a queue
pub fn allocate() !QID {
    if (nextQid > NUM_QUEUE_ENTRIES) {
        return Error.NoMoreQueues;
    }

    // we allocate pairs of entries, one for the head of the dlist one
    // for the tail

    var q = nextQid;
    nextQid += 2;

    const head = quetab(quehead(q));
    head.next = quetail(q);
    head.prev = QEMPTY;
    head.key = MAXKEY;

    const tail = quetab(quetail(q));
    tail.next = QEMPTY;
    tail.prev = quehead(q);
    tail.key = MINKEY;

    return q;
}

/// Append to the queue
pub fn enqueue(tid: TID, qid: QID) !TID {
    if (isBadTid(tid)) return Error.BadThreadId;
    if (isBadQid(qid)) return Error.BadQueueId;

    const tail = quetail(qid);
    const prev = quetab(tail).prev;

    const qenttid = quetab(tid);

    qenttid.next = tail;
    qenttid.prev = prev;

    quetab(prev).next = tid;
    quetab(tail).prev = tid;

    return tid;
}

/// Remove and return first item in the queue
pub fn dequeue(qid: QID) !TID {
    return getFirst(qid);
}

/// Insert in the queue according to priority ordering (highest to lowest)
pub fn insert(tid: TID, priority: Key, qid: QID) !TID {
    if (isBadTid(tid)) return Error.BadThreadId;
    if (isBadQid(qid)) return Error.BadQueueId;

    var next = quetab(quehead(qid)).next;
    while (quetab(next).key >= priority) {
        next = quetab(next).next;
    }

    quetab(tid).next = next;
    const prev = quetab(next).prev;
    quetab(tid).prev = prev;
    quetab(tid).key = priority;
    quetab(prev).next = tid;
    quetab(next).prev = tid;

    return tid;
}

// ----------------------------------------------------------------------
// Low level functions
// ----------------------------------------------------------------------

/// Convenience for indexing into the table with an i16
/// Caller MUST verify the value is non-negative
pub inline fn quetab(x: QID) *QueueEntry {
    return &queue_table[@intCast(x)];
}

pub fn getFirst(qid: QID) !TID {
    if (isBadQid(qid)) return Error.BadQueueId;
    if (isEmpty(qid)) return NO_TID;

    const head = quehead(qid);
    return getItem(quetab(head).next);
}

pub fn getLast(qid: QID) !TID {
    if (isBadQid(qid)) return Error.BadQueueId;
    if (isEmpty(qid)) return NO_TID;

    const tail = quetail(qid);
    return getItem(quetab(tail).prev);
}

pub fn getItem(tid: TID) TID {
    const next = quetab(tid).next;
    const prev = quetab(tid).prev;

    quetab(prev).next = next;
    quetab(next).prev = prev;
    quetab(tid).next = QEMPTY;
    quetab(tid).prev = QEMPTY;
    return tid;
}

// ----------------------------------------------------------------------
// Table manipulation
// ----------------------------------------------------------------------

pub inline fn isBadQid(q: QID) bool {
    return (quehead(q) < 0 or quehead(q) != quetail(q) - 1 or quetail(q) >= NUM_QUEUE_ENTRIES);
}

pub inline fn quehead(q: QID) QID {
    return q;
}

pub inline fn quetail(q: QID) QID {
    return q + 1;
}

pub inline fn isEmpty(q: QID) bool {
    return quetab(q).next >= NUM_THREADS;
}

pub inline fn nonEmpty(q: QID) bool {
    return quetab(q).next < NUM_THREADS;
}

pub inline fn firstKey(q: QID) Key {
    return quetab(quetab(quehead(q)).next).key;
}

pub inline fn lastKey(q: QID) Key {
    return quetab(quetab(quetail(q)).prev).key;
}

pub inline fn firstId(q: QID) QID {
    return quetab(quehead(q)).next;
}

// ----------------------------------------------------------------------
// Test and debug support
// ----------------------------------------------------------------------
pub fn reinit() void {
    // reinitialize between test cases
    for (&queue_table) |*qe| {
        qe.* = QueueEntry.init();
    }

    nextQid = NUM_THREADS;
}

pub fn dumpQ(qid: QID) void {
    const root = @import("root");
    const printf = root.printf;

    if (isBadQid(qid)) {
        _ = printf("bad queue id: %d\n", qid);
        return;
    }

    if (isEmpty(qid)) {
        _ = printf("empty queue: %d\n", qid);
        return;
    }

    _ = printf("QID %d: [", qid);

    const head = quehead(qid);
    _ = printf("head: %d, ", head);

    var qent = quetab(head).next;
    while (qent != QEMPTY) {
        if (qent == quetail(qid)) {
            _ = printf("tail: %d", qent);
        } else {
            _ = printf("%d", qent);
        }

        const next = quetab(qent).next;

        if (next == QEMPTY) {
            _ = printf("]\n");
            break;
        }

        if (quetab(next).prev != qent) {
            _ = printf(" !]");
            break;
        }

        _ = printf(", ");

        qent = next;
    }
}
