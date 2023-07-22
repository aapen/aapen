const std = @import("std");
const bsp = @import("bsp.zig");
const root = @import("root");

pub const Interpreter = struct {
    const Error = error{ SyntaxError, OverflowError, AlignmentError };
    const Writer = root.FrameBufferConsole.Writer;

    console: *root.FrameBufferConsole,
    writer: *Writer,

    const CommandType = enum {
        comment,
        peek,
        poke,
    };

    const Command = union(CommandType) {
        comment: bool,
        peek: u64,
        poke: struct { u64, u32 },
    };

    const Echo = struct {};

    pub fn execute(self: *Interpreter) !void {
        self.emitPrompt("READY.\n");

        var command = try self.readCommand();
        try self.runCommand(command);
    }

    fn readCommand(self: *Interpreter) !Command {
        var ch = self.getc();

        return switch (ch) {
            '@' => self.readPoke(),
            '?' => self.readPeek(),
            else => self.readComment(ch),
        };
    }

    fn readComment(self: *Interpreter, firstChar: u8) !Command {
        self.putc(firstChar);

        while (true) {
            var ch = self.getc();
            self.putc(ch);
            if (ch == '\n') {
                return Command{ .comment = true };
            }
        }
    }

    fn readPoke(self: *Interpreter) !Command {
        var addr = try self.readAddress();
        var value = try self.readValue();
        return Command{ .poke = .{ addr, value } };
    }

    fn readPeek(self: *Interpreter) !Command {
        var addr = try self.readAddress();
        return Command{ .peek = addr };
    }

    fn readHex(self: *Interpreter, comptime T: type, pr: []const u8) !T {
        self.emitPrompt(pr);

        var v: T = 0;
        while (true) {
            var ch = self.getc();
            if (isHexDigit(ch)) {
                v <<= 4;
                v |= hexdigit(ch);
                self.putc(ch);
            } else if (isBackspace(ch)) {
                v >>= 4;
                self.putc(ch);
            } else if (ch == ' ' or ch == '\n') {
                self.putc(ch);
                return v;
            }
        }
    }

    fn readAddress(self: *Interpreter) !u64 {
        return self.readHex(u64, "addr> ");
    }

    fn readValue(self: *Interpreter) !u32 {
        return self.readHex(u32, "value> ");
    }

    fn runCommand(self: *Interpreter, command: Command) !void {
        _ = self;
        switch (command) {
            Command.peek => |addr| {
                var v: u32 = try readAligned(u32, addr);

                try root.console.print("0x{x:0>8}: 0x{x:0>8}\n", .{ addr, v });
            },
            Command.poke => |poke| {
                try writeAligned(u32, poke[0], poke[1]);
                // try root.console.print("poke @ 0x{x:0>8} <- 0x{x:0>8}\n", .{ poke[0], poke[1] });
            },
            Command.comment => {},
        }
    }

    fn aligned(comptime T: type, addr: u64) bool {
        const alignment = @alignOf(T);
        const mask = alignment - 1;
        return addr & mask == 0;
    }

    fn readAligned(comptime T: type, addr: u64) !T {
        if (!aligned(T, addr)) {
            return Error.AlignmentError;
        }
        var a: *volatile T = @ptrFromInt(addr);
        return a.*;
    }

    fn writeAligned(comptime ValueType: type, addr: u64, value: ValueType) !void {
        if (!aligned(ValueType, addr)) {
            return Error.AlignmentError;
        }
        var a: *volatile ValueType = @ptrFromInt(addr);
        a.* = value;
    }

    fn emitPrompt(self: *Interpreter, prompt: []const u8) void {
        self.console.emit_string(prompt);
    }

    fn getc(self: *Interpreter) u8 {
        _ = self;
        var ch = bsp.io.receive();
        return if (ch == '\r') '\n' else ch;
    }

    fn putc(self: *Interpreter, ch: u8) void {
        bsp.io.send(ch);
        self.console.emit(ch);
    }
};

fn isBackspace(ch: u8) bool {
    return ch == 0x7f;
}

fn isHexDigit(ch: u8) bool {
    return ('0' <= ch and ch <= '9') or ('a' <= ch and ch <= 'f') or ('A' <= ch and ch <= 'F');
}

fn hexdigit(ch: u8) u8 {
    if ('0' <= ch and ch <= '9') {
        return ch - '0';
    } else if ('a' <= ch and ch <= 'f') {
        return ch - 'a' + 10;
    } else if ('A' <= ch and ch <= 'F') {
        return ch - 'A' + 10;
    } else {
        return 0;
    }
}
