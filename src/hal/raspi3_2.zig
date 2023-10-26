pub const device_start: u64 = 0x3b40_0000;
pub const peripheral_base: u64 = 0x3f00_0000;

const memory = @import("../memory.zig");

// ARM devices
const arm_local_interrupt = @import("../drivers/arm_local_interrupt_controller.zig");
const arm_local_timer = @import("../drivers/arm_local_timer.zig");
const pl011 = @import("../drivers/pl011_2.zig");

// Broadcom devices
const simple_bus = @import("../drivers/simple_bus.zig");
const bcm_gpio = @import("../drivers/bcm_gpio.zig");
const bcm_mailbox = @import("../drivers/bcm_mailbox.zig");
const bcm_board_info = @import("../drivers/bcm_board_info.zig");

pub var arm_memory_range = memory.Region{ .name = "ARM memory" };
pub var videocore_memory_range = memory.Region{ .name = "Videocore memory" };

pub const BoardInfoController = bcm_board_info.BroadcomBoardInfoController;
pub const board_info_controller = BoardInfoController{
    .arm_memory_range = &arm_memory_range,
    .videocore_memory_range = &videocore_memory_range,
    .mailbox = &mailbox,
};

pub const InterruptController = arm_local_interrupt.LocalInterruptController;
pub const interrupt_controller = InterruptController{
    .registers = @ptrFromInt(peripheral_base + 0xb200),
};

pub const GPIO = bcm_gpio.BroadcomGpio2;
pub const gpio = GPIO{
    .registers = @ptrFromInt(peripheral_base + 0x200000),
};

pub const Mailbox = bcm_mailbox.BroadcomMailbox;
pub const mailbox = Mailbox{
    .registers = @ptrFromInt(peripheral_base + 0xB880),
    .intc2 = &interrupt_controller,
    .translations = &soc.bus_ranges,
};

pub const Serial = pl011.Pl011Uart;
pub const serial = pl011.Pl011Uart{
    .registers = @ptrFromInt(peripheral_base + 0x201000),
    .gpio = &gpio,
};

pub const SOC = simple_bus.SimpleBus;
pub const soc = SOC{
    //    .bus_ranges = null,
};

pub const Clock = arm_local_timer.FreeRunningCounter;
pub const clock = Clock{
    .count_low = @ptrFromInt(peripheral_base + 0x3004),
    .count_high = @ptrFromInt(peripheral_base + 0x3008),
};
