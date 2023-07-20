const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = Allocator.Error;
const regions = @import("memory/region.zig");
pub const Region = regions.Region;

pub const Heap = struct {
    page_size: u64,
    memory: Region,

    pub fn allocator(self: *Heap) HeapAllocator {
        return HeapAllocator{
            .memory = self.memory,
            .first_available = @ptrFromInt(self.memory.base),
            .last_available = @ptrFromInt(self.memory.end),
        };
    }

    /// WARNINGS
    ///
    /// This is not thread safe.
    ///
    /// It is riddled with race conditions.
    ///
    /// It has bad hygeine
    ///
    /// When memory is exhausted, it will fail forever
    ///
    pub const HeapAllocator = struct {
        memory: Region,
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

        /// Attempt to allocate exactly `len` bytes aligned to `1 << ptr_align`.
        ///
        /// `ret_addr` is optionally provided as the first return address of the
        /// allocation call stack. If the value is `0` it means no return address
        /// has been provided.
        fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
            _ = ret_addr;

            const self: *HeapAllocator = @ptrCast(@alignCast(ctx));

            if (len > (@intFromPtr(self.last_available) - @intFromPtr(self.first_available)))
                return null;

            const aligned_start = std.mem.alignForward(usize, @intFromPtr(self.first_available), @as(usize, 1) << @as(Allocator.Log2Align, @intCast(ptr_align)));
            const end = aligned_start + len;
            const aligned_end = std.mem.alignForward(usize, end, 4);

            self.first_available = @ptrFromInt(aligned_end);

            return @ptrFromInt(aligned_start);
        }

        /// Attempt to expand or shrink memory in place. `buf.len` must equal the
        /// length requested from the most recent successful call to `alloc` or
        /// `resize`. `buf_align` must equal the same value that was passed as the
        /// `ptr_align` parameter to the original `alloc` call.
        ///
        /// A result of `true` indicates the resize was successful and the
        /// allocation now has the same address but a size of `new_len`. `false`
        /// indicates the resize could not be completed without moving the
        /// allocation to a different address.
        ///
        /// `new_len` must be greater than zero.
        ///
        /// `ret_addr` is optionally provided as the first return address of the
        /// allocation call stack. If the value is `0` it means no return address
        /// has been provided.
        fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
            const self: *HeapAllocator = @ptrCast(@alignCast(ctx));
            _ = self;
            _ = buf;
            _ = buf_align;
            _ = new_len;
            _ = ret_addr;
            return false;
        }

        /// Free and invalidate a buffer.
        ///
        /// `buf.len` must equal the most recent length returned by `alloc` or
        /// given to a successful `resize` call.
        ///
        /// `buf_align` must equal the same value that was passed as the
        /// `ptr_align` parameter to the original `alloc` call.
        ///
        /// `ret_addr` is optionally provided as the first return address of the
        /// allocation call stack. If the value is `0` it means no return address
        /// has been provided.
        fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
            const self: *HeapAllocator = @ptrCast(@alignCast(ctx));
            _ = self;
            _ = buf;
            _ = buf_align;
            _ = ret_addr;
        }
    };
};
