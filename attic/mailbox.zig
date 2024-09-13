/// A mailbox delivers messages from one thread to another.
/// Messages are queued, the mailbox is synchronized by semaphores.
/// Receiving from an empty mailbox will block until a message is
/// available.
///
/// All messages in a given mailbox must have the same type.
const std = @import("std");
const Allocator = std.mem.Allocator;

const arch = @import("architecture.zig");
const cpu = arch.cpu;
const memory = @import("memory.zig");

const semaphore = @import("semaphore.zig");
const SID = semaphore.SID;

const synchronize = @import("synchronize.zig");

/// Create and initialize a mailbox with fixed, reserved capacity
pub fn Mailbox(comptime T: type, comptime capacity: u16) type {
    return MailboxReturnType(T, capacity);
}

pub fn MailboxReturnType(comptime T: type, comptime capacity: u16) type {
    return struct {
        pub const Self = @This();

        sender: SID,
        receiver: SID,
        max: u16 = capacity,
        count: u16 = 0,
        start: u16 = 0,
        items: [capacity]T = undefined,

        pub fn init(self: *Self) !void {
            self.* = .{
                .sender = try semaphore.create(capacity),
                .receiver = try semaphore.create(0),
            };
        }

        pub fn deinit(self: *Self) !void {
            try semaphore.free(self.sender);
            try semaphore.free(self.receiver);
        }

        pub fn count(self: *Self) u16 {
            return self.count;
        }

        pub fn send(self: *Self, val: T) !void {
            const im = cpu.disable();
            defer cpu.restore(im);

            // wait for space in the queue
            try semaphore.wait(self.sender);

            // place the item
            const idx = (self.start + self.count) % self.max;
            self.items[idx] = val;
            self.count += 1;

            // notify receivers
            try semaphore.signal(self.receiver);
        }

        pub fn receive(self: *Self) !T {
            const im = cpu.disable();
            defer cpu.restore(im);

            // wait for something in the queue
            try semaphore.wait(self.receiver);

            // get the item
            const val = self.items[self.start];
            self.start = (self.start + 1) % self.max;
            self.count -= 1;

            // notify senders that there is space
            try semaphore.signal(self.sender);

            return val;
        }
    };
}
