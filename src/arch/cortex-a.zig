pub const barriers = @import("aarch64/barriers.zig");
pub const cache = @import("aarch64/cache.zig");
pub const exceptions = @import("aarch64/exceptions.zig");
pub const mmu = @import("aarch64/mmu.zig");
pub const registers = @import("aarch64/registers.zig");
pub const time = @import("aarch64/time.zig");

// The BSS symbols are provided by the linker script, which computes
// them from the object files produced by the compiler.
pub const Sections = struct {
    pub extern var __bss_start: u8;
    pub extern var __bss_end_exclusive: u8;
    pub extern var __page_tables_start: u8;
};

export fn bssInit() void {
    const bss_start: [*]u8 = @ptrCast(&Sections.__bss_start);
    const bss_end: [*]u8 = @ptrCast(&Sections.__bss_end_exclusive);
    const bss_len = @intFromPtr(bss_end) - @intFromPtr(bss_start);

    @memset(bss_start[0..bss_len], 0);
}

/// Note: this performs an "exception return" on the CPU. It will
/// change the stack point and exception level, meaning that this does
/// not return to the call site.
pub inline fn eret() noreturn {
    asm volatile ("eret");
    unreachable;
}

/// Wait for interrupt
pub inline fn wfi() void {
    asm volatile ("wfi");
}

/// Cause a software breakpoint
pub inline fn brk(breakpoint_id: u32) void {
    asm volatile ("brk " ++ breakpoint_id);
}

pub const MAX_CORES = 8;

/// Return core # for the currently executing PE
pub inline fn coreId() u8 {
    var mpidr = asm (
        \\ mrs %[ret], MPIDR_EL1
        : [ret] "=r" (-> u64),
    );
    return @truncate(mpidr & (MAX_CORES - 1));
}

pub fn init() void {
    exceptions.init();
}

// ----------------------------------------------------------------------
// Low level interrupt control
// ----------------------------------------------------------------------

pub fn irqFlagsRead() u32 {
    return asm (
        \\ mrs %[ret], daif
        : [ret] "=r" (-> u32),
    );
}

pub fn irqFlagsWrite(flags: u32) void {
    asm volatile (
        \\ msr daif, %[flags]
        :
        : [flags] "r" (flags),
    );
}

pub fn fiqEnable() void {
    asm volatile (
        \\ msr DAIFClr, #1
    );
}

pub fn fiqDisable() void {
    asm volatile (
        \\ msr DAIFSet, #1
    );
}

pub fn irqEnable() void {
    asm volatile (
        \\ msr DAIFClr, #2
    );
}

pub fn irqDisable() void {
    asm volatile (
        \\ msr DAIFSet, #2
    );
}

pub fn irqAndFiqDisable() void {
    asm volatile (
        \\ msr DAIFSet, #3
    );
}

pub const InterruptLevel = enum(u8) {
    Task = 0, // IRQs and FIQs are enabled
    IRQ = 1, // IRQs disabled, FIQs enabled
    FIQ = 2, // IRQs and FIQs disabled
};

pub fn currentInterruptLevel() InterruptLevel {
    const FIQ_flag = @as(u32, 1 << 6);
    const IRQ_flag = @as(u32, 1 << 7);

    var flags: u32 = asm volatile (
        \\ mrs %[f], daif
        : [f] "=r" (-> u32),
    );

    if (flags & FIQ_flag != 0) {
        return .FIQ;
    } else if (flags & IRQ_flag != 0) {
        return .IRQ;
    } else {
        return .Task;
    }
}

pub const ExecutionLevel = enum(u2) {
    EL0 = 0,
    EL1 = 1,
    EL2 = 2,
    EL3 = 3,
};

pub fn currentExecutionLevel() ExecutionLevel {
    var el = asm volatile (
        \\ mrs %[el], CurrentEL
        : [el] "=r" (-> u64),
    );

    return @enumFromInt(@as(u2, @truncate(el >> 2)));
}
