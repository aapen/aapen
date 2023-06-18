const std = @import("std");
const cpu = @import("architecture").cpu;
const io = @import("bsp").io;

const kernel_stack_end: *u8 = @extern(*u8, .{ .name = "__boot_core_stack_end_exclusive" });

fn transition_to_el1() void {
    // this is harmelss at the moment, but it lets me get the code
    // infrastructure in place to make the EL2 -> EL1 transition
    cpu.registers.CNTHCTL_EL2.modify(.{
        .EL1PCEN = .trap_disable,
        .EL1PCTEN = .trap_disable,
    });

    cpu.registers.CPACR_EL1.write(.{
        .zen = .trap_none,
        .fpen = .trap_none,
        .tta = .trap_disable,
    });

    cpu.registers.CNTVOFF_EL2.write(0);

    cpu.registers.HCR_EL2.modify(.{ .RW = .el1_is_aarch64 });

    cpu.registers.SPSR_EL2.write(.{
        .M = .el1h,
        .D = .masked,
        .I = .masked,
        .A = .masked,
        .F = .masked,
    });

    // fake a return stack pointer to a function
    // this function will begin executing when we do `eret` from here
    cpu.registers.ELR_EL2.write(@ptrToInt(&kernel_init));

    cpu.registers.SP_EL1.write(@ptrToInt(kernel_stack_end));

    cpu.eret();
}

fn kernel_init() callconv(.C) u8 {
    io.pl011_uart_init();
    io.pl011_uart_write_text("Hello, world!\n");

    cpu.time.spin(cpu.time.Duration{ .seconds = 1 }) catch unreachable;

    io.pl011_uart_write_text("... and hello again\n");

    return 0;
}

export fn kernel_main() callconv(.C) void {
    transition_to_el1();
    // unreachable
}
