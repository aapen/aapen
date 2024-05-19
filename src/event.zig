const std = @import("std");
const RingBuffer = std.RingBuffer;

const root = @import("root");

const arch = @import("architecture.zig");

const schedule = @import("schedule.zig");

const synchronize = @import("synchronize.zig");
const TicketLock = synchronize.TicketLock;

const Forth = @import("forty/forth.zig").Forth;

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------

pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(@This(), .{
        .{ "nextEvent", "next-event" },
        .{ "clear", "events-clear" },
    });

    try forth.defineStruct("event-type", EventType, .{ .recursive = true, .declarations = true });
    try forth.defineStruct("event-subtype", EventSubtype, .{ .recursive = true, .declarations = true });
}

pub fn nextEvent() u64 {
    return @bitCast(dequeue());
}

// ----------------------------------------------------------------------
// Public API
// ----------------------------------------------------------------------

pub const Event = packed struct {
    type: u8 = 0,
    subtype: u8 = 0,
    value: u16 = 0,
    extra: u32 = 0,
};

pub const EVENT_SIZE = @sizeOf(Event);

pub fn enqueue(event: Event) void {
    queue_lock.acquire();
    defer queue_lock.release();

    queue.writeSliceAssumeCapacity(std.mem.asBytes(&event));
    wakeWaiting();
}

pub fn dequeue() Event {
    queue_lock.acquire();

    // if the queue is empty, park (but remember to release the
    // spinlock before parking!)
    if (queue.isEmpty()) {
        queue_lock.release();
        waitForEvent();
        queue_lock.acquire();
    }
    defer queue_lock.release();

    // this looks like it will return stack memory, but when you
    // return a struct value Zig automatically generates code to copy
    // it out of the stack to the caller's space.
    var buf: [EVENT_SIZE]u8 = undefined;
    readSlice(&buf);
    const ev: Event = std.mem.bytesAsValue(Event, &buf).*;
    return ev;
}

// Voilent clear of the envent queue, mostly for debugging.
pub fn clear() void {
    queue_lock.acquire();
    defer queue_lock.release();

    queue.write_index = 0;
    queue.read_index = 0;
}

// ----------------------------------------------------------------------
// Public Constants
// ----------------------------------------------------------------------

pub const EventType = struct {
    pub const GPIO = 0x01;
    pub const Key = 0x02;
    pub const Mouse = 0x03;
    pub const IO_Completion = 0x04;
    pub const I2C = 0x05;
    pub const SPI = 0x06;
    pub const Timer = 0x07;
    pub const Core = 0x80;
};

pub const EventSubtype = struct {
    pub const GPIO = struct {
        pub const EdgeChange = 0b00;
    };

    pub const Key = struct {
        pub const Pressed = 0x01;
        pub const Released = 0x00;
    };

    // Mouse is TBD

    pub const IO_Completion = struct {
        pub const Succeeded = 0x00;
        pub const Failed = 0x7f;
    };

    // I2C is TBD
    // SPI is TBD
    // Timer is TBD
};

// ----------------------------------------------------------------------
// Implementation
// ----------------------------------------------------------------------

fn wakeWaiting() void {
    arch.cpu.barriers.dsb(arch.cpu.barriers.BarrierType.SY);
    arch.cpu.sev();
}

// Park the CPU until an event arrives (presumably via interrupt or
// from another core)
fn waitForEvent() void {
    while (queue.isEmpty()) {
        arch.cpu.wfe();
    }
}

var queue_lock: TicketLock = TicketLock.initWithTargetLevel("kevqueue", true, .FIQ);
const queue_size = 1024 * @sizeOf(Event); // room for 1K events
var queue_storage: [queue_size]u8 = undefined;
var queue: RingBuffer = .{
    .data = &queue_storage,
    .write_index = 0,
    .read_index = 0,
};

// This is the same thing as RingBuffer.readFirstAssumeLength, but
// that function doesn't exist yet in our currently-pinned version of
// Zig.
fn readSlice(dest: []u8) void {
    const length = dest.len;

    const data_start = queue.mask(queue.read_index);
    const part1_data_end = @min(queue.data.len, data_start + length);
    const part1_len = part1_data_end - data_start;
    const part2_len = length - part1_len;
    @memcpy(dest[0..part1_len], queue.data[data_start..part1_data_end]);
    @memcpy(dest[part1_len..length], queue.data[0..part2_len]);
    queue.read_index = queue.mask2(queue.read_index + length);
}

// ----------------------------------------------------------------------
// Heartbeat
// ----------------------------------------------------------------------

pub fn timerSignal() !void {
    enqueue(.{ .type = EventType.Timer });
    schedule.sleep(3000);
}
