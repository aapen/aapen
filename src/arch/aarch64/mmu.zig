extern fn pagetable_init() void;
extern fn mmu_on() void;

pub fn init() void {
    pagetable_init();
    mmu_on();
}
