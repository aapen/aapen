const std = @import("std");
const Allocator = std.mem.Allocator;

const bsp = @import("../bsp.zig");
const fbcons = @import("../fbcons.zig");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const value = @import("value.zig");
const Value = value.Value;
const ValueType = value.ValueType;

const stack = @import("stack.zig");
const DataStack = stack.Stack(Value);
const ReturnStack = stack.Stack(i32);

const dict = @import("dictionary.zig");
const ValueDictionary = dict.Dictionary(Value);

const string = @import("string.zig");
const WordFunction = *const fn (forth: *Forth) ForthError!void;

const forth_module = @import("forth.zig");
const Forth = forth_module.Forth;

pub fn wordColon(forth: *Forth) !void {
    var name = forth.words.next() orelse return ForthError.WordReadError;
    string.copyTo(&forth.new_word_name, name);
    forth.composing = true;
    forth.new_word_def = forth.nextFree;
    try forth.print("defining new word {s}\n", .{forth.new_word_name});
}

pub fn wordSemi(forth: *Forth) !void {
    forth.memory[@intCast(forth.nextFree)] = Value{
        .fp = @intFromPtr(&wordReturn),
    };
    forth.nextFree += 1;
    try forth.defineSecondary(&forth.new_word_name, forth.new_word_def);
    forth.composing = false;
    forth.new_word_def = -888;
}

// a -- ()
pub fn wordEmit(forth: *Forth) !void {
    var s = &forth.stack;
    const a = try s.pop();
    var ch = try a.asChar();
    forth.console.emit(ch);
}

// -- ch
pub fn wordKey(forth: *Forth) !void {
    var s = &forth.stack;
    var ch = forth.getc();
    try s.push(Value{ .ch = ch });
}

// -- bool
pub fn wordKeyMaybe(forth: *Forth) !void {
    var s = &forth.stack;
    var byte_available = forth.char_available();
    try s.push(Value{ .i = if (byte_available) 1 else 0 });
}

/// --
pub fn wordCr(forth: *Forth) ForthError!void {
    forth.putc(0x0a);
}

/// --
pub fn wordClearScreen(forth: *Forth) !void {
    forth.putc(0x0c);
}

/// --
pub fn wordHello(forth: *Forth) !void {
    try forth.print("Hello world!\n", .{});
}

/// n --
pub fn wordDot(forth: *Forth) !void {
    var v: Value = try forth.stack.pop();
    try v.pr(forth, false);
}

/// n --
pub fn wordHexDot(forth: *Forth) !void {
    var v: Value = try forth.stack.pop();
    try v.pr(forth, true);
}

/// --
pub fn wordStack(forth: *Forth) !void {
    for (forth.stack.items()) |item| {
        try item.pr(forth, false);
        try forth.print("\n", .{});
    }
}

/// --
pub fn wordRStack(forth: *Forth) !void {
    for (forth.rstack.items()) |item| {
        try forth.print("{}\n", .{item});
    }
}

/// w1 w2 -- w2 w1
pub fn wordSwap(forth: *Forth) !void {
    var s = &forth.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(a);
    try s.push(b);
}

/// w1 w2 w3 w4 -- w3 w4 w1 w2
pub fn word2Swap(forth: *Forth) !void {
    var s = &forth.stack;
    var w4 = try s.pop();
    var w3 = try s.pop();
    var w2 = try s.pop();
    var w1 = try s.pop();
    try s.push(w3);
    try s.push(w4);
    try s.push(w1);
    try s.push(w2);
}

/// w -- w w
pub fn wordDup(forth: *Forth) !void {
    var s = &forth.stack;
    const a = try s.pop();
    try s.push(a);
    try s.push(a);
}

/// w1 w2 -- w1 w2 w1 w2
pub fn word2Dup(forth: *Forth) !void {
    var s = &forth.stack;
    const w2 = try s.pop();
    const w1 = try s.pop();
    try s.push(w1);
    try s.push(w2);
    try s.push(w1);
    try s.push(w2);
}

/// w1 --
pub fn wordDrop(forth: *Forth) !void {
    var s = &forth.stack;
    _ = try s.pop();
}

/// w1 w2 --
pub fn word2Drop(forth: *Forth) !void {
    var s = &forth.stack;
    _ = try s.pop();
    _ = try s.pop();
}

/// w1 w2 w3 -- w2 w3 w1
pub fn wordRot(forth: *Forth) !void {
    var s = &forth.stack;
    const w3 = try s.pop();
    const w2 = try s.pop();
    const w1 = try s.pop();
    try s.push(w2);
    try s.push(w3);
    try s.push(w1);
}

/// w1 w2 w3 w4 w5 w6 -- w3 w4 w5 w6 w1 w2
pub fn word2Rot(forth: *Forth) !void {
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
}

