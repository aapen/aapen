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

export fn irqCurrentElx(context: *const ExceptionContext) void {
    root.hal.interrupt_controller.irqHandle(context);
}

// ----------------------------------------------------------------------
// Exception display
// ----------------------------------------------------------------------
const ZIG_PANIC_BREAKPOINT: u16 = 0xf000;

inline fn isBreakpoint(context: *ExceptionContext) bool {
    return context.esr.ec == ErrorCodes.brk;
}

inline fn exceptionIss(context: *ExceptionContext) u16 {
    return @truncate(context.esr.iss & 0xffff);
}

inline fn isPanic(context: *ExceptionContext) bool {
    return isBreakpoint(context) and ZIG_PANIC_BREAKPOINT == exceptionIss(context);
}

export fn synchronousExceptionElx(context: *ExceptionContext) void {
    if (isPanic(context)) {
        panicDisplay(context);
    } else if (isBreakpoint(context)) {
        unknownBreakpointDisplay(context);
    } else {
        unhandledExceptionDisplay(context, 0);
        context.elr += 4;
    }
}

export fn unhandledException(context: *ExceptionContext, entry_type: u64) void {
    unhandledExceptionDisplay(context, entry_type);
    context.elr += 4;
}

fn panicDisplay(context: *ExceptionContext) void {
    _ = printf("[panic]: ELR 0x%08x\n", context.elr);

    var it = std.debug.StackIterator.init(null, null);
    defer it.deinit();

    _ = printf("\nStack trace\n");
    _ = printf("Frame PC\n");
    for (0..40) |i| {
        const addr = it.next() orelse {
            _ = printf(".\n");
            return;
        };
        _ = printf("%02d    0x%08x\n", i, addr);
    }
    _ = printf("--stack trace truncated--\n");
}

fn unknownBreakpointDisplay(context: *ExceptionContext) void {
    const elr = context.elr;
    const bkpt_number: u16 = @truncate(context.esr.iss & 0xffff);

    _ = printf("[breakpoint]: ELR 0x%08x, Type 0x%08x\n", elr, bkpt_number);
}

fn unhandledExceptionDisplay(context: *ExceptionContext, entry_type: u64) void {
    const elr = context.elr;
    const esr = context.esr;
    const ec = esr.ec;

    _ = printf(
        "[exception]: ELR: 0x%08x, Type 0x%08x, ESR 0x%08x, EC 0b%06b (%s)\n",
        elr,
        entry_type,
        @as(u64, @bitCast(esr)),
        @as(u8, ec),
        reg_esr.errorCodeName(ec).ptr,
    );

    // If we are in a test, exit on the first unhandled exception
    const config = @import("config");

    if (!(comptime std.mem.eql(u8, config.testname, ""))) {
        const helpers = @import("../../test/helpers.zig");
        helpers.expect(false);
        helpers.exitWithTestResult();
    }
}
