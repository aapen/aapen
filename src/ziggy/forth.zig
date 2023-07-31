const std = @import("std");
const Allocator = std.mem.Allocator;
// const print = std.debug.print;

const bsp = @import("../bsp.zig");
const fbcons = @import("../fbcons.zig");
const stack = @import("stack.zig");
const reader = @import("reader.zig");
const dict = @import("dictionary.zig");
const value = @import("value.zig");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const Value = value.Value;
const ValueType = value.ValueType;

const DataStack = stack.Stack(Value);
const ReturnStack = stack.Stack(i32);

const ValueDictionary = dict.Dictionary(Value);

const WordFunction = *const fn (forth: *Forth) ForthError!void;

pub const Forth = struct {
    allocator: Allocator = undefined,
    console: *fbcons.FrameBufferConsole,

    stack: DataStack = undefined,
    rstack: ReturnStack = undefined,
    dictionary: ValueDictionary = undefined,
    reader: reader.ForthReader = undefined,
    memory: [2000]Value = undefined,
    nextFree: i32 = 0,
    nexti: i32 = -999,
    composing: bool = false,
    newWordName: [reader.max_line_len:0]u8 = undefined,
    newWordDef: i32 = -888,

    pub fn init(self: *Forth, allocator: Allocator) !void {
        self.stack = DataStack.init(allocator);
        self.rstack = ReturnStack.init(allocator);
        self.dictionary = ValueDictionary.init(allocator);
    }

    pub fn print(self: *Forth, comptime fmt: []const u8, args: anytype) !void {
        try self.console.print(fmt, args);
    }

    pub fn evalFP(forth: *Forth, v: Value) dict.ForthError!void {
        const fp: *fn (forth: *Forth) void = v.fp;
        try fp(forth);
    }

    pub fn addToDefinition(forth: *Forth, v: Value) void {
        forth.memory[@intCast(forth.nextFree)] = v;
        forth.nextFree += 1;
    }

    pub fn _evalValue(forth: *Forth, v: Value) !void {
        switch (v) {
            .w => |name| {
                const assoc_value = try forth.dictionary.get(name);
                try evalValue(forth, assoc_value);
            },
            .fp => |p| {
                //var wordf = @intToPtr(WordFunction, p);
                var wordf: WordFunction = @ptrFromInt(p);
                try wordf(forth);
            },
            .call => |address| {
                try inner(forth, address);
            },
            else => |_| {
                try forth.stack.push(v);
            },
        }
    }

    pub fn evalValue(forth: *Forth, v: Value) ForthError!void {
        // try forth.print("eval value {any}\n", .{v});
        switch (v) {
            .w => |name| {
                const entry = try forth.dictionary.getEntry(name);
                // try forth.print("word: {s} entry: {any}\n", .{ name, entry });
                if (entry.immediate) {
                    try _evalValue(forth, entry.value);
                } else if (forth.composing) {
                    forth.addToDefinition(entry.value);
                } else {
                    try _evalValue(forth, entry.value);
                }
            },
            .fp => |p| {
                if (forth.composing) {
                    forth.addToDefinition(v);
                } else {
                    var wordf: WordFunction = @ptrFromInt(p);
                    try wordf(forth);
                }
            },
            .call => |address| {
                if (forth.composing) {
                    forth.addToDefinition(v);
                } else {
                    try inner(forth, address);
                }
            },
            else => |_| {
                if (forth.composing) {
                    forth.addToDefinition(v);
                } else {
                    try forth.stack.push(v);
                }
            },
        }
    }

    pub fn wordColon(self: *Forth) !void {
        try self.print("colon:\n", .{});
        @memset(&self.newWordName, 0);
        _ = try self.reader.getWord(&self.newWordName);
        self.composing = true;
        self.newWordDef = self.nextFree;
    }

    pub fn wordSemi(self: *Forth) !void {
        try self.print("***semi:\n", .{});
        self.memory[@intCast(self.nextFree)] = Value{
            //.fp = @ptrToInt(&wordReturn),
            .fp = @intFromPtr(&wordReturn),
        };
        self.nextFree += 1;
        try self.print("semi: {s} {any}\n", .{ self.newWordName, self.newWordDef });
        try self.defineSecondary(&self.newWordName, self.newWordDef);
        self.composing = false;
        @memset(&self.newWordName, 0);
        self.newWordDef = -888;
    }

    // a -- ()
    pub fn wordEmit(self: *Forth) !void {
        var s = &self.stack;
        const a = try s.pop();
        self.console.emit(@intCast(a.u));
    }

    pub fn wordClearScreen(self: *Forth) !void {
        _ = self;
    }

    fn definePrimitive(this: *Forth, name: []const u8, fp: WordFunction, immediate: bool) !void {
        // try this.print("define word {s} -> {*}\n", .{ name, fp });
        try this.dictionary.put(name, Value{ .fp = @intFromPtr(fp) }, immediate);
    }

    fn defineSecondary(this: *Forth, name: []const u8, address: i32) !void {
        // try this.print("define secondary {s} {}\n", .{ name, address });
        try this.dictionary.put(name, Value{ .call = address }, false);
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
            buffer[i] = ch;
            i += 1;
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

    pub fn repl(this: *Forth) !void {
        var buf: [reader.max_line_len:0]u8 = undefined;

        // outer loop, one line at a time.
        while (true) {
            this.emitPrompt("READY.\n");
            var line_len: usize = this.readline(&buf) catch 0;

            var words = std.mem.tokenizeAny(u8, buf[0..line_len], " \t\n\r");

            // inner loop, one word at a time.
            var word = words.next();
            while (word != null) : (word = words.next()) {
                if (word) |w| {
                    var v = Value.fromString(w) catch |err| {
                        try this.print("Parse error({s}): {}\n", .{ w, err });
                        continue;
                    };
                    this.evalValue(v) catch |err| {
                        try this.print("error: {any}\n", .{err});
                    };
                }
            }
        }
    }

    pub fn define_core(forth: *Forth) !void {
        // Screen control
        try forth.definePrimitive("emit", &Forth.wordEmit, false);
        try forth.definePrimitive("cls", &Forth.wordClearScreen, false);

        // Secondary definition words.
        try forth.definePrimitive(":", &Forth.wordColon, false);
        try forth.definePrimitive(";", &Forth.wordSemi, true);

        // Debug and inspection words.

        try forth.definePrimitive("stack", &wordStack, false);
        try forth.definePrimitive("?", &wordStack, false);
        try forth.definePrimitive("??", &wordDictionary, false);
        try forth.definePrimitive("rstack", &wordRStack, false);
        try forth.definePrimitive("info", &wordInfo, true);
        try forth.definePrimitive("ip", &wordNext, false);
        try forth.definePrimitive("value-size", &wordValueSize, false);

        // Basic Forth words.

        try forth.definePrimitive("hello", &wordHello, false);
        try forth.definePrimitive(".", &wordDot, false);
        try forth.definePrimitive("cr", &wordCr, false);
        try forth.definePrimitive("swap", &wordSwap, false);
        try forth.definePrimitive("+", &wordAdd, false);
        try forth.definePrimitive("!i", &wordStoreI32, false);
        try forth.definePrimitive("@i", &wordLoadI32, false);
    }
};

pub fn wordHello(forth: *Forth) !void {
    try forth.print("hello world\n", .{});
}

pub fn wordDot(forth: *Forth) !void {
    var v: Value = try forth.stack.pop();
    try v.pr(forth);
}

pub fn wordStack(forth: *Forth) !void {
    for (forth.stack.items()) |item| {
        try item.pr(forth);
        try forth.print("\n", .{});
    }
}

pub fn wordRStack(forth: *Forth) !void {
    for (forth.rstack.items()) |item| {
        try forth.print("{}\n", .{item});
    }
}

pub fn wordSwap(forth: *Forth) !void {
    var s = &forth.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(a);
    try s.push(b);
}

pub fn wordAdd(forth: *Forth) !void {
    var s = &forth.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(try a.add(&b));
}

pub fn wordCr(forth: *Forth) ForthError!void {
    try forth.print("\n", .{});
}

pub fn wordReturn(forth: *Forth) ForthError!void {
    forth.nexti = -999;
}

pub fn wordDictionary(forth: *Forth) ForthError!void {
    try forth.dictionary.pr(forth);
}

pub fn wordInfo(forth: *Forth) ForthError!void {
    try forth.print("nexti: {}\n", .{forth.nexti});
    try forth.print("composing: {}\n", .{forth.composing});
    try forth.print("new word: {s}\n", .{forth.newWordName});
    try forth.print("new word def: {}\n", .{forth.newWordDef});
}
pub fn wordNext(forth: *Forth) ForthError!void {
    var nexti_address: usize = @intFromPtr(&forth.nexti);
    var v = Value{ .addr = nexti_address };
    try forth.stack.push(v);
}

pub fn wordLoadI32(forth: *Forth) !void {
    const addressValue = try forth.stack.pop();
    if (addressValue != ValueType.addr) {
        return ForthError.BadOperation;
    }
    const p: *i32 = @ptrFromInt(addressValue.addr);
    const v = Value{ .i = p.* };
    try forth.stack.push(v);
}

pub fn wordStoreI32(forth: *Forth) !void {
    const addressValue = try forth.stack.pop();
    const v = try forth.stack.pop();

    if (addressValue != ValueType.addr) {
        return ForthError.BadOperation;
    }

    if (v != ValueType.i) {
        return ForthError.BadOperation;
    }
    const p: *i32 = @ptrFromInt(addressValue.addr);
    p.* = v.i;
}

pub fn wordValueSize(forth: *Forth) ForthError!void {
    const l: usize = @sizeOf(Value);
    try forth.print("size of value: {d}\n", .{l});
    try forth.stack.push(Value{ .sz = l });
}

pub fn inner(forth: *Forth, address: i32) ForthError!void {
    try forth.rstack.push(forth.nexti);
    forth.nexti = address;
    try forth.print("start loop: {}\n", .{forth.nexti});
    while (forth.nexti >= 0) {
        try forth.print("inner loop: {}\n", .{forth.nexti});
        var v = forth.memory[@intCast(forth.nexti)];
        forth.nexti += 1;
        forth._evalValue(v) catch |err| {
            try forth.print("Error: {any}\n", .{err});
            break;
        };
    }
    forth.nexti = try forth.rstack.pop();
}

fn newline(ch: u8) bool {
    return ch == '\r' or ch == '\n';
}
