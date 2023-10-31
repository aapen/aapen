const std = @import("std");
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const RingBuffer = std.RingBuffer;

const root = @import("root");
const arch = @import("architecture.zig");
const hal = @import("hal.zig");
const sprint = hal.serial_writer.print;

const serial_log_level: u2 = 1;
const log_level: u2 = 1;

pub inline fn ticks() u64 {
    return hal.clock.ticks();
}

inline fn log_info() bool {
    return log_level > 1;
}

inline fn serial_log_info() bool {
    return serial_log_level > 1;
}

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = "[" ++ comptime level.asText() ++ "] (" ++ @tagName(scope) ++ "): ";

    // TODO acquire spinlock
    // TODO defer release spinlock
    if (root.uart_valid) {
        hal.serial_writer.print(prefix ++ format ++ "\n", args) catch {};
    }

    if (root.console_valid) {
        root.frame_buffer_console.print(prefix ++ format ++ "\n", args) catch {};
    }
}

pub fn kinfo(comptime loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (serial_log_info()) {
        if (root.uart_valid) {
            hal.serial_writer.print("{s} {s}:{d} ", .{ loc.file, loc.fn_name, loc.line }) catch {};
            hal.serial_writer.print(fmt, args) catch {};
        }
    }
    if (log_info()) {
        if (root.console_valid) {
            root.frame_buffer_console.print("{s} {s}:{d} ", .{ loc.file, loc.fn_name, loc.line }) catch {};
            root.frame_buffer_console.print(fmt, args) catch {};
        }
    }
}

inline fn log_warnings() bool {
    return log_level > 0;
}

inline fn serial_log_warnings() bool {
    return serial_log_level > 0;
}

pub fn kwarn(comptime loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (serial_log_warnings()) {
        if (root.uart_valid) {
            hal.serial_writer.print("{s} {s}:{d} ", .{ loc.file, loc.fn_name, loc.line }) catch {};
            hal.serial_writer.print(fmt, args) catch {};
        }
    }
    if (log_warnings()) {
        if (root.console_valid) {
            root.frame_buffer_console.print("{s} {s}:{d} ", .{ loc.file, loc.fn_name, loc.line }) catch {};
            root.frame_buffer_console.print(fmt, args) catch {};
        }
    }
}

pub fn kerror(comptime loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (root.uart_valid) {
        hal.serial_writer.print("{s} {s}:{d} ", .{ loc.file, loc.fn_name, loc.line }) catch {};
        hal.serial_writer.print(fmt, args) catch {};
    }

    if (root.console_valid) {
        root.frame_buffer_console.print("{s} {s}:{d} ", .{ loc.file, loc.fn_name, loc.line }) catch {};
        root.frame_buffer_console.print(fmt, args) catch {};
    }
}

pub fn kprint(comptime fmt: []const u8, args: anytype) void {
    if (root.uart_valid) {
        hal.serial_writer.print(fmt, args) catch {};
    }

    if (root.console_valid) {
        root.frame_buffer_console.print(fmt, args) catch {
            // not much we can do here
        };
    }
}

pub fn panicDisplay(elr: ?u64) void {
    if (elr) |addr| {
        kprint("Panic!\nELR: 0x{x:0>8}\n", .{addr});
        stackTraceDisplay(addr);
    } else {
        kprint("Panic!\nSource unknown.\n", .{});
    }
}

pub fn unknownBreakpointDisplay(from_addr: ?u64, bkpt_number: u16) void {
    if (from_addr) |addr| {
        kprint("Breakpoint\nComment: 0x{x:0>8}\n ELR: 0x{x:0>8}\n", .{ bkpt_number, addr });
    } else {
        kprint("Breakpoint\nComment: 0x{x:0>8}\n ELR: unknown\n", .{bkpt_number});
    }
}

pub fn unhandledExceptionDisplay(from_addr: ?u64, entry_type: u64, esr: u64, ec: arch.cpu.registers.EC) void {
    if (from_addr) |addr| {
        kprint("Unhandled exception!\nType: 0x{x:0>8}\n ESR: 0x{x:0>8}\n ELR: 0x{x:0>8}\n  EC: {s}\n", .{ entry_type, @as(u64, @bitCast(esr)), addr, @tagName(ec) });
    } else {
        kprint("Unhandled exception!\nType: 0x{x:0>8}\n ESR: 0x{x:0>8}\n ELR: unknown\n  EC: 0b{b:0>6}\n", .{ entry_type, esr, @tagName(ec) });
    }
}

fn stackTraceDisplay(from_addr: u64) void {
    _ = from_addr;
    var it = std.debug.StackIterator.init(null, null);
    defer it.deinit();

    kprint("\nStack trace\n", .{});
    kprint("Frame\tPC\n", .{});
    for (0..40) |i| {
        var addr = it.next() orelse {
            kprint(".\n", .{});
            return;
        };
        stackFrameDisplay(i, addr);
    }
    kprint("--stack trace truncated--\n", .{});
}

fn stackFrameDisplay(frame_number: usize, frame_pointer: usize) void {
    kprint("{d}\t0x{x:0>8}\n", .{ frame_number, frame_pointer });
}

// ------------------------------------------------------------------------------
// Kernel message buffer
// ------------------------------------------------------------------------------

pub const MessageBuffer = struct {
    const Self = @This();

    ring: RingBuffer,

    pub fn init(raw_space: []u8) Allocator.Error!Self {
        var fba = FixedBufferAllocator.init(raw_space);
        var allocator = fba.allocator();
        var ring = try RingBuffer.init(allocator, raw_space.len);
        return .{
            .ring = ring,
        };
    }

    pub fn append(message_buffer: *Self, msg: []const u8) void {
        message_buffer.ring.writeSliceAssumeCapacity(msg);
        message_buffer.ring.writeAssumeCapacity(@as(u8, 0));
    }
};
