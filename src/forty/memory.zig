const std = @import("std");
const string = @import("string.zig");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const WordFunction = @import("forth.zig").WordFunction;

pub const Header = struct {
    name: [20:0]u8 = undefined,
    func: WordFunction = undefined,
    immediate: bool = false,
    previous: ?*Header = null,

    pub fn init(name: []const u8, func: WordFunction, immediate: bool, previous: ?*Header) Header {
        var this = Header{
            .name = undefined,
            .func = func,
            .immediate = immediate,
            .previous = previous,
        };
        string.copyTo(&this.name, name);
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
    p: [*]u8, // The data
    length: usize, // Length of the data.
    current: [*]u8, // Next Free memory space.
    alignment: usize = @alignOf(*void),

    pub fn init(p: [*]u8, length: usize) Memory {
        return Memory{
            .p = p,
            .length = length,
            .current = p,
        };
    }

    // Add a string to memory, move the current pointer.
    // Note that a string is stored as u64 count of the number of words
    // (including the count) followed by the zero terminated string.
    // Returns a pointer to the number in memory.
    pub fn addString(this: *Memory, s: []const u8) [*]u8 {
        const len_words = intAlignBy(s.len, @alignOf(u64)) / @sizeOf(u64) + 1;

        const result = this.addNumber(len_words);
        var current = this.rawAddBytes(@constCast(@ptrCast(s.ptr)), s.len);
        current[0] = 0;
        current += 1;
        this.current = current;
        return result;
    }

    // Add a u64 to the memory, aligning it corrects. Moves the current pointer.
    // Returns a pointer to the number in memory.
    pub fn addNumber(this: *Memory, v: u64) [*]u8 {
        return this.addBytes(@constCast(@ptrCast(&v)), @alignOf(u64), @sizeOf(u64));
    }

    // Copy n bytes into the current location of memory with the given alignment.
    // Moves the current pointer past the newly copied data and returns the
    // beginning address of the newly copied data.
    pub fn addBytes(this: *Memory, src: [*]u8, alignment: usize, n: usize) [*]u8 {
        //print("addBytes: align {} size {}\n", .{alignment, n});
        this.current = alignBy(this.current, alignment);
        const result = this.current;
        this.current = this.rawAddBytes(src, n);
        return result;
    }

    // Copy bytes into the current location of memory but does
    // not move the current index. Returns a pointer to the next (unaligned)
    // spot in memory after the new data.
    fn rawAddBytes(this: *Memory, src: [*]u8, n: usize) [*]u8 {
        //print("raw add bytes: n: {}\n", .{n});
        var current = this.current;
        for (0..n) |i| {
            current[i] = src[i];
        }
        return current + n;
    }
};
