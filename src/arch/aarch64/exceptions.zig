const root = @import("root");
const debug = @import("../../debug.zig");
const cpu = @import("../../architecture.zig").cpu;
const hal = @import("../../hal.zig");
const registers = @import("registers.zig");
const Esr = @import("registers/esr.zig").Layout;

const __exception_handler_table: *u64 = @extern(*u64, .{ .name = "__exception_handler_table" });

pub const UnwindPoint = struct {
    sp: u64 = undefined,
    pc: u64 = undefined,
    fp: u64 = undefined,
    lr: u64 = undefined,
};

pub var global_unwind_point = UnwindPoint{};

pub extern fn markUnwindPoint(point: *UnwindPoint) void;

const IrqHandler = *const fn (context: *const ExceptionContext) void;

pub fn init(handler: IrqHandler) void {
    registers.vbar_el1.write(@intFromPtr(__exception_handler_table));
    irq_handler = handler;
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

// TODO Seems odd to have a dependency from the CPU-specific module to
// the screen object. Should this be injected? If so, how?
export fn invalidEntryMessageShow(context: *ExceptionContext, entry_type: u64) void {
    // Check if this was a breakpoint due to std.builtin.default_panic
    if (context.esr.ec == .brk) {
        // Breakpoint number is the lower 16 bits of ESR's ISS
        var breakpoint_number: u16 = @truncate(context.esr.iss & 0xffff);

        // Zig uses 0xf000 to indicate a panic
        if (breakpoint_number == 0xf000) {
            // Could we get the panic string and arguments from the
            // stack?
            debug.panicDisplay(context.elr);
            if (global_unwind_point.sp != undefined) {
                context.elr = global_unwind_point.pc;
                context.force_sp = global_unwind_point.sp;
                context.lr = global_unwind_point.lr;
                context.gpr[29] = global_unwind_point.fp;
            }
        } else {
            debug.unknownBreakpointDisplay(context.elr, breakpoint_number);
        }
    } else {
        debug.unhandledExceptionDisplay(context.elr, entry_type, @as(u64, @bitCast(context.esr)), context.esr.ec);
    }
}

var irq_handler: ?IrqHandler = null;

export fn irqCurrentElx(context: *const ExceptionContext) void {
    if (irq_handler != null) {
        irq_handler.?(context);
    }
}

pub fn irqDisable() void {
    asm volatile ("msr daifset, #2");
}

pub fn irqEnable() void {
    asm volatile ("msr daifclr, #2");
}
