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

const formatText = std.fmt.formatText;
const FormatOptions = std.fmt.FormatOptions;

const memory_module = @import("memory.zig");
const Header = memory_module.Header;

const InvalidOffset = std.math.maxInt(u64);

// This is the inner interpreter, effectively the word
// that runs all the secondary words.
pub fn inner(forth: *Forth, _: [*]u64, _: u64, header: *Header) ForthError!u64 {
    var body = header.bodyOfType([*]u64);
    var i: usize = 0;
    while (true) {
        try forth.trace("{}: {x}:\n", .{ i, body[i] });
        switch (body[i]) {
            @intFromEnum(OpCode.stop) => break,

            @intFromEnum(OpCode.push_u64) => {
                try forth.trace("Push {x}\n", .{body[i + 1]});
                try forth.stack.push(body[i + 1]);
                i += 2;
            },

            @intFromEnum(OpCode.push_string) => {
                try forth.trace("Push string {x}\n", .{body[i + 1]});
                const data_size = body[i + 1];
                var p_string: [*]u8 = @ptrCast(body + 2);
                try forth.stack.push(@intFromPtr(p_string));
                i += data_size + 2;
            },

            @intFromEnum(OpCode.jump) => {
                const offset = body[i + 1];
                try forth.trace("Jump {}\n", .{offset});
                i = i + 2 + offset;
            },

            @intFromEnum(OpCode.jump_if_not) => {
                const offset = body[i + 1];
                var c: u64 = try forth.stack.pop();
                try forth.trace("JumpIfNot {} {}\n", .{ c, offset });
                if (c == 0) {
                    i = i + 2 + offset;
                } else {
                    i = i + 2;
                }
            },

            else => {
                const p: *Header = @ptrFromInt(body[i]);
                try forth.trace("Header: {x}\n", .{&p});
                const delta = try p.func(forth, body, i, p);
                i = i + 1 + delta;
            },
        }
    }
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
    _ = try forth.startWord(name, desc, &inner, false);
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

    if (header.func != &inner) {
        const h: u64 = @intFromPtr(header);
        const p: u64 = @intFromPtr(header.func);
        try forth.print("Word name: {s} header: {x} func: {x}\n", .{ header.name, h, p });
        try forth.print("Description: {s}\n", .{header.desc});
        return 0;
    }

    var body = header.bodyOfType([*]u64);
    var len = header.bodyLen();
    try forth.print("Word name: {s} len: {} immed: {}\n", .{ header.name, len, header.immediate });
    try forth.print("Description: {s}\n", .{header.desc});

    try forth.print("Bytes:", .{});

    var cbody = header.bodyOfType([*]u8);
    for (0..len) |j| {
        const ch = cbody[j];
        const vis_ch = if ((ch >= ' ') and (ch <= '~')) ch else '.';
        if ((j % 8) == 0) {
            try forth.print("\n{:4}: ", .{j});
        }
        try forth.print("{c}[{x:2}]  ", .{ vis_ch, ch });
    }
    try forth.print("\n\nInstructions:\n", .{});

    var i: usize = 0;
    while (true) {
        switch (body[i]) {
            @intFromEnum(OpCode.stop) => {
                try forth.print("{}: Stop\n", .{i});
                break;
            },

            @intFromEnum(OpCode.push_u64) => {
                try forth.print("{}: PushU64 {x:2}\n", .{ i, body[i + 1] });
                i += 2;
            },

            @intFromEnum(OpCode.push_string) => {
                const data_size = body[i + 1];
                var p_string: [*:0]u8 = @ptrCast(body + 2);
                try forth.print("{}: PushString [{}] {s}\n", .{ i, data_size, p_string });
                i += data_size + 2;
            },

            @intFromEnum(OpCode.jump) => {
                const offset = body[i + 1];
                try forth.print("{}: Jump [{}]\n", .{ i, offset });
                i = i + 2;
            },

            @intFromEnum(OpCode.jump_if_not) => {
                const offset = body[i + 1];
                try forth.print("{} :JumpIfNot [{}]\n", .{ i, offset });
                i = i + 2;
            },
            else => {
                const addr = body[i];
                try forth.print("{}: Call [{x}]\n", .{ i, addr });
                i = i + 1;
            },
        }
    }
    return 0;
}

// Testing - jump relative
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
// pops the address (pushed by if) off of the rstack and plus in the address
// just after the jump instruction.
pub fn wordElse(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertCompiling();

    const current_p = forth.current();
    const if_jump_p = try forth.rstack.pop();

    // Back fill the jump address for the If.

    const delta = ((@intFromPtr(current_p) - if_jump_p) / @sizeOf(u64)) + 1;
    const if_jump_p_u64: [*]u64 = @ptrFromInt(if_jump_p);
    if_jump_p_u64[0] = delta;

    // Add the else jump instruction and push its address onto the stack
    // to be filled in later by endif.

    forth.addOpCode(OpCode.jump);
    try forth.rstack.push(@intFromPtr(forth.current()));
    forth.addNumber(InvalidOffset);

    return 0;
}

