const std = @import("std");
const Allocator = std.mem.Allocator;

const time = @import("../time.zig");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const string = @import("string.zig");
const parser = @import("parser.zig");

const forth_module = @import("forth.zig");
const Forth = forth_module.Forth;
const WordFunction = forth_module.WordFunction;

const memory_module = @import("memory.zig");
const Header = memory_module.Header;

const inner_module = @import("inner.zig");
const OpCode = inner_module.OpCode;
const inner = inner_module.inner;

/// *Header  --  <results>
pub fn wordExec(forth: *Forth, _: *Header) ForthError!void {
    const p = try forth.popAs(*Header);
    //try p.func(forth, p);
    try inner_module.executeHeader(forth, p);
    //try inner(forth, p);
}

/// *[]u8  --  <results>
pub fn wordEval(forth: *Forth, _: *Header) ForthError!void {
    const pStr: [*]u8 = try forth.popAs([*]u8);
    const token = string.asSlice(pStr);
    try forth.evalToken(token);
}

/// *[]u8  --  <results>
pub fn wordEvalCommand(forth: *Forth, _: *Header) ForthError!void {
    const pStr: [*]u8 = try forth.popAs([*]u8);
    const token = string.asSlice(pStr);
    try forth.evalCommand(token);
}

/// *[]u8  --  <results>
pub fn wordLookup(forth: *Forth, _: *Header) ForthError!void {
    const pName: [*]u8 = try forth.popAs([*]u8);
    const name = string.asSlice(pName);
    const word = forth.findWord(name);
    const iWord = @intFromPtr(word);
    try forth.stack.push(iWord);
}

/// word-addr catch-addr -- <result>"
pub fn wordTry(forth: *Forth, _: *Header) ForthError!void {
    const catcher: *Header = try forth.popAs(*Header);
    const word: *Header = try forth.popAs(*Header);

    const initialStackDepth = forth.call_stack.depth();
    word.func(forth, word) catch |err| {
        try forth.print("Error: {any}\n", .{err});
        try catcher.func(forth, catcher);
    };
    while (forth.call_stack.depth() > initialStackDepth) {
        _ = try forth.call_stack.pop();
    }
}

/// value addr len --
pub fn wordSetMemory(forth: *Forth, _: *Header) ForthError!void {
    const len = try forth.stack.pop();
    const addr = try forth.popAs([*]u8);
    const value = try forth.stack.pop();
    const byteValue: u8 = @intCast(value % 256);

    var offset: usize = 0;
    while (offset < len) {
        addr[offset] = byteValue;
        offset += 1;
    }
}

/// a -- ()
pub fn wordEmit(forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.stack.pop();
    const ch: u8 = @intCast(a);
    try forth.emit(ch);
}

// -- ch
pub fn wordKey(forth: *Forth, _: *Header) ForthError!void {
    const ch = forth.console.getc();
    try forth.stack.push(@intCast(ch));
}

// -- bool
pub fn wordKeyMaybe(forth: *Forth, _: *Header) ForthError!void {
    const byte_available = forth.console.char_available();
    try forth.stack.push(if (byte_available) 1 else 0);
}

/// --
pub fn wordReset(_: *Forth, _: *Header) ForthError!void {
    asm volatile ("brk 0x07c5");
}

/// --
pub fn wordSleep(forth: *Forth, _: *Header) ForthError!void {
    const n = try forth.popAs(u32);
    time.delayMillis(n);
}

/// --
pub fn wordHello(forth: *Forth, _: *Header) ForthError!void {
    try forth.print("Hello world!\n", .{});
}

/// n -- n
pub fn wordToRStack(forth: *Forth, _: *Header) ForthError!void {
    const v = try forth.stack.peek();
    try forth.istack.push(v);
}

/// n -- n
pub fn wordToDStack(forth: *Forth, _: *Header) ForthError!void {
    const v = try forth.istack.peek();
    try forth.stack.push(v);
}

