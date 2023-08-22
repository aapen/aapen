const std = @import("std");
const Allocator = std.mem.Allocator;

const bsp = @import("../bsp.zig");
const fbcons = @import("../fbcons.zig");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const stack = @import("stack.zig");
const DataStack = stack.Stack(u64);
const ReturnStack = stack.Stack(i32);

const string = @import("string.zig");
const parser = @import("parser.zig");
const memory = @import("memory.zig");

const forth_module = @import("forth.zig");
const Forth = forth_module.Forth;
const OpCode = forth_module.OpCode;
const WordFunction = forth_module.WordFunction;

const formatText = std.fmt.formatText;
const FormatOptions = std.fmt.FormatOptions;

const memory_module = @import("memory.zig");
const Header = memory_module.Header;

const InvalidOffset = std.math.maxInt(u64);

inline fn intFromPtr(comptime ResultType: type, p: anytype) ResultType {
    return @intCast(@intFromPtr(p));
}

inline fn sizeOf(comptime ResultType: type, comptime T: type) ResultType {
    return @intCast(@sizeOf(T));
}

inline fn addDelta(i: u64, delta: i64) u64 {
    const result: i64 = @as(i64, @intCast(i)) + delta;
    return @intCast(result);
}

inline fn wordOffset(a: anytype, b: anytype) i64 {
    const i_a: i64 = intFromPtr(i64, a);
    const i_b: i64 = intFromPtr(i64, b);
    const diff = i_a - i_b;
    return @divTrunc(diff, sizeOf(i64, u64));
}

// This is the inner interpreter, effectively the word
// that runs all the secondary words.
pub fn inner(forth: *Forth, _: [*]u64, _: u64, header: *Header) ForthError!u64 {
    var body = header.bodyOfType([*]u64);
    var i: usize = 0;
    while (true) {
        try forth.trace("{:4}: {x:4}: ", .{ i, body[i] });
        switch (body[i]) {
            @intFromEnum(OpCode.stop) => break,

            @intFromEnum(OpCode.push_u64) => {
                try forth.trace("Push {x}\n", .{body[i + 1]});
                try forth.stack.push(body[i + 1]);
                i += 2;
            },

            @intFromEnum(OpCode.push_string) => {
                try forth.trace("Push string len: {}\n", .{body[i + 1]});
                const data_size = body[i + 1];
                var p_string: [*]u8 = @ptrCast(body + i + 2);
                try forth.stack.push(@intFromPtr(p_string));
                i += data_size + 2;
            },

            @intFromEnum(OpCode.jump) => {
                const delta: i64 = @as(i64, @bitCast(body[i + 1]));
                i = addDelta(i, delta);
                try forth.trace("Jump -> {}\n", .{i});
            },

            @intFromEnum(OpCode.jump_if_not) => {
                var c: u64 = try forth.stack.pop();
                const delta: i64 = @as(i64, @bitCast(body[i + 1]));
                try forth.trace("JumpIfNot cond: {} target {} ", .{ c, delta });

                if (c == 0) {
                    i = addDelta(i, delta);
                    try forth.trace(" -> {}\n", .{i});
                } else {
                    i = i + 2;
                    try forth.trace(" {}\n", .{i});
                }
            },

            else => {
                const p: *Header = @ptrFromInt(body[i]);
                try forth.trace("Header: {x}\n", .{body[i]});
                const delta = try p.func(forth, body, i, p);
                i = i + 1 + delta;
            },
        }
    }
    return 0;
}

// Push the address of the word body onto the stack.
pub fn pushBodyAddress(forth: *Forth, _: [*]u64, _: u64, header: *Header) ForthError!u64 {
    var body = header.bodyOfType([*]u8);
    try forth.stack.push(@intFromPtr(body));
    return 0;
}

// Create a new dictionary definition.
// Resulting dictionary entry just pushes its body address onto the stack.
// This is a fairly low level word.
pub fn wordCreate(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertNotCompiling();

    var name = forth.words.next() orelse return ForthError.WordReadError;
    var token = forth.words.peek();
    var desc: []const u8 = "";
    if (token) |t| {
        if (parser.isComment(t)) {
            _ = forth.words.next() orelse return ForthError.WordReadError;
            desc = try parser.parseComment(t);
        }
    }
    _ = try forth.create(name, desc, &pushBodyAddress, 0);
    return 0;
}

