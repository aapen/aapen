pub const barriers = @import("aarch64/barriers.zig");
pub const cache = @import("aarch64/cache.zig");
pub const exceptions = @import("aarch64/exceptions.zig");
pub const mmu = @import("aarch64/mmu.zig");
pub const registers = @import("aarch64/registers.zig");
pub const time = @import("aarch64/time.zig");

/// Note: this performs an "exception return" on the CPU. It will
/// change the stack point and exception level, meaning that this does
/// not return to the call site.
pub inline fn eret() void {
    asm volatile ("eret");
}

/// Wait for interrupt
pub inline fn wfi() void {
    asm volatile ("wfi");
}

pub fn mmuInit() void {
    mmu.init();
}
