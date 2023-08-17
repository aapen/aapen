const std = @import("std");
const Allocator = std.mem.Allocator;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

pub fn parseString(token: []const u8) ![]const u8 {
    if (token[0] != '"') {
        return ForthError.ParseError;
    }
    const l = token.len - 1;
    return token[1..l];
}

pub fn isComment(token: []const u8) bool {
    return token[0] == '(';
}

pub fn parseComment(token: []const u8) ![]const u8 {
    if (!isComment(token)) {
        return ForthError.ParseError;
    }
    const l = token.len - 1;
    return token[1..l];
}

pub fn parseNumber(token: []const u8, base: u64) !u64 {
    if (token.len <= 0) {
        return ForthError.ParseError;
    }

    if (token[0] == '\\') {
        return token[1];
    }

    if (token.len >= 3 and token[0] == '0' and token[1] == 'x') {
        var sNumber = token[2..];
        const uValue = std.fmt.parseInt(u64, sNumber, 16) catch {
            return ForthError.ParseError;
        };
        return uValue;
    }

    if (token.len >= 3 and token[0] == '0' and token[1] == '#') {
        var sNumber = token[2..];
        const iValue = std.fmt.parseInt(i64, sNumber, 10) catch {
            return ForthError.ParseError;
        };
        return @bitCast(iValue);
    }

    var iValue = std.fmt.parseInt(i64, token, @intCast(base)) catch {
        var fValue = std.fmt.parseFloat(f64, token) catch {
            return ForthError.ParseError;
        };
        return @bitCast(fValue);
    };
    return @bitCast(iValue);
}

pub const ForthTokenIterator = struct {
    buffer: []const u8 = undefined,
    index: usize = 0,

    pub fn init(buffer: []const u8) ForthTokenIterator {
        return .{ .buffer = buffer, .index = 0 };
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
            while (end < self.buffer.len and self.buffer[end] != '"') : (end += 1) {}
            if (end < self.buffer.len) {
                end += 1;
            }
        } else if (self.buffer[start] == '(') {
            end += 1;
            while (end < self.buffer.len and self.buffer[end] != ')') : (end += 1) {}
            if (end < self.buffer.len) {
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

//pub fn main() !void {
//    const assert = std.debug.assert;
//
//    var i = try parseNumber("123");
//    assert(i == 123);
//
//    i = try parseNumber("0xff");
//    assert(i == 255);
//
//    i = try parseNumber("1.00");
//    var f: f64 = @bitCast(i);
//    assert(std.math.approxEqAbs(f64, f, 1.00, 0.0001));
//
//    i = try parseNumber("\\X");
//    assert(i == 'X');
//}
//
//pub fn main2() !void {
//    const print = std.debug.print;
//    var s = "hello out there a string \"foo bar baz\" and an empty string \"\" the end";
//    var words = ForthTokenIterator.init(s);
//    var word = words.next();
//    while (word != null) : (word = words.next()) {
//        print("in loop\n", .{});
//        if (word) |w| {
//            print("WORD: [{s}]\n", .{w});
//        }
//    }
//}
//
//pub fn main3() !void {
//    const print = std.debug.print;
//    const string = @import("string.zig");
//
//    var line: [500]u8 = undefined;
//    var s = "line buffer hello out there a string \"foo bar baz\" and an empty string \"\" the end   ";
//
//    var i: usize = 0;
//    for(s) |ch| {
//      line[i] = ch;
//      i += 1;
//    }
//    line[i] = 0;
//
//
//    print("string: {s}\n", .{line});
//    var l: usize = try string.chIndex(0, &line);
//
//    var words = ForthTokenIterator.init(line[0..l]);
//
//   var word = words.next();
//    while (word != null) : (word = words.next()) {
//        print("in loop\n", .{});
//        if (word) |w| {
//            print("WORD: [{s}]\n", .{w});
//        }
//    }
//}
//
////const print = std.debug.print;
////
////pub fn main() !void {
////    var s = "hello out there a string \"foo bar baz\" and an empty string \"\" the end";
////    var words = ForthTokenIterator{};
////    try ForthTokenIterator.init(&words, s);
////
////    var word = words.next();
////    while (word != null) : (word = words.next()) {
////        print("in loop\n", .{});
////        if (word) |w| {
////            print("WORD: [{s}]\n", .{w});
////        }
////    }
////}
