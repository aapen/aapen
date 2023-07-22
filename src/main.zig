const std = @import("std");
const arch = @import("architecture.zig");
const bsp = @import("bsp.zig");
const qemu = @import("qemu.zig");
const mem = @import("mem.zig");
const interp = @import("interp.zig");
const fbcons = @import("fbcons.zig");

const Freestanding = struct {
    page_allocator: std.mem.Allocator,
};

var os = Freestanding{
    .page_allocator = undefined,
};

const Self = @This();

// pub var console: fbcons.FrameBufferConsole.Writer = undefined;
pub var frameBufferConsole: fbcons.FrameBufferConsole = undefined;
pub var interpreter: interp.Interpreter = undefined;

fn kernel_init() !void {
    // State: one core, no interrupts, no MMU, no Allocator, no display, no serial
    arch.cpu.mmu2.init();
    arch.cpu.exceptions.init();
    arch.cpu.irq.init();

    // State: one core, interrupts, MMU, no Allocator, no display, no serial
    bsp.timer.timer_init();
    bsp.io.uart_init();

    var heap = bsp.memory.create_greedy(arch.cpu.mmu2.PAGE_SIZE);

    var heap_allocator = heap.allocator();
    os.page_allocator = heap_allocator.allocator();

    // State: one core, interrupts, MMU, Allocator, no display, serial

    var fb = bsp.video.FrameBuffer{};
    fb.set_resolution(1024, 768, 8) catch |err| {
        bsp.io.uart_writer.print("Error initializing framebuffer: {any}\n", .{err}) catch {};
    };

    var fb_console = fbcons.FrameBufferConsole.init(&fb, 1024, 768);

    // console = fb_console.writer();

    // State: one core, interrupts, MMU, Allocator, display, serial
    diagnostics(&fb_console, &heap) catch |err| {
        fb_console.print("Error printing diagnostics: {any}\n", .{err}) catch {};
        bsp.io.uart_writer.print("Error printing diagnostics: {any}\n", .{err}) catch {};
    };

    interpreter = interp.Interpreter{
        .console = &fb_console,
        // .writer = &console,
    };

    while (true) {
        interpreter.execute() catch |err| {
            try fb_console.print("{any}\n", .{err});
        };
    }

    // Does not return
    qemu.exit(0);

    unreachable;
}

fn diagnostics(fb_console: *fbcons.FrameBufferConsole, heap: *mem.Heap) !void {
    var board = bsp.mailbox.BoardInfo{};

    try board.read();

    try fb_console.print("Booted...\n", .{});
    try fb_console.print("Running on {s} (a {s}) with {?}MB\n\n", .{ board.model.name, board.model.processor, board.model.memory });
    try fb_console.print("    MAC address: {?}\n", .{board.device.mac_address});
    try fb_console.print("  Serial number: {?}\n", .{board.device.serial_number});
    try fb_console.print("Manufactured by: {?s}\n\n", .{board.device.manufacturer});

    try board.arm_memory.print(fb_console);
    try board.videocore_memory.print(fb_console);
    try heap.memory.print(fb_console);

    try print_clock_rate(fb_console, .uart);
    try print_clock_rate(fb_console, .emmc);
    try print_clock_rate(fb_console, .core);
    try print_clock_rate(fb_console, .arm);
}

fn print_clock_rate(fb_console: *fbcons.FrameBufferConsole, clock_type: bsp.mailbox.ClockRate.Clock) !void {
    var clock = try bsp.mailbox.get_clock_rate(clock_type);
    var clock_mhz = clock[1] / 1_000_000;
    try fb_console.print("{s:>14} clock: {} MHz\n", .{ @tagName(clock_type), clock_mhz });
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

// TODO: re-enable this when
// https://github.com/ziglang/zig/issues/16327 is fixed.

// pub fn panic(msg: []const u8, stack: ?*std.builtin.StackTrace, return_addr: ?usize) noreturn {
//     _ = stack;
//     _ = return_addr;

//     console.print(msg, .{}) catch {};
//     while (true) {}

//     unreachable;
// }
