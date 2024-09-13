const std = @import("std");
const Allocator = std.mem.Allocator;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

pub fn parseQuoted(token: []const u8) ![]const u8 {
    if (token[0] == '\'') {
        const l = token.len;
        return token[1..l];
    }
    return ForthError.ParseError;
}

pub fn parseString(token: []const u8) ![]const u8 {
    var l: usize = 0;

    if (token[0] == '"') {
        l = token.len - 1;
    } else if (token[0] == ':') {
        l = token.len;
    } else {
        return ForthError.ParseError;
    }
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
        const sNumber = token[2..];
        const uValue = std.fmt.parseInt(u64, sNumber, 16) catch {
            return ForthError.ParseError;
        };
        return uValue;
    }

    if (token.len >= 3 and token[0] == '0' and token[1] == '#') {
        const sNumber = token[2..];
        const iValue = std.fmt.parseInt(i64, sNumber, 10) catch {
            return ForthError.ParseError;
        };
        return @bitCast(iValue);
    }

    const iValue = std.fmt.parseInt(i64, token, @intCast(base)) catch {
        const fValue = std.fmt.parseFloat(f64, token) catch {
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
        const result = allocator.create(ForthTokenIterator);
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
