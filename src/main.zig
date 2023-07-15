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
    arch.cpu.mmu2.init();
    arch.cpu.exceptions.init();
    arch.cpu.irq.init();

    bsp.timer.timer_init();
    bsp.io.uart_init();

    var heap_bounds = bsp.memory.get_heap_bounds();
    var heap_allocator = mem.HeapAllocator{
        .first_available = heap_bounds[0],
        .last_available = heap_bounds[1],
    };
    os.page_allocator = heap_allocator.allocator();

    try debug_writer.print("Heap start: 0x{x:0>8}\r\n", .{@intFromPtr(heap_allocator.first_available)});
    try debug_writer.print("Heap end:   0x{x:0>8}\r\n", .{@intFromPtr(heap_allocator.last_available)});

    try print_clock_rate(.emmc);
    try print_clock_rate(.uart);
    try print_clock_rate(.core);
    try print_clock_rate(.arm);

    var fb = bsp.video.FrameBuffer{};
    try fb.set_resolution(1024, 768, 8);

    for (100..200) |x| {
        for (100..200) |y| {
            fb.draw_pixel(x, y, 0x02); // 0x02 - index into the palette
        }
    }

    for (120..180) |x| {
        for (120..180) |y| {
            fb.draw_pixel(x, y, 0x07); // 0x02 - index into the palette
        }
    }

    while (true) {
        var ch: u8 = bsp.io.receive();
        bsp.io.send(ch);
        if (ch == 'q') break;
    }

    // Does not return
    qemu.exit(0);

    unreachable;
}

fn print_clock_rate(clock_type: bsp.mailbox.ClockRate.Clock) !void {
    if (bsp.mailbox.get_clock_rate(clock_type)) |clock| {
        try debug_writer.print("{s} clock: {}\r\n", .{ @tagName(clock_type), clock[1] });
    } else |err| {
        try debug_writer.print("Error getting clock: {}\r\n", .{err});
    }
}

export fn _start_zig(phys_boot_core_stack_end_exclusive: u64) noreturn {
    const registers = arch.cpu.registers;

    registers.SCTLR_EL1.modify(.{
        .MMU_ENABLE = .disable,
        .EE = .little_endian,
        .E0E = .little_endian,
        .I_CACHE = .disabled,
        .D_CACHE = .disabled,
    });

    // this is harmless at the moment, but it lets me get the code
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

    asm volatile ("mov x29, xzr");
    asm volatile ("mov x30, xzr");

    arch.cpu.eret();

    unreachable;
}