// Finish out a word created with create.
// Currently just fills in the length of the word.
pub fn wordFinish(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    forth.complete();
    return 0;
}

// Allocate a word in the dictionary and set its value to TOS.
// Should be between a create/finish pair, but this is not checked.
pub fn wordComma(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const value = try forth.stack.pop();
    //const addr = forth.allocate(@alignOf(u64), @sizeOf(u64));
    //const wordAddr: [*]u64 = @alignCast(@ptrCast(addr));
    //wordAddr[0] = value;
    forth.addNumber(value);
    return 0;
}

// Allocate a word in the dictionary and set its value to the string point to by TOS.
// Should be between a create/finish pair, but this is not checked.
pub fn wordSComma(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const value = try forth.stack.pop();
    const s: [*:0]const u8 = @ptrFromInt(value);
    forth.addString(s[0..string.strlen(s)]);
    return 0;
}

// Allocate n words in the dictionary. Should be in the middle
// of a create/finish pair, but this is not checked.
pub fn wordAllot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const n = try forth.stack.pop();
    _ = forth.allocate(@alignOf(u64), n * @sizeOf(u64));
    return 0;
}

// Temporarily turn compile mode off.
pub fn wordLBrace(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertCompiling();
    forth.compiling = 0;
    return 0;
}

// Turn compile mode back on.
pub fn wordRBrace(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertNotCompiling();
    forth.compiling = 1;
    return 0;
}

// Begin the definition of a new secondary word.
pub fn wordColon(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertNotCompiling();
    var name = forth.words.next() orelse return ForthError.WordReadError;
    var token = forth.words.peek() orelse return ForthError.WordReadError;
    var desc: []const u8 = "";
    if (parser.isComment(token)) {
        _ = forth.words.next() orelse return ForthError.WordReadError;
        desc = try parser.parseComment(token);
    }
    _ = try forth.startWord(name, desc, &inner, 0);
    return 0;
}

// Complete a secondary word.
pub fn wordSemi(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertCompiling();
    forth.addOpCode(OpCode.stop);
    try forth.completeWord();
    return 0;
}

pub fn wordDesc(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var name = forth.words.next() orelse return ForthError.WordReadError;
    var header = forth.findWord(name) orelse return ForthError.NotFound;
    try forth.print("{s}: {s}\n", .{ header.name, header.desc });
    return 0;
}

pub fn wordDumpWord(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var name = forth.words.next() orelse return ForthError.WordReadError;
    var header = forth.findWord(name) orelse return ForthError.NotFound;

    // Dump info about a primitive word.

    if (header.func != &inner) {
        const h: u64 = @intFromPtr(header);
        const p: u64 = @intFromPtr(header.func);
        try forth.print("Word name: {s} header: {x} func: {x}\n", .{ header.name, h, p });
        try forth.print("Description: {s}\n", .{header.desc});
        return 0;
    }

    // Word is a secondary, dump the meta info first.

    var body = header.bodyOfType([*]u64);
    var len = header.bodyLen();
    try forth.print("Word name: {s} len: {} immed: {}\n", .{ header.name, len, header.immediate });
    try forth.print("Description: {s}\n", .{header.desc});


    // Followed by a byte dump.

    try forth.print("Bytes:", .{});
    var cbody = header.bodyOfType([*]u8);
    for (0..len) |j| {
        const ch = cbody[j];
        const vis_ch = if ((ch >= ' ') and (ch <= '~')) ch else '.';
        if ((j % 8) == 0) {
            try forth.print("\n{:4}: ", .{j/8});
        }
        try forth.print("{c}[{x:2}]  ", .{ vis_ch, ch });
    }
    try forth.print("\n\nInstructions:\n", .{});

    // Followed by a dump of the instructions.
    var i: usize = 0;
    while (true) {
        try forth.print("{:4} {x:8}: ", .{i, body[i]});
        switch (body[i]) {
            @intFromEnum(OpCode.stop) => {
                try forth.print("Stop\n", .{});
                break;
            },

            @intFromEnum(OpCode.push_u64) => {
                try forth.print("PushU64 {x:2}\n", .{body[i + 1] });
                i += 2;
            },

            @intFromEnum(OpCode.push_string) => {
                const data_size = body[i + 1];
                var p_string: [*:0]u8 = @ptrCast(body + i + 2);
                try forth.print("PushString [{}] {s}\n", .{data_size, p_string });
                i += data_size + 2;
            },

            @intFromEnum(OpCode.jump) => {
                const offset: i64 = @bitCast(body[i + 1]);
                try forth.print("Jump [{}]\n", .{offset });
                i = i + 2;
            },

            @intFromEnum(OpCode.jump_if_not) => {
                const offset: i64 = @bitCast(body[i + 1]);
                try forth.print("JumpIfNot [{}]\n", .{offset });
                i = i + 2;
            },
            else => {
                try forth.print("Call\n", .{});
                i = i + 1;
            },
        }
    }
    return 0;
}

