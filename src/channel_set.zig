const std = @import("std");
const log = std.log.scoped(.channel_set);

const synchronize = @import("synchronize.zig");
const Spinlock = synchronize.Spinlock;

pub fn init(comptime name: []const u8, comptime T: type, comptime max: T) type {
    return struct {
        const Self = @This();
        const Bitset = std.bit_set.ArrayBitSet(u32, max);

        // 1 bit means free, 0 is allocated.
        // (This is due to the asymmetry in Zig's
        // std.bit_set.ArrayBitSet API... all its functions look for
        // bits set, not cleared)
        available: Bitset = Bitset.initFull(),
        lock: Spinlock = Spinlock.init(name, true),

        pub fn allocate(this: *Self) error{NoAvailableChannel}!T {
            this.lock.acquire();
            defer this.lock.release();

            if (this.available.toggleFirstSet()) |allocated| {
                if (allocated > max) {
                    return error.NoAvailableChannel;
                }
                return @truncate(allocated);
            } else {
                return error.NoAvailableChannel;
            }
        }

        pub fn free(this: *Self, channel: T) void {
            this.lock.acquire();
            defer this.lock.release();

            if (channel >= max) {
                // invalid channel, ignore
                return;
            }

            if (this.available.isSet(channel)) {
                log.err("Attempt to free channel {d} but it was not allocated.", .{channel});
            } else {
                this.available.set(channel);
            }
        }

        pub fn isAllocated(this: *Self, channel: T) bool {
            this.lock.acquire();
            defer this.lock.release();

            return !this.available.isSet(channel);
        }
    };
}
