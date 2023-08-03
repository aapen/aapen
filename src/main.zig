const std = @import("std");
const arch = @import("architecture.zig");
const bsp = @import("bsp.zig");
const qemu = @import("qemu.zig");
const mem = @import("mem.zig");
const fbcons = @import("fbcons.zig");
const bcd = @import("bcd.zig");
const forth = @import("ziggy/forth.zig");
const Forth = forth.Forth;

const Freestanding = struct {
    page_allocator: std.mem.Allocator,
};

var os = Freestanding{
    .page_allocator = undefined,
};

const Self = @This();

pub const page_size = arch.cpu.mmu.page_size;

pub var board = bsp.mailbox.BoardInfo{};
pub var heap = mem{};
pub var frame_buffer: bsp.video.FrameBuffer = bsp.video.FrameBuffer{};
pub var frame_buffer_console: fbcons.FrameBufferConsole = fbcons.FrameBufferConsole{ .frame_buffer = &frame_buffer };
pub var interpreter: Forth = Forth{ .console = &frame_buffer_console };

fn kernelInit() !void {
    // State: one core, no interrupts, no MMU, no heap Allocator, no display, no serial
    arch.cpu.mmuInit();
    arch.cpu.exceptionInit();
    arch.cpu.irqInit();

    // State: one core, interrupts, MMU, no heap Allocator, no display, no serial
    // bsp.timer.timerInit();
    bsp.io.uartInit();

    heap.init(page_size);

    os.page_allocator = heap.allocator();

    board.read() catch {};

    // State: one core, interrupts, MMU, heap Allocator, no display, serial

    frame_buffer.setResolution(1024, 768, 8) catch |err| {
        bsp.io.uart_writer.print("Error initializing framebuffer: {any}\n", .{err}) catch {};
    };

    frame_buffer_console.init();

    try frame_buffer_console.print("Running on {s} (a {s}) with {?}MB\n\n", .{
        board.model.name,
        board.model.processor,
        board.model.memory,
    });
    try frame_buffer_console.print("    MAC address: {?}\n", .{board.device.mac_address});
    try frame_buffer_console.print("  Serial number: {?}\n", .{board.device.serial_number});
    try frame_buffer_console.print("Manufactured by: {?s}\n", .{board.device.manufacturer});

    // Attempt to power up the USB
    var usb_power_result = bsp.mailbox.powerOn(.usb_hcd) catch bsp.mailbox.power.Result.failed;
    try frame_buffer_console.print("   Power on USB: {s}\n\n", .{@tagName(usb_power_result)});

    // State: one core, interrupts, MMU, heap Allocator, display, serial
    diagnostics() catch |err| {
        frame_buffer_console.print("Error printing diagnostics: {any}\n", .{err}) catch {};
        bsp.io.uart_writer.print("Error printing diagnostics: {any}\n", .{err}) catch {};
    };

    bsp.usb.init();

    interpreter.init(os.page_allocator) catch |err| {
        try frame_buffer_console.print("Forth init: {any}\n", .{err});
    };

    interpreter.define_core() catch |err| {
        try frame_buffer_console.print("Forth define core: {any}\n", .{err});
    };

    // interpret embedded startup file
    interpreter.evalBuffer(forth.init_f) catch |err| {
        try frame_buffer_console.print("Forth eval buffer: {any}\n", .{err});
    };

    interpreter.repl() catch |err| {
        try frame_buffer_console.print("REPL error: {any}\n\nABORT.\n", .{err});
    };

    // Does not return
    qemu.exit(0);

    unreachable;
}

fn diagnostics() !void {
    try board.arm_memory.print(&frame_buffer_console);
    try board.videocore_memory.print(&frame_buffer_console);
    try heap.memory.print(&frame_buffer_console);
    try frame_buffer.memory.print(&frame_buffer_console);

    try printClockRate(.uart);
    try printClockRate(.emmc);
    try printClockRate(.core);
    try printClockRate(.arm);

    try printPowerState(.usb_hcd);
}

fn printClockRate(clock_type: bsp.mailbox.Clock) !void {
    var rate = bsp.mailbox.getClockRate(clock_type) catch 0;
    var clock_mhz = rate / 1_000_000;
    try frame_buffer_console.print("{s:>14} clock: {} MHz \n", .{ @tagName(clock_type), clock_mhz });
}

fn printPowerState(device: bsp.mailbox.PowerDevice) !void {
    var state = bsp.mailbox.isPowered(device) catch .failed;
    try frame_buffer_console.print("{s:>14} power: {s}\n", .{ @tagName(device), @tagName(state) });
}

export fn _soft_reset() noreturn {
    kernelInit() catch {};

    unreachable;
}

export fn _start_zig(phys_boot_core_stack_end_exclusive: u64) noreturn {
    const registers = arch.cpu.registers;

    registers.sctlr_el1.write(.{
        .mmu_enable = .disable,
        .a = .disable,
        .sa = 0,
        .sa0 = 0,
        .naa = .trap_disable,
        .ee = .little_endian,
        .e0e = .little_endian,
        .i_cache = .disabled,
        .d_cache = .disabled,
        .wxn = 0,
    });

    // this is harmless at the moment, but it lets me get the code
    // infrastructure in place to make the EL2 -> EL1 transition
    registers.cnthctl_el2.modify(.{
        .el1pcen = .trap_disable,
        .el1pcten = .trap_disable,
    });

    // Zig and LLVM like to use vector registers. Must not trap on the
    // SIMD/FPE instructions for that to work.
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

//     frame_buffer_console.print(msg, .{}) catch {};
//     while (true) {
//         arch.cpu.wfe();
//     }

//     unreachable;
// }
