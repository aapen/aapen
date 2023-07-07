extern fn global_enable_irq() void;
extern fn global_disable_irq() void;

pub fn init() void {
    global_enable_irq();
}

pub fn disable() void {
    global_disable_irq();
}

pub fn enable() void {
    global_enable_irq();
}
