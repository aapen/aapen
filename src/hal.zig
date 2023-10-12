const std = @import("std");
const Allocator = std.mem.Allocator;

const devicetree = @import("devicetree.zig");

pub const interfaces = @import("hal/interfaces.zig");
pub const detect = @import("hal/detect.zig");
pub const common = @import("hal/common.zig");

pub var dma_controller: common.DMAController = undefined;
pub var irq_thunk: common.IrqThunk = undefined;
pub var info_controller: common.BoardInfoController = undefined;
pub var interrupt_controller: common.InterruptController = undefined;
pub var timer: common.Timer = undefined;
pub var clock: common.Clock = undefined;
pub var serial: common.Serial = undefined;
pub var serial2: *interfaces.Serial = undefined;
pub var usb: common.USB = undefined;
pub var video_controller: common.VideoController = undefined;

const SerialWriter = std.io.Writer(*common.Serial, error{}, serialStringSend);

pub var serial_writer: SerialWriter = undefined;

fn serialStringSend(uart: *common.Serial, str: []const u8) !usize {
    return uart.puts(str);
}

pub fn init(root: *devicetree.Fdt.Node, allocator: *Allocator) !void {
    try detect.detectAndInit(root, allocator);
    serial_writer = SerialWriter{ .context = &serial };
}
