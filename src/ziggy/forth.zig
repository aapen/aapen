const std = @import("std");
const Allocator = std.mem.Allocator;

const bsp = @import("../bsp.zig");
const fbcons = @import("../fbcons.zig");
const stack = @import("stack.zig");
const dict = @import("dictionary.zig");
const value = @import("value.zig");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

pub const init_f = @embedFile("init.f");

const Value = value.Value;
const ValueType = value.ValueType;

const DataStack = stack.Stack(Value);
const ReturnStack = stack.Stack(i32);

const ValueDictionary = dict.Dictionary(Value);

const WordFunction = *const fn (self: *Forth) ForthError!void;

pub const Forth = struct {
    const max_line_len = 256;

    allocator: Allocator = undefined,
    console: *fbcons.FrameBufferConsole,

    stack: DataStack = undefined,
    rstack: ReturnStack = undefined,
    dictionary: ValueDictionary = undefined,
    memory: [2000]Value = undefined,
    nextFree: i32 = 0,
    nexti: i32 = -999,
    composing: bool = false,
    line_buffer: [max_line_len:0]u8 = undefined,
    words: std.mem.TokenIterator(u8, std.mem.DelimiterType.any) = undefined,
    new_word_name: []const u8 = undefined,
    new_word_def: i32 = -888,

    pub fn init(self: *Forth, allocator: Allocator) !void {
        self.stack = DataStack.init(allocator);
        self.rstack = ReturnStack.init(allocator);
        self.dictionary = ValueDictionary.init(allocator);
    }

    pub fn print(self: *Forth, comptime fmt: []const u8, args: anytype) !void {
        try self.console.print(fmt, args);
    }

    pub fn writer(self: *Forth) fbcons.FrameBufferConsole.Writer {
        return self.console.writer();
    }

    pub fn evalFP(self: *Forth, v: Value) dict.ForthError!void {
        const fp: *fn (self: *Forth) void = v.fp;
        try fp(self);
    }

    pub fn addToDefinition(self: *Forth, v: Value) void {
        self.memory[@intCast(self.nextFree)] = v;
        self.nextFree += 1;
    }

    pub fn _evalValue(self: *Forth, v: Value) !void {
        switch (v) {
            .w => |name| {
                const assoc_value = try self.dictionary.get(name);
                try evalValue(self, assoc_value);
            },
            .fp => |p| {
                //var wordf = @intToPtr(WordFunction, p);
                var wordf: WordFunction = @ptrFromInt(p);
                try wordf(self);
            },
            .call => |address| {
                try inner(self, address);
            },
            else => |_| {
                try self.stack.push(v);
            },
        }
    }

    pub fn evalValue(self: *Forth, v: Value) ForthError!void {
        // try self.print("eval value {any}\n", .{v});
        switch (v) {
            .w => |name| {
                const entry = try self.dictionary.getEntry(name);
                // try self.print("word: {s} entry: {any}\n", .{ name, entry });
                if (entry.immediate) {
                    try _evalValue(self, entry.value);
                } else if (self.composing) {
                    self.addToDefinition(entry.value);
                } else {
                    try _evalValue(self, entry.value);
                }
            },
            .fp => |p| {
                if (self.composing) {
                    self.addToDefinition(v);
                } else {
                    var wordf: WordFunction = @ptrFromInt(p);
                    try wordf(self);
                }
            },
            .call => |address| {
                if (self.composing) {
                    self.addToDefinition(v);
                } else {
                    try inner(self, address);
                }
            },
            else => |_| {
                if (self.composing) {
                    self.addToDefinition(v);
                } else {
                    try self.stack.push(v);
                }
            },
        }
    }

    pub fn wordColon(self: *Forth) !void {
        // try self.print("colon:\n", .{});
        self.new_word_name = self.words.next() orelse return ForthError.WordReadError;
        // @memset(&self.newWordName, 0);
        // _ = try self.reader.getWord(&self.newWordName);
        self.composing = true;
        self.new_word_def = self.nextFree;
    }

    pub fn wordSemi(self: *Forth) !void {
        // try self.print("***semi:\n", .{});
        self.memory[@intCast(self.nextFree)] = Value{
            //.fp = @ptrToInt(&wordReturn),
            .fp = @intFromPtr(&wordReturn),
        };
        self.nextFree += 1;
        // try self.print("semi: {s} {any}\n", .{ self.new_word_name, self.new_word_def });
        try self.defineSecondary(self.new_word_name, self.new_word_def);
        self.composing = false;
        // @memset(&self.new_word_name, 0);
        self.new_word_def = -888;
    }

    // a -- ()
    pub fn wordEmit(self: *Forth) !void {
        var s = &self.stack;
        const a = try s.pop();
        var ch = try a.asChar();
        self.console.emit(ch);
    }

    pub fn wordCr(self: *Forth) ForthError!void {
        self.putc(0x0a);
    }

    pub fn wordClearScreen(self: *Forth) !void {
        self.putc(0x0c);
    }

    fn definePrimitive(self: *Forth, name: []const u8, fp: WordFunction, immediate: bool) !void {
        // try self.print("define word {s} -> {*}\n", .{ name, fp });
        try self.dictionary.put(name, Value{ .fp = @intFromPtr(fp) }, immediate);
    }

    fn defineSecondary(self: *Forth, name: []const u8, address: i32) !void {
        // try self.print("define secondary {s} {}\n", .{ name, address });
        try self.dictionary.put(name, Value{ .call = address }, false);
    }

    fn emitPrompt(self: *Forth, prompt: []const u8) void {
        self.console.emitString(prompt);
    }

    fn readline(self: *Forth, buffer: []u8) !usize {
        var i: usize = 0;
        var ch: u8 = 0;

        while (i < (buffer.len - 1) and !newline(ch)) {
            ch = self.getc();
            self.putc(ch);

            switch (ch) {
                0x7f => if (i > 0) {
                    i -= 1;
                },
                else => {
                    buffer[i] = ch;
                    i += 1;
                },
            }
            buffer[i] = 0;
        }
        return i;
    }

    fn getc(self: *Forth) u8 {
        _ = self;
        var ch = bsp.io.receive();
        return if (ch == '\r') '\n' else ch;
    }

    fn putc(self: *Forth, ch: u8) void {
        bsp.io.send(ch);
        self.console.emit(ch);
    }

    pub fn repl(self: *Forth) !void {
        // outer loop, one line at a time.
        while (true) {
            self.emitPrompt("READY.\n");
            var line_len: usize = self.readline(&self.line_buffer) catch 0;

            self.words = std.mem.tokenizeAny(u8, self.line_buffer[0..line_len], " \t\n\r");

            // inner loop, one word at a time.
            var word = self.words.next();
            while (word != null) : (word = self.words.next()) {
                if (word) |w| {
                    var v = Value.fromString(w) catch |err| {
                        try self.print("Parse error({s}): {}\n", .{ w, err });
                        continue;
                    };
                    self.evalValue(v) catch |err| {
                        try self.print("error: {any}\n", .{err});
                    };
                }
            }
        }
    }

    /// Evaluate a (potentially large) buffer of code. Mainly used for
    /// loading init.f
    pub fn evalBuffer(self: *Forth, buffer: []const u8) !void {
        self.words = std.mem.tokenizeAny(u8, buffer, " \t\n\r");

        // inner loop, one word at a time.
        var word = self.words.next();
        while (word != null) : (word = self.words.next()) {
            if (word) |w| {
                var v = Value.fromString(w) catch |err| {
                    try self.print("Parse error({s}): {}\n", .{ w, err });
                    continue;
                };
                self.evalValue(v) catch |err| {
                    try self.print("error: {any}\n", .{err});
                };
            }
        }

        self.words = undefined;
    }

    pub fn define_core(self: *Forth) !void {
        // Screen control
        try self.definePrimitive("emit", &Forth.wordEmit, false);
        try self.definePrimitive("cls", &Forth.wordClearScreen, false);

        // Secondary definition words.
        try self.definePrimitive(":", &Forth.wordColon, false);
        try self.definePrimitive(";", &Forth.wordSemi, true);

        // Debug and inspection words.
        try self.definePrimitive("stack", &wordStack, false);
        try self.definePrimitive("?", &wordStack, false);
        try self.definePrimitive("??", &wordDictionary, false);
        try self.definePrimitive("rstack", &wordRStack, false);
        try self.definePrimitive("info", &wordInfo, true);
        try self.definePrimitive("ip", &wordNext, false);
        try self.definePrimitive("value-size", &wordValueSize, false);

        // Basic Forth words.
        try self.definePrimitive("dup", &wordDup, false);
        try self.definePrimitive("swap", &wordSwap, false);
        try self.definePrimitive("drop", &wordDrop, false);
        try self.definePrimitive("hello", &wordHello, false);
        try self.definePrimitive(".", &wordDot, false);
        try self.definePrimitive("h.", &wordHexDot, false);
        try self.definePrimitive("cr", &Forth.wordCr, false);
        try self.definePrimitive("+", &wordAdd, false);
        try self.definePrimitive("!i", &wordStoreI32, false);
        try self.definePrimitive("@i", &wordLoadI32, false);
    }
};

