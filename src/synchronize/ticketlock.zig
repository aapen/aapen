/// Ticket lock. One holder can have the lock at any time. Not
/// re-entrant.
///
const arch = @import("../architecture.zig");
const barriers = arch.barriers;
const cpu = arch.cpu;
const atomic = @import("../atomic.zig");

const TicketLock = @This();

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
