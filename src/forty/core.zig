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

const forth_module = @import("forth.zig");
const Forth = forth_module.Forth;
const OpCode = forth_module.OpCode;

const memory_module = @import("memory.zig");
const Header = memory_module.Header;

// This is the inner interpreter, effectively the word
// that runs all the secondary words.
pub fn inner(forth: *Forth, _: [*]u64, _: u64, header: *Header) ForthError!u64 {
    var body = header.bodyOfType([*]u64);
    var i: usize = 0;
    while (true) {
        switch (body[i]) {
            @intFromEnum(OpCode.stop) => break,

            @intFromEnum(OpCode.push_string) => {
                const data_size = body[i + 1];
                var p_string: [*]u8 = @ptrCast(body + 2);
                try forth.stack.push(@intFromPtr(p_string));
                i += data_size + 1;
            },

            @intFromEnum(OpCode.push_u64) => {
                try forth.stack.push(body[i + 1]);
                i += 2;
            },

            else => {
                const p: *Header = @ptrFromInt(body[i]);
                const delta = try p.func(forth, body, i, p);
                i = i + 1 + delta;
            },
        }
    }
    return 0;
}

// Begin the definition of a new secondary word.
pub fn wordColon(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var name = forth.words.next() orelse return ForthError.WordReadError;
    _ = try forth.startWord(name, &inner, false);
    return 0;
}

// Complete a secondary word.
pub fn wordSemi(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    forth.addOpCode(OpCode.stop);
    try forth.completeWord();
    return 0;
}

/// sAddr flag -- ()
pub fn wordImmediate(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const i = try forth.stack.pop();
    const name: [*:0]u8 = @ptrFromInt(i);
    const l = string.strlen(name);

    var header = forth.findWord(name[0..l]);
    if (header) |h| {
        h.immediate = (i != 0);
    } else {
        try forth.print("{s}??\n", .{name});
    }
    return 0;
}

/// a -- ()
pub fn wordEmit(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const a = try forth.stack.pop();
    var ch: u8 = @intCast(a);
    forth.console.emit(ch);
    return 0;
}

// -- ch
pub fn wordKey(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const ch = forth.console.getc();
    try forth.stack.push(@intCast(ch));
    return 0;
}

// -- bool
pub fn wordKeyMaybe(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var byte_available = forth.console.char_available();
    try forth.stack.push(if (byte_available) 1 else 0);
    return 0;
}

/// --
pub fn wordCr(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    forth.console.emit(0x0a);
    return 0;
}

/// --
pub fn wordClearScreen(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    forth.console.emit(0x0c);
    return 0;
}

/// --
pub fn wordHello(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.print("Hello world!\n", .{});
    return 0;
}

/// n --
pub fn wordDot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var v: u64 = try forth.stack.pop();
    try forth.print("{} ", .{v});
    return 0;
}

/// sAddr --
pub fn wordSDot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const i = try forth.stack.pop();
    const p_string: [*:0]u8 = @ptrFromInt(i);
    try forth.print("{s}", .{p_string});
    return 0;
}

/// n --
pub fn wordHexDot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var v: u64 = try forth.stack.pop();
    try forth.print("{x} ", .{v});
    return 0;
}

/// --
pub fn wordStack(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    for (forth.stack.items()) |item| {
        try forth.print("{}\n", .{item});
    }
    return 0;
}

/// --
pub fn wordRStack(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    for (forth.rstack.items()) |item| {
        try forth.print("{}\n", .{item});
    }
    return 0;
}

/// w1 w2 -- w2 w1
pub fn wordSwap(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var s = &forth.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(a);
    try s.push(b);
    return 0;
}

/// w1 w2 w3 w4 -- w3 w4 w1 w2
pub fn word2Swap(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var s = &forth.stack;
    var w4 = try s.pop();
    var w3 = try s.pop();
    var w2 = try s.pop();
    var w1 = try s.pop();
    try s.push(w3);
    try s.push(w4);
    try s.push(w1);
    try s.push(w2);
    return 0;
}

/// w -- w w
pub fn wordDup(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var s = &forth.stack;
    const a = try s.pop();
    try s.push(a);
    try s.push(a);
    return 0;
}

/// w1 w2 -- w1 w2 w1 w2
pub fn word2Dup(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var s = &forth.stack;
    const w2 = try s.pop();
    const w1 = try s.pop();
    try s.push(w1);
    try s.push(w2);
    try s.push(w1);
    try s.push(w2);
    return 0;
}

/// w1 --
pub fn wordDrop(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var s = &forth.stack;
    _ = try s.pop();
    return 0;
}

/// w1 w2 --
pub fn word2Drop(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var s = &forth.stack;
    _ = try s.pop();
    _ = try s.pop();
    return 0;
}

/// w1 w2 w3 -- w2 w3 w1
pub fn wordRot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var s = &forth.stack;
    const w3 = try s.pop();
    const w2 = try s.pop();
    const w1 = try s.pop();
    try s.push(w2);
    try s.push(w3);
    try s.push(w1);
    return 0;
}

