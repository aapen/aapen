const std = @import("std");

const Self = @This();

valid: bool,
left: u64,
right: u64,
top: u64,
bottom: u64,

pub fn init(l: u64, r: u64, t: u64, b: u64) Self {
    return Self{
        .valid = true,
        .left = l,
        .right = r,
        .top = t,
        .bottom = b,
    };
}

pub fn invalid() Self {
    return Self{ .valid = false, .left = 1, .right = 0, .top = 1, .bottom = 0 };
}

pub fn contains(self: *const Self, x: u64, y: u64) bool {
    if (!self.valid) {
        return false;
    }
    return x >= self.left and x < self.right and y >= self.top and y < self.bottom;
}

pub fn expand(self: *Self, x: u64, y: u64) void {
    if (self.valid) {
        self.left = @min(x, self.left);
        self.right = @max(x + 1, self.right);
        self.top = @min(y, self.top);
        self.bottom = @max(y + 1, self.bottom);
    } else {
        self.valid = true;
        self.left = x;
        self.right = x + 1;
        self.top = y;
        self.bottom = y + 1;
    }
}

pub fn scrollUp(self: *Self) void {
    if (self.valid) {
        self.top = @max(0, self.top - 1);
        self.bottom = @max(0, self.bottom - 1);
    }
    // Have we scrolled off of the top?
    if (self.bottom <= self.top) {
        self.valid = false;
    }
}
