const std = @import("std");
const panic = std.builtin.panic;
const Ordering = std.atomic.Ordering;

const arch = @import("architecture.zig");
const barriers = arch.barriers;

pub const Spinlock = struct {
    name: []const u8,
    locked: bool = false,
    core: u8 = 0,

    pub fn init(lock: *Spinlock, name: []const u8) void {
        lock.* = .{
            .name = name,
            .locked = false,
            .core = 0,
        };
    }

    pub fn acquire(lock: *Spinlock) void {
        // disable interrupts to avoid deadlock
        // these are "stacked" so nesting is OK
        arch.cpu.interruptDisable();

        if (lock.holding()) {
            std.debug.panic("double acquire: {s}", .{lock.name});
        }

        while (@cmpxchgStrong(bool, &lock.locked, false, true, Ordering.Acquire, Ordering.Acquire) == false) {}

        // Make sure reads & writes are synchronized here
        barriers.dmb(.ISH);

        lock.core = arch.cpu.coreCurrent().core_id;

        arch.cpu.interruptEnable();
    }

    pub fn release(lock: *Spinlock) void {
        // disable interrupts to avoid deadlock
        // these are "stacked" so nesting is OK
        arch.cpu.interruptDisable();

        if (!lock.holding()) {
            std.debug.panic("release unheld: {s}", .{lock.name});
        }

        lock.core = 0;

        barriers.dmb(.ISH);

        @atomicStore(bool, &lock.locked, false, Ordering.Release);

        arch.cpu.interruptEnable();
    }

    /// True if the current core is the one holding the lock
    fn holding(lock: *Spinlock) bool {
        var result: bool = false;

        arch.cpu.interruptDisable();
        result = lock.locked and lock.core == arch.cpu.coreCurrent().core_id;
        arch.cpu.interruptEnable();

        return result;
    }
};
