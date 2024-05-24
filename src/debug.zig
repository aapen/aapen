const std = @import("std");
const Allocator = std.mem.Allocator;
const RingBuffer = std.RingBuffer;

const root = @import("root");

const p = @import("printf.zig");
const printf = p.printf;

const Forth = @import("forty/forth.zig").Forth;

const memory = @import("memory.zig");
const Sections = memory.Sections;

const schedule = @import("schedule.zig");

const synchronize = @import("synchronize.zig");
const TicketLock = synchronize.TicketLock;

const string = @import("forty/string.zig");

const StackTrace = std.builtin.StackTrace;

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------
pub fn defineModule(forth: *Forth) !void {
    try forth.defineConstant("mring", @intFromPtr(&mring_storage));
    try forth.defineConstant("debug-info-valid", @intFromPtr(&debug_info_valid));
    try forth.defineNamespace(@This(), .{
        .{ "lookupSymbol", "symbol-at" },
        .{ "addressOf", "address-of" },
    });
}

// ----------------------------------------------------------------------
// Initialization
// ----------------------------------------------------------------------
const DEBUG_INFO_MAGIC_NUMBER: u32 = 0x00abacab;

pub fn init() void {
    const maybe_debug_info_magic: *u32 = @ptrCast(@alignCast(&Sections.__debug_info_start));
    if (maybe_debug_info_magic.* == DEBUG_INFO_MAGIC_NUMBER) {
        initDebugInfo();
    }

    initMring();
}

// ----------------------------------------------------------------------
// Debug info lookup
// ----------------------------------------------------------------------
var debug_info_valid: bool = false;
var debug_symbols: []Symbol = undefined;
var debug_strings: ?[*]u8 = null;

const DebugInfoHeader = extern struct {
    magic: u32,
    strings_offset: u32,
    symbol_entries: u32,
    padding: u32,
};

const Symbol = struct {
    low_pc: u64,
    high_pc: u64,
    symbol_offset: u64,

    const none: Symbol = .{ .low_pc = 0, .high_pc = std.math.maxInt(u64), .symbol_offset = 0 };

    pub fn lookupByAddr(addr: u64) ?*const Symbol {
        if (!debug_info_valid) {
            return null;
        }

        var best_match = &Symbol.none;
        for (debug_symbols) |*symb| {
            if (symb.contains(addr)) {
                if (best_match.isWider(symb)) {
                    best_match = symb;
                }
            }
        }

        return if (best_match == &Symbol.none) null else best_match;
    }

    pub fn lookupByName(nm: [*:0]const u8) ?*const Symbol {
        if (!debug_info_valid) {
            return null;
        }

        for (debug_symbols) |*symb| {
            if (symb.nameMatches(nm)) {
                return symb;
            }
        } else {
            return null;
        }
    }

    pub fn name(symbol: *const Symbol) [*:0]const u8 {
        return @ptrCast(debug_strings.? + symbol.symbol_offset);
    }

    fn contains(symbol: *const Symbol, addr: u64) bool {
        return symbol.low_pc <= addr and addr < symbol.high_pc;
    }

    fn nameMatches(symbol: *const Symbol, b: [*:0]const u8) bool {
        const a: [*:0]const u8 = symbol.name();
        var i: usize = 0;
        while (true) {
            if (a[i] == 0 and b[i] == 0) return true; // same length
            if (a[i] != b[i]) return false; // different char
            if (a[i] == 0 or b[i] == 0) return false; // different lengths
            i += 1;
        }
    }

    fn span(symbol: *const Symbol) usize {
        if (symbol.high_pc > symbol.low_pc) {
            return symbol.high_pc - symbol.low_pc;
        } else {
            return std.math.maxInt(usize);
        }
    }

    fn isWider(this: *const Symbol, that: *const Symbol) bool {
        return this.span() > that.span();
    }
};

pub fn initDebugInfo() void {
    debug_info_valid = true;

    const debug_loc = @intFromPtr(&Sections.__debug_info_start);
    const header: *DebugInfoHeader = @ptrFromInt(debug_loc);

    debug_symbols.ptr = @ptrFromInt(debug_loc + @sizeOf(DebugInfoHeader));
    debug_symbols.len = header.symbol_entries;

    const string_locations = debug_loc + header.strings_offset;
    debug_strings = @ptrFromInt(string_locations);
}

pub fn lookupSymbol(addr: u64) ?[*:0]const u8 {
    if (Symbol.lookupByAddr(addr)) |found| {
        return found.name();
    } else {
        return null;
    }
}

pub fn addressOf(name: [*:0]const u8) u64 {
    if (Symbol.lookupByName(name)) |found| {
        return found.low_pc;
    } else {
        return 0;
    }
}

// ----------------------------------------------------------------------
// Panic support
// ----------------------------------------------------------------------
pub fn panic(msg: []const u8, error_return_trace: ?*StackTrace, return_addr: ?usize) noreturn {
    _ = error_return_trace;
    @setCold(true);

    if (return_addr) |ret| {
        _ = printf("[panic]: '%s' at [0x%08x]\n", ret, msg.ptr);
    } else {
        _ = printf("[panic]: '%s' from unknown location\n", msg.ptr);
    }

    const first_trace_addr = return_addr orelse @returnAddress();
    var stack = std.debug.StackIterator.init(first_trace_addr, null);
    defer stack.deinit();

    for (0..40) |i| {
        if (stack.next()) |addr| {
            if (lookupSymbol(addr)) |sym| {
                _ = printf("%02d    0x%08x  %s\n", i, addr, sym);
            } else {
                _ = printf("%02d    0x%08x\n", i, addr);
            }
        } else {
            _ = printf(".\n");
            break;
        }
    } else {
        _ = printf("--stack trace truncated--\n");
    }

    schedule.kill(schedule.current);

    unreachable;
}

// ------------------------------------------------------------------------------
// Kernel message buffer
// ------------------------------------------------------------------------------

const mring_space_bytes = 1024 * 1024;
pub var mring_storage: [mring_space_bytes]u8 = undefined;
var mring_spinlock: TicketLock("kernel_message_ring") = .{};
var ring: RingBuffer = undefined;

fn initMring() void {
    ring = RingBuffer{
        .data = &mring_storage,
        .write_index = 0,
        .read_index = 0,
    };
}

/// Use this to report low-level errors. It bypasses the serial
/// interface, the frame buffer, and even Zig's formatting. (This does
/// mean you don't get formatted messages, but it also has no chance
/// of panicking.)
pub fn kernelMessage(msg: []const u8) void {
    mring_spinlock.acquire();
    defer mring_spinlock.release();

    ring.writeSliceAssumeCapacity(msg);
    ring.writeAssumeCapacity(@as(u8, 0));
}

pub fn kernelError(msg: []const u8, err: anyerror) void {
    kernelMessage(msg);
    kernelMessage(@errorName(err));

    if (root.main_console_valid) {
        _ = printf("%s: %s\n", msg.ptr, @errorName(err).ptr);
    }
}
