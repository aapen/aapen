const std = @import("std");
const memory = @import("../memory.zig");
const Region = memory.Region;

// Memory map
pub const device_start: u64 = 0x3b40_0000;
pub const peripheral_base: u64 = 0x3f00_0000;
pub const heap_start: [*]u8 = @extern([*]u8, .{ .name = "__heap_start" });
pub const heap_end: usize = device_start - 1;

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

pub const BoardInfoController = bcm_board_info;
pub const Clock = arm_local_timer.Clock;
pub const DMA = bcm_dma;
pub const InterruptController = arm_local_interrupt;
pub const GPIO = bcm_gpio;
pub const Mailbox = bcm_mailbox;
pub const PowerController = bcm_power;
pub const SOC = simple_bus;
pub const Timer = arm_local_timer.Timer;
pub const TimerHandler = arm_local_timer.TimerHandler;
pub const TimerCallbackFn = arm_local_timer.TimerCallbackFn;
pub const Uart = pl011;
pub const USBHCI = dwc_otg_usb;
pub const VideoController = bcm_video_controller;

const Self = @This();

board_info_controller: BoardInfoController,
clock: Clock,
dma: DMA,
interrupt_controller: *InterruptController,
gpio: GPIO,
mailbox: Mailbox,
power_controller: PowerController,
uart: Uart,
soc: SOC,
system_timer: *Timer,
timer: [4]*Timer,
usb_hci: USBHCI,
video_controller: VideoController,

pub fn init(allocator: std.mem.Allocator) !*Self {
    var self: *Self = try allocator.create(Self);

    self.soc = SOC.init(allocator);

    try self.soc.appendBusRange(0x7e000000, 0x3f000000, 0x1000000);
    try self.soc.appendBusRange(0x40000000, 0x40000000, 0x1000);

    try self.soc.appendDmaRange(0xc0000000, 0x00, 0x3f000000);
    try self.soc.appendDmaRange(0x7e000000, 0x3f000000, 0x1000000);

    self.interrupt_controller = try InterruptController.init(allocator, peripheral_base + 0xb200);

    self.clock = Clock.init(peripheral_base + 0x3000);

    self.dma = DMA.init(allocator, peripheral_base + 0x7000, self.interrupt_controller, &self.soc.dma_ranges);

    self.gpio = GPIO.init(peripheral_base + 0x200000);

    self.mailbox = Mailbox.init(allocator, peripheral_base + 0xb880, &self.soc.bus_ranges);

    self.board_info_controller = BoardInfoController.init(&self.mailbox);

    self.power_controller = PowerController.init(&self.mailbox);

    self.uart = Uart.init(peripheral_base + 0x201000, &self.gpio);

    self.video_controller = VideoController.init(&self.mailbox, &self.dma);

    self.usb_hci = USBHCI.init(allocator, peripheral_base + 0x980000, self.interrupt_controller, &self.soc.bus_ranges, &self.power_controller, &self.clock);

    for (0..3) |timer_id| {
        self.timer[timer_id] = try Timer.init(allocator, timer_id, peripheral_base + 0x3000, &self.clock, self.interrupt_controller);
    }

    self.system_timer = self.timer[1];

    self.uart.initializeUart();

    return self;
}
