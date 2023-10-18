const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const hal = @import("../hal.zig");
const fbcons = @import("../fbcons.zig");
const Readline = @import("../readline.zig");
const buffer = @import("buffer.zig");

const stack = @import("stack.zig");
const string = @import("string.zig");
const core = @import("core.zig");
const compiler = @import("compiler.zig");
const interop = @import("interop.zig");
const inspect = @import("inspect.zig");

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

pub const WordFunction = *const fn (forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!i64;

const parser = @import("parser.zig");
const ForthTokenIterator = parser.ForthTokenIterator;

const MemSize = 16_777_215;

pub const Forth = struct {
    allocator: Allocator = undefined,
    arena_allocator: ArenaAllocator = undefined,
    temp_allocator: Allocator = undefined,
    console: *fbcons.FrameBufferConsole = undefined,
    stack: DataStack = undefined,
    rstack: ReturnStack = undefined,
    input: InputStack = undefined,
    buffer: []u8 = undefined,
    ibase: u64 = 10,
    obase: u64 = 10,
    debug: u64 = 0,
    memory: Memory = undefined,
    lastWord: ?*Header = null,
    newWord: ?*Header = null,
    pushU64: *Header = undefined,
    pushString: *Header = undefined,
    drop: *Header = undefined,
    rDrop: *Header = undefined,
    toRStack: *Header = undefined,
    toDStack: *Header = undefined,
    jumpIfRLE: *Header = undefined,
    incRStack: *Header = undefined,
    jump: *Header = undefined,
    jumpIfNot: *Header = undefined,
    compiling: u64 = 0,
    line_buffer: *string.LineBuffer = undefined,
    words: ForthTokenIterator = undefined,

    pub fn init(this: *Forth, a: Allocator, c: *fbcons.FrameBufferConsole) !void {
        this.ibase = 10;
        this.obase = 10;
        this.debug = 0;
        this.lastWord = null;
        this.newWord = null;
        this.allocator = a;
        this.arena_allocator = ArenaAllocator.init(a);
        this.temp_allocator = this.arena_allocator.allocator();
        this.console = c;
        this.stack = DataStack.init(&a);
        this.rstack = ReturnStack.init(&a);
        this.buffer = try a.alloc(u8, MemSize); // TBD make size a parameter.
        this.memory = Memory.init(this.buffer.ptr, this.buffer.len);
        this.line_buffer = try a.create(string.LineBuffer);

        this.pushString = try this.definePrimitive("*push-string", &wordPushString, false);
        this.pushU64 = try this.definePrimitive("*push-u64", &wordPushU64, false);
        this.jump = try this.definePrimitive("*jump", &wordJump, false);
        this.jumpIfNot = try this.definePrimitive("*jump-if-not", &wordJumpIfNot, false);
        this.drop = try this.definePrimitiveDesc("drop", " n -- : Drop the top stack value", &wordDrop, false);
        this.rDrop = try this.definePrimitiveDesc("rdrop", " n -- : Drop the top rstack value", &wordRDrop, false);
        this.toRStack = try this.definePrimitiveDesc("->rstack", " n -- : Push the data TOS onto the rstack, doen't pop stack.", &wordToRStack, false);
        this.toDStack = try this.definePrimitiveDesc("->stack", " -- n : Copies the rstack TOS onto the data stack, doesn't pop rstack", &wordToDStack, false);
        this.jumpIfRLE = try this.definePrimitive("*jump-if-rle", &wordJumpIfRLE, false);
        this.incRStack = try this.definePrimitive("rstack-inc", &wordIncRStack, false);

        _ = try this.defineBuffer("cmd-buffer", 20);
        try this.defineConstant("inner", @intFromPtr(&inner));
        try this.defineConstant("*stop", 0);
        try this.defineConstant("forth", @intFromPtr(this));
        try this.defineConstant("this", @intFromPtr(this));
        try this.defineStruct("forth", Forth);
        try this.defineStruct("header", Header);
        try this.defineStruct("memory", Memory);

        try compiler.defineCompiler(this);
        try core.defineCore(this);
        try inspect.defineInspect(this);
        try interop.defineInterop(this);

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

    pub inline fn popAs(this: *Forth, comptime T: type) !T {
        const v = try this.stack.pop();
        switch (@typeInfo(T)) {
            .Int => {
                const tSize = @sizeOf(T);
                if (tSize >= @sizeOf(i64)) {
                    const casted_v: T = @bitCast(v);
                    return casted_v;
                } else {
                    const trunc_v: T = @intCast(v);
                    return trunc_v;
                }
            },
            .Pointer => {
                const casted_p: T = @ptrFromInt(v);
                return casted_p;
            },
            else => {
                @compileError("Expected an int or pointer, found '" ++ @typeName(T) ++ "'");
            },
        }
    }

    // TBD handle pointers...
    pub inline fn pushAny(this: *Forth, v: anytype) !void {
        const T = @TypeOf(v);
        switch (@typeInfo(T)) {
            .Int => {
                const v_u64: u64 = @bitCast(v);
                try this.stack.push(v_u64);
            },
            .Pointer => {
                const v_u64: u64 = @intFromPtr(v);
                try this.stack.push(v_u64);
            },
            else => {
                @compileError("Expected an int or pointer, found '" ++ @typeName(T) ++ "'");
            },
        }
    }

    // Reset the state of the interpreter, probably due to an error.
    // Clears the stacks and aborts a new word definition.
    pub fn reset(this: *Forth) !void {
        try this.stack.reset();
        try this.rstack.reset();
        this.newWord = null;
        this.compiling = 0;
    }

    // Begin a new interactive transaction. We take the opportunity to
    // reset the arena allocator that is used for temp string operations.
    pub fn begin(this: *Forth) void {
        _ = this.arena_allocator.reset(.{ .retain_with_limit = 2048 });
    }

    // Eng an interactive transation.
    pub fn end(_: *Forth) void {}

    // Read and return the next word in the input.
    pub fn readWord(this: *Forth) ForthError![]const u8 {
        return this.words.next() orelse return ForthError.WordReadError;
    }

    // Peek at the next word in the input.
    pub fn peekWord(this: *Forth) ?[]const u8 {
        return this.words.peek();
    }

    // Find a word in the dictionary by name, ignores words that are under construction.
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

    // Returns true if wp points at a word in the dictionary, ignores words that are under construction.
    pub fn isWordP(this: *Forth, wp: u64) bool {
        var e = this.lastWord;
        while (e) |entry| {
            if (wp == @intFromPtr(entry)) {
                return true;
            }
            e = entry.previous;
        }
        return false;
    }

    // Define a primitive (i.e. a word backed up by a zig function).
    pub fn definePrimitiveDesc(this: *Forth, name: []const u8, desc: []const u8, f: WordFunction, immed: bool) !*Header {
        const header = try this.startWord(name, desc, f, immed);
        try this.completeWord();
        return header;
    }

    // Define a primitive w/o a description.
    pub fn definePrimitive(this: *Forth, name: []const u8, f: WordFunction, immed: bool) !*Header {
        const header = try this.startWord(name, "A prim", f, immed);
        try this.completeWord();
        return header;
    }

    // Push the address of the word body onto the stack.
    pub fn pushBodyAddress(self: *Forth, _: [*]u64, _: u64, header: *Header) ForthError!i64 {
        var body = header.bodyOfType([*]u8);
        try self.stack.push(@intFromPtr(body));
        return 0;
    }

    // Define a primitive w/o a description.
    pub fn defineBuffer(this: *Forth, name: []const u8, lenInWords: u64) !*Header {
        const header = try this.startWord(name, "A buffer", &pushBodyAddress, false);
        _ = try this.allocate(@alignOf(u64), lenInWords);
        try this.completeWord();
        return header;
    }

    // Define a constant with a single u64 value. What we really end up with
    // is a secondary word that pushes the value onto the stack.
    pub fn defineConstant(this: *Forth, name: []const u8, v: u64) !void {
        _ = try this.startWord(name, "A constant", &inner, false);
        try this.addCall(this.pushU64);
        try this.addNumber(v);
        try this.addStop();
        try this.completeWord();
    }

    pub fn defineStruct(this: *Forth, comptime name: []const u8, comptime It: type) !void {
        switch (@typeInfo(It)) {
            .Struct => |struct_info| {
                try this.defineConstant(name ++ ".*len", @sizeOf(It));
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
    pub fn create(this: *Forth, name: []const u8, desc: []const u8, f: WordFunction, immediate: bool) !*Header {
        var owned_name = try std.mem.Allocator.dupeZ(this.allocator, u8, name);
        var owned_desc = try std.mem.Allocator.dupeZ(this.allocator, u8, desc);
        const entry: Header = Header.init(owned_name, owned_desc, f, immediate, this.lastWord);
        this.newWord = try this.addScalar(Header, entry);
        return this.newWord.?;
    }

    // Finish out the new dictionary entry and add it to the dictionary.
    pub fn complete(this: *Forth) void {
        const wordLength = @intFromPtr(this.memory.current) - @intFromPtr(this.newWord);
        this.newWord.?.len = @intCast(wordLength);
        this.lastWord = this.newWord;
        this.newWord = null;
    }

    // Allocate some memory, starting on the given alignment.
    // Return a pointer to the start of the memory.
    // Intended for use between create and complete.
    pub fn allocate(this: *Forth, alignment: usize, n: usize) ![*]u8 {
        return this.memory.allocate(alignment, n);
    }

    // Start a new word in the interpreter. Dictionary searches will not find
    // the new word until completeWord is called.
    pub fn startWord(this: *Forth, name: []const u8, desc: []const u8, f: WordFunction, immediate: bool) !*Header {
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

    // This is the inner interpreter, effectively the word
    // that runs all the secondary words.
    pub fn inner(forth: *Forth, _: [*]u64, _: u64, header: *Header) ForthError!i64 {
        var body = header.bodyOfType([*]u64);
        var i: usize = 0;
        while (true) {
            try forth.trace("{:4}: {x:4}: ", .{ i, body[i] });
            if (body[i] == 0) {
                break;
            }
            const p: *Header = @ptrFromInt(body[i]);
            try forth.trace("Call: {x} {s}\n", .{ body[i], p.name });
            const delta = try p.func(forth, body, i, p);
            var new_i: i64 = @intCast(i);
            new_i = new_i + 1 + delta;
            i = @intCast(new_i);
        }
        return 0;
    }

    // This is the word that pushes ints onto the stack.
    fn wordPushU64(this: *Forth, body: [*]u64, i: u64, _: *Header) ForthError!i64 {
        try this.stack.push(body[i + 1]);
        return 1;
    }

    // This is the word that pushes strings onto the stack.
    fn wordPushString(this: *Forth, body: [*]u64, i: u64, _: *Header) ForthError!i64 {
        try this.trace("Push string len: {}\n", .{body[i + 1]});
        const data_size = body[i + 1];
        var p_string: [*]u8 = @ptrCast(body + i + 2);
        try this.stack.push(@intFromPtr(p_string));
        return @intCast(data_size + 1);
    }

    // This is the word that does an unconditional jump, used in loops and if's etc.
    fn wordJump(this: *Forth, body: [*]u64, i: u64, _: *Header) ForthError!i64 {
        const delta: i64 = @as(i64, @bitCast(body[i + 1]));
        try this.trace("Jump -> {}\n", .{i});
        return delta - 1;
    }

    // This is the word that does a conditional jump, used in loops and if's etc.
    fn wordJumpIfNot(this: *Forth, body: [*]u64, i: u64, _: *Header) ForthError!i64 {
        var c: u64 = try this.stack.pop();
        const delta: i64 = @as(i64, @bitCast(body[i + 1]));
        try this.trace("JumpIfNot cond: {} target {} ", .{ c, delta });

        if (c == 0) {
            return delta - 1;
        } else {
            return 1;
        }
    }

    // This is the word that does a conditional jump if the top of the rstack
    // is <= 0. *Does not pop the rstack*.
    fn wordJumpIfRLE(this: *Forth, body: [*]u64, i: u64, _: *Header) ForthError!i64 {
        var first: u64 = try this.rstack.pop();
        var second: u64 = try this.rstack.pop();
        try this.rstack.push(second);
        try this.rstack.push(first);

        const delta: i64 = @as(i64, @bitCast(body[i + 1]));
        try this.trace("JumpIfRNP first {} second {} target {} ", .{ first, second, delta });

        if (second <= first) {
            return delta - 1;
        } else {
            return 1;
        }
    }

    pub fn wordDrop(this: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
        _ = try this.stack.pop();
        return 0;
    }

    pub fn wordRDrop(this: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
        _ = try this.rstack.pop();
        return 0;
    }

    pub fn wordIncRStack(this: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
        const v = try this.rstack.pop();
        try this.rstack.push(v + 1);
        return 0;
    }

    pub fn wordToRStack(this: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
        const v = try this.stack.peek();
        try this.rstack.push(v);
        return 0;
    }

    pub fn wordToDStack(this: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!i64 {
        const v = try this.rstack.peek();
        try this.stack.push(v);
        return 0;
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
        } else if (token[0] == '"' or token[0] == ':') {
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
            try this.addCall(this.pushU64);
            try this.addNumber(i);
        } else {
            try this.stack.push(i);
        }
    }

    // If we are compiling, compile the code to push the number onto the stack.
    // If we are not compiling, just push the numnber onto the stack.
    fn evalNumber(this: *Forth, i: u64) !void {
        if (this.compiling != 0) {
            try this.addCall(this.pushU64);
            try this.addNumber(i);
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
            try this.addCall(this.pushString);
            try this.addString(s);
        } else {
            const allocated_s = try this.temp_allocator.dupeZ(u8, s);
            try this.stack.push(@intFromPtr(allocated_s.ptr));
        }
    }

    // If the header is marked immediate, execute it.
    // Otherwise, if we are compiling, compile a call to the header.
    // Otherwise just execute it.
    fn evalHeader(this: *Forth, header: *Header) !void {
        if ((this.compiling == 0) or header.immediate) {
            var fake_body: [1]u64 = .{0};
            _ = try header.func(this, &fake_body, 0, header);
        } else {
            try this.addCall(header);
        }
    }

    // Return the next unused location in memory.
    pub inline fn current(this: *Forth) [*]u8 {
        return this.memory.current;
    }

    // Copy a u64 number into memory.
    pub inline fn addNumber(this: *Forth, v: u64) !void {
        _ = try this.memory.addBytes(@constCast(@ptrCast(&v)), @alignOf(u64), @sizeOf(u64));
    }

    // Add a stop command to memory.
    pub inline fn addStop(this: *Forth) !void {
        try this.addNumber(0);
    }

    // Copy a call to a word into memory.
    pub inline fn addCall(this: *Forth, header: *Header) !void {
        try this.addNumber(@intFromPtr(header));
    }

    // Copy the value s of type T into memory, aligning it correctly.
    // Returns a pointer to the beginning of the newly copied value.
    pub fn addScalar(this: *Forth, comptime T: type, s: T) !*T {
        const p = try this.memory.addBytes(@alignCast(@constCast(@ptrCast(&s))), @alignOf(T), @sizeOf(T));
        return @alignCast(@ptrCast(p));
    }

    // Copy n bytes with the given alignment into memory.
    pub fn addBytes(this: *Forth, src: [*]const u8, alignment: usize, n: usize) !void {
        _ = try this.memory.addBytes(@constCast(src), alignment, n);
    }

    // Add a string to memory, move the current pointer.
    // Note that a string is stored as u64 count of the number of words
    // (including the count) followed by the zero terminated string.
    pub fn addString(this: *Forth, s: []const u8) !void {
        const str_len_words = (s.len + @sizeOf(u64) - 1 + 1) / @sizeOf(u64);
        try this.addNumber(str_len_words);
        try this.addBytes(s.ptr, @alignOf(u8), s.len);
        _ = try this.addScalar(u8, 0);
    }

    // Print stuff out only if debug is non-zero.
    pub inline fn trace(this: *Forth, comptime fmt: []const u8, args: anytype) !void {
        if (this.debug > 0) {
            try this.print(fmt, args);
        }
    }

    pub fn print(this: *Forth, comptime fmt: []const u8, args: anytype) !void {
        try this.console.print(fmt, args);
        try hal.serial_writer.print(fmt, args);
    }

    pub fn emit(this: *Forth, ch: u8) !void {
        this.console.emit(ch);
        try hal.serial_writer.writeByte(ch);
    }

    pub fn writer(this: *Forth) fbcons.FrameBufferConsole.Writer {
        return this.console.writer();
    }

    fn readline(this: *Forth) !usize {
        var source = try this.input.peek();
        return source.read("OK>> ", this.line_buffer);
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
            this.begin();
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
            this.end();
        }
    }
};
