// TODO: Is this really the right thing to do? Seems very odd to have
// the directory traversal here!
const bsp = @import("../../bsp.zig");
const io = bsp.io;
const registers = @import("registers.zig");
const irq = @import("irq.zig");

const __exception_handler_table: *u64 = @extern(*u64, .{ .name = "__exception_handler_table" });

pub fn init() void {
    registers.VBAR_EL1.write(@intFromPtr(__exception_handler_table));
}

pub const DebugWrite = fn ([]const u8) void;

// TODO: This induces a dependency from the CPU architecture module to
// the board support module. That seems very strange. There's got to
// be a better way to inject the output writer here.
pub const debug_write: DebugWrite = io.pl011_uart_write_text;

/// Context passed in to every exception handler.
/// This is created by the EXC_HANDLER macro in `exceptions.s`
const ExceptionContext = struct {
    /// General purpose registers' stored state
    gpr: [30]u64,

    /// Link Register (a.k.a. x30)
    link_register: u64,

    /// Exception Link Register (PC at the time the exception
    /// happened)
    elr: u64,

    /// Saved Program Status Register
    spsr: u64,

    /// Exception Syndrome Register
    esr: u64,
};

pub fn default_exception_handler(context: *const ExceptionContext) void {
    _ = context;
    debug_write("Unhandled exception.\n");
}

/// Stub functions for the various ways of getting an exception
export fn current_el0_synchronous(context: *const ExceptionContext) void {
    default_exception_handler(context);
}

export fn current_el0_irq(context: *const ExceptionContext) void {
    default_exception_handler(context);
}

export fn current_el0_serror(context: *const ExceptionContext) void {
    default_exception_handler(context);
}

export fn current_elx_synchronous(context: *const ExceptionContext) void {
    default_exception_handler(context);
}

export fn current_elx_irq(context: *const ExceptionContext) void {
    _ = context;
    irq.disable();
    defer irq.enable();

    bsp.interrupts.handle_irq();
}

export fn current_elx_serror(context: *const ExceptionContext) void {
    default_exception_handler(context);
}

export fn lower_aarch64_synchronous(context: *const ExceptionContext) void {
    default_exception_handler(context);
}

export fn lower_aarch64_irq(context: *const ExceptionContext) void {
    default_exception_handler(context);
}

export fn lower_aarch64_serror(context: *const ExceptionContext) void {
    default_exception_handler(context);
}

export fn lower_aarch32_synchronous(context: *const ExceptionContext) void {
    default_exception_handler(context);
}

export fn lower_aarch32_irq(context: *const ExceptionContext) void {
    default_exception_handler(context);
}

export fn lower_aarch32_serror(context: *const ExceptionContext) void {
    default_exception_handler(context);
}
