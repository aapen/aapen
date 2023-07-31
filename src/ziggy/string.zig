const std = @import("std");

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

pub fn clear(s: [:0]u8) void {
    @memset(s, 0);
}
