const std = @import("std");
const panic = std.builtin.panic;
const Ordering = std.atomic.Ordering;

const arch = @import("architecture.zig");
const barriers = arch.barriers;
const cpu = arch.cpu;
const InterruptLevel = cpu.InterruptLevel;

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

    pub fn acquire(lock: *Spinlock) void {
        if (lock.target_level == .IRQ or lock.target_level == .FIQ) {
            criticalEnter(lock.target_level);
        }

        // This is an atomic test-and-set operation on lock.locked
        //
        // See Section K13.3.1 "Acquiring a lock" in "Arm Architecture
        // Reference Manual for A-profile architecture" revision J.a
        // from 21 April 2023

        asm volatile (
            \\ mov x1, %[ptr_locked]
            \\ mov w2, #1
            \\ prfm pstl1keep, [x1]
            \\ 1: ldaxr w3, [x1]
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
        // See Section K13.3.2 "Releasing a lock" in "Arm Architecture
        // Reference Manual for A-profile architecture" revision J.a
        // from 21 April 2023
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
