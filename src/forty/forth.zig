const std = @import("std");
const Allocator = std.mem.Allocator;

const bsp = @import("../bsp.zig");
const fbcons = @import("../fbcons.zig");
const Readline = @import("../readline.zig");
const buffer = @import("buffer.zig");

const stack = @import("stack.zig");
const string = @import("string.zig");
const core = @import("core.zig");
const compiler = @import("compiler.zig");

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
    jump_if_not = 5,
    jump = 7,
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
    debug: u64 = 0,
    memory: Memory = undefined,
    lastWord: ?*Header = null,
    newWord: ?*Header = null,
    compiling: u64 = 0,
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
        try compiler.defineCompiler(this);

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
        this.compiling = 0;
    }

    // Read and return the next word in the input.
    pub fn readWord(this: *Forth) ForthError![]const u8 {
        return this.words.next() orelse return ForthError.WordReadError;
    }

    // Peek at the next word in the input.
    pub fn peekWord(this: *Forth) ?[]const u8 {
        return this.words.peek();
    }

    // Find a word in the dictionary, ignores words that are under construction.
    pub fn findWord(this: *Forth, name: []const u8) ?*Header {
        //print("Finding word: {s}\n", .{name});
        var e = this.lastWord;
        while (e) |entry| {
            //print("Name: {s}\n", .{entry.name});
            if (string.same(entry.name, name)) {
                return entry;
            }
            e = entry.previous;
        }
        return null;
    }

    // Define a primitive (i.e. a word backed up by a zig function).
    pub fn definePrimitiveDesc(this: *Forth, name: []const u8, desc: []const u8, f: WordFunction, immed: u64) !*Header {
        const header = try this.startWord(name, desc, f, immed);
        try this.completeWord();
        return header;
    }

    // Define a primitive w/o a description.
    pub fn definePrimitive(this: *Forth, name: []const u8, f: WordFunction, immed: u64) !*Header {
        const header = try this.startWord(name, "A prim", f, immed);
        try this.completeWord();
        return header;
    }

    // Define a constant with a single u64 value. What we really end up with
    // is a secondary word that pushes the value onto the stack.
    pub fn defineConstant(this: *Forth, name: []const u8, v: u64) !void {
        _ = try this.startWord(name, "A constant", &compiler.inner, 0);
        this.addOpCode(OpCode.push_u64);
        this.addNumber(v);
        this.addOpCode(OpCode.stop);
        try this.completeWord();
    }

    pub fn defineStruct(this: *Forth, comptime name: []const u8, comptime It: type) !void {
        switch (@typeInfo(It)) {
            .Struct => |struct_info| {
                inline for (struct_info.fields) |field| {
                    try this.defineConstant(name ++ "." ++ field.name, @offsetOf(It, field.name));
                }
            },
            else => {
                @compileError("expected a struct, found '" ++ @typeName(It) ++ "'");
            },
        }
    }

    // Returns the constant asssociated with the given Forty name.
    // Note this relies on the specifics of the code generated by defineConstant.
    pub fn internalConstantValue(this: *Forth, name: []const u8) !u64 {
        const header = this.findWord(name) orelse return ForthError.NotFound;
        var body = header.bodyOfType([*]u64);
        return body[1];
    }

    // Define a variable with a single u64 value. What we really end up with
    // is a secondary word that pushes the *address* of the u64 onto the stack.
    // Really just sugar around defineConstant.
    pub fn defineInternalVariable(this: *Forth, name: []const u8, p: *u64) !void {
        return this.defineConstant(name, @intFromPtr(p));
    }

    // Returns the value asssociated with the given Forty internal variable.
    pub fn internalVariableValue(this: *Forth, name: []const u8) !u64 {
        const i = try this.internalConstantValue(name);
        const p: [*]u64 = @ptrFromInt(i);
        return p[0];
    }

    // Return an error if we are not compiling.
    pub inline fn assertCompiling(this: *Forth) !void {
        if (this.compiling == 0) {
            return ForthError.NotCompiling;
        }
    }

    // Return an error if we are compiling.
    pub inline fn assertNotCompiling(this: *Forth) !void {
        if (this.compiling != 0) {
            return ForthError.AlreadyCompiling;
        }
    }

    // Start a new dictionary entry in the interpreter. Dictionary searches will not find
    // the new word until completeWord is called.
    pub fn create(this: *Forth, name: []const u8, desc: []const u8, f: WordFunction, immediate: u64) !*Header {
        var owned_name = try std.mem.Allocator.dupeZ(this.allocator, u8, name);
        var owned_desc = try std.mem.Allocator.dupeZ(this.allocator, u8, desc);
        const entry: Header = Header.init(owned_name, owned_desc, f, immediate, this.lastWord);
        this.newWord = this.addScalar(Header, entry);
        return this.newWord.?;
    }

    // Finish out the new dictionary entry and add it to the dictionary.
    pub fn complete(this: *Forth) void {
        this.newWord.?.len = @intFromPtr(this.memory.current) - @intFromPtr(this.newWord);
        this.lastWord = this.newWord;
        this.newWord = null;
    }

    // Allocate some memory, starting on the given alignment.
    // Return a pointer to the start of the memory.
    // Intended for use between create and complete.
    pub fn allocate(this: *Forth, alignment: usize, n: usize) [*]u8 {
        return this.memory.allocate(alignment, n);
    }

    // Start a new word in the interpreter. Dictionary searches will not find
    // the new word until completeWord is called.
    pub fn startWord(this: *Forth, name: []const u8, desc: []const u8, f: WordFunction, immediate: u64) !*Header {
        try this.assertNotCompiling();
        const newWord = try this.create(name, desc, f, immediate);
        this.compiling = 1;
        return newWord;
    }

    // Finish out a new word and add it to the dictionary.
    pub fn completeWord(this: *Forth) !void {
        try this.assertCompiling();
        this.complete();
        this.compiling = 0;
    }

    // Convert the token into a value, either a string, a number
    // or a reference to a word and either compile it or execute
    // directly. Note that this is the place where we ignore comments.
    pub fn evalToken(this: *Forth, token: []const u8) !void {
        var header = this.findWord(token);

        if (header) |h| {
            try this.evalHeader(h);
        } else if (token[0] == '\'') {
            try this.evalQuoted(token);
        } else if (token[0] == '"') {
            try this.evalString(token);
        } else if (token[0] != '(') {
            var v: u64 = try parser.parseNumber(token, this.ibase);
            try this.evalNumber(v);
        }
    }

    // Evaluate a word that starts with a single quote.
    // We look up the symbol
    fn evalQuoted(this: *Forth, token: []const u8) !void {
        const name = try parser.parseQuoted(token);
        const header = this.findWord(name) orelse return ForthError.NotFound;
        const i: u64 = @intFromPtr(header);

        if (this.compiling != 0) {
            this.addOpCode(OpCode.push_u64);
            this.addNumber(i);
        } else {
            try this.stack.push(i);
        }
    }

    // If we are compiling, compile the code to push the number onto the stack.
    // If we are not compiling, just push the numnber onto the stack.
    fn evalNumber(this: *Forth, i: u64) !void {
        if (this.compiling != 0) {
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
        const s = try parser.parseString(token);
        if (this.compiling != 0) {
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
        if ((this.compiling == 0) or (header.immediate != 0)) {
            var fake_body: [1]u64 = .{0};
            _ = try header.func(this, &fake_body, 0, header);
        } else {
            this.addCall(header);
        }
    }

    // Return the next unused location in memory.
    pub inline fn current(this: *Forth) [*]u8 {
        return this.memory.current;
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
        const str_len_words = (s.len + @sizeOf(u64) - 1 + 1) / @sizeOf(u64);
        this.addNumber(str_len_words);
        this.addBytes(s.ptr, @alignOf(u8), s.len);
        _ = this.addScalar(u8, 0);
    }

    // Print stuff out only if debug is non-zero.
    pub inline fn trace(this: *Forth, comptime fmt: []const u8, args: anytype) !void {
        if (this.debug > 0) {
            try this.print(fmt, args);
        }
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