pub fn wordHello(self: *Forth) !void {
    try self.print("hello world\n", .{});
}

pub fn wordDot(self: *Forth) !void {
    var v: Value = try self.stack.pop();
    try v.pr(self, false);
}

pub fn wordHexDot(self: *Forth) !void {
    var v: Value = try self.stack.pop();
    try v.pr(self, true);
}

pub fn wordStack(self: *Forth) !void {
    for (self.stack.items()) |item| {
        try item.pr(self, false);
        try self.print("\n", .{});
    }
}

pub fn wordRStack(self: *Forth) !void {
    for (self.rstack.items()) |item| {
        try self.print("{}\n", .{item});
    }
}

pub fn wordDup(self: *Forth) !void {
    var s = &self.stack;
    const a = try s.pop();
    try s.push(a);
    try s.push(a);
}

pub fn wordSwap(self: *Forth) !void {
    var s = &self.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(a);
    try s.push(b);
}

pub fn wordDrop(self: *Forth) !void {
    var s = &self.stack;
    _ = try s.pop();
}

pub fn wordAdd(self: *Forth) !void {
    var s = &self.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(try a.add(&b));
}

pub fn wordReturn(self: *Forth) ForthError!void {
    self.nexti = -999;
}

pub fn wordDictionary(self: *Forth) ForthError!void {
    try self.dictionary.pr(self);
}

