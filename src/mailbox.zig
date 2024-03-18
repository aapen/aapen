/// A mailbox delivers messages from one thread to another.
/// Messages are queued, the mailbox is synchronized by semaphores.
/// Receiving from an empty mailbox will block until a message is
/// available.
///
/// All messages in a given mailbox must have the same type.
const std = @import("std");

const arch = @import("architecture.zig");
const cpu = arch.cpu;
const memory = @import("memory.zig");

const semaphore = @import("semaphore.zig");
const SID = semaphore.SID;

const synchronize = @import("synchronize.zig");

/// Create a mailbox type.
pub fn Mailbox(comptime T: type) type {
    return struct {
        pub const MailboxCapacity = u15;

        const Self = @This();

        sender: SID,
        receiver: SID,
        max: MailboxCapacity,
        count: MailboxCapacity,
        start: MailboxCapacity,
        items: []T,

        /// Caller is responsible for providing the memory.
        pub fn init(self: *Self, capacity: MailboxCapacity) !void {
            const bytes = capacity * @sizeOf(T);
            const space: u64 = try memory.get(bytes);
            const space_ptr: [*]u8 = @ptrFromInt(space);
            const items: []T = @as([*]T, @alignCast(@ptrCast(space_ptr)))[0..capacity];

            self.* = .{
                .sender = try semaphore.create(capacity),
                .receiver = try semaphore.create(0),
                .max = capacity,
                .count = 0,
                .start = 0,
                .items = items,
            };
        }

        pub fn deinit(self: *Self) !void {
            try semaphore.free(self.sender);
            try semaphore.free(self.receiver);

            const bytes = self.max * @sizeOf(T);
            try memory.free(@intFromPtr(self.items.ptr), bytes);
        }

        pub fn count(self: *Self) MailboxCapacity {
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
