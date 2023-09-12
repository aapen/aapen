const std = @import("std");

pub const common = @import("bsp/common.zig");

pub const io = @import("bsp/raspi3/io.zig");
pub const memory = @import("bsp/raspi3/memory.zig");

pub var info_controller: common.BoardInfoController = undefined;
pub var interrupt_controller: common.InterruptController = undefined;
pub var timer: common.Timer = undefined;
pub var clock: common.Clock = undefined;
pub var serial: common.Serial = undefined;
pub var usb: common.USB = undefined;
pub var video_controller: common.VideoController = undefined;

const SerialWriter = std.io.Writer(u32, error{}, serialStringSend);
pub var serial_writer = SerialWriter{ .context = 0 };

fn serialStringSend(_: u32, str: []const u8) !usize {
    serial.puts(str);
    return str.len;
}
