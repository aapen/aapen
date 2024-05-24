/// Ticket lock. One holder can have the lock at any time. Not
/// re-entrant.
///
const arch = @import("../architecture.zig");
const barriers = arch.barriers;
const cpu = arch.cpu;
const atomic = @import("../atomic.zig");

pub fn Type(comptime name: []const u8) type {
    return struct {
        const Self = @This();

        name: []const u8 = name,
        now_serving: u64 = 0,
        next_ticket: u64 = 0,
        enabled: bool = true,

        pub fn acquire(lock: *Self) void {
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

        pub fn release(lock: *Self) void {
            const im = cpu.disable();
            defer cpu.restore(im);

            _ = atomic.atomicInc(&lock.now_serving);
            cpu.sev();
        }
    };
}
