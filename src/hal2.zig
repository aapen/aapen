const std = @import("std");

const config = @import("config");
const board_support = switch (config.board) {
    .pi3 => @import("hal/raspi3_2.zig"),
    inline else => @compileError("Unsupported board " ++ @tagName(config.board)),
};

pub const BoardInfoController = board_support.BoardInfoController;
pub const board_info_controller = board_support.board_info_controller;

pub const Clock = board_support.Clock;
pub const clock = board_support.clock;

pub const GPIO = board_support.GPIO;
pub const gpio = board_support.gpio;

pub const InterruptController = board_support.InterruptController;
pub const interrupt_controller = board_support.interrupt_controller;

pub const PowerController = board_support.PowerController;
pub const power_controller = board_support.power_controller;

pub const Serial = board_support.Serial;
pub const serial = board_support.serial;

pub const Timer = board_support.Timer;
pub const timer = board_support.timer;

const SerialWriter = std.io.Writer(*const Serial, error{}, serialStringSend);

pub const serial_writer: SerialWriter = .{
    .context = &serial,
};

fn serialStringSend(uart: *const Serial, str: []const u8) !usize {
    return uart.puts(str);
}
