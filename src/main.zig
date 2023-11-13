const std = @import("std");
const config = @import("config");

const arch = @import("architecture.zig");
const qemu = @import("qemu.zig");

const Heap = @import("heap.zig");
const FrameBuffer = @import("frame_buffer.zig");
const FrameBufferConsole = @import("fbcons.zig");

const bcd = @import("bcd.zig");
const synchronize = @import("synchronize.zig");
const Spinlock = synchronize.Spinlock;

const forty = @import("forty/forth.zig");
const Forth = forty.Forth;

pub const debug = @import("debug.zig");
pub const kprint = debug.kprint;

const raspi3 = @import("hal/raspi3.zig");
pub const HAL = switch (config.board) {
    .pi3 => @import("hal/raspi3.zig"),
    inline else => @compileError("Unsupported board " ++ @tagName(config.board)),
};
const diagnostics = @import("hal/diagnostics.zig");

pub const std_options = struct {
    pub const log_level = .warn;
    pub const logFn = debug.log;
};

const Freestanding = struct {
    page_allocator: std.mem.Allocator,
};

var os: Freestanding = undefined;

pub var heap: *Heap = undefined;
pub var hal: *HAL = undefined;
pub var fb: *FrameBuffer = undefined;
pub var frame_buffer_console: *FrameBufferConsole = undefined;

pub var interpreter: Forth = Forth{};
pub var global_unwind_point = arch.cpu.exceptions.UnwindPoint{
    .sp = undefined,
    .pc = undefined,
    .fp = undefined,
    .lr = undefined,
};

pub var message_ring_valid = false;
pub var uart_valid = false;
pub var console_valid = false;

fn kernelInit() void {
    // State: one core, no interrupts, no MMU, no heap Allocator, no
    // display, serial
    arch.cpu.mmu.init();

    // Needed for enter/leave critical sections
    arch.cpu.fiqEnable();

    if (debug.init()) {
        debug.kernel_message("init");
        message_ring_valid = true;
    } else |_| {
        // not much we can do here
    }

    if (Heap.init()) |h| {
        debug.kernel_message("heap init");
        heap = h;
    } else |err| {
        debug.kernel_error("heap init error", err);
    }

    os = Freestanding{
        .page_allocator = heap.allocator,
    };

    if (HAL.init(heap.allocator)) |h| {
        debug.kernel_message("hal init");
        hal = h;
        uart_valid = true;
    } else |err| {
        debug.kernel_error("hal init error", err);
    }

    // State: one core, no interrupts, MMU, heap Allocator, no
    // display, serial
    if (arch.cpu.exceptions.init()) {
        debug.kernel_message("exceptions init");
    } else |err| {
        debug.kernel_error("exceptions init error", err);
    }

    // State: one core, interrupts, MMU, heap Allocator, no display,
    // serial
    if (FrameBuffer.init(heap.allocator, hal)) |buf| {
        debug.kernel_message("frame buffer init");
        fb = buf;
    } else |err| {
        debug.kernel_error("frame buffer init error", err);
    }

    if (FrameBufferConsole.init(heap.allocator, fb, &hal.serial)) |cons| {
        debug.kernel_message("fbcons init");
        frame_buffer_console = cons;
        console_valid = true;
    } else |err| {
        debug.kernel_error("fbcons init error", err);
    }

    // State: one core, interrupts, MMU, heap Allocator, display,
    // serial
    if (diagnostics.init(heap.allocator)) {
        debug.kernel_message("diagnostics init");
    } else |err| {
        debug.kernel_error("diagnostics init error", err);
    }

    if (hal.usb.hostControllerInitialize()) {
        debug.kernel_message("USB host init");
    } else |err| {
        debug.kernel_error("USB host init error", err);
    }

    if (interpreter.init(heap.allocator, frame_buffer_console)) {
        debug.kernel_message("Forth init");
    } else |err| {
        debug.kernel_error("Forth init error", err);
    }

    // TODO should this move to forty/core.zig?
    supplyAddress("fbcons", @intFromPtr(frame_buffer_console));
    supplyAddress("fb", @intFromPtr(fb));
    supplyAddress("hal", @intFromPtr(hal));
    supplyAddress("board", @intFromPtr(&diagnostics.board));
    supplyAddress("mring", @intFromPtr(&debug.mring_storage));

    arch.cpu.exceptions.markUnwindPoint(&global_unwind_point);
    global_unwind_point.pc = @as(u64, @intFromPtr(&repl));

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
            std.log.err("REPL error: {any}\n\nABORT.\n", .{err});
        };
    }
}

fn supplyAddress(name: []const u8, addr: usize) void {
    interpreter.defineConstant(name, addr) catch |err| {
        std.log.warn("Failed to define {s}: {any}\n", .{ name, err });
    };
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

const StackTrace = std.builtin.StackTrace;

pub fn panic(msg: []const u8, stack: ?*StackTrace, return_addr: ?usize) noreturn {
    @setCold(true);

    if (return_addr) |ret| {
        kprint("[{x:0>8}] {s}\n", .{ ret, msg });
    } else {
        kprint("[unknown] {s}\n", .{msg});
    }

    if (stack) |stack_trace| {
        for (stack_trace.instruction_addresses, 0..) |addr, i| {
            kprint("{d}: {x:0>8}\n", .{ i, addr });
        }
    }

    @breakpoint();

    unreachable;
}

// The assembly portion of soft reset (does the stack magic)
pub extern fn _soft_reset(resume_address: u64) noreturn;

pub fn resetSoft() noreturn {
    _soft_reset(@intFromPtr(&kernelInit));
}
