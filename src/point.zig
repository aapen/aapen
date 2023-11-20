const std = @import("std");

const serial = @import("serial.zig");

pub const Point = struct {
    x: u64,
    y: u64,

    pub fn init(x: u64, y: u64) Point {
        return Point{
            .x = x,
            .y = y,
        };
    }
};
