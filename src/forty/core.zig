const std = @import("std");
const Allocator = std.mem.Allocator;

const hal = @import("../hal.zig");
const BoardInfo = hal.BoardInfo;

const frame_buffer = @import("../frame_buffer.zig");
const FrameBuffer = frame_buffer.FrameBuffer;

const fbcons = @import("../fbcons.zig");
const FrameBufferConsole = fbcons.FrameBufferConsole;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const string = @import("string.zig");
const parser = @import("parser.zig");

const forth_module = @import("forth.zig");
const Forth = forth_module.Forth;

const memory_module = @import("memory.zig");
const Header = memory_module.Header;

/// len *[]u8  --  <results>
pub fn wordEval(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const pStr: [*]u8 = try forth.popAs([*]u8);
    const token = string.asSlice(pStr);
    try forth.evalToken(token);
    return 0;
}

/// len *[]u8  --  <results>
pub fn wordEvalCommand(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const pStr: [*]u8 = try forth.popAs([*]u8);
    const token = string.asSlice(pStr);
    try forth.evalCommand(token);
    return 0;
}

/// value addr len --
pub fn wordSetMemory(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const len = try forth.stack.pop();
    const addr = try forth.popAs([*]u8);
    const value = try forth.stack.pop();
    const byteValue: u8 = @intCast(value % 256);

    var offset: usize = 0;
    while (offset < len) {
        addr[offset] = byteValue;
        offset += 1;
    }
    return 0;
}

/// x y a -- ()
pub fn wordDrawChar(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.stack.pop();
    const y = try forth.stack.pop();
    const x = try forth.stack.pop();
    var ch: u8 = @intCast(a);
    forth.console.drawChar(x, y, ch);
    return 0;
}

/// a -- ()
pub fn wordEmit(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.stack.pop();
    var ch: u8 = @intCast(a);
    try forth.emit(ch);
    return 0;
}

// -- ch
pub fn wordKey(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const ch = forth.console.getc();
    try forth.stack.push(@intCast(ch));
    return 0;
}

// -- bool
pub fn wordKeyMaybe(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var byte_available = forth.console.char_available();
    try forth.stack.push(if (byte_available) 1 else 0);
    return 0;
}

/// -- n
pub fn wordTicks(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var ticks = hal.clock.ticks();
    try forth.stack.push(ticks);
    return 0;
}

/// sx sy w h dx dy --
pub fn wordBlit(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var dy = try forth.stack.pop();
    var dx = try forth.stack.pop();
    var h = try forth.stack.pop();
    var w = try forth.stack.pop();
    var sy = try forth.stack.pop();
    var sx = try forth.stack.pop();
    forth.console.fb.blit(sx, sy, w, h, dx, dy);
    return 0;
}

/// l t r b c --
pub fn wordFill(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var color = try forth.stack.pop();
    var bottom = try forth.stack.pop();
    var right = try forth.stack.pop();
    var top = try forth.stack.pop();
    var left = try forth.stack.pop();

    forth.console.fb.fill(left, top, right, bottom, @truncate(color & 0xff)) catch return ForthError.BadOperation;
    return 0;
}

/// x0 y0 x1 y1 c --
pub fn wordLine(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var color = try forth.stack.pop();
    var y1 = try forth.stack.pop();
    var x1 = try forth.stack.pop();
    var y0 = try forth.stack.pop();
    var x0 = try forth.stack.pop();

    forth.console.fb.line(x0, y0, x1, y1, @truncate(color & 0xff)) catch return ForthError.BadOperation;
    return 0;
}

/// str x y --
pub fn wordText(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var y = try forth.stack.pop();
    var x = try forth.stack.pop();
    var str = try forth.popAs([*:0]u8);
    forth.console.fb.drawString(str, x, y);
    return 0;
}

/// --
pub fn wordReset(_: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    asm volatile ("brk 0x07c5");
    return 0;
}

/// --
pub fn wordCr(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.emit(0x0a);
    return 0;
}

/// --
pub fn wordClearScreen(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.emit(0x0c);
    return 0;
}

/// --
pub fn wordHello(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.print("Hello world!\n", .{});
    return 0;
}