/// n --
pub fn wordDot(forth: *Forth, _: *Header) ForthError!void {
    const v = try forth.popAs(i64);
    try std.fmt.formatInt(v, @intCast(forth.obase), .lower, .{}, forth.writer());
}

/// n --
pub fn wordSignedDot(forth: *Forth, _: *Header) ForthError!void {
    const v: i64 = @bitCast(try forth.stack.pop());
    try std.fmt.formatInt(v, @intCast(forth.obase), .lower, .{}, forth.writer());
}

/// n --
pub fn wordSDecimalDot(forth: *Forth, _: *Header) ForthError!void {
    const v: i64 = @bitCast(try forth.stack.pop());
    try std.fmt.formatInt(v, 10, .lower, .{}, forth.writer());
}

/// saddr --
pub fn wordSDot(forth: *Forth, _: *Header) ForthError!void {
    const i = try forth.stack.pop();
    const p_string: [*:0]u8 = @ptrFromInt(i);
    try forth.print("{s}", .{p_string});
}

/// saddr saddr --
pub fn wordSEqual(forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.stack.pop();
    const a_string: [*:0]u8 = @ptrFromInt(a);
    const b = try forth.stack.pop();
    const b_string: [*:0]u8 = @ptrFromInt(b);
    const result: u64 = if (string.streql(a_string, b_string)) 1 else 0;
    try forth.stack.push(result);
}

/// n --
pub fn wordHexDot(forth: *Forth, _: *Header) ForthError!void {
    const v: u64 = try forth.stack.pop();
    try forth.print("{x} ", .{v});
}

/// n --
pub fn wordDecimalDot(forth: *Forth, _: *Header) ForthError!void {
    const v: u64 = try forth.stack.pop();
    try std.fmt.formatInt(v, 10, .lower, .{}, forth.writer());
}

/// w1 w2 -- w2 w1
pub fn wordSwap(forth: *Forth, _: *Header) ForthError!void {
    if (forth.compiling == 1) {
        try forth.addOpCode(OpCode.Swap);
    } else {
        var s = &forth.stack;
        const a = try s.pop();
        const b = try s.pop();
        try s.push(a);
        try s.push(b);
    }
}

/// w1 w2 w3 w4 -- w3 w4 w1 w2
pub fn word2Swap(forth: *Forth, _: *Header) ForthError!void {
    const s = &forth.stack;
    const w4 = try s.pop();
    const w3 = try s.pop();
    const w2 = try s.pop();
    const w1 = try s.pop();
    try s.push(w3);
    try s.push(w4);
    try s.push(w1);
    try s.push(w2);
}

/// w -- w w
pub fn wordDup(forth: *Forth, _: *Header) ForthError!void {
    if (forth.compiling == 1) {
        try forth.addOpCode(OpCode.Dup);
    } else {
        var s = &forth.stack;
        const a = try s.pop();
        try s.push(a);
        try s.push(a);
    }
}

/// w1 w2 -- w1 w2 w1 w2
pub fn word2Dup(forth: *Forth, _: *Header) ForthError!void {
    var s = &forth.stack;
    const w2 = try s.pop();
    const w1 = try s.pop();
    try s.push(w1);
    try s.push(w2);
    try s.push(w1);
    try s.push(w2);
}

/// w1 w2 w3 -- w1 w2 w3 w1 w2 w3
pub fn word3Dup(forth: *Forth, _: *Header) ForthError!void {
    var s = &forth.stack;
    const w3 = try s.pop();
    const w2 = try s.pop();
    const w1 = try s.pop();
    try s.push(w1);
    try s.push(w2);
    try s.push(w3);
    try s.push(w1);
    try s.push(w2);
    try s.push(w3);
}

///  -- : Clear the stack.
pub fn wordClear(forth: *Forth, _: *Header) ForthError!void {
    try forth.stack.reset();
}

/// w1 --
pub fn wordDrop(forth: *Forth, _: *Header) ForthError!void {
    if (forth.compiling == 1) {
        try forth.addOpCode(OpCode.Drop);
    } else {
        var s = &forth.stack;
        _ = try s.pop();
    }
}

