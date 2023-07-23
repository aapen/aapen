const root = @import("root");

const cpu = @import("../../architecture.zig").cpu;
const bsp = @import("../../bsp.zig");
const registers = @import("registers.zig");

const __exception_handler_table: *u64 = @extern(*u64, .{ .name = "__exception_handler_table" });

pub fn init() void {
    registers.vbar_el1.write(@intFromPtr(__exception_handler_table));
}

/// Context passed in to every exception handler.
/// This is created by the KERNEL_ENTRY macro in `exceptions.s`
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

// TODO Seems odd to have a dependency from the CPU-specific module to
// the screen object. Should this be injected? If so, how?
export fn invalidEntryMessageShow(entry_type: u64, esr: u64, elr: u64) void {
    root.frameBufferConsole.print("Unhandled exception: {x:0>8}\nESR: {x:0>8}\nELR: {x:0>8}\n", .{ entry_type, esr, elr }) catch {};
}

export fn irqCurrentElx(context: *const ExceptionContext) void {
    _ = context;
    cpu.irqDisable();
    defer cpu.irqEnable();

    bsp.interrupts.irqHandle();
}
