const std = @import("std");

pub const cache_line_size = 64;

extern fn flushDCacheRange(start: u64, end: u64) void;
extern fn invalidateDCacheRange(start: u64, end: u64) void;

// pub fn flushDCache(start: *u64, size: usize) void {
//     var range_start: u64 = @intFromPtr(start);
//     var range_end: u64 = start + size;
//     range_end = std.mem.alignForward(u64, range_end, cache_line_size);

//     flushDCacheRange(range_start, range_end);
// }

pub fn flushDCache(comptime T: type, buffer: []T) void {
    var range_start: u64 = @intFromPtr(&buffer);
    var range_end: u64 = range_start + (buffer.len * @sizeOf(T));
    range_end = std.mem.alignForward(u64, range_end, cache_line_size);

    flushDCacheRange(range_start, range_end);
}

pub fn invalidateDCache(comptime T: type, buffer: []T) void {
    var range_start: u64 = @intFromPtr(&buffer);
    var range_end: u64 = range_start + (buffer.len * @sizeOf(T));
    range_end = std.mem.alignForward(u64, range_end, cache_line_size);

    invalidateDCacheRange(range_start, range_end);
}
