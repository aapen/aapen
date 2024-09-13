const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const root = @import("root");
const term = @import("../term.zig");
const ascii = @import("../ascii.zig");
const key = @import("../key.zig");
const schedule = @import("../schedule.zig");

const MainConsole = @import("../main_console.zig");
const CharBuffer = @import("../char_buffer.zig");
const InputBuffer = @import("../input_buffer.zig");
const FileBuffer = @import("file_buffer.zig");

const auto = @import("auto.zig");
const stack = @import("stack.zig");
const string = @import("string.zig");
const core = @import("core.zig");
const compiler = @import("compiler.zig");
const interop = @import("interop.zig");
const inspect = @import("inspect.zig");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const Memory = @import("memory.zig");
const Header = Memory.Header;
const intAlignBy = Memory.intAlignBy;

const inner_module = @import("inner.zig");
const inner = inner_module.inner;
const OpCode = inner_module.OpCode;
const isOpCode = inner_module.isOpCode;

const History = @import("history.zig");

const WordStack = stack.Stack(u64);

pub const WordFunction = *const fn (forth: *Forth, header: *Header) ForthError!void;

const parser = @import("parser.zig");
const ForthTokenIterator = parser.ForthTokenIterator;

const MemSize = 16_777_215;

const Forth = @This();

allocator: Allocator = undefined,
arena_allocator: ArenaAllocator = undefined,
temp_allocator: Allocator = undefined,
console: *MainConsole = undefined,
char_buffer: *CharBuffer = undefined,
stack: WordStack = undefined,
istack: WordStack = undefined,
call_stack: WordStack = undefined,
buffer: []u8 = undefined,
history: History = undefined,
ibase: u64 = 10,
obase: u64 = 10,
debug: u64 = 0,
memory: Memory = undefined,
last_word: ?*Header = null,
new_word: ?*Header = null,
compiling: u64 = 0,
words: ForthTokenIterator = undefined,
source_buffer: ?[]u8 = null,
current_file_buffer: FileBuffer = undefined,

pub fn init(this: *Forth, a: Allocator, c: *MainConsole, cb: *CharBuffer) !void {
    this.ibase = 10;
    this.obase = 10;
    this.debug = 0;
    this.last_word = null;
    this.new_word = null;
    this.allocator = a;
    this.arena_allocator = ArenaAllocator.init(a);
    this.temp_allocator = this.arena_allocator.allocator();
    this.console = c;
    this.char_buffer = cb;
    this.stack = try WordStack.initCapacity(a, 64);
    this.istack = try WordStack.initCapacity(a, 64);
    this.call_stack = try WordStack.initCapacity(a, 64);
    this.buffer = try a.alloc(u8, MemSize); // TBD make size a parameter.
    this.memory = Memory.init(this.buffer.ptr, this.buffer.len);
    this.history = History.init(a, 15);
    this.current_file_buffer = FileBuffer.init(@embedFile("init.f"));

    _ = try this.defineBuffer("cmd-buffer", 20);
    try this.defineConstant("inner", @intFromPtr(&inner));
    try this.defineConstant("forth", @intFromPtr(this));
    try this.defineConstant("this", @intFromPtr(this));
    try this.defineStruct("forth", Forth, .{});
    try this.defineStruct("header", Header, .{});
    try this.defineStruct("memory", Memory, .{});

    try compiler.defineCompiler(this);
    try core.defineCore(this);
    try inspect.defineInspect(this);
    try interop.defineInterop(this);
}

