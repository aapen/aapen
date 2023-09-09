const std = @import("std");

// TODO: Choose the value of `io` based on the boot-time hardware.
// TODO (alternative): Choose the value of `io` based on a comptime definition.
const arch = @import("architecture.zig");

pub const raspi3 = @import("bsp/raspi3.zig");

pub const common = @import("bsp/common.zig");

pub const io = @import("bsp/raspi3/io.zig");
pub const mailbox = @import("bsp/raspi3/mailbox.zig");
pub const memory = @import("bsp/raspi3/memory.zig");
//pub const usb = @import("bsp/raspi3/usb.zig");
pub const video = @import("bsp/raspi3/video.zig");

pub var interrupt_controller: common.InterruptController = undefined;
pub var timer: common.Timer = undefined;
pub var clock: common.Clock = undefined;
pub var serial: common.Serial = undefined;
pub var usb: common.USB = undefined;

const SerialWriter = std.io.Writer(u32, error{}, serialStringSend);
pub var serial_writer = SerialWriter{ .context = 0 };

fn serialStringSend(_: u32, str: []const u8) !usize {
    serial.puts(str);
    return str.len;
}