pub fn wordInfo(self: *Forth) ForthError!void {
    try self.print("nexti: {}\n", .{self.nexti});
    try self.print("composing: {}\n", .{self.composing});
    try self.print("new word: {s}\n", .{self.new_word_name});
    try self.print("new word def: {}\n", .{self.new_word_def});
}

pub fn wordNext(self: *Forth) ForthError!void {
    var nexti_address: usize = @intFromPtr(&self.nexti);
    var v = Value{ .addr = nexti_address };
    try self.stack.push(v);
}

pub fn wordLoadI32(self: *Forth) !void {
    const addressValue = try self.stack.pop();
    if (addressValue != ValueType.addr) {
        return ForthError.BadOperation;
    }
    const p: *i32 = @ptrFromInt(addressValue.addr);
    const v = Value{ .i = p.* };
    try self.stack.push(v);
}

pub fn wordStoreI32(self: *Forth) !void {
    const addressValue = try self.stack.pop();
    const v = try self.stack.pop();

    if (addressValue != ValueType.addr) {
        return ForthError.BadOperation;
    }

    if (v != ValueType.i) {
        return ForthError.BadOperation;
    }
    const p: *i32 = @ptrFromInt(addressValue.addr);
    p.* = v.i;
}

pub fn wordValueSize(self: *Forth) ForthError!void {
    const l: usize = @sizeOf(Value);
    try self.print("size of value: {d}\n", .{l});
    try self.stack.push(Value{ .sz = l });
}

pub fn inner(self: *Forth, address: i32) ForthError!void {
    try self.rstack.push(self.nexti);
    self.nexti = address;
    // try forth.print("start loop: {}\n", .{forth.nexti});
    while (self.nexti >= 0) {
        // try forth.print("inner loop: {}\n", .{forth.nexti});
        var v = self.memory[@intCast(self.nexti)];
        self.nexti += 1;
        self._evalValue(v) catch |err| {
            try self.print("Error: {any}\n", .{err});
            break;
        };
    }
    self.nexti = try self.rstack.pop();
}

fn newline(ch: u8) bool {
    return ch == '\r' or ch == '\n';
}
