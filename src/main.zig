const std = @import("std");
const arch = @import("architecture.zig");
const bsp = @import("bsp.zig");
const qemu = @import("qemu.zig");
const mem = @import("mem.zig");
const interp = @import("interp.zig");
const fbcons = @import("fbcons.zig");
const bcd = @import("bcd.zig");

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

fn kernelInit() !void {
    // State: one core, no interrupts, no MMU, no Allocator, no display, no serial
    arch.cpu.mmuInit();
    arch.cpu.exceptionInit();
    arch.cpu.irqInit();

    // State: one core, interrupts, MMU, no Allocator, no display, no serial
    bsp.timer.timerInit();
    bsp.io.uartInit();

    var heap = bsp.memory.createGreedy(arch.cpu.mmu2.page_size);

    var heap_allocator = heap.allocator();
    os.page_allocator = heap_allocator.allocator();

    // State: one core, interrupts, MMU, Allocator, no display, serial

    var fb = bsp.video.FrameBuffer{};
    fb.setResolution(1024, 768, 8) catch |err| {
        bsp.io.uart_writer.print("Error initializing framebuffer: {any}\n", .{err}) catch {};
    };

    var fb_console = fbcons.FrameBufferConsole.init(&fb, 1024, 768);

    // console = fb_console.writer();

    // State: one core, interrupts, MMU, Allocator, display, serial
    diagnostics(&fb_console, &fb, &heap) catch |err| {
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

fn diagnostics(fb_console: *fbcons.FrameBufferConsole, fb: *bsp.video.FrameBuffer, heap: *mem.Heap) !void {
    var board = bsp.mailbox.BoardInfo{};

    board.read() catch {};

    try fb_console.print("Booted...\n", .{});
    try fb_console.print("Running on {s} (a {s}) with {?}MB\n\n", .{ board.model.name, board.model.processor, board.model.memory });
    try fb_console.print("    MAC address: {?}\n", .{board.device.mac_address});
    try fb_console.print("  Serial number: {?}\n", .{board.device.serial_number});
    try fb_console.print("Manufactured by: {?s}\n\n", .{board.device.manufacturer});

    try board.arm_memory.print(fb_console);
    try board.videocore_memory.print(fb_console);
    try heap.memory.print(fb_console);
    try fb.memory.print(fb_console);

    try printClockRate(fb_console, .uart);
    try printClockRate(fb_console, .emmc);
    try printClockRate(fb_console, .core);
    try printClockRate(fb_console, .arm);

    try fb_console.print("\nxHCI capability length: {}\n", .{bsp.usb.xhci_capability_register_base.read().length});
    try fb_console.print("xHCI version: {any}\n", .{bcd.decode(u16, bsp.usb.xhci_capability_register_base.read().hci_version)});
}

fn printClockRate(fb_console: *fbcons.FrameBufferConsole, clock_type: bsp.mailbox.ClockRate.Clock) !void {
    var rate = bsp.mailbox.getClockRate(clock_type) catch 0;
    var clock_mhz = rate / 1_000_000;
    try fb_console.print("{s:>14} clock: {} MHz \n", .{ @tagName(clock_type), clock_mhz });
}

export fn _start_zig(phys_boot_core_stack_end_exclusive: u64) noreturn {
    const registers = arch.cpu.registers;

    registers.sctlr_el1.modify(.{
        .mmu_enable = .disable,
        .ee = .little_endian,
        .e0e = .little_endian,
        .i_cache = .disabled,
        .d_cache = .disabled,
    });

    // this is harmless at the moment, but it lets me get the code
    // infrastructure in place to make the EL2 -> EL1 transition
    registers.cnthctl_el2.modify(.{
        .el1pcen = .trap_disable,
        .el1pcten = .trap_disable,
    });

    registers.cpacr_el1.write(.{
        .zen = .trap_none,
        .fpen = .trap_none,
        .tta = .trap_disable,
    });

    registers.cntvoff_el2.write(0);

    registers.hcr_el2.modify(.{ .rw = .el1_is_aarch64 });

    registers.spsr_el2.write(.{
        .m = .el1h,
        .d = .masked,
        .i = .masked,
        .a = .masked,
        .f = .masked,
    });

    // fake a return stack pointer and exception link register to a function
    // this function will begin executing when we do `eret` from here
    registers.elr_el2.write(@intFromPtr(&kernelInit));
    registers.sp_el1.write(phys_boot_core_stack_end_exclusive);

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
