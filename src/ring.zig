const std = @import("std");

//
// Ring buffer implementation
//

pub fn Ring(comptime T: anytype) type {
    return struct {
        const Self = @This();

        buffer: [64]T,
        capacity: u8 = undefined,
        consume: u8 = undefined,
        produce: u8 = undefined,

        pub fn init() Self {
            return .{
                .buffer = std.mem.zeroes([64]T),
                .capacity = 64,
                .consume = 0,
                .produce = 0,
            };
        }

        pub fn enqueue(self: *Self, item: T) void {
            // TODO: absolutely any amount of error checking.
            self.buffer[self.produce] = item;
            self.produce = @mod(self.produce + 1, self.capacity);
        }

        pub fn dequeue(self: *Self) T {
            var value = self.buffer[self.consume];
            self.consume = @mod(self.consume + 1, self.capacity);
            return value;
        }

        pub fn empty(self: *const Self) bool {
            return self.produce == self.consume;
        }
    };
}

test "starts empty" {
    const expect = std.testing.expect;
    var ring = Ring(u32).init();
    try expect(ring.empty());
}

test "consume what you produce" {
    const expect = std.testing.expect;
    var ring = Ring(u8).init();

    ring.enqueue(115);
    try expect(!ring.empty());
    try expect(115 == ring.dequeue());

    try expect(ring.empty());

    ring.enqueue(97);
    ring.enqueue(65);
    try expect(!ring.empty());
    try expect(97 == ring.dequeue());
    try expect(65 == ring.dequeue());

    try expect(ring.empty());
}

test "consume up to capacity items" {
    const expect = std.testing.expect;
    var ring = Ring(usize).init();
    for (0..64) |i| {
        ring.enqueue(i);
    }
    for (0..64) |i| {
        try expect(i == ring.dequeue());
    }
}

test "consumer chases producer" {
    const expect = std.testing.expect;
    var ring = Ring(u8).init();
    inline for (65..75) |c| {
        ring.enqueue(c);
    }
    inline for (65..75) |e| {
        try expect(e == ring.dequeue());
    }
    inline for (75..85) |c| {
        ring.enqueue(c);
    }
    inline for (75..85) |e| {
        try expect(e == ring.dequeue());
    }
}

test "items are overwritten" {
    const expect = std.testing.expect;
    var ring = Ring(usize).init();
    for (0..65) |i| {
        ring.enqueue(i);
    }
    try expect(64 == ring.dequeue());
    for (1..65) |i| {
        try expect(i == ring.dequeue());
    }
    try expect(ring.empty());
}
