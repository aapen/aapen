const std = @import("std");
const print = std.debug.print;

const stack = @import("stack.zig");
const reader = @import("reader.zig");
const dict = @import("dictionary.zig");
const value = @import("value.zig");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const Value = value.Value;
const ValueType = value.ValueType;

const DataStack = stack.Stack(Value, 20);
const ReturnStack = stack.Stack(i32, 100);

const ValueDictionary = dict.Dictionary(Value, 500);

const WordFunction = *const fn (forth: *Forth) ForthError!void;

const Forth = struct {
    stack: DataStack,
    rstack: ReturnStack,
    dictionary: ValueDictionary,
    reader: *reader.ForthReader,
    memory: [2000]Value,
    nextFree: i32,
    nexti: i32,
    composing: bool,
    newWordName: [reader.max_line_len:0]u8,
    newWordDef: i32,

    pub fn init(r: *reader.ForthReader) Forth {
        return Forth{
            .rstack = ReturnStack.init(),
            .stack = DataStack.init(),
            .dictionary = ValueDictionary.init(),
            .reader = r,
            .memory = undefined,
            .nextFree = 0,
            .nexti = -999,
            .composing = false,
            .newWordName = undefined,
            .newWordDef = -888,
        };
    }

    pub fn evalFP(forth: *Forth, v: Value) dict.ForthError!void {
        const fp: *fn (forth: *Forth) void = v.fp;
        try fp(forth);
    }

    pub fn addToDefinition(forth: *Forth, v: Value) void {
        forth.memory[@intCast(forth.nextFree)] = v;
        forth.nextFree += 1;
    }

    pub fn _evalValue(forth: *Forth, v: Value) ForthError!void {
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

    pub fn evalValue(forth: *Forth, v: Value) !void {
        //print("eval value {any}\n", .{v});
        switch (v) {
            .w => |name| {
                const entry = try forth.dictionary.getEntry(name);
                //print("word: {s} entry: {any}\n", .{name, entry});
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

    pub fn wordColon(self: *Forth) ForthError!void {
        print("colon:\n", .{});
        @memset(&self.newWordName, 0);
        _ = try self.reader.getWord(&self.newWordName);
        self.composing = true;
        self.newWordDef = self.nextFree;
    }

    pub fn wordSemi(self: *Forth) ForthError!void {
        print("***semi:\n", .{});
        self.memory[@intCast(self.nextFree)] = Value{
            //.fp = @ptrToInt(&wordReturn),
            .fp = @intFromPtr(&wordReturn),
        };
        self.nextFree += 1;
        print("semi: {s} {any}\n", .{ self.newWordName, self.newWordDef });
        try self.defineSecondary(&self.newWordName, self.newWordDef);
        self.composing = false;
        @memset(&self.newWordName, 0);
        self.newWordDef = -888;
    }

    fn definePrimitive(this: *Forth, name: []const u8, fp: WordFunction, immediate: bool) !void {
        //print("define word {s} -> {*}\n", .{ name, fp });
        try this.dictionary.put(name, Value{ .fp = @intFromPtr(fp) }, immediate);
    }

    fn defineSecondary(this: *Forth, name: []const u8, address: i32) !void {
        print("define secondary {s} {}\n", .{ name, address });
        try this.dictionary.put(name, Value{ .call = address }, false);
    }

    pub fn repl(this: *Forth) !void {
        // This is the outter loop.

        var buf: [reader.max_line_len:0]u8 = undefined;

        while (true) {
            //print("calling getword\n", .{});
            var word = this.reader.getWord(&buf) catch |err| {
                if (err == ForthError.EOF) {
                    break;
                }
                print("Error: {}\n", .{err});
                return err;
            };
            var v = Value.fromString(word) catch |err| {
                print("Parse error({s}): {}\n", .{ word, err });
                continue;
            };
            this.evalValue(v) catch |err| {
                print("error: {any}\n", .{err});
            };
        }
    }
};

pub fn wordHello(_: *Forth) ForthError!void {
    print("hello world\n", .{});
}

pub fn wordDot(forth: *Forth) ForthError!void {
    var v: Value = try forth.stack.pop();
    v.pr(print);
}

pub fn wordStack(forth: *Forth) ForthError!void {
    for (forth.stack.items()) |item| {
        item.pr(print);
        print("\n", .{});
    }
}

pub fn wordRStack(forth: *Forth) ForthError!void {
    for (forth.rstack.items()) |item| {
        print("{}\n", .{item});
    }
}

pub fn wordSwap(forth: *Forth) ForthError!void {
    var s = &forth.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(a);
    try s.push(b);
}

pub fn wordAdd(forth: *Forth) ForthError!void {
    var s = &forth.stack;
    const a = try s.pop();
    const b = try s.pop();
    try s.push(try a.add(&b));
}

pub fn wordCr(_: *Forth) ForthError!void {
    print("\n", .{});
}

pub fn wordReturn(forth: *Forth) ForthError!void {
    forth.nexti = -999;
}

pub fn wordDictionary(forth: *Forth) ForthError!void {
    try forth.dictionary.pr(print);
}

pub fn wordInfo(forth: *Forth) ForthError!void {
    print("nexti: {}\n", .{forth.nexti});
    print("composing: {}\n", .{forth.composing});
    print("new word: {s}\n", .{forth.newWordName});
    print("new word def: {}\n", .{forth.newWordDef});
}
pub fn wordNext(forth: *Forth) ForthError!void {
    var nexti_address: usize = @intFromPtr(&forth.nexti);
    var v = Value{ .addr = nexti_address };
    try forth.stack.push(v);
}

pub fn wordLoadI32(forth: *Forth) ForthError!void {
    const addressValue = try forth.stack.pop();
    if (addressValue != ValueType.addr) {
        return ForthError.BadOperation;
    }
    const p: *i32 = @ptrFromInt(addressValue.addr);
    const v = Value{ .i = p.* };
    try forth.stack.push(v);
}

pub fn wordStoreI32(forth: *Forth) ForthError!void {
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
    print("size of value: {d}\n", .{l});
    try forth.stack.push(Value{ .sz = l });
}

pub fn inner(forth: *Forth, address: i32) ForthError!void {
    try forth.rstack.push(forth.nexti);
    forth.nexti = address;
    //print("start loop: {}\n", .{forth.nexti});
    while (forth.nexti >= 0) {
        //print("inner loop: {}\n", .{forth.nexti});
        var v = forth.memory[@intCast(forth.nexti)];
        forth.nexti += 1;
        forth._evalValue(v) catch |err| {
            print("Error: {any}\n", .{err});
            break;
        };
    }
    forth.nexti = try forth.rstack.pop();
}

pub fn define_core(forth: *Forth) !void {
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

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var cr = reader.ConsoleReader.init(stdin, stdout, ">> ");
    var fr = reader.ForthReader.init(&cr);

    var forth = Forth.init(&fr);
    try define_core(&forth);

    try forth.repl();
}
