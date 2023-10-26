pub const device_start: u64 = 0x3b40_0000;
pub const peripheral_base: u64 = 0x3f00_0000;

const bcm_gpio = @import("../drivers/bcm_gpio.zig");
const pl011 = @import("../drivers/pl011_2.zig");

pub const gpio = bcm_gpio.BroadcomGpio2{
    .registers = @ptrFromInt(peripheral_base + 0x200000),
};

pub const Serial = pl011.Pl011Uart;
pub const serial = pl011.Pl011Uart{
    .registers = @ptrFromInt(peripheral_base + 0x201000),
    .gpio = &gpio,
};
