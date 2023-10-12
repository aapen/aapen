const std = @import("std");
const Allocator = std.mem.Allocator;

const devicetree = @import("devicetree.zig");

pub const interfaces = @import("hal/interfaces.zig");
pub const detect = @import("hal/detect.zig");
pub const common = @import("hal/common.zig");

pub var dma_controller: *interfaces.DMAController = undefined;
pub var irq_thunk: common.IrqThunk = undefined;
pub var info_controller: *interfaces.BoardInfoController = undefined;
pub var interrupt_controller: common.InterruptController = undefined;
pub var timer: *interfaces.Timer = undefined;
pub var clock: *interfaces.Clock = undefined;
pub var serial: *interfaces.Serial = undefined;
pub var usb: *interfaces.USB = undefined;
pub var video_controller: *interfaces.VideoController = undefined;

const SerialWriter = std.io.Writer(*interfaces.Serial, error{}, serialStringSend);

pub var serial_writer: SerialWriter = undefined;

fn serialStringSend(uart: *interfaces.Serial, str: []const u8) !usize {
    return uart.puts(uart, str);
}

pub fn init(root: *devicetree.Fdt.Node, allocator: *Allocator) !void {
    try detect.detectAndInit(root, allocator);
    serial_writer = SerialWriter{ .context = serial };
}
