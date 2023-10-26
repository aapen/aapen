const std = @import("std");

const config = @import("config");
const board_support = switch (config.board) {
    .pi3 => @import("hal/raspi3.zig"),
    inline else => @compileError("Unsupported board " ++ @tagName(config.board)),
};

pub const BoardInfoController = board_support.BoardInfoController;
pub const BoardInfo = board_support.BoardInfo;
pub const board_info_controller = &board_support.board_info_controller;

pub const Clock = board_support.Clock;
pub const clock = &board_support.clock;

pub const DMA = board_support.DMA;
pub const DMAChannel = board_support.DMAChannel;
pub const DMAError = board_support.DMAError;
pub const DMARequest = board_support.DMARequest;
pub const dma = &board_support.dma;

pub const GPIO = board_support.GPIO;
pub const gpio = &board_support.gpio;

pub const heap_start = board_support.heap_start;
pub const heap_end = board_support.heap_end;

pub const InterruptController = board_support.InterruptController;
pub const IrqId = board_support.IrqId;
pub const interrupt_controller = &board_support.interrupt_controller;

pub const PowerController = board_support.PowerController;
pub const PowerResult = board_support.PowerResult;
pub const power_controller = &board_support.power_controller;

pub const Serial = board_support.Serial;
pub const serial = &board_support.serial;

pub const Timer = board_support.Timer;
pub const TimerCallbackFn = board_support.TimerCallbackFn;
pub const timer = &board_support.timer;

pub const USB = board_support.USB;
pub const usb = &board_support.usb;

pub const VideoController = board_support.VideoController;
pub const video_controller = &board_support.video_controller;

const SerialWriter = std.io.Writer(*const Serial, error{}, serialStringSend);

pub const serial_writer: SerialWriter = .{
    .context = serial,
};

fn serialStringSend(uart: *const Serial, str: []const u8) !usize {
    return uart.puts(str);
}

pub fn init(allocator: std.mem.Allocator) !void {
    try board_support.init(allocator);
}
