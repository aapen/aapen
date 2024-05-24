const Forth = @import("forty/forth.zig").Forth;
const memory = @import("forty/memory.zig");
const errors = @import("forty/errors.zig");

const fb = @import("frame_buffer.zig");

pub fn defineModule(forth: *Forth) !void {
    _ = try forth.definePrimitiveDesc("mouse", "-- btns y x : get mouse state", info, false);
}

pub fn info(forth: *Forth, _: *memory.Header) errors.ForthError!void {
    try forth.stack.push(buttons);
    try forth.stack.push(@max(0, y));
    try forth.stack.push(@max(0, x));
}

pub var x_max: i32 = @intCast(fb.DEFAULT_X_RESOLUTION);
pub var y_max: i32 = @intCast(fb.DEFAULT_Y_RESOLUTION);

pub var x: i32 = 0;
pub var y: i32 = 0;
pub var dx: i8 = 0;
pub var dy: i8 = 0;
pub var buttons: u8 = 0;

pub fn update(new_buttons: u8, x_move: i8, y_move: i8) void {
    buttons = new_buttons;
    dx = x_move;
    dy = y_move;
    x = clamp(i32, 0, x + dx, x_max);
    y = clamp(i32, 0, y + dy, y_max);
}

inline fn clamp(comptime T: type, min: T, val: T, max: T) T {
    return @max(min, @min(val, max));
}
