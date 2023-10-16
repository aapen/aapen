const std = @import("std");
const string = @import("string.zig");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const WordFunction = @import("forth.zig").WordFunction;

pub const WordNameLen = 20;

pub const Header = struct {
    func: WordFunction = undefined,
    name: []const u8 = undefined,
    desc: []const u8 = undefined,
    previous: ?*Header = null,
    len: u32 = 0,
    immediate: bool = false,

    pub fn init(name: []const u8, desc: []const u8, func: WordFunction, immediate: bool, previous: ?*Header) Header {
        var this = Header{
            .name = name,
            .func = func,
            .desc = desc,
            .immediate = immediate,
            .previous = previous,
            .len = 0,
        };
        return this;
    }

    pub fn bodyOfType(this: *Header, comptime T: type) T {
        const p = this.bodyPointer();
        return @alignCast(@ptrCast(alignByType(p, T)));
    }

    pub fn bodyPointer(this: *Header) [*]u8 {
        const i: usize = @intFromPtr(this) + @sizeOf(Header);
        return @ptrFromInt(i);
    }

    pub fn bodyLen(this: *Header) u64 {
        return this.len - @sizeOf(Header);
    }
};

pub fn alignByType(p: [*]u8, comptime T: type) [*]u8 {
    return alignBy(p, @alignOf(T));
}

pub fn alignBy(p: [*]u8, alignment: usize) [*]u8 {
    const i: usize = @intFromPtr(p);
    return @ptrFromInt(intAlignBy(i, alignment));
}

pub fn intAlignBy(i: u64, alignment: usize) u64 {
    var words = (i + alignment - 1) / alignment;
    return words * alignment;
}

pub const Memory = struct {
    // The data.
    p: [*]u8,

    // Total length of the data (in # bytes).
    length: usize,

    // Next free memory space.
    current: [*]u8,

    pub fn init(p: [*]u8, length: usize) Memory {
        return Memory{
            .p = p,
            .length = length,
            .current = p,
        };
    }

    inline fn bytesUsed(this: *Memory) usize {
        return @intFromPtr(this.current) - @intFromPtr(this.p);
    }

    fn checkForSpace(this: *Memory, n: usize) !usize {
        const newUsed = this.bytesUsed() + n;
        if (newUsed >= this.length) {
            return ForthError.OutOfMemory;
        }
        return newUsed;
    }

    // Allocate some memory, ensuring that the start is aligned.
    // Returns a pointer to the number in memory.
    pub fn allocate(this: *Memory, alignment: usize, n: usize) ![*]u8 {
        _ = try this.checkForSpace(n);
        this.current = alignBy(this.current, alignment);
        const result = this.current;
        this.current += n;
        return result;
    }

    // Add a string to memory, move the current pointer.
    // Note that a string is stored as u64 count of the number of words
    // (including the count) followed by the zero terminated string.
    // Returns a pointer to the string.
    pub fn addString(this: *Memory, s: []const u8) ![*]u8 {
        const len_words = intAlignBy(s.len, @alignOf(u64)) / @sizeOf(u64) + 1;

        _ = try this.checkForSpace(len_words * @sizeOf(u64));

        const result = try this.addNumber(len_words);
        var current = try this.rawAddBytes(@constCast(@ptrCast(s.ptr)), s.len);
        current[0] = 0;
        current += 1;
        this.current = current;
        return result;
    }

    // Add a u64 to the memory, aligning it corrects. Moves the current pointer.
    // Returns a pointer to the number in memory.
    pub fn addNumber(this: *Memory, v: u64) ![*]u8 {
        return this.addBytes(@constCast(@ptrCast(&v)), @alignOf(u64), @sizeOf(u64));
    }

    // Copy n bytes into the current location of memory with the given alignment.
    // Moves the current pointer past the newly copied data and returns the
    // beginning address of the newly copied data.
    pub fn addBytes(this: *Memory, src: [*]u8, alignment: usize, n: usize) ![*]u8 {
        this.current = alignBy(this.current, alignment);
        const result = this.current;
        this.current = try this.rawAddBytes(src, n);
        return result;
    }

    // Copy bytes into the current location of memory but does
    // not move the current index. Returns a pointer to the next (unaligned)
    // spot in memory after the new data.
    fn rawAddBytes(this: *Memory, src: [*]u8, n: usize) ![*]u8 {
        _ = try this.checkForSpace(n);
        var current = this.current;
        for (0..n) |i| {
            current[i] = src[i];
        }
        return current + n;
    }
};
