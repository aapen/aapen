pub const registers = @import("aarch64/registers.zig");
pub const time = @import("aarch64/time.zig");
pub const exceptions = @import("aarch64/exceptions.zig");
pub const mmu2 = @import("aarch64/mmu2.zig");

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

pub const BarrierType = enum {
    SY,
    ST,
    LD,
    ISH,
    ISHST,
    ISHLD,
    NSH,
    NSHST,
    NSHLD,
    OSH,
    OSHHT,
    OSHLD,
};

pub fn dmb(comptime ty: BarrierType) void {
    asm volatile ("dmb " ++ @tagName(ty));
}

pub fn dsb(comptime ty: BarrierType) void {
    asm volatile ("dsb " ++ @tagName(ty));
}

pub fn isb() void {
    asm volatile ("isb sy");
}

// Memory barrier for device read
pub inline fn barrierMemoryDevice() void {
    dsb(BarrierType.SY);
}

pub inline fn barrierInstruction() void {
    isb();
}

pub fn irqInit() void {
    irqEnable();
}

pub fn irqDisable() void {
    asm volatile ("msr daifset, #2");
}

pub fn irqEnable() void {
    asm volatile ("msr daifclr, #2");
}

pub fn mmuInit() void {
    mmu2.init();
}

pub fn exceptionInit() void {
    exceptions.init();
}
