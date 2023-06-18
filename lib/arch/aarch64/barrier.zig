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

pub fn dmb(ty: BarrierType) void {
    asm volatile ("dmb " ++ @tagName(ty));
}

pub fn isb(ty: BarrierType) void {
    asm volatile ("isb " ++ @tagName(ty));
}