/// w1 w2 w3 w4 w5 w6 -- w3 w4 w5 w6 w1 w2
pub fn word2Rot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var s = &forth.stack;
    const w6 = try s.pop();
    const w5 = try s.pop();
    const w4 = try s.pop();
    const w3 = try s.pop();
    const w2 = try s.pop();
    const w1 = try s.pop();
    try s.push(w3);
    try s.push(w4);
    try s.push(w5);
    try s.push(w6);
    try s.push(w1);
    try s.push(w2);
    return 0;
}

/// w1 w2 -- w1 w2 w1
pub fn wordOver(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var s = &forth.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(b);
    try s.push(a);
    try s.push(b);
    return 0;
}

/// w1 w2 w3 w4 -- w1 w2 w3 w4 w1 w2
pub fn word2Over(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var s = &forth.stack;
    const w4 = try s.pop();
    const w3 = try s.pop();
    const w2 = try s.pop();
    const w1 = try s.pop();
    try s.push(w1);
    try s.push(w2);
    try s.push(w3);
    try s.push(w4);
    try s.push(w1);
    try s.push(w2);
    return 0;
}

/// n n -- n
pub fn wordAdd(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    try forth.stack.push(a + b);
    return 0;
}

/// n n -- n
pub fn wordSub(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    try forth.stack.push(b - a);
    return 0;
}

/// n n -- n
pub fn wordMul(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    try forth.stack.push(a * b);
    return 0;
}

/// n n -- n
pub fn wordDiv(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    try forth.stack.push(b / a);
    return 0;
}

/// n n -- n
pub fn wordMod(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    try forth.stack.push(b % a);
    return 0;
}

/// --
pub fn wordDictionary(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var e = forth.lastWord;
    while (e) |entry| {
        const immed = if (entry.immediate) "*" else " ";
        try forth.print("{s} {s}\n", .{ immed, entry.name });
        e = entry.previous;
    }
    return 0;
}

/// addr -- u64
pub fn wordLoadU64(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const a = try forth.stack.pop();

    const p: *u64 = @ptrFromInt(a);
    const v = p.*;
    try forth.stack.push(v);
    return 0;
}

/// u64 addr --
pub fn wordStoreU64(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const a = try forth.stack.pop();
    const v = try forth.stack.pop();

    const p: *u64 = @ptrFromInt(a);
    p.* = v;
    return 0;
}

pub fn defineCore(forth: *Forth) !void {
    // IO
    _ = try forth.definePrimitive("hello", &wordHello, false);
    _ = try forth.definePrimitive("cr", &wordCr, false);
    _ = try forth.definePrimitive("emit", &wordEmit, false);
    _ = try forth.definePrimitive("cls", &wordClearScreen, false);
    _ = try forth.definePrimitive("key", &wordKey, false);
    _ = try forth.definePrimitive("key?", &wordKeyMaybe, false);

    // Secondary definition words.
    _ = try forth.definePrimitive(":", &wordColon, false);
    _ = try forth.definePrimitive(";", &wordSemi, true);
    _ = try forth.definePrimitive("immediate", &wordImmediate, false);

    // Debug and inspection words.
    _ = try forth.definePrimitive("stack", &wordStack, false);
    _ = try forth.definePrimitive("?", &wordStack, false);
    _ = try forth.definePrimitive("??", &wordDictionary, false);
    _ = try forth.definePrimitive("rstack", &wordRStack, false);

    // Basic Forth words.
    _ = try forth.definePrimitive("swap", &wordSwap, false);
    _ = try forth.definePrimitive("2swap", &word2Swap, false);
    _ = try forth.definePrimitive("dup", &wordDup, false);
    _ = try forth.definePrimitive("2dup", &word2Dup, false);
    _ = try forth.definePrimitive("drop", &wordDrop, false);
    _ = try forth.definePrimitive("2drop", &word2Drop, false);
    _ = try forth.definePrimitive("rot", &wordRot, false);
    _ = try forth.definePrimitive("2rot", &word2Rot, false);
    _ = try forth.definePrimitive("over", &wordOver, false);
    _ = try forth.definePrimitive("2over", &word2Over, false);

    _ = try forth.definePrimitive(".", &wordDot, false);
    _ = try forth.definePrimitive("s.", &wordSDot, false);
    _ = try forth.definePrimitive("h.", &wordHexDot, false);
    _ = try forth.definePrimitive("+", &wordAdd, false);
    _ = try forth.definePrimitive("-", &wordSub, false);
    _ = try forth.definePrimitive("*", &wordMul, false);
    _ = try forth.definePrimitive("/", &wordDiv, false);
    _ = try forth.definePrimitive("%", &wordMod, false);
    _ = try forth.definePrimitive("!i", &wordStoreU64, false);
    _ = try forth.definePrimitive("@i", &wordLoadU64, false);
}
