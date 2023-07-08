const std = @import("std");
const arch = @import("architecture.zig");
const bsp = @import("bsp.zig");
const qemu = @import("qemu.zig");

const os = struct {
    .page_allocator = @import("mem.zig"),
};

export fn kernel_init() callconv(.C) void {
    arch.cpu.exceptions.init();
    arch.cpu.mmu.init();
    arch.cpu.irq.init();

    bsp.timer.timer_init();

    bsp.io.uart_init();
    bsp.io.send_string("Hello, world!\n");

    while (true) {
        var ch: u8 = bsp.io.receive();
        bsp.io.send(ch);
        if (ch == 'q') break;
    }

    // Does not return
    qemu.exit(0);

    unreachable;
}

export fn _start_zig(phys_boot_core_stack_end_exclusive: u64) noreturn {
    const registers = arch.cpu.registers;

    // this is harmelss at the moment, but it lets me get the code
    // infrastructure in place to make the EL2 -> EL1 transition
    registers.CNTHCTL_EL2.modify(.{
        .EL1PCEN = .trap_disable,
        .EL1PCTEN = .trap_disable,
    });

    registers.CPACR_EL1.write(.{
        .zen = .trap_none,
        .fpen = .trap_none,
        .tta = .trap_disable,
    });

    registers.CNTVOFF_EL2.write(0);

    registers.HCR_EL2.modify(.{ .RW = .el1_is_aarch64 });

    registers.SPSR_EL2.write(.{
        .M = .el1h,
        .D = .masked,
        .I = .masked,
        .A = .masked,
        .F = .masked,
    });

    // fake a return stack pointer and exception link register to a function
    // this function will begin executing when we do `eret` from here
    registers.ELR_EL2.write(@intFromPtr(&kernel_init));
    registers.SP_EL1.write(phys_boot_core_stack_end_exclusive);

    arch.cpu.eret();

    unreachable;
}
