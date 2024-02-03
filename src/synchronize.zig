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
// Critical sections
// ----------------------------------------------------------------------

// Critical sections are reentrant, but only one core can execute
// inside one at a time. While in a critical section, IRQs (and
// maybe FIQs, depending on the target_level) are disabled.
//
// When entering a critical section at IRQ level, FIQs can still
// interrupt the core. When entering at FIQ level, all interrupts will
// be masked.

const MAX_CRITICAL_NESTING = 40;

var critical_levels: [cpu.MAX_CORES]u8 = [_]u8{0} ** cpu.MAX_CORES;
var saved_flags: [cpu.MAX_CORES][MAX_CRITICAL_NESTING]u32 = [_][MAX_CRITICAL_NESTING]u32{[_]u32{0} ** MAX_CRITICAL_NESTING} ** cpu.MAX_CORES;

pub fn criticalEnter(target_level: InterruptLevel) void {
    if (target_level != .IRQ and target_level != .FIQ) {
        std.log.err("target_level must be higher than Task", .{});
    }

    const current_level = cpu.currentInterruptLevel();
    const core_id = cpu.coreId();
    const exflags = cpu.irqFlagsRead();

    if (current_level == .FIQ and target_level != .FIQ) {
        std.log.err("attempt to enter a critical section at lower interrupt level", .{});
    }

    cpu.irqAndFiqDisable();

    if (critical_levels[core_id] >= MAX_CRITICAL_NESTING) {
        std.log.err("too many nested critical sections", .{});
    }

    critical_levels[core_id] += 1;
    saved_flags[core_id][critical_levels[core_id]] = exflags;

    if (target_level == .IRQ) {
        cpu.fiqEnable();
    }

    barriers.barrierMemory();
}

// Leaving a critical section returns the processor to it's previous
// masking state. That is, if IRQs were masked before entering the
// critical section, they will be masked upon leaving it. Same for
// FIQs.

pub fn criticalLeave() void {
    const core_id = cpu.coreId();
    barriers.barrierMemory();
    cpu.fiqDisable();

    if (critical_levels[core_id] == 0) {
        std.log.err("unbalanced critical sections", .{});
    }

    critical_levels[core_id] -= 1;
    const exflags = saved_flags[core_id][critical_levels[core_id]];
    cpu.irqFlagsWrite(exflags);
}

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

        if (lock.target_level == .IRQ or lock.target_level == .FIQ) {
            criticalEnter(lock.target_level);
        }

        const my_ticket = atomic.atomicInc(&lock.next_ticket);
        while (atomic.atomicFetch(&lock.now_serving) != my_ticket) {
            cpu.wfe();
        }
    }

    pub fn release(lock: *TicketLock) void {
        _ = atomic.atomicInc(&lock.now_serving);
        cpu.sev();

        if (lock.target_level == .IRQ or lock.target_level == .FIQ) {
            criticalLeave();
        }
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
