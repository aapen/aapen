const cpu = @import("architecture").cpu;
const io = @import("bsp").io;

export fn kernel_main() callconv(.C) u8 {
    // this is harmelss at the moment, but it lets me get the code
    // infrastructure in place to make the EL2 -> EL1 transition
    cpu.registers.CNTHCTL_EL2.modify(.{
        .EL1PCEN = .trap_disable,
        .EL1PCTEN = .trap_disable,
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

    io.pl011_uart_init();
    io.pl011_uart_write_text("Hello, world!\n");

    cpu.time.spin(cpu.time.Duration{ .seconds = 1 }) catch unreachable;

    io.pl011_uart_write_text("... and hello again\n");

    return 0;
}