/// n --
pub fn wordDot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var v = try forth.popAs(i64);
    try std.fmt.formatInt(v, @intCast(forth.obase), .lower, .{}, forth.writer());
    return 0;
}

/// n --
pub fn wordSignedDot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var v: i64 = @bitCast(try forth.stack.pop());
    try std.fmt.formatInt(v, @intCast(forth.obase), .lower, .{}, forth.writer());
    return 0;
}

/// n --
pub fn wordSDecimalDot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var v: i64 = @bitCast(try forth.stack.pop());
    try std.fmt.formatInt(v, 10, .lower, .{}, forth.writer());
    return 0;
}

/// saddr --
pub fn wordSDot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const i = try forth.stack.pop();
    const p_string: [*:0]u8 = @ptrFromInt(i);
    try forth.print("{s}", .{p_string});
    return 0;
}

/// saddr saddr --
pub fn wordSEqual(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.stack.pop();
    const a_string: [*:0]u8 = @ptrFromInt(a);
    const b = try forth.stack.pop();
    const b_string: [*:0]u8 = @ptrFromInt(b);
    const result: u64 = if (string.streql(a_string, b_string)) 1 else 0;
    try forth.stack.push(result);
    return 0;
}

/// n --
pub fn wordHexDot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var v: u64 = try forth.stack.pop();
    try forth.print("{x} ", .{v});
    return 0;
}

/// n --
pub fn wordDecimalDot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var v: u64 = try forth.stack.pop();
    try std.fmt.formatInt(v, 10, .lower, .{}, forth.writer());
    return 0;
}

/// w1 w2 -- w2 w1
pub fn wordSwap(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var s = &forth.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(a);
    try s.push(b);
    return 0;
}

