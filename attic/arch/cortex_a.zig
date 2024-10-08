pub const barriers = @import("aarch64/barriers.zig");
pub const exceptions = @import("aarch64/exceptions.zig");
pub const mmu = @import("aarch64/mmu.zig");
pub const registers = @import("aarch64/registers.zig");
pub const time = @import("aarch64/time.zig");

// ----------------------------------------------------------------------
// Primitive instructions
// ----------------------------------------------------------------------

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

/// Wait for event
pub inline fn wfe() void {
    asm volatile ("wfe");
}

/// Send event
pub inline fn sev() void {
    asm volatile ("sev");
}

/// Cause a software breakpoint
pub inline fn brk(breakpoint_id: u32) void {
    asm volatile ("brk " ++ breakpoint_id);
}

// ----------------------------------------------------------------------
// Core control
// ----------------------------------------------------------------------

pub const MAX_CORES = 8;

/// Return core # for the currently executing PE
pub inline fn coreId() u8 {
    const mpidr = asm (
        \\ mrs %[ret], MPIDR_EL1
        : [ret] "=r" (-> u64),
    );
    return @truncate(mpidr & (MAX_CORES - 1));
}

pub fn init(core_id: usize) void {
    if (core_id == 0) {
        mmu.pageTablesCreate();
    }
    mmu.enable();
    exceptions.init();
}

pub fn park() void {
    while (true) {
        wfe();
    }
}

// ----------------------------------------------------------------------
// Exception table control
// ----------------------------------------------------------------------

pub fn exceptionHandlerTableWrite(table_base: *anyopaque) void {
    registers.vbar_el1.write(@intFromPtr(table_base));
}

// ----------------------------------------------------------------------
// Low level interrupt control
// ----------------------------------------------------------------------

pub fn enable() void {
    asm volatile (
        \\ msr DAIFClr, #0b0011
    );
}

pub fn disable() u32 {
    const ret = irqFlagsRead();
    asm volatile (
        \\ msr DAIFSet, #0b0011
    );
    return ret;
}

pub fn restore(flags: u32) void {
    irqFlagsWrite(flags);
}

pub fn irqFlagsRead() u32 {
    return asm (
        \\ mrs %[ret], daif
        : [ret] "=r" (-> u32),
    );
}

fn irqFlagsWrite(flags: u32) void {
    asm volatile (
        \\ msr daif, %[flags]
        :
        : [flags] "r" (flags),
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

    const flags: u32 = asm volatile (
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
    const el = asm volatile (
        \\ mrs %[el], CurrentEL
        : [el] "=r" (-> u64),
    );

    return @enumFromInt(@as(u2, @truncate(el >> 2)));
}
