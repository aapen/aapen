const root = @import("root");

const cpu = @import("../../architecture.zig").cpu;
const bsp = @import("../../bsp.zig");
const registers = @import("registers.zig");
const Esr = @import("registers/esr.zig").Layout;

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
    lr: u64,

    /// Exception Link Register (PC at the time the exception
    /// happened)
    elr: u64,

    /// Saved Program Status Register
    spsr: u64,

    /// Exception Syndrome Register
    esr: Esr,
};

// TODO Seems odd to have a dependency from the CPU-specific module to
// the screen object. Should this be injected? If so, how?
export fn invalidEntryMessageShow(context: *const ExceptionContext, entry_type: u64) void {
    // Check if this was a breakpoint due to std.builtin.default_panic
    if (context.esr.ec == .brk) {
        // Breakpoint number is the lower 16 bits of ESR's ISS
        var breakpoint_number: u16 = @truncate(context.esr.iss & 0xffff);

        // Zig uses 0xf000 to indicate a panic
        if (breakpoint_number == 0xf000) {
            // Could we get the panic string and arguments from the stack?
            root.frameBufferConsole.print("Panic!\nELR: 0x{x:0>8}\n", .{context.elr}) catch {};
        } else {
            root.frameBufferConsole.print("Breakpoint\nComment: 0x{x:0>8}\n ELR: 0x{x:0>8}\n", .{ breakpoint_number, context.elr }) catch {};
        }
    } else {
        root.frameBufferConsole.print("Unhandled exception!\nType: 0x{x:0>8}\n ESR: 0x{x:0>8}\n ELR: 0x{x:0>8}\n  EC: 0b{b:0>6}\n", .{ entry_type, @as(u64, @bitCast(context.esr)), context.elr, @intFromEnum(context.esr.ec) }) catch {};
    }
}

export fn irqCurrentElx(context: *const ExceptionContext) void {
    _ = context;
    cpu.irqDisable();
    defer cpu.irqEnable();

    bsp.interrupts.irqHandle();
}
