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

pub const sections = struct {
    // The BSS symbols are provided by the linker script, which computes
    // them from the object files produced by the compiler.
    pub extern var __bss_start: u8;
    pub extern var __bss_end_exclusive: u8;
    pub extern var __page_tables_start: u8;
};

export fn bssInit() void {
    const bss_start: [*]u8 = @ptrCast(&sections.__bss_start);
    const bss_end: [*]u8 = @ptrCast(&sections.__bss_end_exclusive);
    const bss_len = @intFromPtr(bss_end) - @intFromPtr(bss_start);

    @memset(bss_start[0..bss_len], 0);
}
