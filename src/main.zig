const std = @import("std");
const arch = @import("architecture.zig");
const bsp = @import("bsp.zig");
const qemu = @import("qemu.zig");
const mem = @import("mem.zig");
const fbcons = @import("fbcons.zig");
const bcd = @import("bcd.zig");
const forty = @import("forty/forth.zig");
const Forth = forty.Forth;
const debug = @import("debug.zig");
pub const devicetree = @import("devicetree.zig");

pub const kinfo = debug.kinfo;
pub const kwarn = debug.kwarn;
pub const kerror = debug.kerror;
pub const kprint = debug.kprint;

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
pub var interpreter: Forth = Forth{};
pub var fdt: devicetree.Fdt = devicetree.Fdt{};

fn kernelInit() void {
    // State: one core, no interrupts, no MMU, no heap Allocator, no display, no serial
    arch.cpu.mmuInit();

    heap.init(page_size);
    os.page_allocator = heap.allocator();

    // State: one core, no interrupts, MMU, heap Allocator, no display, no serial
    arch.cpu.exceptionInit();
    arch.cpu.irqInit();

    // State: one core, interrupts, MMU, heap Allocator, no display, no serial
    // bsp.timer.timerInit();
    bsp.io.uartInit();

    board.read() catch {};

    // State: one core, interrupts, MMU, heap Allocator, no display, serial

    frame_buffer.setResolution(1024, 768, 8) catch |err| {
        bsp.io.uart_writer.print("Error initializing framebuffer: {any}\n", .{err}) catch {};
    };

    frame_buffer_console.init();

    // State: one core, interrupts, MMU, heap Allocator, display,
    // serial, logging available

    fdt.init(os.page_allocator) catch |err| {
        kerror(@src(), "Unable to initialize device tree. Things are likely to break: {any}\n", .{err});
    };

    kprint("Running on {s} (a {s}) with {?}MB\n\n", .{
        board.model.name,
        board.model.processor,
        board.model.memory,
    });
    kprint("    MAC address: {?}\n", .{board.device.mac_address});
    kprint("  Serial number: {?}\n", .{board.device.serial_number});
    kprint("Manufactured by: {?s}\n\n", .{board.device.manufacturer});

    diagnostics() catch |err| {
        kerror(@src(), "Error printing diagnostics: {any}\n", .{err});
        bsp.io.uart_writer.print("Error printing diagnostics: {any}\n", .{err}) catch {};
    };

    bsp.usb.init();

    // sampleDeviceTree();

    interpreter.init(os.page_allocator, &frame_buffer_console) catch |err| {
        kerror(@src(), "Forth init: {any}\n", .{err});
    };

    supplyAddress("fb", @intFromPtr(frame_buffer.base));
    supplyUsize("fbsize", frame_buffer.buffer_size);
    supplyAddress("fdt", devicetree.__fdt_address);

    arch.cpu.exceptions.markUnwindPoint(&arch.cpu.exceptions.global_unwind_point);
    arch.cpu.exceptions.global_unwind_point.pc = @as(u64, @intFromPtr(&repl));

    // State: one core, interrupts, MMU, heap Allocator, display,
    // serial, logging available, exception recovery available
    repl();

    // Does not return
    qemu.exit(0);

    unreachable;
}

fn repl() callconv(.C) noreturn {
    while (true) {
        interpreter.repl() catch |err| {
            kerror(@src(), "REPL error: {any}\n\nABORT.\n", .{err});
        };
    }
}

// TODO do we need both of these now?

fn supplyAddress(name: []const u8, addr: usize) void {
    interpreter.defineConstant(name, addr) catch |err| {
        kwarn(@src(), "Failed to define {s}: {any}\n", .{ name, err });
    };
}

fn supplyUsize(name: []const u8, sz: usize) void {
    interpreter.defineConstant(name, sz) catch |err| {
        kwarn(@src(), "Failed to define {s}: {any}\n", .{ name, err });
    };
}

fn sampleDeviceTree() void {
    kprint("\nDevice tree diagnostics\n", .{});
    reportDeviceTreeNode("soc");
    reportDeviceTreeNode("reserved-memory");
    reportDeviceTreeNode("thermal-zones/cpu-thermal");
    reportDeviceTreeNode("soc/usb@7e980000/usb1@1/ethernet@1");
}

pub fn reportDeviceTreeNode(path: [:0]const u8) void {
    const node = fdt.nodeLookupByPath(path) catch |err| blk: {
        kprint("Error looking up {s}: {any}\n", .{ path, err });
        break :blk null;
    };

    if (node) |n| {
        kprint("{s:>40}: offset: {d}\tchildren: {d}\tproperties: {d}\n", .{ path, n.offset, n.children.items.len, n.properties.items.len });
    } else {
        kprint("{s:>40}: not found.\n", .{path});
    }
}

fn diagnostics() !void {
    try board.arm_memory.print();
    try board.videocore_memory.print();
    try heap.memory.print();
    try frame_buffer.memory.print();

    try printClockRate(.uart);
    try printClockRate(.emmc);
    try printClockRate(.core);
    try printClockRate(.arm);
}

fn printClockRate(clock_type: bsp.mailbox.Clock) !void {
    var rate = bsp.mailbox.getClockRate(clock_type) catch 0;
    var clock_mhz = rate / 1_000_000;
    kprint("{s:>14} clock: {} MHz \n", .{ @tagName(clock_type), clock_mhz });
}

export fn _soft_reset() noreturn {
    kernelInit();

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

//     kerror(@src(), msg, .{});
//     while (true) {
//         arch.cpu.wfe();
//     }

//     unreachable;
// }
