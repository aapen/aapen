const memory = @import("../../memory.zig");
const Region = memory.Region;

// RPi 3
pub const device_start: u64 = 0x3b40_0000;
pub const peripheral_base: u64 = 0x3f00_0000;
pub const heap_start: [*]u8 = @extern([*]u8, .{ .name = "__heap_start" });
pub const heap_end: usize = device_start - 1;
