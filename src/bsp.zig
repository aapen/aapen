const std = @import("std");

pub const detect = @import("bsp/detect.zig");
pub const common = @import("bsp/common.zig");

pub var irq_thunk: common.IrqThunk = undefined;
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
