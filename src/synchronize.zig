const std = @import("std");
const panic = std.builtin.panic;
const Ordering = std.atomic.Ordering;

const atomic = @import("atomic.zig");
const arch = @import("architecture.zig");
const barriers = arch.barriers;
const cpu = arch.cpu;
const InterruptLevel = cpu.InterruptLevel;

// ----------------------------------------------------------------------
// Architecture-specific constants
// ----------------------------------------------------------------------
const root = @import("root");
const data_cache_line_length = root.HAL.data_cache_line_length;

// ----------------------------------------------------------------------
// Locks and Mutexes
// ----------------------------------------------------------------------

/// Ticket lock. One holder can have the lock at any time. Not
/// re-entrant.
///
/// "target_level" refers to the interruptibility of the
/// operation. Precedence order is Task < IRQ < FIQ.
pub const TicketLock = struct {
    name: []const u8,
    target_level: cpu.InterruptLevel = .Task,
    now_serving: u64 = 0,
    next_ticket: u64 = 0,
    enabled: bool = false,

    pub fn init(name: []const u8, enabled: bool) TicketLock {
        return .{
            .name = name,
            .enabled = enabled,
        };
    }

    pub fn initWithTargetLevel(name: []const u8, enabled: bool, target_level: cpu.InterruptLevel) TicketLock {
        return .{
            .name = name,
            .enabled = enabled,
            .target_level = target_level,
        };
    }

    pub fn acquire(lock: *TicketLock) void {
        if (!lock.enabled) return;

        const im = cpu.disable();

        const my_ticket = atomic.atomicInc(&lock.next_ticket);
        while (atomic.atomicFetch(&lock.now_serving) != my_ticket) {
            cpu.restore(im);
            cpu.wfe();
            _ = cpu.disable();
        }
        cpu.restore(im);
    }

    pub fn release(lock: *TicketLock) void {
        const im = cpu.disable();
        defer cpu.restore(im);

        _ = atomic.atomicInc(&lock.now_serving);
        cpu.sev();
    }
};

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
