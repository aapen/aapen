const std = @import("std");
const ScopeLevel = std.log.ScopeLevel;

const arch = @import("architecture.zig");
const qemu = @import("qemu.zig");

const Heap = @import("heap.zig");
const FrameBuffer = @import("frame_buffer.zig");
const CharBuffer = @import("char_buffer.zig");
const CharBufferConsole = @import("char_buffer_console.zig");
const MainConsole = @import("main_console.zig");
const Rectangle = @import("rectangle.zig").Rectangle;

pub const debug = @import("debug.zig");
pub const kprint = debug.kprint;

const synchronize = @import("synchronize.zig");
const Spinlock = synchronize.Spinlock;

const forty = @import("forty/forth.zig");
pub const Forth = forty.Forth;

const Serial = @import("serial.zig"); //TBD

const Usb = @import("usb.zig");

const config = @import("config");
pub const HAL = switch (config.board) {
    .pi3 => @import("hal/raspi3.zig"),
    inline else => @compileError("Unsupported board " ++ @tagName(config.board)),
};
const diagnostics = @import("hal/diagnostics.zig");

pub const std_options = struct {
    pub const logFn = debug.log;
    pub const log_level = .warn;
    pub const log_scope_levels = &[_]ScopeLevel{
        .{ .scope = .dwc_otg_usb, .level = .info },
        .{ .scope = .dwc_otg_usb_channel, .level = .info },
        .{ .scope = .usb, .level = .info },
        .{ .scope = .forty, .level = .debug },
    };
};

const Freestanding = struct {
    page_allocator: std.mem.Allocator,
};

var os: Freestanding = undefined;

pub var heap: *Heap = undefined;
pub var hal: *HAL = undefined;
pub var fb: *FrameBuffer = undefined;
pub var char_buffer_console: *CharBufferConsole = undefined;
pub var char_buffer: *CharBuffer = undefined;
pub var main_console: *MainConsole = undefined;

pub var interpreter: Forth = Forth{};
pub var global_unwind_point = arch.cpu.exceptions.UnwindPoint{
    .sp = undefined,
    .pc = undefined,
    .fp = undefined,
    .lr = undefined,
};

pub var message_ring_valid = false;
pub var uart_valid = false;
pub var char_buffer_console_valid = false;
pub var main_console_valid = false;

fn kernelInit() void {
    // State: one core, no interrupts, no MMU, no heap Allocator, no
    // display, serial
    arch.cpu.mmu.init();

    // Needed for enter/leave critical sections
    arch.cpu.fiqEnable();

    if (debug.init()) {
        debug.kernelMessage("init");
        message_ring_valid = true;
    } else |_| {
        // not much we can do here
    }

    if (Heap.init()) |h| {
        debug.kernelMessage("heap init");
        heap = h;
    } else |err| {
        debug.kernelError("heap init error", err);
    }

    os = Freestanding{
        .page_allocator = heap.allocator,
    };

    if (HAL.init(heap.allocator)) |h| {
        debug.kernelMessage("hal init");
        hal = h;
        uart_valid = true;
    } else |err| {
        debug.kernelError("hal init error", err);
    }

    // State: one core, no interrupts, MMU, heap Allocator, no
    // display, serial
    if (arch.cpu.exceptions.init()) {
        debug.kernelMessage("exceptions init");
    } else |err| {
        debug.kernelError("exceptions init error", err);
    }

    // State: one core, interrupts, MMU, heap Allocator, no display,
    // serial
    if (FrameBuffer.init(heap.allocator, hal)) |buf| {
        debug.kernelMessage("frame buffer init");
        fb = buf;
    } else |err| {
        debug.kernelError("frame buffer init error", err);
    }

    if (CharBuffer.init(heap.allocator, fb)) |cb| {
        debug.kernelMessage("char buffer init");
        char_buffer = cb;
    } else |err| {
        debug.kernelError("char buffer init error", err);
    }

    if (CharBufferConsole.init(heap.allocator, char_buffer)) |cbc| {
        debug.kernelMessage("fbcons init");
        char_buffer_console = cbc;
        char_buffer_console_valid = true;
    } else |err| {
        debug.kernelError("fbcons init error", err);
    }

    if (MainConsole.init(heap.allocator, char_buffer_console)) |c| {
        debug.kernelMessage("console init");
        main_console = c;
        main_console_valid = true;
    } else |err| {
        debug.kernelError("console init error", err);
    }

    // State: one core, interrupts, MMU, heap Allocator, display,
    // serial
    if (diagnostics.init(heap.allocator)) {
        debug.kernelMessage("diagnostics init");
    } else |err| {
        debug.kernelError("diagnostics init error", err);
    }

    // if (Usb.init(heap.allocator)) |_| {
    //     debug.kernelMessage("USB core init");
    // } else |err| {
    //     debug.kernelError("USB core init error", err);
    // }

    if (interpreter.init(heap.allocator, main_console, char_buffer)) {
        debug.kernelMessage("Forth init");
    } else |err| {
        debug.kernelError("Forth init error", err);
    }

    hal.system_timer.schedule(heartbeat_interval, &heartbeat);

    debug.defineModule(&interpreter) catch |err| {
        debug.kernelError("Debug ring define module", err);
    };

    HAL.defineModule(&interpreter, hal) catch |err| {
        debug.kernelError("HAL define module", err);
    };

    diagnostics.defineModule(&interpreter) catch |err| {
        debug.kernelError("diagnostics define module", err);
    };

    Usb.defineModule(&interpreter) catch |err| {
        debug.kernelError("USB define module", err);
    };

    FrameBuffer.defineModule(&interpreter, fb) catch |err| {
        debug.kernelError("Frame buffer define module", err);
    };

    CharBuffer.defineModule(&interpreter, char_buffer) catch |err| {
        debug.kernelError("Char buffer define module", err);
    };

    MainConsole.defineModule(&interpreter, main_console) catch |err| {
        debug.kernelError("Main console define module", err);
    };

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

const heartbeat_interval: u32 = 600_000;
const heartbeat: HAL.TimerHandler = .{
    .callback = showHeartbeat,
};

fn showHeartbeat(_: *const HAL.TimerHandler, _: *const HAL.Timer) u32 {
    var ch = char_buffer.charGet(0, 0);
    if (ch >= 65) {
        ch = ((ch - 64) % 26) + 65;
    } else {
        ch = 65;
    }
    char_buffer.charSet(0, 0, ch);
    char_buffer.renderRect(Rectangle.init(0, 1, 0, 1));

    return heartbeat_interval;
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
        .i_cache = .enabled,
        .d_cache = .enabled,
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