/// w1 w2 --
pub fn word2Drop(forth: *Forth, _: *Header) ForthError!void {
    if (forth.compiling == 1) {
        try forth.addOpCode(OpCode.Drop);
        try forth.addOpCode(OpCode.Drop);
    } else {
        var s = &forth.stack;
        _ = try s.pop();
        _ = try s.pop();
    }
}

/// w1 w2 w3 -- w2 w3 w1
pub fn wordRot(forth: *Forth, _: *Header) ForthError!void {
    var s = &forth.stack;
    const w3 = try s.pop();
    const w2 = try s.pop();
    const w1 = try s.pop();
    try s.push(w2);
    try s.push(w3);
    try s.push(w1);
}

/// w1 w2 w3 w4 w5 w6 -- w3 w4 w5 w6 w1 w2
pub fn word2Rot(forth: *Forth, _: *Header) ForthError!void {
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
pub fn wordOver(forth: *Forth, _: *Header) ForthError!void {
    var s = &forth.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(b);
    try s.push(a);
    try s.push(b);
}

/// w1 w2 w3 w4 -- w1 w2 w3 w4 w1 w2
pub fn word2Over(forth: *Forth, _: *Header) ForthError!void {
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
pub fn wordAdd(forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.popAs(i64);
    const b = try forth.popAs(i64);
    try forth.pushAny(b + a);
}

/// n n -- n
pub fn wordSub(forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.popAs(i64);
    const b = try forth.popAs(i64);
    try forth.pushAny(b - a);
}

/// n n -- n
pub fn wordMul(forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.popAs(i64);
    const b = try forth.popAs(i64);
    try forth.pushAny(b * a);
}

/// n n -- n
pub fn wordDiv(forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.popAs(i64);
    const b = try forth.popAs(i64);
    try forth.pushAny(@divTrunc(b, a));
}

/// n n -- n
pub fn wordMod(forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.popAs(i64);
    const b = try forth.popAs(i64);
    try forth.pushAny(@mod(b, a));
}

/// n -- n
pub fn wordNot(forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.stack.pop();
    if (a == 0) {
        try forth.stack.push(1);
    } else {
        try forth.stack.push(0);
    }
}

/// n n -- n
pub fn wordOr(forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    try forth.stack.push(a | b);
}

/// n n -- n
pub fn wordXor(forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    try forth.stack.push(a ^ b);
}

/// n n -- n
pub fn wordAnd(forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    try forth.stack.push(a & b);
}

/// n u -- n
pub fn wordLeftShift(forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    if (a > 64) {
        try forth.stack.push(0);
    } else {
        try forth.stack.push(b << @truncate(a));
    }
}

/// n u -- n
pub fn wordRightShift(forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    if (a > 64) {
        try forth.stack.push(0);
    } else {
        try forth.stack.push(b >> @truncate(a));
    }
}

/// addr -- u8
pub fn wordLoadU8(forth: *Forth, header: *Header) ForthError!void {
    try wordLoad(u8, forth, header);
}

/// u8 addr --
pub fn wordStoreU8(forth: *Forth, header: *Header) ForthError!void {
    try wordStore(u8, forth, header);
}

/// addr -- u32
pub fn wordLoadU32(forth: *Forth, header: *Header) ForthError!void {
    try wordLoad(u32, forth, header);
}

/// u32 addr --
pub fn wordStoreU32(forth: *Forth, header: *Header) ForthError!void {
    try wordStore(u32, forth, header);
}

/// u32 -- u32
pub fn wordByteExchangeU32(forth: *Forth, header: *Header) ForthError!void {
    try wordByteExchange(u32, forth, header);
}

/// addr -- u64
pub fn wordLoadU64(forth: *Forth, header: *Header) ForthError!void {
    try wordLoad(u64, forth, header);
}

/// u64 addr --
pub fn wordStoreU64(forth: *Forth, header: *Header) ForthError!void {
    try wordStore(u64, forth, header);
}

/// u64 -- u64
pub fn wordByteExchangeU64(forth: *Forth, header: *Header) ForthError!void {
    try wordByteExchange(u64, forth, header);
}

/// u64 u64 -- u64
pub fn wordEqualU64(forth: *Forth, header: *Header) ForthError!void {
    try wordArithmeticComparison(u64, .eq, forth, header);
}

/// u64 u64 -- u64
pub fn wordLessThanU64(forth: *Forth, header: *Header) ForthError!void {
    try wordArithmeticComparison(u64, .lt, forth, header);
}

/// u64 u64 -- u64
pub fn wordLessThanEqualU64(forth: *Forth, header: *Header) ForthError!void {
    try wordArithmeticComparison(u64, .lteq, forth, header);
}

/// u64 u64 -- u64
pub fn wordGreaterThanU64(forth: *Forth, header: *Header) ForthError!void {
    try wordArithmeticComparison(u64, .gt, forth, header);
}

/// u64 u64 -- u64
pub fn wordGreaterThanEqualU64(forth: *Forth, header: *Header) ForthError!void {
    try wordArithmeticComparison(u64, .gteq, forth, header);
}

/// addr -- T
pub fn wordLoad(comptime T: type, forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.stack.pop();
    const p: *T = @ptrFromInt(a);
    const v = p.*;
    try forth.stack.push(v);
}

/// T addr --
pub fn wordStore(comptime T: type, forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.stack.pop();
    const v = try forth.stack.pop();

    const p: *T = @ptrFromInt(a);
    const nv: T = @truncate(v);
    p.* = nv;
}

/// T -- T
fn wordByteExchange(comptime T: type, forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.stack.pop();
    var v: T = @truncate(a);
    v = @byteSwap(v);
    try forth.stack.push(v);
}

const Comparison = enum { eq, lt, lteq, gt, gteq };

/// T -- T
fn wordArithmeticComparison(comptime T: type, comptime comparison: Comparison, forth: *Forth, _: *Header) ForthError!void {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    const lhs: T = @truncate(b);
    const rhs: T = @truncate(a);
    const result = switch (comparison) {
        .eq => lhs == rhs,
        .lt => lhs < rhs,
        .lteq => lhs <= rhs,
        .gt => lhs > rhs,
        .gteq => lhs >= rhs,
    };
    try forth.stack.push(@intFromBool(result));
}

pub fn wordGetScreenText(forth: *Forth, _: *Header) ForthError!void {
    const n = try forth.popAs(i64);
    const pStr = try forth.popAs([*]u8);
    const line_no: u64 = if (n < 0) @intCast(forth.char_buffer.current_row) else @intCast(n);

    forth.char_buffer.rowTextGet(line_no, pStr);
    pStr[forth.char_buffer.current_col] = 0;
    try forth.pushAny(pStr);
}

pub fn wordHistoryAdd(forth: *Forth, _: *Header) ForthError!void {
    const pStr = try forth.popAs([*]u8);
    const str = string.asSlice(pStr);
    forth.history.add(str) catch |e| {
        forth.print("Exception: {any}\n", .{e}) catch {};
    };
}

pub fn wordHistoryPrint(forth: *Forth, _: *Header) ForthError!void {
    const items = forth.history.items();
    for (items) |item| {
        try forth.print("{s}\n", .{item});
    }
}
pub fn wordSerialSDot(forth: *Forth, _: *Header) ForthError!void {
    const p = try forth.popAs([*]u8);
    const s = string.asSlice(p);
    try forth.serial_print("{s}", .{s});
}

pub fn wordSerialDot(forth: *Forth, _: *Header) ForthError!void {
    const v = try forth.popAs(i64);
    try forth.serial_print("{}", .{v});
}

pub fn wordTest2(forth: *Forth, _: *Header) ForthError!void {
    _ = forth;
}

pub fn wordDumpFreelist(_: *Forth, _: *Header) ForthError!void {
    const memory = @import("../memory.zig");
    memory.dumpFreelist();
}

pub fn defineCore(forth: *Forth) !void {

    // Expose internal values to forty.
    try forth.defineConstant("word", @sizeOf(u64));

    // IO
    _ = try forth.definePrimitiveDesc("hello", " -- :Hello world!", &wordHello, false);
    _ = try forth.definePrimitiveDesc("emit", "ch -- :Emit a char", &wordEmit, false);
    _ = try forth.definePrimitiveDesc("key", " -- ch :Read a key", &wordKey, false);
    _ = try forth.definePrimitiveDesc("key?", " -- n: Check for a key press", &wordKeyMaybe, false);
    _ = try forth.definePrimitiveDesc("sleep", " n -- : Pause for some milliseconds", &wordSleep, false);

    // Basic Forth words.
    _ = try forth.definePrimitiveDesc("exec", "pHeader -- <Results>", &wordExec, false);
    _ = try forth.definePrimitiveDesc("eval", "pStr -- <Results>", &wordEval, false);
    _ = try forth.definePrimitiveDesc("eval-command", "pStr -- <Results>", &wordEvalCommand, false);
    _ = try forth.definePrimitiveDesc("lookup", "word-name -- wordp or 0", &wordLookup, false);
    _ = try forth.definePrimitiveDesc("try", "word-addr catch-addr -- <<result>>", &wordTry, false);

    // Stack related words.
    _ = try forth.definePrimitiveDesc("swap", "w1 w2 -- w2 w1", &wordSwap, true);
    _ = try forth.definePrimitiveDesc("2swap", " w1 w2 w3 w4 -- w3 w4 w1 w2 ", &word2Swap, false);
    _ = try forth.definePrimitiveDesc("dup", "w -- w w", &wordDup, true);
    _ = try forth.definePrimitiveDesc("2dup", "w1 w2 -- w1 w2 w1 w2", &word2Dup, false);
    _ = try forth.definePrimitiveDesc("3dup", "w1 w2 w3 -- w1 w2 w3 w1 w2 w3 ", &word3Dup, false);
    _ = try forth.definePrimitiveDesc("clear", "<anything> --", &wordClear, false);
    _ = try forth.definePrimitiveDesc("drop", "w --", &wordDrop, true);
    _ = try forth.definePrimitiveDesc("2drop", "w w --", &word2Drop, true);
    _ = try forth.definePrimitiveDesc("rot", "w1 w2 w3 -- w2 w3 w1", &wordRot, false);
    _ = try forth.definePrimitiveDesc("2rot", "w1 w2 w3 w4 w5 w6 -- w3 w4 w5 w6 w1 w2", &word2Rot, false);
    _ = try forth.definePrimitiveDesc("over", "w1 w2 -- w1 w2 w1", &wordOver, false);
    _ = try forth.definePrimitiveDesc("2over", ", w1 w2 w3 w4 -- w1 w2 w3 w4 w1 w2", &word2Over, false);

    _ = try forth.definePrimitiveDesc("->istack", "n -- n :copy tos to istack", &wordToRStack, false);
    _ = try forth.definePrimitiveDesc("->stack", "n -- n :copy top of istack to data stack", &wordToDStack, false);

    _ = try forth.definePrimitiveDesc("+.", "n -- :print tos as i64 in current obase", &wordSignedDot, false);
    _ = try forth.definePrimitiveDesc("+#.", "n -- :print tos as i64 in current obase", &wordSDecimalDot, false);
    _ = try forth.definePrimitiveDesc(".", "n -- :print tos as u64 in current obase", &wordDot, false);
    _ = try forth.definePrimitiveDesc("~", "n -- :print tos as i64 to serial", &wordSerialDot, false);
    _ = try forth.definePrimitiveDesc("#.", "n -- :print tos as u64 in decimal", &wordDecimalDot, false);
    _ = try forth.definePrimitiveDesc("h.", "n -- :print tos as u64 in decimal", &wordHexDot, false);
    _ = try forth.definePrimitiveDesc("s.", "s -- :print tos as a string", &wordSDot, false);
    _ = try forth.definePrimitiveDesc("s~", "s -- :print tos as a string to serial port", &wordSerialSDot, false);
    _ = try forth.definePrimitiveDesc("s=", "s s -- b :string contents equality", &wordSEqual, false);
    _ = try forth.definePrimitiveDesc("+", "n n -- n :u64 addition", &wordAdd, false);
    _ = try forth.definePrimitiveDesc("-", "n n -- n :u64 subtraction", &wordSub, false);
    _ = try forth.definePrimitiveDesc("*", "n n -- n :u64 multiplication", &wordMul, false);
    _ = try forth.definePrimitiveDesc("/", "n n -- n :u64 division", &wordDiv, false);
    _ = try forth.definePrimitiveDesc("%", "n n -- n :u64 modulo", &wordMod, false);
    _ = try forth.definePrimitiveDesc("=", "n n -- n :u64 equality test", &wordEqualU64, false);
    _ = try forth.definePrimitiveDesc("not", "n -- n :u64 not", &wordNot, false);
    _ = try forth.definePrimitiveDesc("or", "n -- n :u64 or", &wordOr, false);
    _ = try forth.definePrimitiveDesc("xor", "n -- n :u64 xor", &wordXor, false);
    _ = try forth.definePrimitiveDesc("and", "n -- n :u64 and", &wordAnd, false);
    _ = try forth.definePrimitiveDesc("lshift", "n u -- n : u64 bitwise left shift", &wordLeftShift, false);
    _ = try forth.definePrimitiveDesc("rshift", "n u -- n : u64 bitwise right shift", &wordRightShift, false);
    _ = try forth.definePrimitiveDesc("<", "n n -- n :u64 less-than test", &wordLessThanU64, false);
    _ = try forth.definePrimitiveDesc("<=", "n n -- n :u64 less-than or equal test", &wordLessThanEqualU64, false);
    _ = try forth.definePrimitiveDesc(">", "n n -- n :u64 greater-than test", &wordGreaterThanU64, false);
    _ = try forth.definePrimitiveDesc(">=", "n n -- n :u64 greater-than or equal test", &wordGreaterThanEqualU64, false);

    _ = try forth.definePrimitiveDesc("!", "w addr -- : Store a 64 bit unsigned word.", &wordStoreU64, false);
    _ = try forth.definePrimitiveDesc("@", "addr - w : Load a 64 bit unsigned word.", &wordLoadU64, false);
    _ = try forth.definePrimitive("be", &wordByteExchangeU64, false);
    _ = try forth.definePrimitiveDesc("!b", "b addr -- : Store a byte.", &wordStoreU8, false);
    _ = try forth.definePrimitiveDesc("@b", "addr -- b : Load a byte.", &wordLoadU8, false);
    _ = try forth.definePrimitiveDesc("!w", "w addr -- : Store a 32 unsigned bit word.", &wordStoreU32, false);
    _ = try forth.definePrimitiveDesc("@w", "addr -- : Load a 32 bit unsigned word", &wordLoadU32, false);
    _ = try forth.definePrimitive("wbe", &wordByteExchangeU32, false);

    _ = try forth.definePrimitiveDesc("set-mem", "value addr len -- : Initialize a block of memory.", &wordSetMemory, false);

    // Screen and history related words.
    _ = try forth.definePrimitiveDesc("get-scr-text", "nline -- str : Get the text of the given line.", &wordGetScreenText, false);
    _ = try forth.definePrimitiveDesc("history-add", "str -- : Add a string to the command history.", &wordHistoryAdd, false);
    _ = try forth.definePrimitiveDesc("history", " -- : Print the command history.", &wordHistoryPrint, false);
    _ = try forth.definePrimitiveDesc("dump-freelist", " -- : Print the memory manager's freelist", &wordDumpFreelist, false);
}
