// TODO: Choose the value of `io` based on the boot-time hardware.
// TODO (alternative): Choose the value of `io` based on a comptime definition.
pub const io = @import("bsp/raspi3/io.zig");
pub const interrupts = @import("bsp/raspi3/interrupts.zig");
pub const mailbox = @import("bsp/raspi3/mailbox.zig");
pub const memory = @import("bsp/raspi3/memory.zig");
pub const timer = @import("bsp/raspi3/timer.zig");
pub const usb = @import("bsp/raspi3/usb.zig");
pub const video = @import("bsp/raspi3/video.zig");
