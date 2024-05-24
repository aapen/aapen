const std = @import("std");

const Forth = @import("forth.zig");
const Memory = @import("memory.zig");
const Header = Memory.Header;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

/// There is no magic in the value of opcode_base except that
/// the 888 tends to stand out in a memory dump.
const opcode_base: u64 = 0x888000;

/// The heart of the interpreter are these op codes plus
/// pointers to WordFunction function. We can always tell the
/// difference because all of the op code values are odd.
pub const OpCode = struct {
    pub const Return: u64 = opcode_base + 0x1;
    pub const CallSecondary: u64 = opcode_base + 0x3;
    pub const PushU64: u64 = opcode_base + 0x5;
    pub const PushString: u64 = opcode_base + 0x7;
    pub const JumpIfNot: u64 = opcode_base + 0x9;
    pub const JumpIfRLE: u64 = opcode_base + 0xb;
    pub const Drop: u64 = opcode_base + 0xd;
    pub const IDrop: u64 = opcode_base + 0xf;
    pub const Dup: u64 = opcode_base + 0x11;
    pub const Swap: u64 = opcode_base + 0x13;
    pub const IncIStack: u64 = opcode_base + 0x15;
    pub const Jump: u64 = opcode_base + 0x17;
    pub const ToIStack: u64 = opcode_base + 0x19;
    pub const ToDStack: u64 = opcode_base + 0x1b;
};

const NumOpCodes = (OpCode.ToDStack - opcode_base + 1) / 2;

const Names: [NumOpCodes][]const u8 = .{
    "Return",
    "CallSecondary",
    "PushU64",
    "PushString",
    "JumpIfNot",
    "JumpIfRLE",
    "Drop",
    "IDrop",
    "Dup",
    "Swap",
    "IncIStack",
    "Jump",
    "ToIStack",
    "ToDStack",
};

pub fn opCodeNameLookup(i: u64) []const u8 {
    if (isOpCode(i)) {
        const index = (i - opcode_base) / 2;
        return Names[index];
    }
    return "Not an opcode!";
}

pub fn isOpCode(i: u64) bool {
    if (i < opcode_base or i > OpCode.ToDStack) {
        return false;
    } else if (i % 2 == 0) {
        return false;
    }
    return true;
}

pub fn executeHeader(forth: *Forth, header: *Header) !void {
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
            OpCode.CallSecondary => {
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
            OpCode.Return => {
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

            OpCode.PushU64 => {
                const v = body[i + 1];
                try forth.stack.push(v);
                i += 2;
            },

            OpCode.PushString => {
                const data_size = body[i + 1];
                const p_string: [*]u8 = @ptrCast(body + i + 2);
                try forth.stack.push(@intFromPtr(p_string));
                i = i + data_size + 2;
            },

            OpCode.Jump => {
                const delta: i64 = @as(i64, @bitCast(body[i + 1]));
                var new_i: i64 = @intCast(i);
                new_i = new_i + delta;
                i = @intCast(new_i);
            },

            OpCode.JumpIfNot => {
                const c: u64 = try forth.stack.pop();
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
            OpCode.JumpIfRLE => {
                const first: u64 = try forth.istack.pop();
                const second: u64 = try forth.istack.pop();
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

            OpCode.Drop => {
                _ = try forth.stack.pop();
                i += 1;
            },

            OpCode.IDrop => {
                _ = try forth.istack.pop();
                i += 1;
            },

            OpCode.Dup => {
                const a = try forth.stack.pop();
                try forth.stack.push(a);
                try forth.stack.push(a);
                i += 1;
            },

            OpCode.Swap => {
                const a = try forth.stack.pop();
                const b = try forth.stack.pop();
                try forth.stack.push(a);
                try forth.stack.push(b);
                i += 1;
            },

            OpCode.IncIStack => {
                const v = try forth.istack.pop() + 1;
                try forth.istack.push(v);
                i += 1;
            },

            OpCode.ToIStack => {
                const v = try forth.stack.peek();
                try forth.istack.push(v);
                i += 1;
            },

            OpCode.ToDStack => {
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
