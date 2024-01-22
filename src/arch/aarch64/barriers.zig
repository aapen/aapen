pub const BarrierType = struct {
    pub const SY = "SY";
    pub const ST = "ST";
    pub const LD = "LD";
    pub const ISH = "ISH";
    pub const ISHST = "ISHST";
    pub const ISHLD = "ISHLD";
    pub const NSH = "NSH";
    pub const NSHST = "NSHST";
    pub const NSHLD = "NSHLD";
    pub const OSH = "OSH";
    pub const OSHHT = "OSHHT";
    pub const OSHLD = "OSHLD";
};

pub fn dmb(comptime ty: [*:0]const u8) void {
    asm volatile ("dmb " ++ ty);
}

pub fn dsb(comptime ty: [*:0]const u8) void {
    asm volatile ("dsb " ++ ty);
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
