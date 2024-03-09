const std = @import("std");

const root = @import("root");
const printf = root.printf;

const debug = @import("../../debug.zig");
const cpu = @import("../../architecture.zig").cpu;
const registers = @import("registers.zig");
const reg_esr = @import("registers/esr.zig");
const Esr = reg_esr.Layout;
const ErrorCodes = reg_esr.ErrorCodes;

const __exception_handler_table = @extern([*]u8, .{ .name = "__exception_handler_table" });

pub const UnwindPoint = struct {
    sp: u64 = undefined,
    pc: u64 = undefined,
    fp: u64 = undefined,
    lr: u64 = undefined,
};

pub extern fn markUnwindPoint(point: *UnwindPoint) void;

const IrqHandler = *const fn (context: *const ExceptionContext) void;

pub fn init() void {
    cpu.exceptionHandlerTableWrite(__exception_handler_table);
}

/// Context passed in to every exception handler.
/// This is created by the KERNEL_ENTRY macro in `exceptions.s` and it
/// is stored on the stack.
pub const ExceptionContext = struct {
    /// General purpose registers' stored state
    gpr: [30]u64,

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

// ----------------------------------------------------------------------
// Exception display
// ----------------------------------------------------------------------

export fn invalidEntryMessageShow(context: *ExceptionContext, entry_type: u64) void {
    // Check if this was a breakpoint due to std.builtin.default_panic
    if (context.esr.ec == ErrorCodes.brk) {
        // Breakpoint number is the lower 16 bits of ESR's ISS
        const breakpoint_number: u16 = @truncate(context.esr.iss & 0xffff);

        // Zig uses 0xf000 to indicate a panic
        if (breakpoint_number == 0xf000) {
            // Could we get the panic string and arguments from the
            // stack?
            panicDisplay(context.elr);
            const unwind = unwindPointLocate(context);
            if (unwind.sp != undefined) {
                context.elr = unwind.pc;
                context.force_sp = unwind.sp;
                context.gpr[29] = unwind.fp;
            }
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
        _ = printf("Panic!\nELR: 0x%08x\n", addr);
        stackTraceDisplay(addr);
    } else {
        _ = printf("Panic!\nSource unknown.\n");
    }
}

fn unknownBreakpointDisplay(from_addr: ?u64, bkpt_number: u16) void {
    if (from_addr) |addr| {
        _ = printf("Breakpoint\nComment: 0x%08x\n ELR: 0x%08x\n", bkpt_number, addr);
    } else {
        _ = printf("Breakpoint\nComment: 0x%08x\n ELR: unknown\n", bkpt_number);
    }
}

fn unhandledExceptionDisplay(from_addr: ?u64, entry_type: u64, esr: u64, ec: u6) void {
    if (from_addr) |addr| {
        _ = printf("Unhandled exception!\nType: 0x%08x\n ESR: 0x%08x\n ELR: 0x%08x\n  EC: 0b%06b (%s)\n", entry_type, esr, addr, @as(u8, ec), reg_esr.errorCodeName(ec).ptr);
    } else {
        _ = printf("Unhandled exception!\nType: 0x%08x\n ESR: 0x%08x\n ELR: unknown\n  EC: 0b%06b (%s)\n", entry_type, esr, @as(u8, ec), reg_esr.errorCodeName(ec).ptr);
    }

    // If we are in a test, exit on the first unhandled exception
    const config = @import("config");

    if (!(comptime std.mem.eql(u8, config.testname, ""))) {
        const helpers = @import("../../test/helpers.zig");
        helpers.expect(false);
        helpers.exitWithTestResult();
    }
}

fn stackTraceDisplay(from_addr: u64) void {
    _ = from_addr;
    var it = std.debug.StackIterator.init(null, null);
    defer it.deinit();

    _ = printf("\nStack trace\n");
    _ = printf("Frame\tPC\n");
    for (0..40) |i| {
        const addr = it.next() orelse {
            _ = printf(".\n");
            return;
        };
        stackFrameDisplay(i, addr);
    }
    _ = printf("--stack trace truncated--\n");
}

fn stackFrameDisplay(frame_number: usize, frame_pointer: usize) void {
    _ = printf("%d\t0x%08x\n", frame_number, frame_pointer);
}
