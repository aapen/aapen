const arch = @import("../architecture.zig");

const bsp = @import("../bsp.zig");

const memory = @import("../memory.zig");
const AddressTranslations = memory.AddressTranslations;

pub const common = @import("common.zig");

pub const bcm_board_info = @import("../drivers/bcm_board_info.zig");
pub const bcm_mailbox = @import("../drivers/bcm_mailbox.zig");
pub const bcm_peripheral_clocks = @import("../drivers/bcm_peripheral_clocks.zig");
pub const bcm_power = @import("../drivers/bcm_power.zig");
pub const bcm_video_controller = @import("../drivers/bcm_video_controller.zig");
pub const bcm_gpio = @import("../drivers/bcm_gpio.zig");
pub const interrupts = @import("../drivers/arm_local_interrupt_controller.zig");
pub const pl011 = @import("../drivers/pl011.zig");
pub const simple_bus = @import("../drivers/simple_bus.zig");
pub const timer = @import("../drivers/arm_local_timer.zig");
pub const dwc_otg_usb = @import("../drivers/dwc_otg_usb.zig");

pub const memory_map = @import("raspi3/memory_map.zig");
pub const peripheral_base = memory_map.peripheral_base;
pub const device_start = memory_map.device_start;

pub var soc_bus = simple_bus.SimpleBus{};
pub var local_interrupt_controller = interrupts.LocalInterruptController{};
pub var gpio = bcm_gpio.BroadcomGpio{};
pub var pl011_uart = pl011.Pl011Uart{};
pub var mailbox = bcm_mailbox.BroadcomMailbox{};
pub var peripheral_clock_controller = bcm_peripheral_clocks.PeripheralClockController{};
pub var video_controller = bcm_video_controller.BroadcomVideoController{};
pub var power_controller = bcm_power.PowerController{};
pub var board_info_controller = bcm_board_info.BroadcomBoardInfoController{};
pub var usb = dwc_otg_usb.UsbController{};

pub fn init() !void {
    try soc_bus.deviceTreeParse("soc");

    local_interrupt_controller.init(peripheral_base + 0xb200);
    bsp.interrupt_controller = local_interrupt_controller.controller();
    bsp.irq_thunk = irqHandleThunk;

    timer.init(peripheral_base + 0x3000, &bsp.interrupt_controller);
    bsp.timer = timer.timers[1].timer();
    bsp.clock = timer.counter.clock();

    gpio.init(peripheral_base + 0x200000);

    pl011_uart.init(peripheral_base + 0x201000, &bsp.interrupt_controller, &gpio);
    bsp.serial = pl011_uart.serial();

    mailbox.init(peripheral_base + 0xB880, &bsp.interrupt_controller, &soc_bus.bus_ranges);
    peripheral_clock_controller.init(&mailbox);
    power_controller.init(&mailbox);

    board_info_controller.init(&mailbox);
    bsp.info_controller = board_info_controller.controller();

    video_controller.init(&mailbox);
    bsp.video_controller = video_controller.controller();

    usb.init(peripheral_base + 0x980000, &bsp.interrupt_controller, &soc_bus.bus_ranges, &power_controller);
    bsp.usb = usb.usb();
}

pub fn irqHandleThunk(context: *const arch.cpu.exceptions.ExceptionContext) void {
    local_interrupt_controller.irqHandle(context);
}
