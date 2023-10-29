const std = @import("std");
const memory = @import("../memory.zig");

const memory_map = @import("raspi3/memory_map.zig");
const peripheral_base = memory_map.peripheral_base;

// ARM devices
const arm_local_interrupt = @import("../drivers/arm_local_interrupt_controller.zig");
const arm_local_timer = @import("../drivers/arm_local_timer.zig");
const pl011 = @import("../drivers/pl011.zig");

// Broadcom devices
const bcm_dma = @import("../drivers/bcm_dma.zig");
const bcm_gpio = @import("../drivers/bcm_gpio.zig");
const bcm_mailbox = @import("../drivers/bcm_mailbox.zig");
const bcm_board_info = @import("../drivers/bcm_board_info.zig");
const bcm_power = @import("../drivers/bcm_power.zig");
const bcm_video_controller = @import("../drivers/bcm_video_controller.zig");

// Other devices
const dwc_otg_usb = @import("../drivers/dwc_otg_usb.zig");
const simple_bus = @import("../drivers/simple_bus.zig");

pub const BoardInfoController = bcm_board_info.BroadcomBoardInfoController;
pub const BoardInfo = bcm_board_info.BoardInfo;
pub const board_info_controller = BoardInfoController{
    .mailbox = &mailbox,
};

pub const Clock = arm_local_timer.FreeRunningCounter;
pub const clock = Clock{
    .count_low = @ptrFromInt(peripheral_base + 0x3004),
    .count_high = @ptrFromInt(peripheral_base + 0x3008),
};

pub const DMA = bcm_dma.BroadcomDMAController;
pub const DMAChannel = bcm_dma.DMAChannel;
pub const DMARequest = bcm_dma.BroadcomDMARequest;
pub const DMAError = bcm_dma.DMAError;
pub const dma = DMA{
    .register_base = peripheral_base + 0x7000,
    .intc = &interrupt_controller,
    .interrupt_status = @ptrFromInt(peripheral_base + 0x7000 + 0xfe0),
    .transfer_enabled = @ptrFromInt(peripheral_base + 0x7000 + 0xff0),
    .translations = &soc.dma_ranges,
};

pub const InterruptController = arm_local_interrupt.LocalInterruptController;
pub const interrupt_controller = InterruptController{
    .registers = @ptrFromInt(peripheral_base + 0xb200),
};

pub const GPIO = bcm_gpio.BroadcomGpio;
pub const gpio = GPIO{
    .registers = @ptrFromInt(peripheral_base + 0x200000),
};

pub const heap_start = memory_map.heap_start;
pub const heap_end = memory_map.heap_end;

pub const Mailbox = bcm_mailbox.BroadcomMailbox;
pub const mailbox = Mailbox{
    .registers = @ptrFromInt(peripheral_base + 0xB880),
    .translations = &soc.bus_ranges,
};

pub const PowerController = bcm_power.BroadcomPowerController;
pub const PowerResult = bcm_power.PowerResult;
pub const power_controller = PowerController{
    .mailbox = &mailbox,
};

pub const Serial = pl011.Pl011Uart;
pub const serial = pl011.Pl011Uart{
    .registers = @ptrFromInt(peripheral_base + 0x201000),
    .gpio = &gpio,
};

pub const SOC = simple_bus.SimpleBus;
pub const soc = SOC{};

pub const Timer = arm_local_timer.Timer;
pub const TimerCallbackFn = arm_local_timer.TimerCallbackFn;
pub const timer: [4]Timer = [_]Timer{
    arm_local_timer.mktimer(0, peripheral_base + 0x3000, interrupt_controller),
    arm_local_timer.mktimer(1, peripheral_base + 0x3000, interrupt_controller),
    arm_local_timer.mktimer(2, peripheral_base + 0x3000, interrupt_controller),
    arm_local_timer.mktimer(3, peripheral_base + 0x3000, interrupt_controller),
};

const usb_base = peripheral_base + 0x980000;

pub const USB = dwc_otg_usb.UsbController;
pub const usb = dwc_otg_usb.UsbController{
    .core_registers = @ptrFromInt(usb_base),
    .host_registers = @ptrFromInt(usb_base + 0x400),
    .intc = &interrupt_controller,
    .power_controller = &power_controller,
    .translations = &soc.bus_ranges,
};

pub const VideoController = bcm_video_controller.BroadcomVideoController;
pub const video_controller = VideoController{
    .mailbox = &mailbox,
    .dma = &dma,
};

pub fn init(allocator: std.mem.Allocator) !void {
    try soc.init(allocator);

    try soc.appendBusRange(0x7e000000, 0x3f000000, 0x1000000);
    try soc.appendBusRange(0x40000000, 0x40000000, 0x1000);

    try soc.appendDmaRange(0xc0000000, 0x00, 0x3f000000);
    try soc.appendDmaRange(0x7e000000, 0x3f000000, 0x1000000);

    serial.init();
    dma.init(allocator);
}
