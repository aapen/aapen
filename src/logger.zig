// This is a lot of BS to work around the fact that I can't
// construct a va_args list to pass to vprintf.
//
// At this time, Zig (0.12-dev-6dcbad780) thanks to
// https://github.com/ziglang/zig/blob/6dcbad780cb716fe1d2a4b2ce201a757ea7f03a4/lib/std/builtin.zig#L601
// it is not permitted to use @cVaCopy to convert a Zig variadic
// to a printf-compatible call.
//
// And Zig's built in std.log only allows the log level to be set at
// compile time. But we want to be able to modify log levels at
// runtime to facilitate debugging.

const std = @import("std");
const root = @import("root");

const Forth = @import("forty/forth.zig").Forth;

const p = @import("printf.zig");
const printf = p.printf;
const putchar = p._putchar;

const string = @import("forty/string.zig");

const Lock = @import("synchronize.zig").TicketLock;

const Logger = @This();

pub const Level = enum {
    none, // disables logging
    fatal,
    err,
    warn,
    info,
    debug,
};

const Loggers = std.StringHashMap(*Logger);

var initialized: bool = false;
var init_lock: Lock = Lock.init("log_init", true);
var all_loggers: Loggers = undefined;

pub var allocator: std.mem.Allocator = undefined;

/// Minimum level this logger will emit
level: Level = .info,

/// Prefix to use for this logger
prefix: ?[]const u8 = null,

/// Lock to prevent corrupted logs
lock: Lock = undefined,

pub fn init(prefix: []const u8, level: Level) *Logger {
    init_lock.acquire();
    defer init_lock.release();

    if (!initialized) {
        all_loggers = Loggers.init(allocator);
        initialized = true;
    }

    if (all_loggers.get(prefix)) |existing_logger| {
        return existing_logger;
    }

    var self: *Logger = create();
    self.* = .{
        .prefix = prefix,
        .level = level,
        .lock = Lock.init(prefix, true),
    };
    all_loggers.put(prefix, self) catch unreachable;

    return self;
}

pub fn get(prefix: []const u8) ?*Logger {
    init_lock.acquire();
    defer init_lock.release();

    if (initialized) {
        if (all_loggers.get(prefix)) |existing_logger| {
            return existing_logger;
        }
    }
    return null;
}

fn create() *Logger {
    return allocator.create(Logger) catch unreachable;
}

pub fn debug(self: *Logger, loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (!self.enabled(.debug)) return;

    self.logAtLevel(.debug, loc, fmt, args);
}

pub fn info(self: *Logger, loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (!self.enabled(.info)) return;

    self.logAtLevel(.info, loc, fmt, args);
}

pub fn warn(self: *Logger, loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (!self.enabled(.warn)) return;

    self.logAtLevel(.warn, loc, fmt, args);
}

pub fn err(self: *Logger, loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (!self.enabled(.err)) return;

    self.logAtLevel(.err, loc, fmt, args);
}

pub fn fatal(self: *Logger, loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (!self.enabled(.fatal)) return;

    self.logAtLevel(.fatal, loc, fmt, args);
}

fn logAtLevel(self: *Logger, level: Level, loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    self.lock.acquire();
    defer self.lock.release();

    self.writeHeader(level, loc);

    std.fmt.format(FmtWriter{ .logger = self }, fmt, args) catch {};

    self.writeByte('\n');
}

pub fn source(self: *const Logger, loc: std.builtin.SourceLocation) void {
    self.writeTruncated(loc.file, 20);
    self.writeByte(':');
    self.writeInt(u32, loc.line);
}

fn enabled(self: *const Logger, requested_level: Level) bool {
    return @intFromEnum(self.level) >= @intFromEnum(requested_level);
}

inline fn newline(self: *const Logger) void {
    self.writeByte('\n');
}

fn writeHeader(self: *const Logger, level: Level, loc: std.builtin.SourceLocation) void {
    self.writePrefix(level);
    self.source(loc);
    self.writeByte(' ');
}

fn writePrefix(self: *const Logger, level: Level) void {
    if (self.prefix) |pre| {
        self.writeByte('[');
        self.writeAll(@tagName(level));
        self.writeByte(']');
        self.writeByte(' ');
        self.writeAll(pre);
        self.writeByte(' ');
    }
}

fn writeAll(self: *const Logger, bytes: []const u8) void {
    var buf: [256]u8 = undefined;
    const copylen = @min(bytes.len, 254);
    @memcpy(buf[0..copylen], bytes[0..copylen]);
    buf[copylen] = 0;

    _ = self;
    _ = root.printf("%s", &buf);
}