// n --  : Jump relative
pub fn wordJump(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertCompiling();
    var s_offset = forth.words.next() orelse return ForthError.WordReadError;
    try forth.print("Offset: {s}\n", .{s_offset});
    var i = try parser.parseNumber(s_offset, forth.ibase);
    forth.addOpCode(OpCode.jump);
    forth.addNumber(i);
    return 0;
}

// Compiler word, generate the code for an if.
// Emits an jump_if_not instruction with an invalid target address
// and pushes the address of the target address onto the rstack.
pub fn wordIf(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertCompiling();
    forth.addOpCode(OpCode.jump_if_not);
    try forth.rstack.push(@intFromPtr(forth.current()));
    forth.addNumber(InvalidOffset);
    return 0;
}

// Compiler word, generate the code for the else of if/else/endif.
// Generates an unconditional jump instruction with an invalid target address,
// pops the address (pushed by if) off of the rstack and plugs in the address
// just after the jump instruction.
pub fn wordElse(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertCompiling();

    const if_jump_p = try forth.rstack.pop();
    const if_jump_p_u64: [*]u64 = @ptrFromInt(if_jump_p);

    // Add the else jump instruction and push its address onto the stack
    // to be filled in later by endif.

    forth.addOpCode(OpCode.jump);
    try forth.rstack.push(@intFromPtr(forth.current()));
    forth.addNumber(InvalidOffset);

    // Back fill the jump address for the If.

    const current = memory.alignByType(forth.current(), u64);
    const jump_addr = wordOffset(current, if_jump_p_u64) + 1;
    if_jump_p_u64[0] = @bitCast(jump_addr);

    return 0;
}

// Compiler word, generate the end code for if/endif or if/else/endif.
// Pops the address off of the rstack and plugs in the offset to the
// current instuction.
pub fn wordEndif(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertCompiling();

    const if_jump_p = try forth.rstack.pop();
    const if_jump_p_u64: [*]u64 = @ptrFromInt(if_jump_p);

    const current = memory.alignByType(forth.current(), u64);

    const jump_addr = wordOffset(current, if_jump_p_u64) + 1;

    if_jump_p_u64[0] = @bitCast(jump_addr);
    return 0;
}

// Compiler word, generate the code for the begining of a while loop.
// Just pushes the current address onto the rstack.
// Structure of a while loop is:  while <cond> do <body> done
pub fn wordWhile(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertCompiling();
    try forth.rstack.push(@intFromPtr(forth.current()));
    return 0;
}

// Compiler word, generate the code for do, which ends the condition part of a while loop.
// Emits an jump_if_not instruction with an invalid target address (done will fill it in)
// and pushes the address of the target address onto the rstack.
pub fn wordDo(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertCompiling();
    forth.addOpCode(OpCode.jump_if_not);
    try forth.rstack.push(@intFromPtr(forth.current()));
    forth.addNumber(InvalidOffset);
    return 0;
}

// Compiler word, generate the end code for the end of a while loop.
// Pops the address of the jump_if_not target and the address of the
// beginning of the loop off of the rstack.
// Generates the jump back to the beginning of the loop and
// fills in the jump-if-not target with the post loop address.
pub fn wordDone(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertCompiling();

    const do_p: [*]u64 = @ptrFromInt(try forth.rstack.pop());
    const while_p: [*]u64 = @ptrFromInt(try forth.rstack.pop());


    // Add jump to begining of the loop instruction.

    forth.addOpCode(OpCode.jump);
    var current_p = memory.alignByType(forth.current(), u64);
    const while_offset = wordOffset(while_p, current_p) + 1;
    forth.addNumber(@bitCast(while_offset));
    
    // Fill in the conditional jump target that exits the loop.
    current_p = memory.alignByType(forth.current(), u64);
    const do_offset = wordOffset(current_p, do_p) + 1;
    do_p[0] = @bitCast(do_offset);
    
    return 0;
}