/// w1 w2 -- w1 w2 w1
pub fn wordOver(forth: *Forth) !void {
    var s = &forth.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(b);
    try s.push(a);
    try s.push(b);
}

/// w1 w2 w3 w4 -- w1 w2 w3 w4 w1 w2
pub fn word2Over(forth: *Forth) !void {
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
}

/// n n -- n
pub fn wordAdd(forth: *Forth) !void {
    var s = &forth.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(try a.add(&b));
}

/// n n -- n
pub fn wordSub(forth: *Forth) !void {
    var s = &forth.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(try b.sub(&a));
}

/// --
pub fn wordReturn(forth: *Forth) ForthError!void {
    forth.nexti = -999;
}

/// --
pub fn wordDictionary(forth: *Forth) ForthError!void {
    try forth.dictionary.pr(forth);
}

/// s -- w
pub fn wordLookup(forth: *Forth) ForthError!void {
    const name_value = try forth.stack.pop();
    try forth.print("looking up {s}\n", .{name_value.s});
    const v = try forth.dictionary.get(name_value.s);
    try forth.stack.push(v);
}

/// --
pub fn wordInfo(forth: *Forth) ForthError!void {
    try forth.print("nexti: {}\n", .{forth.nexti});
    try forth.print("composing: {}\n", .{forth.composing});
    try forth.print("new word: {s}\n", .{forth.new_word_name});
    try forth.print("new word def: {}\n", .{forth.new_word_def});
}

/// --
pub fn wordNext(forth: *Forth) ForthError!void {
    var nexti_address: usize = @intFromPtr(&forth.nexti);
    var v = Value{ .addr = nexti_address };
    try forth.stack.push(v);
}

/// addr -- i32
pub fn wordLoadI32(forth: *Forth) !void {
    const addressValue = try forth.stack.pop();
    if (addressValue != ValueType.addr) {
        return ForthError.BadOperation;
    }
    const p: *i32 = @ptrFromInt(addressValue.addr);
    const v = Value{ .i = p.* };
    try forth.stack.push(v);
}

/// i32 addr --
pub fn wordStoreI32(forth: *Forth) !void {
    const addressValue = try forth.stack.pop();
    const v = try forth.stack.pop();

    if (addressValue != ValueType.addr) {
        return ForthError.BadOperation;
    }

    if (v != ValueType.i) {
        return ForthError.BadOperation;
    }
    const p: *i32 = @ptrFromInt(addressValue.addr);
    p.* = v.i;
}

/// -- n
pub fn wordValueSize(forth: *Forth) ForthError!void {
    const l: usize = @sizeOf(Value);
    try forth.print("size of value: {d}\n", .{l});
    try forth.stack.push(Value{ .sz = l });
}

pub fn defineCore(forth: *Forth) !void {
    // IO
    try forth.definePrimitive("hello", &wordHello, false);
    try forth.definePrimitive("cr", &wordCr, false);
    try forth.definePrimitive("emit", &wordEmit, false);
    try forth.definePrimitive("cls", &wordClearScreen, false);
    try forth.definePrimitive("key", &wordKey, false);
    try forth.definePrimitive("key?", &wordKeyMaybe, false);

    // Secondary definition words.
    try forth.definePrimitive(":", &wordColon, false);
    try forth.definePrimitive(";", &wordSemi, true);

    // Debug and inspection words.
    try forth.definePrimitive("stack", &wordStack, false);
    try forth.definePrimitive("?", &wordStack, false);
    try forth.definePrimitive("??", &wordDictionary, false);
    try forth.definePrimitive("rstack", &wordRStack, false);
    try forth.definePrimitive("info", &wordInfo, true);
    try forth.definePrimitive("ip", &wordNext, false);
    try forth.definePrimitive("value-size", &wordValueSize, false);

    // Basic Forth words.
    try forth.definePrimitive("swap", &wordSwap, false);
    try forth.definePrimitive("2swap", &word2Swap, false);
    try forth.definePrimitive("dup", &wordDup, false);
    try forth.definePrimitive("2dup", &word2Dup, false);
    try forth.definePrimitive("drop", &wordDrop, false);
    try forth.definePrimitive("2drop", &word2Drop, false);
    try forth.definePrimitive("rot", &wordRot, false);
    try forth.definePrimitive("2rot", &word2Rot, false);
    try forth.definePrimitive("over", &wordOver, false);
    try forth.definePrimitive("2over", &word2Over, false);

    try forth.definePrimitive(".", &wordDot, false);
    try forth.definePrimitive("h.", &wordHexDot, false);
    try forth.definePrimitive("+", &wordAdd, false);
    try forth.definePrimitive("-", &wordSub, false);
    try forth.definePrimitive("!i", &wordStoreI32, false);
    try forth.definePrimitive("@i", &wordLoadI32, false);
}
