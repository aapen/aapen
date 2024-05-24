const std = @import("std");
const root = @import("root");

const arch = @import("architecture.zig");
const atomic = @import("atomic.zig");

// ----------------------------------------------------------------------
// Architecture-specific constants
// ----------------------------------------------------------------------
const data_cache_line_length = root.HAL.data_cache_line_length;

// ----------------------------------------------------------------------
// One shot signals
// ----------------------------------------------------------------------

pub const OneShot = struct {
    const Self = @This();

    value: u64 = 0,

    pub fn signal(self: *Self) void {
        _ = atomic.atomicInc(&self.value);
    }

    pub fn isSignalled(self: *Self) bool {
        const v = atomic.atomicFetch(&self.value);
        return v != 0;
    }
};

// ----------------------------------------------------------------------
// Ticket locks
// ----------------------------------------------------------------------

pub fn TicketLock(comptime name: []const u8) type {
    return struct {
        const Self = @This();

        name: []const u8 = name,
        now_serving: u64 = 0,
        next_ticket: u64 = 0,
        enabled: bool = true,

        pub fn acquire(lock: *Self) void {
            if (!lock.enabled) return;

            const im = arch.cpu.disable();

            const my_ticket = atomic.atomicInc(&lock.next_ticket);
            while (atomic.atomicFetch(&lock.now_serving) != my_ticket) {
                arch.cpu.restore(im);
                arch.cpu.wfe();
                _ = arch.cpu.disable();
            }
            arch.cpu.restore(im);
        }

        pub fn release(lock: *Self) void {
            const im = arch.cpu.disable();
            defer arch.cpu.restore(im);

            _ = atomic.atomicInc(&lock.now_serving);
            arch.cpu.sev();
        }
    };
}

// ----------------------------------------------------------------------
// Allocation set
// ----------------------------------------------------------------------

pub fn AllocationSet(comptime name: []const u8, comptime T: type, comptime max: T) type {
    return struct {
        const Self = @This();
        const Bitset = std.bit_set.ArrayBitSet(u32, max);

        // 1 bit means free, 0 is allocated.
        // (This is due to the asymmetry in Zig's
        // std.bit_set.ArrayBitSet API... all its functions look for
        // bits set, not cleared)
        available: Bitset = Bitset.initFull(),
        lock: TicketLock(name) = .{},

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
                root.log.err(@src(), "Attempt to free item {d} but it was not allocated.", .{channel});
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

// ----------------------------------------------------------------------
// Cache coherence and maintenance
// ----------------------------------------------------------------------
pub fn dataCacheSliceClean(buf: []u8) void {
    dataCacheRangeClean(@intFromPtr(buf.ptr), buf.len);
}

pub fn dataCacheRangeClean(address: u64, length: u64) void {
    var next_location = address;
    var remaining_length = length + data_cache_line_length;

    while (true) {
        asm volatile (
            \\ dc cvac, %[addr]
            :
            : [addr] "r" (next_location),
        );

        if (remaining_length < data_cache_line_length) {
            break;
        }

        next_location += data_cache_line_length;
        remaining_length -= data_cache_line_length;
    }
}

pub fn dataCacheSliceInvalidate(buf: []u8) void {
    dataCacheRangeInvalidate(@intFromPtr(buf.ptr), buf.len);
}

pub fn dataCacheRangeInvalidate(address: u64, length: u64) void {
    var next_location = address;
    var remaining_length = length + data_cache_line_length;

    while (true) {
        asm volatile (
            \\ dc ivac, %[addr]
            :
            : [addr] "r" (next_location),
        );

        if (remaining_length < data_cache_line_length) {
            break;
        }

        next_location += data_cache_line_length;
        remaining_length -= data_cache_line_length;
    }
}

pub fn dataCacheSliceCleanAndInvalidate(buf: []u8) void {
    dataCacheRangeCleanAndInvalidate(@intFromPtr(buf.ptr), buf.len);
}

pub fn dataCacheRangeCleanAndInvalidate(address: u64, length: u64) void {
    var next_location = address;
    var remaining_length = length + data_cache_line_length;

    while (true) {
        asm volatile (
            \\ dc civac, %[addr]
            :
            : [addr] "r" (next_location),
        );

        if (remaining_length < data_cache_line_length) {
            break;
        }

        next_location += data_cache_line_length;
        remaining_length -= data_cache_line_length;
    }
}
