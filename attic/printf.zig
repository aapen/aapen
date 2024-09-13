const root = @import("root");
const term = @import("term.zig");

pub const printf = cstub.printf;
pub const vprintf = cstub.vprintf;
pub const sprintf = cstub.sprintf;
pub const vsprintf = cstub.vsprintf;

// ----------------------------------------------------------------------
// C interop
// ----------------------------------------------------------------------
var putc: *const fn (u8) void = noVideoPutc;

pub export fn _putchar(ch: u8) callconv(.C) c_int {
    putc(ch);
    return ch;
}

pub fn consoleIsReady() void {
    putc = videoEnabledPutc;
}

fn videoEnabledPutc(ch: u8) void {
    root.main_console.putc(ch);
}

fn noVideoPutc(ch: u8) void {
    term.putch(ch);
}

const cstub = @cImport({
    @cInclude("printf.h");
});
