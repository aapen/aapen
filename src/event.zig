const std = @import("std");
const RingBuffer = std.RingBuffer;

const synchronize = @import("synchronize.zig");
const Spinlock = synchronize.Spinlock;

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
}

pub fn dequeue() Event {
    queue_lock.acquire();
    defer queue_lock.release();

    // TODO if the queue is empty, park (but remember to release the
    // spinlock before parking!)

    // this looks like it will return stack memory, but when you
    // return a struct value Zig automatically generates code to copy
    // it out of the stack to the caller's space.
    var buf: [EVENT_SIZE]u8 = undefined;
    queue.readFirstAssumeLength(buf, EVENT_SIZE);
    const ev = std.mem.bytesAsValue(Event, &buf);
    return ev;
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
};

pub const EventSubtype = struct {
    pub const GPIO = struct {
        pub const RisingEdge = 0b00;
        pub const FallingEdge = 0b01;
        pub const HighLevel = 0b10;
        pub const LowLevel = 0b11;
    };

    pub const Key = struct {
        pub const Pressed = 0x00;
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

var queue_lock: Spinlock = Spinlock.init("kevqueue", true);
const queue_size = 1024 * @sizeOf(Event); // room for 1K events
var queue_storage: [queue_size]u8 = undefined;
var queue: RingBuffer = .{
    .data = &queue_storage,
    .write_index = 0,
    .read_index = 0,
};

// ----------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------

const expectEqual = std.testing.expectEqual;

test "Event must by 64 bits long" {
    std.debug.print("\n", .{});

    try expectEqual(64, @bitSizeOf(Event));
}

test "Event type is easy to extract" {
    std.debug.print("\n", .{});

    const ev: Event = .{};
    try expectEqual(0, ev.type);

    const ev2: Event = .{ .type = EventType.Key, .subtype = EventSubtype.Key.Pressed };
    try expectEqual(2, ev2.type);
    try expectEqual(0, ev2.subtype);
}
