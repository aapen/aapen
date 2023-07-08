const std = @import("std");
const arch = @import("architecture.zig");
const bsp = @import("bsp.zig");
const debug_writer = bsp.io.debug_writer;
const qemu = @import("qemu.zig");
const mem = @import("mem.zig");

const Freestanding = struct {
    page_allocator: std.mem.Allocator,
};

var os = Freestanding{
    .page_allocator = undefined,
};

fn kernel_init() !void {
    arch.cpu.exceptions.init();
    arch.cpu.mmu.init();
    arch.cpu.irq.init();

    bsp.timer.timer_init();
    bsp.io.uart_init();

    var heap_bounds = bsp.memory.get_heap_bounds();
    var heap_allocator = mem.HeapAllocator{
        .first_available = heap_bounds[0],
        .last_available = heap_bounds[1],
    };
    os.page_allocator = heap_allocator.allocator();

    try debug_writer.print("Heap start: 0x{X:0>8}\n", .{@intFromPtr(heap_allocator.first_available)});
    try debug_writer.print("Heap end:   0x{X:0>8}\n", .{@intFromPtr(heap_allocator.last_available)});

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
