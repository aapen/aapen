const std = @import("std");
const panic = std.builtin.panic;
const Ordering = std.atomic.Ordering;

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

/// Only one holder can have the spinlock locked at any time.
/// This is not re-entrant. If a PE already holds the lock and
/// attempts to acquire it again, deadlock will result.
///
/// "target_level" refers to the interruptibility of the
/// operation. Precedence order is Task < IRQ < FIQ.
pub const Spinlock = struct {
    name: []const u8,
    target_level: cpu.InterruptLevel = .Task,
    locked: u32 = 0,
    enabled: bool,

    pub fn init(name: []const u8, enabled: bool) Spinlock {
        return .{
            .name = name,
            .enabled = enabled,
        };
    }

    pub fn initWithTargetLevel(name: []const u8, enabled: bool, target_level: cpu.InterruptLevel) Spinlock {
        return .{
            .name = name,
            .enabled = enabled,
            .target_level = target_level,
        };
    }

    pub fn acquire(lock: *Spinlock) void {
        if (lock.target_level == .IRQ or lock.target_level == .FIQ) {
            criticalEnter(lock.target_level);
        }

        // This is an atomic test-and-set operation on lock.locked
        //
        // See Section K13.3.4 "Use of Wait for Event (WFE) and Send
        // Event (SEV) with locks" in "Arm Architecture Reference
        // Manual for A-profile architecture" revision J.a from 21
        // April 2023

        asm volatile (
            \\ mov x1, %[ptr_locked]
            \\ sevl
            \\ prfm pstl1keep, [x1]
            \\ 1:
            \\ wfe
            \\ ldaxr w3, [x1]
            \\ cbnz w3, 1b
            \\ stxr w3, w2, [x1]
            \\ cbnz w3, 1b
            :
            : [ptr_locked] "r" (&lock.locked),
            : "w3", "w2", "x1"
        );
    }

    pub fn release(lock: *Spinlock) void {
        // This is an atomic reset operation on lock.locked
        //
        // See Section K13.3.4 "Use of Wait for Event (WFE) and Send
        // Event (SEV) with locks" in "Arm Architecture Reference
        // Manual for A-profile architecture" revision J.a from 21
        // April 2023
        asm volatile (
            \\ mov x1, %[ptr_locked]
            \\ stlr wzr, [x1]
            :
            : [ptr_locked] "r" (&lock.locked),
            : "x1"
        );

        if (lock.target_level == .IRQ or lock.target_level == .FIQ) {
            criticalLeave();
        }
    }
};

// Keeping this around for later:
//
// acquire_semaphore:
//     // x0: address of the semaphore variable
// 1:  ldaxr   w1, [x0]         // Load the semaphore value atomically
//     cbz     w1, 2f           // If the semaphore is 0, wait for an event
//     sub     w1, w1, #1       // Decrement the semaphore value
//     stlxr   w2, w1, [x0]     // Attempt to store the new value atomically
//     cbnz    w2, 1b           // If the store failed, retry
//     ret                      // Return when successful
// 2:  wfe                      // Wait for an event
//     b        1b              // Go back to try again
//
// release_semaphore:
//     // x0: address of the semaphore variable
// 1:  ldaxr   w1, [x0]         // Load the semaphore value atomically
//     add     w1, w1, #1       // Increment the semaphore value
//     stlxr   w2, w1, [x0]     // Attempt to store the new value atomically
//     cbnz    w2, 1b           // If the store failed, retry
//     dsb                      // Ensure the semaphore update is visible to all cores
//     sev                      // Send an event to wake up waiting cores
//     ret                      // Return when successful

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
