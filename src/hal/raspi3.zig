const std = @import("std");
const Allocator = std.mem.Allocator;

const arch = @import("../architecture.zig");
const hal = @import("../hal.zig");
const memory = @import("../memory.zig");

pub const bcm_board_info = @import("../drivers/bcm_board_info.zig");
pub const bcm_dma = @import("../drivers/bcm_dma.zig");
pub const bcm_mailbox = @import("../drivers/bcm_mailbox.zig");
pub const bcm_peripheral_clocks = @import("../drivers/bcm_peripheral_clocks.zig");
pub const bcm_video = @import("../drivers/bcm_video_controller.zig");
pub const arm_local_interrupt = @import("../drivers/arm_local_interrupt_controller.zig");
pub const pl011 = @import("../drivers/pl011.zig");
pub const simple_bus = @import("../drivers/simple_bus.zig");
pub const dwc_otg_usb = @import("../drivers/dwc_otg_usb.zig");

pub const memory_map = @import("raspi3/memory_map.zig");
pub const peripheral_base = memory_map.peripheral_base;
pub const device_start = memory_map.device_start;

pub var allocator: *Allocator = undefined;
pub var soc_bus = simple_bus.SimpleBus{};
pub var local_interrupt_controller = arm_local_interrupt.LocalInterruptController{};
pub var mailbox = bcm_mailbox.BroadcomMailbox{};
pub var peripheral_clock_controller = bcm_peripheral_clocks.PeripheralClockController{};
pub var dma_controller = bcm_dma.BroadcomDMAController{};
pub var video_controller = bcm_video.BroadcomVideoController{};
pub var usb = dwc_otg_usb.UsbController{};

pub fn init(alloc: *Allocator) !void {
    allocator = alloc;

    try soc_bus.deviceTreeParse("soc");

    local_interrupt_controller.init(peripheral_base + 0xb200);
    hal.interrupt_controller = local_interrupt_controller.controller();

    mailbox.init(peripheral_base + 0xB880, hal.interrupt_controller, &soc_bus.bus_ranges);
    peripheral_clock_controller.init(&mailbox);

    dma_controller.init(allocator, peripheral_base + 0x7000, hal.interrupt_controller, &soc_bus.dma_ranges);
    hal.dma_controller = dma_controller.dma();

    video_controller.init(&mailbox, hal.dma_controller);
    hal.video_controller = video_controller.controller();

    usb.init(peripheral_base + 0x980000, hal.interrupt_controller, &soc_bus.bus_ranges);
    hal.usb = usb.usb();
}
