const std = @import("std");
const root = @import("root");

const Forth = @import("forty/forth.zig");

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------

pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(@This(), .{.{ "disassemble", "disasm", "disassemble instruction, replace TOS with next addr" }});
}

// ----------------------------------------------------------------------
// Implementation
// ----------------------------------------------------------------------
extern fn disassemble_stub(addr: u64) u64;

pub fn disassemble(addr: u64) u64 {
    return disassemble_stub(addr);
}