/// w1 w2 w3 w4 -- w3 w4 w1 w2
pub fn word2Swap(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
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
pub fn wordDup(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var s = &forth.stack;
    const a = try s.pop();
    try s.push(a);
    try s.push(a);
    return 0;
}

/// w1 w2 -- w1 w2 w1 w2
pub fn word2Dup(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var s = &forth.stack;
    const w2 = try s.pop();
    const w1 = try s.pop();
    try s.push(w1);
    try s.push(w2);
    try s.push(w1);
    try s.push(w2);
    return 0;
}

///  -- : Clear the stack.
pub fn wordClear(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try forth.stack.reset();
    return 0;
}

/// w1 --
pub fn wordDrop(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var s = &forth.stack;
    _ = try s.pop();
    return 0;
}

/// w1 w2 --
pub fn word2Drop(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var s = &forth.stack;
    _ = try s.pop();
    _ = try s.pop();
    return 0;
}

/// w1 w2 w3 -- w2 w3 w1
pub fn wordRot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
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
pub fn word2Rot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
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
pub fn wordOver(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    var s = &forth.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(b);
    try s.push(a);
    try s.push(b);
    return 0;
}

/// w1 w2 w3 w4 -- w1 w2 w3 w4 w1 w2
pub fn word2Over(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
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
pub fn wordAdd(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.popAs(i64);
    const b = try forth.popAs(i64);
    try forth.pushAny(b + a);
    return 0;
}

/// n n -- n
pub fn wordSub(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.popAs(i64);
    const b = try forth.popAs(i64);
    try forth.pushAny(b - a);
    return 0;
}

/// n n -- n
pub fn wordMul(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.popAs(i64);
    const b = try forth.popAs(i64);
    try forth.pushAny(b * a);
    return 0;
}

/// n n -- n
pub fn wordDiv(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.popAs(i64);
    const b = try forth.popAs(i64);
    try forth.pushAny(@divTrunc(b, a));
    return 0;
}

/// n n -- n
pub fn wordMod(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.popAs(i64);
    const b = try forth.popAs(i64);
    try forth.pushAny(@mod(b, a));
    return 0;
}

/// n -- n
pub fn wordNot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.stack.pop();
    if (a == 0) {
        try forth.stack.push(1);
    } else {
        try forth.stack.push(0);
    }
    return 0;
}

/// b b -- b
pub fn wordOr(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    if (a != 0) {
        try forth.stack.push(a);
    } else if (b != 0) {
        try forth.stack.push(b);
    } else {
        try forth.stack.push(0);
    }
    return 0;
}

/// b b -- b
pub fn wordXor(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    if (a != 0 and b != 0) {
        try forth.stack.push(0);
    } else if (a != 0) {
        try forth.stack.push(a);
    } else if (b != 0) {
        try forth.stack.push(b);
    } else {
        try forth.stack.push(0);
    }
    return 0;
}

/// b b -- b
pub fn wordAnd(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    if (a == 0 or b == 0) {
        try forth.stack.push(0);
    } else {
        try forth.stack.push(b);
    }
    return 0;
}

/// addr -- u8
pub fn wordLoadU8(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64 {
    return wordLoad(u8, forth, body, offset, header);
}

/// u8 addr --
pub fn wordStoreU8(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64 {
    return wordStore(u8, forth, body, offset, header);
}

/// addr -- u32
pub fn wordLoadU32(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64 {
    return wordLoad(u32, forth, body, offset, header);
}

/// u32 addr --
pub fn wordStoreU32(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64 {
    return wordStore(u32, forth, body, offset, header);
}

/// u32 -- u32
pub fn wordByteExchangeU32(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64 {
    return wordByteExchange(u32, forth, body, offset, header);
}

/// addr -- u64
pub fn wordLoadU64(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64 {
    return wordLoad(u64, forth, body, offset, header);
}

/// u64 addr --
pub fn wordStoreU64(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64 {
    return wordStore(u64, forth, body, offset, header);
}

/// u64 -- u64
pub fn wordByteExchangeU64(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64 {
    return wordByteExchange(u64, forth, body, offset, header);
}

/// u64 u64 -- u64
pub fn wordEqualU64(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64 {
    return wordArithmeticComparison(u64, .eq, forth, body, offset, header);
}

/// u64 u64 -- u64
pub fn wordLessThanU64(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64 {
    return wordArithmeticComparison(u64, .lt, forth, body, offset, header);
}

/// u64 u64 -- u64
pub fn wordLessThanEqualU64(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64 {
    return wordArithmeticComparison(u64, .lteq, forth, body, offset, header);
}

/// u64 u64 -- u64
pub fn wordGreaterThanU64(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64 {
    return wordArithmeticComparison(u64, .gt, forth, body, offset, header);
}

/// u64 u64 -- u64
pub fn wordGreaterThanEqualU64(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64 {
    return wordArithmeticComparison(u64, .gteq, forth, body, offset, header);
}

/// addr -- T
pub fn wordLoad(comptime T: type, forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.stack.pop();
    const p: *T = @ptrFromInt(a);
    const v = p.*;
    try forth.stack.push(v);
    return 0;
}

/// T addr --
pub fn wordStore(comptime T: type, forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.stack.pop();
    const v = try forth.stack.pop();

    const p: *T = @ptrFromInt(a);
    var nv: T = @truncate(v);
    p.* = nv;
    return 0;
}

/// T -- T
fn wordByteExchange(comptime T: type, forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.stack.pop();
    var v: T = @truncate(a);
    v = @byteSwap(v);
    try forth.stack.push(v);
    return 0;
}

const Comparison = enum { eq, lt, lteq, gt, gteq };

/// T -- T
fn wordArithmeticComparison(comptime T: type, comptime comparison: Comparison, forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const a = try forth.stack.pop();
    const b = try forth.stack.pop();
    var lhs: T = @truncate(b);
    var rhs: T = @truncate(a);
    var result = switch (comparison) {
        .eq => lhs == rhs,
        .lt => lhs < rhs,
        .lteq => lhs <= rhs,
        .gt => lhs > rhs,
        .gteq => lhs >= rhs,
    };
    try forth.stack.push(@intFromBool(result));
    return 0;
}

pub fn defineCore(forth: *Forth) !void {

    // Expose internal values to forty.

    try forth.defineConstant("word", @sizeOf(u64));
    try forth.defineStruct("board", BoardInfo);
    try forth.defineStruct("board.model", BoardInfo.Model);
    try forth.defineStruct("board.device", BoardInfo.Device);
    try forth.defineStruct("board.memory", BoardInfo.Memory);

    try forth.defineStruct("fbcons", FrameBufferConsole);
    try forth.defineStruct("fb", FrameBuffer);
    try forth.defineStruct("fb.vtable", FrameBuffer.VTable);

    // Display.

    _ = try forth.definePrimitiveDesc("blit", "sx sy w h dx dy -- : Copy a screen rect", &wordBlit, false);
    _ = try forth.definePrimitiveDesc("fill", "l t r b c -- : fill rectangle with color", &wordFill, false);
    _ = try forth.definePrimitiveDesc("line", "x0 y0 x1 y1 c -- : draw line with color", &wordLine, false);
    _ = try forth.definePrimitiveDesc("text", "s x y -- : draw string at position", &wordText, false);

    // IO
    _ = try forth.definePrimitiveDesc("hello", " -- :Hello world!", &wordHello, false);
    _ = try forth.definePrimitiveDesc("cr", " -- :Emit a newline", &wordCr, false);
    _ = try forth.definePrimitiveDesc("emit", "ch -- :Emit a char", &wordEmit, false);
    _ = try forth.definePrimitiveDesc("draw-char", "x y ch -- :Draw a char", &wordDrawChar, false);
    _ = try forth.definePrimitiveDesc("cls", " -- :Clear the screen", &wordClearScreen, false);
    _ = try forth.definePrimitiveDesc("key", " -- ch :Read a key", &wordKey, false);
    _ = try forth.definePrimitiveDesc("key?", " -- n: Check for a key press", &wordKeyMaybe, false);
    _ = try forth.definePrimitiveDesc("ticks", " -- n: Read clock", &wordTicks, false);
    _ = try forth.definePrimitiveDesc("reset", " -- : Soft reset the system", &wordReset, false);

    // Basic Forth words.
    _ = try forth.definePrimitiveDesc("eval", "pStr -- <Results>", &wordEval, false);
    _ = try forth.definePrimitiveDesc("eval-cmd", "pStr -- <Results>", &wordEvalCommand, false);
    _ = try forth.definePrimitiveDesc("swap", "w1 w2 -- w2 w1", &wordSwap, false);
    _ = try forth.definePrimitiveDesc("2swap", " w1 w2 w3 w4 -- w3 w4 w1 w2 ", &word2Swap, false);
    _ = try forth.definePrimitiveDesc("dup", "w -- w w", &wordDup, false);
    _ = try forth.definePrimitiveDesc("2dup", "w1 w2 -- w1 w2 w1 w2", &word2Dup, false);
    _ = try forth.definePrimitiveDesc("clear", "<anything> --", &wordClear, false);
    _ = try forth.definePrimitiveDesc("drop", "w --", &wordDrop, false);
    _ = try forth.definePrimitiveDesc("2drop", "w w --", &word2Drop, false);
    _ = try forth.definePrimitiveDesc("rot", "w1 w2 w3 -- w2 w3 w1", &wordRot, false);
    _ = try forth.definePrimitiveDesc("2rot", "w1 w2 w3 w4 w5 w6 -- w3 w4 w5 w6 w1 w2", &word2Rot, false);
    _ = try forth.definePrimitiveDesc("over", "w1 w2 -- w1 w2 w1", &wordOver, false);
    _ = try forth.definePrimitiveDesc("2over", ", w1 w2 w3 w4 -- w1 w2 w3 w4 w1 w2", &word2Over, false);

    _ = try forth.definePrimitiveDesc("+.", "n -- :print tos as i64 in current obase", &wordSignedDot, false);
    _ = try forth.definePrimitiveDesc("+#.", "n -- :print tos as i64 in current obase", &wordSDecimalDot, false);
    _ = try forth.definePrimitiveDesc(".", "n -- :print tos as u64 in current obase", &wordDot, false);
    _ = try forth.definePrimitiveDesc("#.", "n -- :print tos as u64 in decimal", &wordDecimalDot, false);
    _ = try forth.definePrimitiveDesc("h.", "n -- :print tos as u64 in decimal", &wordHexDot, false);
    _ = try forth.definePrimitiveDesc("s.", "s -- :print tos as a string", &wordSDot, false);
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
}
