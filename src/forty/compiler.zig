const std = @import("std");
const Allocator = std.mem.Allocator;

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
    var body = header.bodyOfType([*]u64);
    try forth.stack.push(body[0]);
    return 0;
}

pub fn wordLet(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const pName = try forth.popAs([*:0]u8);
    const value = try forth.stack.pop();

    const name = string.asSlice(pName);

    _ = try forth.create(name, "A constant", &pushBodyValue, false);
    try forth.addNumber(value);
    forth.complete();
    return 0;
}

// Create a new dictionary definition.
// Resulting dictionary entry just pushes its body address onto the stack.
// This is a fairly low level word.
pub fn wordCreate(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertNotCompiling();
    var pName = try forth.popAs([*:0]u8);
    var lName = string.strlen(pName);
    var name = pName[0..lName];

    _ = try forth.create(name, "", Forth.pushBodyAddress, false);
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
    try forth.addNumber(value);
    return 0;
}

// Allocate a word in the dictionary and set its value to the string point to by TOS.
// Should be between a create/finish pair, but this is not checked.
pub fn wordSComma(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const value = try forth.stack.pop();
    const s: [*:0]const u8 = @ptrFromInt(value);
    try forth.addString(s[0..string.strlen(s)]);
    return 0;
}

// Allocate n words in the dictionary. Should be in the middle
// of a create/finish pair, but this is not checked.
pub fn wordAllot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const n = try forth.stack.pop();
    _ = try forth.allocate(@alignOf(u64), n * @sizeOf(u64));
    return 0;
}

// Allocate n *Bytes* in the dictionary. Should be in the middle
// of a create/finish pair, but this is not checked.
pub fn wordBallot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const n = try forth.stack.pop();
    _ = try forth.allocate(@alignOf(u8), n);
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
    _ = try forth.startWord(name, desc, Forth.inner, false);
    return 0;
}

// Complete a secondary word.
pub fn wordSemi(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertCompiling();
    try forth.addStop();
    try forth.completeWord();
    return 0;
}

// Compile an unconditional return from the current word.
pub fn wordReturn(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertCompiling();
    try forth.addStop();
    return 0;
}

// Compiler word, generate the code for an if.
// Emits an jump_if_not instruction with an invalid target address
// and pushes the address of the target address onto the rstack.
pub fn wordIf(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertCompiling();
    try forth.addCall(forth.jump_if_not);
    try forth.rstack.push(@intFromPtr(forth.current()));
    try forth.addNumber(InvalidOffset);
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

    try forth.addCall(forth.jump);
    try forth.rstack.push(@intFromPtr(forth.current()));
    try forth.addNumber(InvalidOffset);

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
    try forth.addCall(forth.jump_if_not);
    try forth.rstack.push(@intFromPtr(forth.current()));
    try forth.addNumber(InvalidOffset);
    return 0;
}

// Generate the end code for the end of a while loop.
// Pops the address of the jump_if_not target and the address of the
// beginning of the loop off of the rstack.
// Generates the jump back to the beginning of the loop and
// fills in the jump-if-not target with the post loop address.
fn generateLoopTail(forth: *Forth) ForthError!void {
    const do_p: [*]u64 = @ptrFromInt(try forth.rstack.pop());
    const while_p: [*]u64 = @ptrFromInt(try forth.rstack.pop());

    // Add jump to begining of the loop instruction.

    try forth.addCall(forth.jump);
    var current_p = memory.alignByType(forth.current(), u64);
    const while_offset = wordOffset(while_p, current_p) + 1;
    try forth.addNumber(@bitCast(while_offset));

    // Fill in the conditional jump target that exits the loop.
    current_p = memory.alignByType(forth.current(), u64);
    const do_offset = wordOffset(current_p, do_p) + 1;
    do_p[0] = @bitCast(do_offset);
}

pub fn wordDone(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try generateLoopTail(forth);

    return 0;
}