pub fn wordToRStack(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const v = try forth.stack.pop();
    try forth.rstack.push(v);
    return 0;
}

pub fn wordFromRStack(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const v = try forth.rstack.pop();
    try forth.stack.push(v);
    return 0;
}

/// --
pub fn wordRStack(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    for (forth.rstack.items()) |item| {
        try forth.print("{}\n", .{item});
    }
    return 0;
}

pub fn defineCompiler(forth: *Forth) !void {
    // Expose internal values to forty.

    try forth.defineInternalVariable("compiling", &forth.compiling);
    try forth.defineInternalVariable("debug", &forth.debug);
    try forth.defineInternalVariable("last-word", @ptrCast(&forth.lastWord));
    try forth.defineInternalVariable("new-word", @ptrCast(&forth.newWord));

    try forth.defineConstant("header-name-offset", @offsetOf(Header, "name"));
    try forth.defineConstant("header-func-offset", @offsetOf(Header, "func"));
    try forth.defineConstant("header-desc-offset", @offsetOf(Header, "desc"));
    try forth.defineConstant("header-immediate-offset", @offsetOf(Header, "immediate"));
    try forth.defineConstant("header-previous-offset", @offsetOf(Header, "previous"));
    try forth.defineConstant("header-len-offset", @offsetOf(Header, "len"));

    try forth.defineConstant("inner", @intFromPtr(&inner));
    try forth.defineConstant("opcode-stop", @intFromEnum(OpCode.stop));
    try forth.defineConstant("opcode-push-u64", @intFromEnum(OpCode.push_u64));
    try forth.defineConstant("opcode-push-string", @intFromEnum(OpCode.push_string));
    try forth.defineConstant("opcode-jump", @intFromEnum(OpCode.jump));
    try forth.defineConstant("opcode-jump-if-not", @intFromEnum(OpCode.jump_if_not));

    // Return stack.

    _ = try forth.definePrimitiveDesc("->rstack", " n -- : Push the TOS onto the rstack", &wordToRStack, 0);
    _ = try forth.definePrimitiveDesc("<-rstack", " -- n : Pop the rstack and push value onto data stack", &wordFromRStack, 0);
    _ = try forth.definePrimitiveDesc("rstack", " -- :Print the return stack.", &wordRStack, 0);


    // Secondary definition words.

    _ = try forth.definePrimitiveDesc(":", " -- :Start a new word definition", &wordColon, 0);
    _ = try forth.definePrimitiveDesc(";", " -- :Complete a new word definition", &wordSemi, 1);

    _ = try forth.definePrimitiveDesc("{", " -- : Temp turn off compile mode.", &wordLBrace, 1);
    _ = try forth.definePrimitiveDesc("}", " -- : Turn compile mode back on", &wordRBrace, 1);
    _ = try forth.definePrimitiveDesc("create", " -- :Start a new definition", &wordCreate, 0);
    _ = try forth.definePrimitiveDesc("finish", " -- :Complete a new definition", &wordFinish, 0);
    _ = try forth.definePrimitiveDesc(",", " n -- :Allocate a word and store n in it.", &wordComma, 0);
    _ = try forth.definePrimitiveDesc("s,", " n -- :Add a string to memory.", &wordSComma, 0);
    _ = try forth.definePrimitiveDesc("allot", " n -- :Allocate n words.", &wordAllot, 0);

    _ = try forth.definePrimitiveDesc("if", " -- :If statement", &wordIf, 1);
    _ = try forth.definePrimitiveDesc("else", " -- :Part of if/else/endif", &wordElse, 1);
    _ = try forth.definePrimitiveDesc("endif", " -- :Part of if/else/endif", &wordEndif, 1);
    _ = try forth.definePrimitiveDesc("$jump", " -- :Compile in a jump instruction", &wordJump, 1);

    _ = try forth.definePrimitiveDesc("while", " -- :Compile the head of a while loop.", &wordWhile, 1);
    _ = try forth.definePrimitiveDesc("do", " -- :Compile the condition part of a while loop.", &wordDo, 1);
    _ = try forth.definePrimitiveDesc("done", " -- :Compile the end of a while loop.", &wordDone, 1);

    _ = try forth.definePrimitiveDesc("?", " -- :Print description of word.", &wordDesc, 0);
    _ = try forth.definePrimitiveDesc("?word", " -- :Print details of word.", &wordDumpWord, 0);

}
