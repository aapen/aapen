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

/// addr len --
pub fn wordDump(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const len = try forth.stack.pop();
    //const word_len = len / @sizeOf(u64);

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
    return 0;
}

/// --
pub fn wordStack(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    for (forth.stack.items()) |item| {
        try forth.print("{}\n", .{item});
    }
    return 0;
}

/// --
pub fn wordDictionary(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    try listDictionary(forth, "");
    return 0;
}

/// --
pub fn wordDictionaryFilter(forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
    const pat = try forth.readWord();
    try listDictionary(forth, pat);
    return 0;
}

fn listDictionary(forth: *Forth, pat: []const u8) ForthError!void {
    var e = forth.lastWord;
    var i: usize = 0;
    while (e) |entry| {
        if (std.mem.startsWith(u8, entry.name, pat)) {
            const immed = if (entry.immediate == 0) " " else "^";
            i += 1;
            var sep: u8 = if ((i % 4) == 0) '\n' else '\t';
            try forth.print("{s} {s: <25}{c}", .{ immed, entry.name, sep });
        }
        e = entry.previous;
    }
    try forth.print("\n", .{});
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

pub fn defineInspect(forth: *Forth) !void {
    _ = try forth.definePrimitiveDesc("dump", "addr len -- : Dump an arbitrary area of memory", &wordDump, 0);

    _ = try forth.definePrimitiveDesc("?stack", " -- :Print the stack.", &wordStack, 0);
    _ = try forth.definePrimitiveDesc("?", " -- :Print description of word.", &wordDesc, 0);
    _ = try forth.definePrimitiveDesc("??", " -- :Print the dictionary.", &wordDictionary, 0);
    _ = try forth.definePrimitiveDesc("???", " -- :Print dictionary words that begin with...", &wordDictionaryFilter, 0);

    _ = try forth.definePrimitiveDesc("?word", " -- :Print details of word.", &wordDumpWord, 0);
}
