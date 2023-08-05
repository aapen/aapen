const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ForthTokenIterator = struct {
    buffer: []const u8 = undefined,
    index: usize = 0,

    pub fn init(buffer: []const u8) ForthTokenIterator {
        return .{.buffer = buffer, .index = 0};
    }
    pub fn create(allocator: *Allocator, buffer: []const u8) *ForthTokenIterator {
        var result = allocator.create(ForthTokenIterator);
        setup(result, buffer);
        return result;
    }

    pub fn setup(this: *ForthTokenIterator, buffer: []const u8) !void {
        this.buffer = buffer;
        this.index = 0;
    }

    /// Returns a slice of the current token, or null if tokenization is
    /// complete, and advances to the next token.
    pub fn next(self: *ForthTokenIterator) ?[]const u8 {
        const result = self.peek() orelse return null;
        self.index += result.len;
        return result;
    }

    /// Returns a slice of the current token, or null if tokenization is
    /// complete. Does not advance to the next token.
    pub fn peek(self: *ForthTokenIterator) ?[]const u8 {
        // move to beginning of token
        while (self.index < self.buffer.len and self.isWhitespace(self.index)) {
            self.index += 1;
        }
        //print("past the whitespace, index: {}\n", .{self.index});

        const start = self.index;
        if (start == self.buffer.len) {
            return null;
        }

        // move to end of token

        var end = start;

        if (self.buffer[start] == '"') {
            end += 1;
            //print("dealing with quoted string, index: {}\n", .{self.index});
            while (end < self.buffer.len and self.buffer[end] != '"') : (end += 1) {}
            if (end < self.buffer.len ) {
                end += 1;
            }
        } else {
            while (end < self.buffer.len and !self.isWhitespace(end)) : (end += 1) {
                //print("dealing with reg word, index: {}\n", .{end});
            }
        }

        //print("returning, start: {} end: {}\n", .{start, end});
        return self.buffer[start..end];
    }

    /// Resets the iterator to the initial token.
    pub fn reset(self: *ForthTokenIterator) void {
        self.index = 0;
    }

    fn isWhitespace(self: ForthTokenIterator, index: usize) bool {
        return std.ascii.isWhitespace(self.buffer[index]);
    }
};

//const print = std.debug.print;
//
//pub fn main() !void {
//    var s = "hello out there a string \"foo bar baz\" and an empty string \"\" the end";
//    var words = ForthTokenIterator{};
//    try ForthTokenIterator.init(&words, s);
//
//    var word = words.next();
//    while (word != null) : (word = words.next()) {
//        print("in loop\n", .{});
//        if (word) |w| {
//            print("WORD: [{s}]\n", .{w});
//        }
//    }
//}
