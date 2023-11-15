const std = @import("std");

const synchronize = @import("synchronize.zig");
const Spinlock = synchronize.Spinlock;

const Self = @This();

const Error = error{
    NoAvailableChannel,
};

// TODO Seems like this should be marked as
// volatile, but Zig only allows that on pointers
allocated: u32,
max: u5,
lock: Spinlock,

pub fn init(name: []const u8, max: u5) Self {
    return .{
        .allocated = 0,
        .max = max,
        .lock = Spinlock.init(name, true),
    };
}

pub fn allocate(channel_set: *Self) !u5 {
    channel_set.lock.acquire();
    defer channel_set.lock.release();

    var mask: u32 = 1;
    var n: u5 = 0;
    while (n < channel_set.max) : (n += 1) {
        if (channel_set.allocated & mask == 0) {
            channel_set.allocated |= mask;
            return n;
        }
        mask <<= 1;
    }
    return Error.NoAvailableChannel;
}

pub fn free(channel_set: *Self, channel: u5) void {
    channel_set.lock.acquire();
    defer channel_set.lock.release();

    var mask: u32 = 1 << channel;

    if (channel_set.allocated & mask == 0) {
        std.log.err("Attempt to free a channel that was not allocated.");
    }

    channel_set.allocated &= ~mask;
}
