const std = @import("std");
const Allocator = std.mem.Allocator;

const hal = @import("../hal.zig");
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

pub fn pushBodyValue(forth: *Forth, _: [*]u64, _: u64, header: *Header) ForthError!i64 {
    var body = header.bodyOfType([*]u8);
    try forth.stack.push(body[0]);
    return 0;
}

pub fn wordLet(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const iName = try forth.stack.pop();
    const value = try forth.stack.pop();

    const name: [*:0]u8 = @ptrFromInt(iName);
    const len = string.strlen(name);

    _  = try forth.create(name[0..len], "A constant", &pushBodyValue, 0);
    forth.addNumber(value);
    forth.complete();
    return 0;
}

// Push the address of the word body onto the stack.
pub fn pushBodyAddress(forth: *Forth, _: [*]u64, _: u64, header: *Header) ForthError!i64 {
    var body = header.bodyOfType([*]u8);
    try forth.stack.push(@intFromPtr(body));
    return 0;
}


// Create a new dictionary definition.
// Resulting dictionary entry just pushes its body address onto the stack.
// This is a fairly low level word.
pub fn wordCreate(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertNotCompiling();

    var name = try forth.readWord();
    var token = forth.peekWord();

    var desc: []const u8 = "";
    if (token) |t| {
        if (parser.isComment(t)) {
            _ = try forth.readWord();
            desc = try parser.parseComment(t);
        }
    }
    _ = try forth.create(name, desc, &pushBodyAddress, 0);
    return 0;
}

// Finish out a word created with create.
// Currently just fills in the length of the word.
pub fn wordFinish(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    forth.complete();
    return 0;
}

// Allocate a word in the dictionary and set its value to TOS.
// Should be between a create/finish pair, but this is not checked.
pub fn wordComma(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const value = try forth.stack.pop();
    forth.addNumber(value);
    return 0;
}

// Allocate a word in the dictionary and set its value to the string point to by TOS.
// Should be between a create/finish pair, but this is not checked.
pub fn wordSComma(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const value = try forth.stack.pop();
    const s: [*:0]const u8 = @ptrFromInt(value);
    forth.addString(s[0..string.strlen(s)]);
    return 0;
}

// Allocate n words in the dictionary. Should be in the middle
// of a create/finish pair, but this is not checked.
pub fn wordAllot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const n = try forth.stack.pop();
    _ = forth.allocate(@alignOf(u64), n * @sizeOf(u64));
    return 0;
}

// Temporarily turn compile mode off.
pub fn wordLBrace(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertCompiling();
    forth.compiling = 0;
    return 0;
}

// Turn compile mode back on.
pub fn wordRBrace(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertNotCompiling();
    forth.compiling = 1;
    return 0;
}

// Begin the definition of a new secondary word.
pub fn wordColon(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertNotCompiling();

    var name = try forth.readWord();
    var token = forth.peekWord();

    var desc: []const u8 = "";
    if (token) |t| {
        if (parser.isComment(t)) {
            _ = try forth.readWord();
            desc = try parser.parseComment(t);
        }
    }
    _ = try forth.startWord(name, desc, Forth.inner, 0);
    return 0;
}

// Complete a secondary word.
pub fn wordSemi(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertCompiling();
    forth.addStop();
    try forth.completeWord();
    return 0;
}

pub fn wordDesc(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var name = forth.words.next() orelse return ForthError.WordReadError;
    var header = forth.findWord(name) orelse return ForthError.NotFound;
    try forth.print("{s}: {s}\n", .{ header.name, header.desc });
    return 0;
}

pub fn wordDumpWord(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var name = forth.words.next() orelse return ForthError.WordReadError;
    var header = forth.findWord(name) orelse return ForthError.NotFound;

    // Dump info about a primitive word.

    if (header.func != &Forth.inner) {
        const h: u64 = @intFromPtr(header);
        const p: u64 = @intFromPtr(header.func);
        try forth.print("Word name: {s} len: {} header: {x} func: {x}\n", .{ header.name, header.len, h, p });

        try forth.print("Description: {s}\n", .{header.desc});
        return 0;
    }

    // Word is a secondary, dump the meta info first.

    //    var body = header.bodyOfType([*]u64);
    var len = header.bodyLen();
    try forth.print("Word name: {s} len: {} immed: {}\n", .{ header.name, len, header.immediate });
    try forth.print("Description: {s}\n\n", .{header.desc});

    // Followed by a byte dump.

    var ubody = header.bodyOfType([*]u64);

    const wLen = len / @sizeOf(u64);
    for (0..wLen) |j| {
        const chars = string.u64ToChars(ubody[j]);
        try forth.print("{:4} {x:16}   {s}", .{ j, ubody[j], chars });
        if (forth.isWordP(ubody[j])) {
            const hp: *Header = @ptrFromInt(ubody[j]);
            try forth.print("      {s}", .{hp.name});
        }
        try forth.print("\n", .{});
    }

    return 0;
}

