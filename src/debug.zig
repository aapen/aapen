const std = @import("std");
const root = @import("root");
const bsp = @import("bsp.zig");
const arch = @import("architecture.zig");

const log_level: u2 = 1;

inline fn log_info() bool {
    return log_level > 1;
}

pub fn kinfo(comptime loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (log_info()) {
        if (root.uart_valid) {
            bsp.io.uart_writer.print("{s}.{s}:{d} ", .{ loc.file, loc.fn_name, loc.line }) catch {};
            bsp.io.uart_writer.print(fmt, args) catch {};
        }

        if (root.console_valid) {
            root.frame_buffer_console.print("{s}.{s}:{d} ", .{ loc.file, loc.fn_name, loc.line }) catch {};
            root.frame_buffer_console.print(fmt, args) catch {};
        }
    }
}

inline fn log_warnings() bool {
    return log_level > 0;
}

pub fn kwarn(comptime loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (log_warnings()) {
        if (root.uart_valid) {
            bsp.io.uart_writer.print("{s}.{s}:{d} ", .{ loc.file, loc.fn_name, loc.line }) catch {};
            bsp.io.uart_writer.print(fmt, args) catch {};
        }

        if (root.console_valid) {
            root.frame_buffer_console.print("{s}.{s}:{d} ", .{ loc.file, loc.fn_name, loc.line }) catch {};
            root.frame_buffer_console.print(fmt, args) catch {};
        }
    }
}

pub fn kerror(comptime loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (root.uart_valid) {
        bsp.io.uart_writer.print("{s}.{s}:{d} ", .{ loc.file, loc.fn_name, loc.line }) catch {};
        bsp.io.uart_writer.print(fmt, args) catch {};
    }

    if (root.console_valid) {
        root.frame_buffer_console.print("{s}.{s}:{d} ", .{ loc.file, loc.fn_name, loc.line }) catch {};
        root.frame_buffer_console.print(fmt, args) catch {};
    }
}

pub fn kprint(comptime fmt: []const u8, args: anytype) void {
    if (root.uart_valid) {
        bsp.io.uart_writer.print(fmt, args) catch {};
    }

    if (root.console_valid) {
        root.frame_buffer_console.print(fmt, args) catch {
            // not much we can do here
        };
    }
}

pub fn panicDisplay(from_addr: ?u64) void {
    if (from_addr) |addr| {
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
