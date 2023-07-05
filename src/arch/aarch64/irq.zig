extern fn global_enable_irq() void;

pub fn init() void {
    global_enable_irq();
}
