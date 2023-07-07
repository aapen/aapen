pub fn init() void {
    enable();
}

pub fn disable() void {
    asm volatile ("msr daifset, #2");
}

pub fn enable() void {
    asm volatile ("msr daifclr, #2");
}
