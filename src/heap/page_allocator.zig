const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.page_allocator);

const memory = @import("../memory.zig");

pub const vtable = Allocator.VTable{
    .alloc = alloc,
    .resize = resize,
    .free = free,
};

var allocator: Allocator = undefined;

pub fn init(start: u64, end: u64) Allocator {
    memory.init(start, end);

    allocator = .{
        .ptr = &.{},
        .vtable = &vtable,
    };

    return allocator;
}

fn alloc(_: *anyopaque, n: usize, log2_align: u8, ra: usize) ?[*]u8 {
    _ = ra;
    _ = log2_align;

    const aligned_len = std.mem.alignForward(usize, n, std.mem.page_size);

    if (memory.get(aligned_len)) |ptr| {
        return @ptrFromInt(ptr);
    } else |_| {
        return null;
    }
}

fn resize(_: *anyopaque, buf_unaligned: []u8, log2_buf_align: u8, new_size: usize, ra: usize) bool {
    _ = ra;
    _ = log2_buf_align;
    // Our freelist allocator cannot resize without relocating
    // For a shrinking operation, we just pretend we resized the
    // buffer.
    return if (new_size <= buf_unaligned.len) true else false;
}

fn free(_: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
    _ = ret_addr;
    _ = buf_align;
    const aligned_len = std.mem.alignForward(usize, buf.len, std.mem.page_size);
    if (memory.free(@intFromPtr(buf.ptr), aligned_len)) {
        return;
    } else |err| {
        log.err("memory.free({x:0>8}, {x:0>8}): {any}", .{ @intFromPtr(buf.ptr), aligned_len, err });
    }
}
