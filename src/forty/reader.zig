const std = @import("std");
const errors = @import("errors.zig");

const FReader = std.fs.File.Reader;
const FWriter = std.fs.File.Writer;
// const print = std.debug.print;

pub const max_line_len: u16 = 200;

// pub const ConsoleReader = struct {
//     in: FReader,
//     out: FWriter,
//     prompt: []const u8,
//     buffer: [max_line_len:0]u8,

//     pub fn init(r: FReader, w: FWriter, msg: []const u8) ConsoleReader {
//         var buf: [max_line_len:0]u8 = undefined;
//         return ConsoleReader{
//             .in = r,
//             .out = w,
//             .prompt = msg,
//             .buffer = buf,
//         };
//     }

//     pub fn readline(self: *ConsoleReader) ![max_line_len:0]u8 {
//         @memset(&self.buffer, 0);
//         var fbs = std.io.fixedBufferStream(&self.buffer);
//         var fbs_writer = fbs.writer();
//         try self.out.print(">> ", .{});
//         _ = try self.in.streamUntilDelimiter(fbs_writer, '\n', max_line_len - 1);
//         try fbs_writer.writeByte('\n');
//         return self.buffer;
//     }
// };

pub const ForthReader = struct {
    line: [max_line_len:0]u8,
    // line_reader: *ConsoleReader,
    ichar: u32,

    pub fn init() ForthReader {
        var result = ForthReader{
            // .line = undefined,
            // .line_reader = lr,
            .ichar = 0,
        };
        result.line[0] = 0;
        return result;
    }

    pub fn getc(self: *ForthReader) !u8 {
        if (self.line[self.ichar] == 0) {
            // self.line = try self.line_reader.readline();
            std.mem.copy(u8, &self.line, "21 01 + . cr");
            self.ichar = 0;
        }
        const result = self.line[self.ichar];
        self.ichar += 1;
        return result;
    }

    pub fn _getWord(self: *ForthReader, buf: []u8) ![]u8 {
        //print("getword \n", .{});
        //@memset(buf, 0);

        //print("skipping ws \n", .{});
        var ch = try self.getc();
        while (std.ascii.isWhitespace(ch)) {
            ch = try self.getc();
        }

        buf[0] = ch;
        var i: u32 = 1;

        ch = try self.getc();
        //print("gathering word {c}\n", .{ch});
        while (!std.ascii.isWhitespace(ch)) {
            //print("gathering word {c}\n", .{ch});
            buf[i] = ch;
            i += 1;
            ch = try self.getc();
        }
        //print("returning buf {}  {any}\n", .{i, buf});
        return buf[0..i];
    }

    pub fn getWord(self: *ForthReader, buf: []u8) ![]u8 {
        return _getWord(self, buf) catch |err| {
            if (err == error.EndOfStream) {
                return errors.ForthError.EOF;
            }
            // print("Error reading word: {any}\n", .{err});
            return errors.ForthError.WordReadError;
        };
    }
};