// Compiler word, generate the end code for if/endif or if/else/endif.
// Pops the address off of the rstack and plugs in the offset to the
// current instuction.
pub fn wordEndif(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    try forth.assertCompiling();

    const if_jump_p = try forth.rstack.pop();

    const current_p = forth.current();
    const delta = ((@intFromPtr(current_p) - if_jump_p) / @sizeOf(u64)) - 1;
    const if_jump_p_u64: [*]u64 = @ptrFromInt(if_jump_p);
    if_jump_p_u64[0] = delta;
    return 0;
}

/// sAddr n -- ()
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
    try std.fmt.formatInt(v, @intCast(forth.obase), .lower, .{}, forth.writer());
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

/// n --
pub fn wordDecimalDot(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    var v: u64 = try forth.stack.pop();
    try std.fmt.formatInt(v, 10, .lower, .{}, forth.writer());
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
    //const w = 100;
    //const options = FormatOptions{ .width = memory.WordNameLen + 1, .alignment = .left };

    var e = forth.lastWord;
    var i: usize = 0;
    while (e) |entry| {
        const immed = if (entry.immediate) "^" else " ";
        i += 1;
        var sep: u8 = if ((i % 5) == 0) '\n' else '\t';
        try forth.print("{s} {s: <20}{c}", .{ immed, entry.name, sep });

        e = entry.previous;
    }
    try forth.print("\n", .{});
    return 0;
}

/// addr -- u8
pub fn wordLoadU8(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return wordLoad(u8, forth, body, offset, header);
}

/// u8 addr --
pub fn wordStoreU8(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return wordStore(u8, forth, body, offset, header);
}

/// addr -- u32
pub fn wordLoadU32(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return wordLoad(u32, forth, body, offset, header);
}

/// u32 addr --
pub fn wordStoreU32(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return wordStore(u32, forth, body, offset, header);
}

/// u32 -- u32
pub fn wordByteExchangeU32(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return wordByteExchange(u32, forth, body, offset, header);
}

/// addr -- u64
pub fn wordLoadU64(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return wordLoad(u64, forth, body, offset, header);
}

/// u64 addr --
pub fn wordStoreU64(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return wordStore(u64, forth, body, offset, header);
}

/// u64 -- u64
pub fn wordByteExchangeU64(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return wordByteExchange(u64, forth, body, offset, header);
}

/// addr -- T
pub fn wordLoad(comptime T: type, forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const a = try forth.stack.pop();
    const p: *T = @ptrFromInt(a);
    const v = p.*;
    try forth.stack.push(v);
    return 0;
}

/// T addr --
pub fn wordStore(comptime T: type, forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const a = try forth.stack.pop();
    const v = try forth.stack.pop();

    const p: *T = @ptrFromInt(a);
    var nv: T = @truncate(v);
    p.* = nv;
    return 0;
}

/// T -- T
fn wordByteExchange(comptime T: type, forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const a = try forth.stack.pop();
    var v: T = @truncate(a);
    v = @byteSwap(v);
    try forth.stack.push(v);
    return 0;
}