fn writeTruncated(self: *const Logger, bytes: []const u8, maxlen: u8) void {
    var max = maxlen;
    var buf: [256]u8 = [_]u8{32} ** 256;

    if (max > 254) {
        max = 254;
    }

    if (bytes.len > (max - 4)) {
        @memcpy(buf[0..3], "...");
        const copylen = max - 3;
        const copystart = bytes.len - copylen;
        @memcpy(buf[3..(3 + copylen)], bytes[copystart..]);
        buf[max] = 0;
    } else {
        const copylen = bytes.len;
        const deststart = maxlen - copylen;
        @memcpy(buf[deststart..(deststart + copylen)], bytes[0..copylen]);
        buf[deststart + copylen] = 0;
    }

    _ = self;
    _ = root.printf("%s", &buf);
}

fn writeByte(self: *const Logger, byte: u8) void {
    _ = self;
    _ = putchar(byte);
}

fn writeByteNTimes(self: *const Logger, byte: u8, n: usize) void {
    _ = self;
    for (0..n) |_| {
        _ = putchar(byte);
    }
}

fn writeBytesNTimes(self: *const Logger, bytes: []const u8, n: usize) void {
    _ = self;
    for (0..n) |_| {
        _ = root.printf("%s", bytes);
    }
}

fn writeInt(self: *const Logger, comptime T: type, val: T) void {
    _ = self;
    _ = root.printf("%d", val);
}

fn writeAddrHex(self: *const Logger, addr: u64) void {
    _ = self;
    _ = root.printf("%016x", addr);
}

fn writeByteHex(self: *const Logger, byte: u8) void {
    _ = self;
    _ = root.printf("%02x", byte);
}

pub fn sliceDump(self: *Logger, loc: std.builtin.SourceLocation, slice: []const u8) void {
    if (!self.enabled(.debug)) return;

    self.lock.acquire();
    defer self.lock.release();

    const len = slice.len;
    var offset: usize = 0;

    while (offset < len) {
        self.writeHeader(.debug, loc);
        self.writeAddrHex(@intFromPtr(slice.ptr) + offset);

        for (0..16) |iByte| {
            if (offset + iByte < len) {
                self.writeByteHex(slice[offset + iByte]);
                self.writeByte(' ');
            } else {
                self.writeAll("   ");
            }
            if (iByte == 7) {
                self.writeAll("  ");
            }
        }
        self.writeAll("  |");

        for (0..16) |iByte| {
            if (offset + iByte < len) {
                self.writeByte(string.toPrintable(slice[offset + iByte]));
            } else {
                self.writeByte('.');
            }
        }
        self.writeAll("|\n");
        offset += 16;
    }
}

const FmtWriter = struct {
    logger: *const Logger,

    pub const Error = anyerror;

    pub fn writeAll(self: FmtWriter, bytes: []const u8) !void {
        self.logger.writeAll(bytes);
    }

    pub fn writeByteNTimes(self: FmtWriter, byte: u8, n: usize) !void {
        return self.logger.writeByteNTimes(byte, n);
    }

    pub fn writeBytesNTimes(self: FmtWriter, bytes: []const u8, n: usize) !void {
        return self.logger.writeBytesNTimes(bytes, n);
    }
};

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------

pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(Logger, .{
        .{ "logLevelSet", "set-log-level", "n s -- n : set logger level, 0 indicates failure" },
        .{ "logLevelGet", "get-log-level", "s -- n : get logger level" },
        .{ "dumpLoggers", "show-log-levels" },
    });
}

pub fn logLevelSet(name: [*:0]u8, level: u64) bool {
    init_lock.acquire();
    defer init_lock.release();

    if (!initialized) {
        _ = printf("not initialized\n");
        return false;
    }

    const new_level: Level = std.meta.intToEnum(Level, level) catch {
        return false;
    };

    const prefix = std.mem.sliceTo(name, 0);
    if (all_loggers.get(prefix)) |existing_logger| {
        existing_logger.level = new_level;
        return true;
    }

    return false;
}

pub fn logLevelGet(name: [*:0]u8) u64 {
    init_lock.acquire();
    defer init_lock.release();

    if (!initialized) {
        _ = printf("not initialized\n");
        return 0;
    }
    const prefix = std.mem.sliceTo(name, 0);
    if (all_loggers.get(prefix)) |existing_logger| {
        return @intFromEnum(existing_logger.level);
    }
    return 0;
}

pub fn dumpLoggers() void {
    init_lock.acquire();
    defer init_lock.release();

    if (!initialized) {
        _ = printf("not initialized\n");
        return;
    }

    var it = all_loggers.iterator();
    while (it.next()) |entry| {
        _ = printf("%s -> %d\n", entry.key_ptr.*.ptr, @as(u32, @intFromEnum(entry.value_ptr.*.level)));
    }
}