pub fn deinit(this: *Forth) !void {
    this.stack.deinit();
    this.istack.deinit();
    this.call_stack.deinit();
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
    try this.istack.reset();
    try this.call_stack.reset();
    this.new_word = null;
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
    var e = this.last_word;
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
    var e = this.last_word;
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
pub fn pushBodyAddress(self: *Forth, header: *Header) ForthError!void {
    const body = header.bodyOfType([*]u8);
    try self.stack.push(@intFromPtr(body));
}

// Define a primitive w/o a description.
pub fn defineBuffer(this: *Forth, name: []const u8, lenInWords: u64) !*Header {
    const header = try this.startWord(name, "A buffer", &pushBodyAddress, false);
    _ = try this.allocate(@alignOf(u64), lenInWords);
    try this.completeWord();
    return header;
}

pub fn defineNamespace(this: *Forth, comptime Module: type, exports: anytype) !void {
    try auto.defineNamespace(Module, exports, this);
}

// Define a constant with a single u64 value. What we really end up with
// is a secondary word that pushes the value onto the stack.
pub fn defineConstant(this: *Forth, name: []const u8, v: u64) !void {
    _ = try this.startWord(name, "A constant", &compiler.pushBodyValue, false);
    try this.addNumber(v);
    try this.completeWord();
}

const DefineStructOptions = struct {
    recursive: bool = false,
    declarations: bool = false,
    debug: bool = false,
};

pub fn defineStruct(this: *Forth, comptime name: []const u8, comptime It: type, comptime opt: DefineStructOptions) !void {
    switch (@typeInfo(It)) {
        .Struct => |struct_info| {
            try this.defineConstant(name ++ ".*len", @sizeOf(It));
            inline for (struct_info.fields) |field| {
                const fname = comptime kebabCase(field.name);
                try this.defineConstant(name ++ "." ++ fname, @offsetOf(It, field.name));
            }
            if (opt.declarations) {
                inline for (struct_info.decls) |decl| {
                    const d = decl.name;
                    const f = @field(It, d);
                    const decl_type = @TypeOf(f);
                    const decl_info = @typeInfo(decl_type);
                    const fname = comptime kebabCase(d);

                    switch (decl_info) {
                        .ComptimeInt => try this.defineConstant(name ++ "." ++ fname, f),
                        .Int => try this.defineConstant(name ++ "." ++ fname, f),
                        .Type => |t| {
                            _ = t;
                            if (opt.recursive) {
                                try this.defineStruct(name ++ "." ++ fname, f, opt);
                            }
                        },
                        inline else => {
                            if (opt.debug) {
                                @compileLog("encountered decl " ++ d ++ " with type " ++ @typeName(decl_type));
                            }
                            // ignore it
                        },
                    }
                }
            }
        },
        else => {
            @compileError("expected a struct, found '" ++ @typeName(It) ++ "'");
        },
    }
}

fn kebabCase(comptime in: []const u8) []u8 {
    @setEvalBranchQuota(5000);
    var out: [in.len]u8 = undefined;
    for (in, 0..) |c, i| {
        out[i] = switch (c) {
            '_' => '-',
            else => std.ascii.toLower(c),
        };
    }
    return out[0..in.len];
}

// Returns the constant asssociated with the given Forty name.
// Note this relies on the specifics of the code generated by defineConstant.
pub fn internalConstantValue(this: *Forth, name: []const u8) !u64 {
    const header = this.findWord(name) orelse return ForthError.NotFound;
    const body = header.bodyOfType([*]u64);
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
    const owned_name = try std.mem.Allocator.dupeZ(this.allocator, u8, name);
    const owned_desc = try std.mem.Allocator.dupeZ(this.allocator, u8, desc);
    const entry: Header = Header.init(owned_name, owned_desc, f, immediate, this.last_word);
    this.new_word = try this.addScalar(Header, entry);
    return this.new_word.?;
}

// Finish out the new dictionary entry and add it to the dictionary.
pub fn complete(this: *Forth) void {
    const wordLength = @intFromPtr(this.memory.current) - @intFromPtr(this.new_word);
    this.new_word.?.len = @intCast(wordLength);
    this.last_word = this.new_word;
    this.new_word = null;
}

// Allocate some memory, starting on the given alignment.
// Return a pointer to the start of the memory.
// Intended for use between create and complete.
pub fn allocate(this: *Forth, comptime alignment: usize, n: usize) ![*]u8 {
    return this.memory.allocate(alignment, n);
}

// Start a new word in the interpreter. Dictionary searches will not find
// the new word until completeWord is called.
pub fn startWord(this: *Forth, name: []const u8, desc: []const u8, f: WordFunction, immediate: bool) !*Header {
    try this.assertNotCompiling();
    const new_word = try this.create(name, desc, f, immediate);
    this.compiling = 1;
    return new_word;
}

// Finish out a new word and add it to the dictionary.
pub fn completeWord(this: *Forth) !void {
    try this.assertCompiling();
    this.complete();
    this.compiling = 0;
}

// Evaluate a command, a string containing zero or more words.
pub fn evalCommand(this: *Forth, cmd: []const u8) void {
    const savedWords = this.words;
    defer {
        this.words = savedWords;
    }

    this.words = ForthTokenIterator.init(cmd);

    var word = this.words.next();
    while (word != null) : (word = this.words.next()) {
        if (word) |w| {
            this.evalToken(w) catch |err| {
                this.print("error: {s} {any}\n", .{ w, err }) catch {};
                this.reset() catch {
                    this.print("Not looking good, can't reset Forth!\n", .{}) catch {};
                    schedule.exit();
                };
                break;
            };
        }
    }
}

// Convert the token into a value, either a string, a number
// or a reference to a word and either compile it or execute
// directly. Note that this is the place where we ignore comments.
pub fn evalToken(this: *Forth, token: []const u8) !void {
    //try this.serial_print("EvalToken {s}\n", .{token});
    const header = this.findWord(token);

    if (header) |h| {
        try this.evalHeader(h);
    } else if (token[0] == '\'') {
        try this.evalQuoted(token);
    } else if (token[0] == '"' or token[0] == ':') {
        try this.evalString(token);
    } else if (token[0] != '(') {
        const v: u64 = try parser.parseNumber(token, this.ibase);
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
        try this.addOpCode(OpCode.PushU64);
        try this.addNumber(i);
    } else {
        try this.stack.push(i);
    }
}

// If we are compiling, compile the code to push the number onto the stack.
// If we are not compiling, just push the numnber onto the stack.
fn evalNumber(this: *Forth, i: u64) !void {
    if (this.compiling != 0) {
        try this.addOpCode(OpCode.PushU64);
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
        try this.addOpCode(OpCode.PushString);
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
        //try header.func(this, header);
        try inner_module.executeHeader(this, header);
    } else if (header.func == inner) {
        try this.addOpCode(OpCode.CallSecondary);
        try this.addNumber(@intFromPtr(header));
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

// Add an opcode to memory.
pub inline fn addOpCode(this: *Forth, oc: u64) !void {
    if (isOpCode(oc)) {
        try this.addNumber(oc);
    } else {
        return ForthError.NotAnOpCode;
    }
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
pub fn addBytes(this: *Forth, src: [*]const u8, comptime alignment: usize, n: usize) !void {
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
        try term.writer.print(fmt, args);
    }
}

pub fn serial_print(_: *Forth, comptime fmt: []const u8, args: anytype) !void {
    try term.writer.print(fmt, args);
}

pub fn print(this: *Forth, comptime fmt: []const u8, args: anytype) !void {
    try this.console.print(fmt, args);
}

pub fn emit(this: *Forth, ch: key.Keycode) void {
    this.console.putc(ch);
}

pub const Writer = std.io.Writer(*Forth, error{}, write);

pub fn writer(this: *Forth) Writer {
    return .{ .context = this };
}

pub fn write(self: *Forth, bytes: []const u8) !usize {
    for (bytes) |ch| {
        self.emit(ch);
    }
    return bytes.len;
}

fn prompt(this: *Forth) void {
    if (!this.current_file_buffer.hasMore()) {
        _ = this.console.write("OK>> ") catch {};
    }
}

fn read(this: *Forth) key.Keycode {
    if (this.current_file_buffer.hasMore()) {
        return this.current_file_buffer.read();
    } else {
        return InputBuffer.read();
    }
}

fn echo(this: *Forth, ch: key.Keycode) void {
    if (!this.current_file_buffer.hasMore()) {
        this.emit(ch);
    }
}

pub fn repl(this: *Forth) !void {
    const MaxLineLen = 256;
    var line_buffer: [MaxLineLen:0]u8 = undefined;
    var line_len: usize = 0;

    // outer loop, one line at a time.
    this.begin();
    this.prompt();

    while (true) {
        const ch = this.read();

        switch (ch) {
            ascii.CR,
            ascii.NL,
            => {
                line_buffer[line_len] = 0;
                this.evalCommand(line_buffer[0..line_len]);
                this.end();
                this.begin();
                this.prompt();
                line_len = 0;
            },
            ascii.DEL,
            ascii.BS,
            => {
                if (line_len > 0) {
                    if (line_len < MaxLineLen) {
                        line_buffer[line_len] = 0;
                    }
                    line_len -= 1;
                    this.echo(ascii.DEL);
                }
            },
            else => {
                if (line_len + 1 >= MaxLineLen) {
                    try this.print("line too long\n", .{});
                } else {
                    this.echo(ch);
                    line_buffer[line_len] = @truncate(ch & 0xff);
                    line_len += 1;
                }
            },
        }
    }
}
