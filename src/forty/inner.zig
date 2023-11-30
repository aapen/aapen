const std = @import("std");

const serial = @import("../serial.zig");

const memory_module = @import("memory.zig");
const Header = memory_module.Header;
const Forth = @import("forth.zig").Forth;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

/// There is no magic in the value of opcode_base except that
/// the 888 tends to stand out in a memory dump.
const opcode_base: u64 = 0x888000;

/// The heart of the interpreter are these op codes plus
/// pointers to WordFunction function. We can always tell the
/// difference because all of the op code values are odd.
pub const OpCode = enum(u64) {
    Return = opcode_base + 0x1,
    CallSecondary = opcode_base + 0x3,
    PushU64 = opcode_base + 0x5,
    PushString = opcode_base + 0x7,
    JumpIfNot = opcode_base + 0x9,
    JumpIfRLE = opcode_base + 0xb,
    Drop = opcode_base + 0xd,
    IDrop = opcode_base + 0xf,
    Dup = opcode_base + 0x11,
    Swap = opcode_base + 0x13,
    IncIStack = opcode_base + 0x15,
    Jump = opcode_base + 0x17,
    ToIStack = opcode_base + 0x19,
    ToDStack = opcode_base + 0x1b,
};

pub fn isOpCode(i: u64) bool {
    if (i < opcode_base or i > @intFromEnum(OpCode.ToDStack)) {
        return false;
    } else if (i % 2 == 0) {
        return false;
    }
    return true;
}

pub fn executeHeader(forth: *Forth, header: *Header) !void {
    try forth.call_stack.push(@intFromPtr(header));
    try forth.call_stack.push(0);
    defer {
        _ = forth.call_stack.pop() catch {};
        _ = forth.call_stack.pop() catch {};
    }
    try header.func(forth, header);
}

// Run the secondary word pointed at by head. Iterate thru the body
// of head, executing each instruction in turn.
// Generally this function only gets called by the outter (i.e. command line)
// interpreter. When a secondary word has a call to another secondary,
// the body of the calling word will contain a CallSecondary instruction
// which is handled inside of the single invocation of innner w/o any
// recursive calls.
pub fn inner(forth: *Forth, head: *Header) ForthError!void {
    var header: *Header = head;
    var body = header.bodyOfType([*]u64);
    var i: u64 = 0;

    const initialStackDepth = forth.call_stack.depth();

    while (true) {
        try forth.trace("Loop {*}\t{}\t{x} -- ", .{ body, i, body[i] });
        switch (body[i]) {
            // Call a secondary: Push the current execution state onto the istack and
            // replace them with the start of the called word.
            @intFromEnum(OpCode.CallSecondary) => {
                try forth.call_stack.push(@intFromPtr(header));
                try forth.call_stack.push(i + 2);
                const p: *Header = @ptrFromInt(body[i + 1]);
                try forth.trace("Call Secondary: from {s} -> {*} {s}\n", .{ header.name, p, p.name });
                i = 0;
                header = p;
                body = header.bodyOfType([*]u64);
            },

            // Return from a secondary: Restore the current execution state from
            // the istack. If the istack is the depth we started with then
            // it's time to return from *this* secondary so break out of the loop.
            @intFromEnum(OpCode.Return) => {
                //try forth.trace("Return from [{s}]\n", .{header.name});
                if (forth.call_stack.depth() == initialStackDepth) {
                    //try forth.trace("Return from inner\n", .{});
                    break;
                }
                i = try forth.call_stack.pop();
                header = @as(*Header, @ptrFromInt(try forth.call_stack.pop()));
                body = header.bodyOfType([*]u64);
                try forth.trace("back in {s}, header: {*} i {}\n", .{ header.name, header, i });
            },

            @intFromEnum(OpCode.PushU64) => {
                const v = body[i + 1];
                try forth.stack.push(v);
                i += 2;
            },

            @intFromEnum(OpCode.PushString) => {
                const data_size = body[i + 1];
                var p_string: [*]u8 = @ptrCast(body + i + 2);
                try forth.stack.push(@intFromPtr(p_string));
                i = i + data_size + 2;
            },

            @intFromEnum(OpCode.Jump) => {
                const delta: i64 = @as(i64, @bitCast(body[i + 1]));
                var new_i: i64 = @intCast(i);
                new_i = new_i + delta;
                i = @intCast(new_i);
            },

            @intFromEnum(OpCode.JumpIfNot) => {
                var c: u64 = try forth.stack.pop();
                const delta: i64 = @as(i64, @bitCast(body[i + 1]));
                try forth.trace("JumpIfNot cond: {} delta {} ", .{ c, delta });
                if (c == 0) {
                    const new_i = @as(i64, @intCast(i)) + delta;
                    i = @intCast(new_i);
                } else {
                    i += 2;
                }
                try forth.trace(": -> {}\n", .{i});
            },

            // Jump if top value of the loop stack is <= the 2nd value.
            // Does not modify the loop stack.
            @intFromEnum(OpCode.JumpIfRLE) => {
                var first: u64 = try forth.istack.pop();
                var second: u64 = try forth.istack.pop();
                try forth.istack.push(second);
                try forth.istack.push(first);

                const delta: i64 = @as(i64, @bitCast(body[i + 1]));
                try forth.trace("JumpIfRLE first {} second {} target {} ", .{ first, second, delta });

                if (second <= first) {
                    const new_i = @as(i64, @intCast(i)) + delta;
                    i = @intCast(new_i);
                } else {
                    i += 2;
                }
                try forth.trace(": -> {}\n", .{i});
            },

            @intFromEnum(OpCode.Drop) => {
                _ = try forth.stack.pop();
                i += 1;
            },

            @intFromEnum(OpCode.IDrop) => {
                _ = try forth.istack.pop();
                i += 1;
            },

            @intFromEnum(OpCode.Dup) => {
                const a = try forth.stack.pop();
                try forth.stack.push(a);
                try forth.stack.push(a);
                i += 1;
            },

            @intFromEnum(OpCode.Swap) => {
                const a = try forth.stack.pop();
                const b = try forth.stack.pop();
                try forth.stack.push(a);
                try forth.stack.push(b);
                i += 1;
            },

            @intFromEnum(OpCode.IncIStack) => {
                const v = try forth.istack.pop() + 1;
                try forth.istack.push(v);
                i += 1;
            },

            @intFromEnum(OpCode.ToIStack) => {
                const v = try forth.stack.peek();
                try forth.istack.push(v);
                i += 1;
            },

            @intFromEnum(OpCode.ToDStack) => {
                const v = try forth.istack.peek();
                try forth.stack.push(v);
                i += 1;
            },

            // If body[i] is not an opcode then it must be a pointer
            // to the primitive.
            else => {
                const p: *Header = @ptrFromInt(body[i]);
                try forth.trace("Call: {s}\n", .{p.name});
                try forth.call_stack.push(@intFromPtr(p));
                try forth.call_stack.push(0);
                try p.func(forth, p);
                _ = try forth.call_stack.pop();
                _ = try forth.call_stack.pop();
                i += 1;
            },
        }
    }
    try forth.trace("inner returning\n", .{});
}
