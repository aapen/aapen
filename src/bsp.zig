// TODO: Choose the value of `io` based on the boot-time hardware.
// TODO (alternative): Choose the value of `io` based on a comptime definition.
pub const io = @import("bsp/raspi3/io.zig");
