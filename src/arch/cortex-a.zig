pub const registers = @import("aarch64/registers.zig");
pub const time = @import("aarch64/time.zig");
pub const exceptions = @import("aarch64/exceptions.zig");
pub const mmu = @import("aarch64/mmu.zig");
pub const irq = @import("aarch64/irq.zig");

/// Note: this performs an "exception return" on the CPU. It will
/// change the stack point and exception level, meaning that this does
/// not return to the call site.
pub inline fn eret() void {
    asm volatile ("eret");
}

pub inline fn wait_for_interrupt() void {
    asm volatile ("wfe");
}