pub fn defineCore(forth: *Forth) !void {
    // Expose internal values to forty.

    try forth.defineInternalVariable("ibase", &forth.ibase);
    try forth.defineInternalVariable("obase", &forth.obase);
    try forth.defineInternalVariable("debug", &forth.debug);

    try forth.defineInternalVariable("screenw", &forth.console.width);
    try forth.defineInternalVariable("screenh", &forth.console.height);
    try forth.defineInternalVariable("cursorx", &forth.console.xpos);
    try forth.defineInternalVariable("cursory", &forth.console.ypos);

    // IO
    _ = try forth.definePrimitiveDesc("hello", " -- :Hello world!", &wordHello, false);
    _ = try forth.definePrimitiveDesc("cr", " -- :Emit a newline", &wordCr, false);
    _ = try forth.definePrimitiveDesc("emit", "ch -- :Emit a char", &wordEmit, false);
    _ = try forth.definePrimitiveDesc("cls", " -- :Clear the screen", &wordClearScreen, false);
    _ = try forth.definePrimitiveDesc("key", " -- ch :Read a key", &wordKey, false);
    _ = try forth.definePrimitiveDesc("key?", " -- n: Check for a key press", &wordKeyMaybe, false);

    // Secondary definition words.

    _ = try forth.definePrimitiveDesc(":", " -- :Start a new word definition", &wordColon, false);
    _ = try forth.definePrimitiveDesc(";", " -- :Complete a new word definition", &wordSemi, true);
    _ = try forth.definePrimitiveDesc("if", " -- :If statement", &wordIf, true);
    _ = try forth.definePrimitiveDesc("else", " -- :Part of if/else/endif", &wordElse, true);
    _ = try forth.definePrimitiveDesc("endif", " -- :Part of if/else/endif", &wordEndif, true);
    _ = try forth.definePrimitiveDesc("$jump", " -- :Compile in a jump instruction", &wordJump, true);
    _ = try forth.definePrimitiveDesc("immediate", " -- :Set the last word to immediate.", &wordImmediate, false);
    _ = try forth.definePrimitiveDesc("?", " -- :Print description of word.", &wordDesc, false);

    // Debug and inspection words.
    _ = try forth.definePrimitiveDesc("?stack", " -- :Print the stack.", &wordStack, false);
    _ = try forth.definePrimitiveDesc("??", " -- :Print the dictionary.", &wordDictionary, false);
    _ = try forth.definePrimitiveDesc("rstack", " -- :Print the return stack.", &wordRStack, false);
    _ = try forth.definePrimitiveDesc("?word", " -- :Print details of word.", &wordDumpWord, false);

    // Basic Forth words.
    _ = try forth.definePrimitiveDesc("swap", "w1 w2 -- w2 w1", &wordSwap, false);
    _ = try forth.definePrimitiveDesc("2swap", " w1 w2 w3 w4 -- w3 w4 w1 w2 ", &word2Swap, false);
    _ = try forth.definePrimitiveDesc("dup", "w -- w w", &wordDup, false);
    _ = try forth.definePrimitiveDesc("2dup", "w1 w2 -- w1 w2 w1 w2", &word2Dup, false);
    _ = try forth.definePrimitiveDesc("drop", "w --", &wordDrop, false);
    _ = try forth.definePrimitiveDesc("2drop", "w w --", &word2Drop, false);
    _ = try forth.definePrimitiveDesc("rot", "w1 w2 w3 -- w2 w3 w1", &wordRot, false);
    _ = try forth.definePrimitiveDesc("2rot", "w1 w2 w3 w4 w5 w6 -- w3 w4 w5 w6 w1 w2", &word2Rot, false);
    _ = try forth.definePrimitiveDesc("over", "w1 w2 -- w1 w2 w1", &wordOver, false);
    _ = try forth.definePrimitiveDesc("2over", ", w1 w2 w3 w4 -- w1 w2 w3 w4 w1 w2", &word2Over, false);

    _ = try forth.definePrimitiveDesc(".", "n -- :print tos as u64 in current obase", &wordDot, false);
    _ = try forth.definePrimitiveDesc("#.", "n -- :print tos as u64 in decimal", &wordDecimalDot, false);
    _ = try forth.definePrimitiveDesc("h.", "n -- :print tos as u64 in decimal", &wordHexDot, false);
    _ = try forth.definePrimitiveDesc("s.", "s -- :print tos as a string", &wordDot, false);
    _ = try forth.definePrimitiveDesc("+", "n n -- n :u64 addition", &wordAdd, false);
    _ = try forth.definePrimitiveDesc("-", "n n -- n :u64 subtraction", &wordSub, false);
    _ = try forth.definePrimitiveDesc("*", "n n -- n :u64 multiplication", &wordMul, false);
    _ = try forth.definePrimitiveDesc("/", "n n -- n :u64 division", &wordDiv, false);
    _ = try forth.definePrimitiveDesc("%", "n n -- n :u64 modulo", &wordMod, false);

    _ = try forth.definePrimitiveDesc("!", "w addr -- : Store a 64 bit unsigned word.", &wordStoreU64, false);
    _ = try forth.definePrimitiveDesc("@", "addr - w : Load a 64 bit unsigned word.", &wordLoadU64, false);
    _ = try forth.definePrimitive("be", &wordByteExchangeU64, false);
    _ = try forth.definePrimitiveDesc("!b", "b addr -- : Store a byte.", &wordStoreU8, false);
    _ = try forth.definePrimitiveDesc("@b", "addr -- b : Load a byte.", &wordLoadU8, false);
    _ = try forth.definePrimitiveDesc("!w", "w addr -- : Store a 32 unsigned bit word.", &wordStoreU32, false);
    _ = try forth.definePrimitiveDesc("@w", "addr -- : Load a 32 bit unsigned word", &wordLoadU32, false);
    _ = try forth.definePrimitive("wbe", &wordByteExchangeU32, false);
}
