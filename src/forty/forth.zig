const std = @import("std");
const Allocator = std.mem.Allocator;

const bsp = @import("../bsp.zig");
const fbcons = @import("../fbcons.zig");
const Readline = @import("../readline.zig");
const buffer = @import("buffer.zig");

const stack = @import("stack.zig");
const string = @import("string.zig");
const core = @import("core.zig");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const memory_module = @import("memory.zig");
const Header = memory_module.Header;
const Memory = memory_module.Memory;
const intAlignBy = memory_module.intAlignBy;

pub const init_f = @embedFile("init.f");
var initBuffer = buffer.BufferSource{};

const InputStack = stack.Stack(*Readline);
const DataStack = stack.Stack(u64);
const ReturnStack = stack.Stack(u64);

pub const WordFunction = *const fn (forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64;

const parser = @import("parser.zig");
const ForthTokenIterator = parser.ForthTokenIterator;

// These are the special op codes that we may see when interpreting a
// secondary.
pub const OpCode = enum(u64) {
    stop = 0,
    push_u64 = 1,
    push_string = 3,
};

pub const Forth = struct {
    allocator: Allocator = undefined,
    console: *fbcons.FrameBufferConsole = undefined,
    stack: DataStack = undefined,
    rstack: ReturnStack = undefined,
    input: InputStack = undefined,
    buffer: [20000]u8 = undefined,
    ibase: u64 = 10,
    obase: u64 = 10,
    memory: Memory = undefined,
    lastWord: ?*Header = null,
    newWord: ?*Header = null,
    compiling: bool = false,
    string_buffer: string.LineBuffer = undefined,
    line_buffer: string.LineBuffer = undefined,
    words: ForthTokenIterator = undefined,

    pub fn init(this: *Forth, a: Allocator, c: *fbcons.FrameBufferConsole) !void {
        this.allocator = a;
        this.console = c;
        this.stack = DataStack.init(&a);
        this.rstack = ReturnStack.init(&a);
        this.buffer = undefined;
        this.memory = Memory.init(&this.buffer, this.buffer.len);
        try core.defineCore(this);

        initBuffer.init(init_f);
        var initBufferReader = try buffer.createReader(a, &initBuffer);
        var consoleReader = try fbcons.createReader(a, c);

        this.input = InputStack.init(&a);
        try this.pushSource(consoleReader);
        try this.pushSource(initBufferReader);
    }

    pub fn deinit(this: *Forth) !void {
        this.stack.deinit();
        this.rstack.deinit();
    }

    // Reset the state of the interpreter, probably due to an error.
    // Clears the stacks and aborts a new word definition.
    pub fn reset(this: *Forth) !void {
        try this.stack.reset();
        try this.rstack.reset();
        this.newWord = null;
        this.compiling = false;
    }

    // Find a word in the dictionary, ignores words that are under construction.
    pub fn findWord(this: *Forth, name: []const u8) ?*Header {
        //print("Finding word: {s}\n", .{name});
        var e = this.lastWord;
        while (e) |entry| {
            //print("Name: {s}\n", .{entry.name});
            if (string.same(&entry.name, name)) {
                return entry;
            }
            e = entry.previous;
        }
        return null;
    }

    // Define a primitive (i.e. a word backed up by a zig function).
    pub fn definePrimitive(this: *Forth, name: []const u8, f: WordFunction, immed: bool) !*Header {
        const header = try this.startWord(name, f, immed);
        try this.completeWord();
        return header;
    }

    // Define a constant with a single u64 value. What we really end up with
    // is a secondary word that pushes the value onto the stack.
    pub fn defineConstant(this: *Forth, name: []const u8, v: u64) !void {
        _ = try this.startWord(name, &core.inner, false);
        this.addOpCode(OpCode.push_u64);
        this.addNumber(v);
        this.addOpCode(OpCode.stop);
        try this.completeWord();
    }

    // Define a variable with a single u64 value. What we really end up with
    // is a secondary word that pushes the *address* of the u64 onto the stack.
    // Really just sugar around defineConstant.
    pub fn defineInternalVariable(this: *Forth, name: []const u8, p: *u64) !void {
        return this.defineConstant(name, @intFromPtr(p));
    }

    // Start a new word in the interpreter. Dictionary searches will not find
    // the new word until completeWord is called.
    pub fn startWord(this: *Forth, name: []const u8, f: WordFunction, immediate: bool) !*Header {
        if (this.compiling) {
            return ForthError.AlreadyCompiling;
        }
        try this.print("New word: {s}\n", .{name});
        const entry: Header = Header.init(name, f, immediate, this.lastWord);
        this.newWord = this.addScalar(Header, entry);
        this.compiling = true;
        return this.newWord.?;
    }

    // Finish out a new word and add it to the dictionary.
    pub fn completeWord(this: *Forth) !void {
        if (!this.compiling) {
            return ForthError.NotCompiling;
        }
        this.lastWord = this.newWord;
        this.newWord = null;
        this.compiling = false;
    }

    // Convert the token into a value, either a string, a number
    // or a reference to a word and either compile it or execute
    // directly.
    pub fn evalToken(this: *Forth, token: []const u8) !void {
        var header = this.findWord(token);

        if (header) |h| {
            try this.evalHeader(h);
        } else if (token[0] == '"') {
            try this.evalString(token);
        } else {
            var v: u64 = try parser.parseNumber(token, this.ibase);
            try this.evalNumber(v);
        }
    }

    // If we are compiling, compile the code to push the number onto the stack.
    // If we are not compiling, just push the numnber onto the stack.
    fn evalNumber(this: *Forth, i: u64) !void {
        if (this.compiling) {
            this.addOpCode(OpCode.push_u64);
            this.addNumber(i);
        } else {
            try this.stack.push(i);
        }
    }

    // If we are compiling, compile the code to push the string onto the stack.
    // If we are not compiling, copy the string to the temp space in the interpreter
    // and push a reference to the string onto the stack.
    fn evalString(this: *Forth, token: []const u8) !void {
        try this.print("eval string: {s}\n", .{token});
        const l = token.len - 1;
        const s = token[1..l];
        if (this.compiling) {
            this.addOpCode(OpCode.push_string);
            this.addString(s);
        } else {
            string.copyTo(&this.string_buffer, s);
            try this.stack.push(@intFromPtr(&this.string_buffer));
        }
    }

    // If the header is marked immediate, execute it.
    // Otherwise, if we are compiling, compile a call to the header.
    // Otherwise just execute it.
    fn evalHeader(this: *Forth, header: *Header) !void {
        if ((!this.compiling) or (header.immediate)) {
            var fake_body: [1]u64 = .{0};
            _ = try header.func(this, &fake_body, 0, header);
        } else {
            this.addCall(header);
        }
    }

    // Copy a u64 number into memory.
    pub inline fn addNumber(this: *Forth, v: u64) void {
        _ = this.memory.addBytes(@constCast(@ptrCast(&v)), @alignOf(u64), @sizeOf(u64));
    }

    // Copy an opcode into memory.
    pub inline fn addOpCode(this: *Forth, oc: OpCode) void {
        this.addNumber(@intFromEnum(oc));
    }

    // Copy a call to a word into memory.
    pub inline fn addCall(this: *Forth, header: *Header) void {
        this.addNumber(@intFromPtr(header));
    }

    // Copy the value s of type T into memory, aligning it correctly.
    // Returns a pointer to the beginning of the newly copied value.
    pub fn addScalar(this: *Forth, comptime T: type, s: T) *T {
        const p = this.memory.addBytes(@alignCast(@constCast(@ptrCast(&s))), @alignOf(T), @sizeOf(T));
        return @alignCast(@ptrCast(p));
    }

    // Copy n bytes with the given alignment into memory.
    pub fn addBytes(this: *Forth, src: [*]const u8, alignment: usize, n: usize) void {
        _ = this.memory.addBytes(@constCast(src), alignment, n);
    }

    // Add a string to memory, move the current pointer.
    // Note that a string is stored as u64 count of the number of words
    // (including the count) followed by the zero terminated string.
    pub fn addString(this: *Forth, s: []const u8) void {
        const len_words = intAlignBy(s.len, @alignOf(u64)) / @sizeOf(u64) + 1;
        this.addNumber(len_words);
        this.addBytes(s.ptr, @alignOf(u8), s.len);
        _ = this.addScalar(u8, 0);
    }

    pub fn print(this: *Forth, comptime fmt: []const u8, args: anytype) !void {
        try this.console.print(fmt, args);
    }

    pub fn writer(this: *Forth) fbcons.FrameBufferConsole.Writer {
        return this.console.writer();
    }

    fn readline(this: *Forth) !usize {
        var source = try this.input.peek();
        return source.read("OK>> ", &this.line_buffer);
    }

    fn popSource(this: *Forth) !void {
        if (this.input.items().len > 1) {
            _ = try this.input.pop();
        }
    }

    fn pushSource(this: *Forth, rl: *Readline) !void {
        try this.input.push(rl);
    }

    pub fn repl(this: *Forth) !void {
        // outer loop, one line at a time.
        while (true) {
            if (this.readline()) |line_len| {
                this.words = ForthTokenIterator.init(this.line_buffer[0..line_len]);

                // inner loop, one word at a time.
                var word = this.words.next();
                while (word != null) : (word = this.words.next()) {
                    if (word) |w| {
                        this.evalToken(w) catch |err| {
                            try this.print("error: {s} {any}\n", .{ w, err });
                            this.reset() catch {
                                try this.print("Not looking good, can't reset Forth!\n", .{});
                            };
                            break;
                        };
                    }
                }
            } else |err| {
                switch (err) {
                    Readline.Error.EOF => try this.popSource(),
                    else => return err,
                }
            }
        }
    }
};