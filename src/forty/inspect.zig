const std = @import("std");
const Allocator = std.mem.Allocator;

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

const inner_module = @import("inner.zig");
const inner = inner_module.inner;
const OpCode = inner_module.OpCode;

///  --
pub fn wordStackTrace(forth: *Forth, _: *Header) ForthError!void {
    const items = forth.call_stack.items();

    // Each call has 2 entries on the stack: a *Header
    // and an current offset into the body.
    var i: usize = 0;
    while (i < items.len) {
        const p: *Header = @ptrFromInt(items[i]);
        const offset = items[i + 1];
        try forth.print("[{}]: {s} ({*}) Offset {}\n", .{ i / 2, p.name, p, offset });
        i += 2;
    }
}

/// addr len --
pub fn wordDump(forth: *Forth, _: *Header) ForthError!void {
    const len = try forth.stack.pop();
    const iAddr = try forth.stack.pop();
    const addr: [*]u8 = @ptrFromInt(iAddr);

    var offset: usize = 0;
    while (offset < len) {
        try forth.print("{x:16}  ", .{iAddr + offset});
        for (0..16) |iByte| {
            try forth.print("{x:2} ", .{addr[offset + iByte]});
            if (iByte == 7) {
                try forth.print("  ", .{});
            }
        }
        try forth.print("  |", .{});
        for (0..16) |iByte| {
            try forth.print("{c}", .{string.toPrintable(addr[offset + iByte])});
        }
        try forth.print("|\n", .{});
        offset += 16;
    }
}

/// addr len -- : Dump memory as text.
pub fn wordTDump(forth: *Forth, _: *Header) ForthError!void {
    const len = try forth.stack.pop();
    const iAddr = try forth.stack.pop();
    const addr: [*]u8 = @ptrFromInt(iAddr);

    var offset: usize = 0;
    while (offset < len) {
        try forth.print("{x:16}   ", .{iAddr + offset});
        for (0..100) |iByte| {
            try forth.print("{c}", .{string.toPrintable(addr[offset + iByte])});
        }
        try forth.print("\n", .{});
        offset += 100;
    }
}

/// --
pub fn wordStack(forth: *Forth, _: *Header) ForthError!void {
    try forth.print("Stack: ", .{});
    for (forth.stack.items()) |item| {
        try forth.print("{}\t", .{item});
    }
    try forth.print("\n", .{});
}

/// --
pub fn wordDictionary(forth: *Forth, _: *Header) ForthError!void {
    try listDictionary(forth, "");
}

/// --
pub fn wordDictionaryFilter(forth: *Forth, _: *Header) ForthError!void {
    const pat = try forth.readWord();
    try listDictionary(forth, pat);
}

fn listDictionary(forth: *Forth, pat: []const u8) ForthError!void {
    var e = forth.last_word;
    var i: usize = 0;
    while (e) |entry| {
        if (std.mem.startsWith(u8, entry.name, pat)) {
            const immed = if (entry.immediate) "^" else " ";
            i += 1;
            var sep: u8 = if ((i % 4) == 0) '\n' else '\t';
            try forth.print("{s} {s: <25}{c}", .{ immed, entry.name, sep });
        }
        e = entry.previous;
    }
    try forth.print("\n", .{});
}

pub fn wordDesc(forth: *Forth, _: *Header) ForthError!void {
    var name = forth.words.next() orelse return ForthError.WordReadError;
    var header = forth.findWord(name) orelse return ForthError.NotFound;
    try forth.print("{s}: {s}\n", .{ header.name, header.desc });
}

pub fn wordDescAll(forth: *Forth, _: *Header) ForthError!void {
    var e = forth.last_word;
    while (e) |entry| {
        try forth.print("{s}: {s}\n", .{ entry.name, entry.desc });
        e = entry.previous;
    }
    try forth.print("\n", .{});
}

pub fn wordDumpWord(forth: *Forth, _: *Header) ForthError!void {
    var name = forth.words.next() orelse return ForthError.WordReadError;
    var header = forth.findWord(name) orelse return ForthError.NotFound;

    // Dump info about a primitive word.

    if (header.func != &inner) {
        const h: u64 = @intFromPtr(header);
        const p: u64 = @intFromPtr(header.func);
        try forth.print("Word name: {s} len: {} header: {x} func: {x}\n", .{ header.name, header.len, h, p });

        try forth.print("Description: {s}\n", .{header.desc});
        return;
    }

    // Word is a secondary, dump the meta info first.

    var len = header.bodyLen();
    try forth.print("Word name: {s} len: {} immed: {}\n", .{ header.name, len, header.immediate });
    try forth.print("Description: {s}\n\n", .{header.desc});

    // Followed by a byte dump.

    var ubody = header.bodyOfType([*]u64);

    const wLen = len / @sizeOf(u64);
    for (0..wLen) |j| {
        const chars = string.u64ToChars(ubody[j]);
        try forth.print("{:4} {x:16}   {s}", .{ j, ubody[j], chars });
        if (inner_module.isOpCode(ubody[j])) {
            const opCode: OpCode = @enumFromInt(ubody[j]);
            try forth.print("     {}", .{opCode});
        } else if (forth.isWordP(ubody[j])) {
            const hp: *Header = @ptrFromInt(ubody[j]);
            try forth.print("     Call {s}", .{hp.name});
        }
        try forth.print("\n", .{});
    }
}

pub fn defineInspect(forth: *Forth) !void {
    _ = try forth.definePrimitiveDesc("stacktrace", " -- : Dump the current forth stacktrace", &wordStackTrace, false);
    _ = try forth.definePrimitiveDesc("dump", "addr len -- : Dump an arbitrary area of memory", &wordDump, false);
    _ = try forth.definePrimitiveDesc("tdump", "addr len -- : Dump an arbitrary area of memory as text", &wordTDump, false);

    _ = try forth.definePrimitiveDesc("?stack", " -- :Print the stack.", &wordStack, false);
    _ = try forth.definePrimitiveDesc("?", " -- :Print description of word.", &wordDesc, false);
    _ = try forth.definePrimitiveDesc("??", " -- :Print the dictionary.", &wordDictionary, false);
    _ = try forth.definePrimitiveDesc("???", " -- :Print dictionary words that begin with...", &wordDictionaryFilter, false);

    _ = try forth.definePrimitiveDesc("?word", " -- :Print details of word.", &wordDumpWord, false);
    _ = try forth.definePrimitiveDesc("?words", " -- :Print details all the words.", &wordDescAll, false);
}
