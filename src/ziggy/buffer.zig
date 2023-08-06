const std = @import("std");
const Allocator = std.mem.Allocator;
const Readline = @import("../readline.zig");
const SplitIterator = std.mem.SplitIterator(u8, .any);

pub const BufferSource = struct {
    source: []const u8 = undefined,
    lines: *SplitIterator = undefined,

    pub fn init(self: *BufferSource, source: []const u8) void {
        self.source = source;
        self.lines.* = std.mem.splitAny(u8, source, "\n");
    }

    pub fn readLine(self: *BufferSource, prompt: []const u8, buffer: []u8) usize {
        _ = prompt;

        if (self.lines.next()) |next| {
            var idx: usize = 0;
            for (next) |c| {
                if (idx == buffer.len) {
                    buffer[idx - 1] = 0;
                    break;
                } else {
                    buffer[idx] = c;
                    idx += 1;
                }
            }
            return idx;
        } else {
            // null return from iterator means no more lines. that's
            // EOF to you and me.
            return 0;
        }
    }
};

fn readLineThunk(ctx: *anyopaque, prompt: []const u8, buffer: []u8) usize {
    var source: *BufferSource = @ptrCast(@alignCast(ctx));
    return source.readLine(prompt, buffer);
}

pub fn createReader(allocator: Allocator, source: *BufferSource) !*Readline {
    return Readline.init(allocator, source, readLineThunk);
}
