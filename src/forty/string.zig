const std = @import("std");
const ForthError = @import("errors.zig").ForthError;

const Allocator = std.mem.Allocator;

pub const MaxLineLen = 256;
pub const LineBuffer = [MaxLineLen:0]u8;

pub fn newline(ch: u8) bool {
    return ch == '\r' or ch == '\n';
}

// Return true if the two (possibly zero terminated) slices are equal.
pub fn same(a: []const u8, b: []const u8) bool {
    const alen = chIndex(0, a) catch a.len;
    const blen = chIndex(0, b) catch b.len;

    //std.debug.print("same: {s} {s} {} {}\n", .{a, b, alen, blen});

    if (alen != blen) {
        return false;
    }

    return std.mem.eql(u8, a[0..alen], b[0..blen]);
}

// Return true if the two zero terminated strings are equal.
pub fn streql(a: [*:0]const u8, b: [*:0]const u8) bool {
    const alen = strlen(a);
    const blen = strlen(b);

    if (alen != blen) {
        return false;
    }

    for (0..alen) |i| {
        if (a[i] != b[i]) {
            return false;
        }
    }
    return true;
}

pub fn strlen(s: [*:0]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) {
        i += 1;
    }
    return i;
}

pub fn chIndex(ch: u8, s: []const u8) !usize {
    for (0..s.len) |i| {
        if (s[i] == ch) {
            return i;
        }
    }
    return ForthError.BadOperation;
}

pub fn copyTo(dst: [:0]u8, src: []const u8) void {
    clear(dst);
    const l = @min(dst.len - 1, src.len);
    var i: usize = 0;
    while (i < l) {
        if (src[i] == 0) {
            break;
        }
        dst[i] = src[i];
        i += 1;
    }
    dst[i] = 0;
}

pub fn dupCString(allocator: Allocator, src: [*:0]const u8) ![*]u8 {
    const len = std.mem.indexOfSentinel(u8, 0, src);
    const result = try allocator.alloc(u8, len);
    for (0..len) |i| {
        result[i] = src[i];
    }
    //result[len] = 0;
    return result.ptr;
}

pub fn asSlice(s: [*]u8) []u8 {
    var l: usize = 0;
    while (s[l] != 0) {
        l += 1;
    }
    return s[0..l];
}

pub fn clear(s: [:0]u8) void {
    @memset(s, 0);
}

pub fn u64ToChars(i: u64) [8]u8 {
    var result: [8]u8 = undefined;

    var j = i;
    for (0..8) |iChar| {
        const ch: u8 = @truncate(j);
        result[iChar] = if ((ch >= ' ') and (ch <= '~')) ch else '.';
        j = j >> 8;
    }
    return result;
}

test "duplicating a slice" {
    //const print = std.debug.print;
    const assert = std.debug.assert;
    const allocator = std.testing.allocator;

    const s = "abcdef";
    const p = try dupCString(allocator, s);
    assert(p[0] == 'a');

    allocator.free(p);
}