// Compiler word, generate the code for the begining of a repeat loop.
// Structure is:  n times <body> repeat
pub fn wordTimes(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertCompiling();
    // code to push count onto return stack
    try forth.addCall(forth.to_rstack);
    try forth.addCall(forth.drop);
    try forth.addCall(forth.push_u64);
    try forth.addNumber(0);
    try forth.addCall(forth.to_rstack);
    try forth.addCall(forth.drop);
    try forth.rstack.push(@intFromPtr(forth.current()));
    try forth.addCall(forth.jump_if_rle);
    try forth.rstack.push(@intFromPtr(forth.current()));
    try forth.addNumber(InvalidOffset);

    return 0;
}

// Compiler word, generate the code for the begining of for-range loop.
// Structure is:  n1 n2 for-range <body> repeat
pub fn wordForRange(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.assertCompiling();
    // code to push count onto return stack
    try forth.addCall(forth.to_rstack);
    try forth.addCall(forth.drop);
    try forth.addCall(forth.to_rstack);
    try forth.addCall(forth.drop);
    try forth.rstack.push(@intFromPtr(forth.current()));
    try forth.addCall(forth.jump_if_rle);
    try forth.rstack.push(@intFromPtr(forth.current()));
    try forth.addNumber(InvalidOffset);

    return 0;
}

pub fn wordRepeat(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.addCall(forth.inc_rstack);
    try generateLoopTail(forth);
    try forth.addCall(forth.r_drop);
    try forth.addCall(forth.r_drop);

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

    _ = try forth.definePrimitiveDesc("?rstack", " -- :Print the return stack.", &wordRStack, false);

    // Secondary definition words.

    _ = try forth.definePrimitiveDesc(":", " -- :Start a new word definition", &wordColon, false);
    _ = try forth.definePrimitiveDesc(";", " -- :Complete a new word definition", &wordSemi, true);
    _ = try forth.definePrimitiveDesc("return", " -- :Return from word", &wordReturn, true);

    _ = try forth.definePrimitiveDesc("{", " -- : Temp turn off compile mode.", &wordLBrace, true);
    _ = try forth.definePrimitiveDesc("}", " -- : Turn compile mode back on", &wordRBrace, true);
    _ = try forth.definePrimitiveDesc("create", " -- :Start a new definition", &wordCreate, false);
    _ = try forth.definePrimitiveDesc("finish", " -- :Complete a new definition", &wordFinish, false);
    _ = try forth.definePrimitiveDesc("let", "v sAddr - :Assign a new variable", &wordLet, false);
    _ = try forth.definePrimitiveDesc(",", " n -- :Allocate a word and store n in it.", &wordComma, false);
    _ = try forth.definePrimitiveDesc("s,", " n -- :Add a string to memory.", &wordSComma, false);
    _ = try forth.definePrimitiveDesc("allot", " n -- :Allocate n words.", &wordAllot, false);
    _ = try forth.definePrimitiveDesc("ballot", " n -- :Allocate n bytes.", &wordBallot, false);

    _ = try forth.definePrimitiveDesc("if", " -- :If statement", &wordIf, true);
    _ = try forth.definePrimitiveDesc("else", " -- :Part of if/else/endif", &wordElse, true);
    _ = try forth.definePrimitiveDesc("endif", " -- :Part of if/else/endif", &wordEndif, true);

    _ = try forth.definePrimitiveDesc("while", " -- :Compile the head of a while loop.", &wordWhile, true);
    _ = try forth.definePrimitiveDesc("do", " -- :Compile the condition part of a while loop.", &wordDo, true);
    _ = try forth.definePrimitiveDesc("done", " -- :Compile the end of a while loop.", &wordDone, true);
    _ = try forth.definePrimitiveDesc("times", "n  -- : repeat the body n times", &wordTimes, true);
    _ = try forth.definePrimitiveDesc("for-range", "n1 n2  -- : repeat the body n2-n1 times", &wordForRange, true);
    _ = try forth.definePrimitiveDesc("repeat", " -- : end of loop", &wordRepeat, true);
}