// Compiler word, generate the code for an if.
// Emits an jump_if_not instruction with an invalid target address
// and pushes the address of the target address onto the rstack.
pub fn wordIf(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertCompiling();
    forth.addCall(forth.jumpIfNot);
    try forth.rstack.push(@intFromPtr(forth.current()));
    forth.addNumber(InvalidOffset);
    return 0;
}

// Compiler word, generate the code for the else of if/else/endif.
// Generates an unconditional jump instruction with an invalid target address,
// pops the address (pushed by if) off of the rstack and plugs in the address
// just after the jump instruction.
pub fn wordElse(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertCompiling();

    const if_jump_p = try forth.rstack.pop();
    const if_jump_p_u64: [*]u64 = @ptrFromInt(if_jump_p);

    // Add the else jump instruction and push its address onto the stack
    // to be filled in later by endif.

    forth.addCall(forth.jump);
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
pub fn wordEndif(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
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
pub fn wordWhile(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertCompiling();
    try forth.rstack.push(@intFromPtr(forth.current()));
    return 0;
}

// Compiler word, generate the code for do, which ends the condition part of a while loop.
// Emits an jump_if_not instruction with an invalid target address (done will fill it in)
// and pushes the address of the target address onto the rstack.
pub fn wordDo(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertCompiling();
    forth.addCall(forth.jumpIfNot);
    try forth.rstack.push(@intFromPtr(forth.current()));
    forth.addNumber(InvalidOffset);
    return 0;
}

// Compiler word, generate the end code for the end of a while loop.
// Pops the address of the jump_if_not target and the address of the
// beginning of the loop off of the rstack.
// Generates the jump back to the beginning of the loop and
// fills in the jump-if-not target with the post loop address.
pub fn wordDone(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertCompiling();

    const do_p: [*]u64 = @ptrFromInt(try forth.rstack.pop());
    const while_p: [*]u64 = @ptrFromInt(try forth.rstack.pop());

    // Add jump to begining of the loop instruction.

    forth.addCall(forth.jump);
    var current_p = memory.alignByType(forth.current(), u64);
    const while_offset = wordOffset(while_p, current_p) + 1;
    forth.addNumber(@bitCast(while_offset));

    // Fill in the conditional jump target that exits the loop.
    current_p = memory.alignByType(forth.current(), u64);
    const do_offset = wordOffset(current_p, do_p) + 1;
    do_p[0] = @bitCast(do_offset);

    return 0;
}

pub fn wordToRStack(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const v = try forth.stack.pop();
    try forth.rstack.push(v);
    return 0;
}

pub fn wordFromRStack(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const v = try forth.rstack.pop();
    try forth.stack.push(v);
    return 0;
}

/// --
pub fn wordRStack(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    for (forth.rstack.items()) |item| {
        try forth.print("{}\n", .{item});
    }
    return 0;
}

pub fn defineCompiler(forth: *Forth) !void {
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
    _ = try forth.definePrimitiveDesc("let", " n sAddr - :Assign a new variable", &wordLet, 0);
    _ = try forth.definePrimitiveDesc(",", " n -- :Allocate a word and store n in it.", &wordComma, 0);
    _ = try forth.definePrimitiveDesc("s,", " n -- :Add a string to memory.", &wordSComma, 0);
    _ = try forth.definePrimitiveDesc("allot", " n -- :Allocate n words.", &wordAllot, 0);

    _ = try forth.definePrimitiveDesc("if", " -- :If statement", &wordIf, 1);
    _ = try forth.definePrimitiveDesc("else", " -- :Part of if/else/endif", &wordElse, 1);
    _ = try forth.definePrimitiveDesc("endif", " -- :Part of if/else/endif", &wordEndif, 1);

    _ = try forth.definePrimitiveDesc("while", " -- :Compile the head of a while loop.", &wordWhile, 1);
    _ = try forth.definePrimitiveDesc("do", " -- :Compile the condition part of a while loop.", &wordDo, 1);
    _ = try forth.definePrimitiveDesc("done", " -- :Compile the end of a while loop.", &wordDone, 1);

    _ = try forth.definePrimitiveDesc("?", " -- :Print description of word.", &wordDesc, 0);
    _ = try forth.definePrimitiveDesc("?word", " -- :Print details of word.", &wordDumpWord, 0);
}
