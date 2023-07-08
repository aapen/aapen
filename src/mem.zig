const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = Allocator.Error;

first_available: *u64,
last_available: *u64,

pub const HeapAllocator = struct {
    first_available: *u64,
    last_available: *u64,

    pub fn allocator(self: *HeapAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *HeapAllocator = @ptrCast(@alignCast(ctx));
        _ = self;
        _ = len;
        _ = ptr_align;
        _ = ret_addr;

        return null;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *HeapAllocator = @ptrCast(@alignCast(ctx));
        _ = self;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *HeapAllocator = @ptrCast(@alignCast(ctx));
        _ = self;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
    }
};
