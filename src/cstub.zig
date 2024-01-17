const std = @import("std");

const c = @cImport({
    @cInclude("printf.h");
});

pub const printf = c.printf;
pub const sprintf = c.sprintf;
pub const vsprintf = c.vsprintf;
