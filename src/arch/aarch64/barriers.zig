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

pub inline fn barrierMemory() void {
    dmb(BarrierType.SY);
}

// Memory barrier for device read
pub inline fn barrierMemoryDevice() void {
    dsb(BarrierType.SY);
}

pub inline fn barrierMemoryWrite() void {
    dsb(BarrierType.ST);
}

pub inline fn barrierMemoryRead() void {
    dsb(BarrierType.LD);
}

pub inline fn barrierInstruction() void {
    isb();
}
