// TODO: Choose the value of `io` based on the boot-time hardware.
// TODO (alternative): Choose the value of `io` based on a comptime definition.
pub const io = @import("bsp/raspi3/io.zig");
pub const interrupts = @import("bsp/raspi3/interrupts.zig");
pub const timer = @import("bsp/raspi3/timer.zig");
