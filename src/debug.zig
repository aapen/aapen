const std = @import("std");
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const RingBuffer = std.RingBuffer;
const ScopeLevel = std.log.ScopeLevel;

const root = @import("root");
const printf = root.printf;

const Forth = @import("forty/forth.zig").Forth;

const memory = @import("memory.zig");
const Sections = memory.Sections;

const schedule = @import("schedule.zig");
const serial = @import("serial.zig");

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
}

// ----------------------------------------------------------------------
// Initialization
// ----------------------------------------------------------------------
const DEBUG_INFO_MAGIC_NUMBER: u32 = 0x00abacab;

var debug_info_valid = false;

pub fn init() void {
    const maybe_debug_info_magic: *u32 = @ptrCast(@alignCast(&Sections.__debug_info_start));
    if (maybe_debug_info_magic.* == DEBUG_INFO_MAGIC_NUMBER) {
        debug_info_valid = true;
    }

    mring_fba = FixedBufferAllocator.init(&mring_storage);
    mring_allocator = mring_fba.allocator();
    ring = RingBuffer{
        .data = &mring_storage,
        .write_index = 0,
        .read_index = 0,
    };
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
            _ = printf("%02d    0x%08x\n", i, addr);
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

// ----------------------------------------------------------------------
// Logging support
// ----------------------------------------------------------------------
pub const options = struct {
    pub const logFn = log;
    pub const log_level = .warn;
    pub const log_scope_levels = &[_]ScopeLevel{
        .{ .scope = .dwc_otg_usb, .level = .debug },
        .{ .scope = .dwc_otg_usb_channel, .level = .debug },
        .{ .scope = .schedule, .level = .debug },
        .{ .scope = .usb, .level = .debug },
        .{ .scope = .usb_hub, .level = .debug },
        .{ .scope = .forty, .level = .info },
    };
};

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (comptime !std.log.logEnabled(level, scope)) return;

    const prefix = switch (scope) {
        std.log.default_log_scope => "",
        else => @tagName(scope) ++ " ",
    } ++ "[" ++ comptime level.asText() ++ "]: ";

    if (root.main_console_valid) {
        root.main_console.print(prefix ++ format ++ "\n", args) catch {};
    } else {
        serial.writer.print(prefix ++ format ++ "\n", args) catch {};
    }
}

pub fn sliceDumpAsWords(buf: []const u8) void {
    const buf_words = std.mem.bytesAsSlice(u32, buf);
    const len = buf_words.len;
    var offset: usize = 0;

    while (offset < len) {
        _ = printf("%016x  %08x\n", @intFromPtr(buf_words.ptr) + offset, buf_words[offset]);
        offset += 1;
    }
}

pub fn sliceDump(buf: []const u8) void {
    const len = buf.len;
    var offset: usize = 0;

    while (offset < len) {
        _ = printf("%016x  ", @intFromPtr(buf.ptr) + offset);

        for (0..16) |iByte| {
            if (offset + iByte < len) {
                _ = printf("%02x ", buf[offset + iByte]);
            } else {
                _ = printf("   ");
            }
            if (iByte == 7) {
                _ = printf("  ");
            }
        }
        _ = printf("  |");
        for (0..16) |iByte| {
            if (offset + iByte < len) {
                _ = printf("%c", string.toPrintable(buf[offset + iByte]));
            } else {
                _ = printf(" ");
            }
        }
        _ = printf("|\n");
        offset += 16;
    }
}

// ------------------------------------------------------------------------------
// Kernel message buffer
// ------------------------------------------------------------------------------

const mring_space_bytes = 1024 * 1024;
pub var mring_storage: [mring_space_bytes]u8 = undefined;
var mring_spinlock: TicketLock = TicketLock.init("kernel_message_ring", true);
var ring: RingBuffer = undefined;

// implementation variables... not for use outside of init()
var mring_fba: FixedBufferAllocator = undefined;
var mring_allocator: Allocator = undefined;

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
