const std = @import("std");
const root = @import("root");
const arch = @import("architecture.zig");

pub fn klog(comptime fmt: []const u8, args: anytype) void {
    root.frame_buffer_console.print(fmt, args) catch {
        // not much we can do here
    };
}

pub fn panicDisplay(from_addr: ?u64) void {
    if (from_addr) |addr| {
        klog("Panic!\nELR: 0x{x:0>8}\n", .{addr});
        stackTraceDisplay(addr);
    } else {
        klog("Panic!\nSource unknown.\n", .{});
    }
}

pub fn unknownBreakpointDisplay(from_addr: ?u64, bkpt_number: u16) void {
    if (from_addr) |addr| {
        klog("Breakpoint\nComment: 0x{x:0>8}\n ELR: 0x{x:0>8}\n", .{ bkpt_number, addr });
    } else {
        klog("Breakpoint\nComment: 0x{x:0>8}\n ELR: unknown\n", .{bkpt_number});
    }
}

pub fn unhandledExceptionDisplay(from_addr: ?u64, entry_type: u64, esr: u64, ec: arch.cpu.registers.EC) void {
    if (from_addr) |addr| {
        klog("Unhandled exception!\nType: 0x{x:0>8}\n ESR: 0x{x:0>8}\n ELR: 0x{x:0>8}\n  EC: {s}\n", .{ entry_type, @as(u64, @bitCast(esr)), addr, @tagName(ec) });
    } else {
        klog("Unhandled exception!\nType: 0x{x:0>8}\n ESR: 0x{x:0>8}\n ELR: unknown\n  EC: 0b{b:0>6}\n", .{ entry_type, esr, @tagName(ec) });
    }
}

fn stackTraceDisplay(from_addr: u64) void {
    _ = from_addr;
    var it = std.debug.StackIterator.init(null, null);
    defer it.deinit();

    klog("\nStack trace\n", .{});
    klog("Frame\tPC\n", .{});
    for (0..40) |i| {
        var addr = it.next() orelse {
            klog(".\n", .{});
            return;
        };
        stackFrameDisplay(i, addr);
    }
    klog("--stack trace truncated--\n", .{});
}

fn stackFrameDisplay(frame_number: usize, frame_pointer: usize) void {
    klog("{d}\t0x{x:0>8}\n", .{ frame_number, frame_pointer });
}
