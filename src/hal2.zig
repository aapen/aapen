const std = @import("std");

const config = @import("config");
const board_support = switch (config.board) {
    .pi3 => @import("hal/raspi3_2.zig"),
    inline else => @compileError("Unsupported board " ++ @tagName(config.board)),
};

pub const Serial = board_support.Serial;
pub const serial = board_support.serial;

const SerialWriter = std.io.Writer(*const Serial, error{}, serialStringSend);

pub const serial_writer: SerialWriter = .{
    .context = &serial,
};

fn serialStringSend(uart: *const Serial, str: []const u8) !usize {
    return uart.puts(str);
}
