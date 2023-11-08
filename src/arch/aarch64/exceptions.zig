const std = @import("std");

const root = @import("root");
const kprint = root.kprint;

const debug = @import("../../debug.zig");
const cpu = @import("../../architecture.zig").cpu;
const registers = @import("registers.zig");
const Esr = @import("registers/esr.zig").Layout;

const __exception_handler_table: *u64 = @extern(*u64, .{ .name = "__exception_handler_table" });

pub const UnwindPoint = struct {
    sp: u64 = undefined,
    pc: u64 = undefined,
    fp: u64 = undefined,
    lr: u64 = undefined,
};

pub extern fn markUnwindPoint(point: *UnwindPoint) void;

const IrqHandler = *const fn (context: *const ExceptionContext) void;

pub fn init() void {
    registers.vbar_el1.write(@intFromPtr(__exception_handler_table));
    irqEnable();
}

/// Context passed in to every exception handler.
/// This is created by the KERNEL_ENTRY macro in `exceptions.s` and it
/// is stored on the stack.
pub const ExceptionContext = struct {
    /// General purpose registers' stored state
    gpr: [30]u64,

    /// Link Register (a.k.a. x30)
    lr: u64,

    /// Exception Link Register (PC at the time the exception
    /// happened)
    elr: u64,

    /// Saved Program Status Register
    spsr: u64,

    /// Exception Syndrome Register
    esr: Esr,

    /// Override the actual stack with this stack pointer on return
    force_sp: u64,
};

fn unwindPointLocate(_: *ExceptionContext) *UnwindPoint {
    return &root.global_unwind_point;
}

export fn irqCurrentElx(context: *const ExceptionContext) void {
    root.hal.interrupt_controller.irqHandle(context);
}

pub fn irqDisable() void {
    asm volatile ("msr daifset, #2");
}

pub fn irqEnable() void {
    asm volatile ("msr daifclr, #2");
}

pub fn irqFlagsSave() u64 {
    return asm (
        \\ mrs %[ret], daif
        : [ret] "=r" (-> u64),
    );
}

pub fn irqFlagsRestore(flags: u64) void {
    asm volatile (
        \\ msr daif, %[flags]
        :
        : [flags] "r" (flags),
    );
}

// This is an arbitrary, but unique, number
const soft_reset_breakpoint = 0x7c5;

pub fn triggerSoftReset() void {
    asm volatile ("brk 0x7c5");
}

// ----------------------------------------------------------------------
// Exception display
// ----------------------------------------------------------------------

export fn invalidEntryMessageShow(context: *ExceptionContext, entry_type: u64) void {
    // Check if this was a breakpoint due to std.builtin.default_panic
    if (context.esr.ec == .brk) {
        // Breakpoint number is the lower 16 bits of ESR's ISS
        var breakpoint_number: u16 = @truncate(context.esr.iss & 0xffff);

        // Zig uses 0xf000 to indicate a panic
        if (breakpoint_number == 0xf000) {
            // Could we get the panic string and arguments from the
            // stack?
            panicDisplay(context.elr);
            var unwind = unwindPointLocate(context);
            if (unwind.sp != undefined) {
                context.elr = unwind.pc;
                context.force_sp = unwind.sp;
                context.lr = unwind.lr;
                context.gpr[29] = unwind.fp;
            }
        } else if (breakpoint_number == soft_reset_breakpoint) {
            root.resetSoft();

            // Adjust ELR to resume execution _after_ the breakpoint instruction
            context.elr += 4;
        } else {
            unknownBreakpointDisplay(context.elr, breakpoint_number);

            // Adjust ELR to resume execution _after_ the breakpoint instruction
            context.elr += 4;
        }
    } else {
        unhandledExceptionDisplay(context.elr, entry_type, @as(u64, @bitCast(context.esr)), context.esr.ec);
    }
}

fn panicDisplay(elr: ?u64) void {
    if (elr) |addr| {
        kprint("Panic!\nELR: 0x{x:0>8}\n", .{addr});
        stackTraceDisplay(addr);
    } else {
        kprint("Panic!\nSource unknown.\n", .{});
    }
}

fn unknownBreakpointDisplay(from_addr: ?u64, bkpt_number: u16) void {
    if (from_addr) |addr| {
        kprint("Breakpoint\nComment: 0x{x:0>8}\n ELR: 0x{x:0>8}\n", .{ bkpt_number, addr });
    } else {
        kprint("Breakpoint\nComment: 0x{x:0>8}\n ELR: unknown\n", .{bkpt_number});
    }
}

fn unhandledExceptionDisplay(from_addr: ?u64, entry_type: u64, esr: u64, ec: cpu.registers.EC) void {
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
