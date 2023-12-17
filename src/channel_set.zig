const std = @import("std");

const synchronize = @import("synchronize.zig");
const Spinlock = synchronize.Spinlock;

const Error = error{
    NoAvailableChannel,
};

pub fn init(comptime name: []const u8, comptime T: type, comptime max: T) type {
    return struct {
        const Self = @This();
        const Bitset = std.bit_set.ArrayBitSet(u32, max);

        available: Bitset = Bitset.initFull(),
        lock: Spinlock = Spinlock.init(name, true),

        pub fn allocate(this: *Self) !T {
            this.lock.acquire();
            defer this.lock.release();

            if (this.available.toggleFirstSet()) |allocated| {
                return @truncate(allocated);
            } else {
                return Error.NoAvailableChannel;
            }
        }

        pub fn free(this: *Self, channel: T) void {
            this.lock.acquire();
            defer this.lock.release();

            if (channel >= max) {
                // invalid channel, ignore
                return;
            }

            if (!this.available.isSet(channel)) {
                std.log.err("Attempt to free channel {d} but it was not allocated.", .{channel});
            } else {
                this.available.set(channel);
            }
        }
    };
}
