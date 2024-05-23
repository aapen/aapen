const Forth = @import("forty/forth.zig").Forth;
const fb = @import("frame_buffer.zig");

pub fn defineModule(forth: *Forth) !void {
    try forth.defineConstant("mouse-x", @intFromPtr(&x));
    try forth.defineConstant("mouse-y", @intFromPtr(&y));
    try forth.defineConstant("mouse-buttons", @intFromPtr(&buttons));
}

pub fn getMouseX() i16 {
    return x;
}

pub fn getMosueY() i16 {
    return y;
}

pub var x_max: i16 = @intCast(fb.DEFAULT_X_RESOLUTION);
pub var y_max: i16 = @intCast(fb.DEFAULT_Y_RESOLUTION);

pub var x: i16 = 0;
pub var y: i16 = 0;
pub var dx: i8 = 0;
pub var dy: i8 = 0;
pub var buttons: u8 = 0;

pub fn update(new_buttons: u8, x_move: i8, y_move: i8) void {
    buttons = new_buttons;
    dx = x_move;
    dy = y_move;
    x = clamp(i16, 0, x + dx, x_max);
    y = clamp(i16, 0, y + dy, y_max);
}

inline fn clamp(comptime T: type, min: T, val: T, max: T) T {
    return @max(min, @min(val, max));
}