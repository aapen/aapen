const std = @import("std");
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const ScopeLevel = std.log.ScopeLevel;

const atomic = @import("atomic.zig");
const arch = @import("architecture.zig");

const Disassemble = @import("disassemble.zig");
const Event = @import("event.zig");
const Heap = @import("heap.zig");
const FrameBuffer = @import("frame_buffer.zig");
const CharBuffer = @import("char_buffer.zig");
const CharBufferConsole = @import("char_buffer_console.zig");
const MainConsole = @import("main_console.zig");

pub const debug = @import("debug.zig");
pub const printf = MainConsole.printf;
pub const panic = debug.panic;

const forty = @import("forty/forth.zig");
pub const Forth = forty.Forth;

const Serial = @import("serial.zig"); //TBD

pub const schedule = @import("schedule.zig");
pub const schedule2 = @import("schedule2.zig");
const heartbeat = @import("heartbeat.zig");

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
        .{ .scope = .schedule, .level = .debug },
    };
};

/// Present an "operating system" interface layer to Zig's stdlib.
const Freestanding = struct {
    pub const system = struct {};
    pub const heap = Heap;
};

pub const os = Freestanding;

pub var hal: *HAL = undefined;
pub var fb: *FrameBuffer = undefined;
pub var char_buffer_console: *CharBufferConsole = undefined;
pub var char_buffer: *CharBuffer = undefined;
pub var main_console: *MainConsole = undefined;
pub var kernel_allocator: Allocator = undefined;

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

extern fn _start() noreturn;

const proc0 = if (std.mem.eql(u8, config.testname, ""))
    startForty
else
    @import("test/all.zig").locateTest(config.testname);

pub const kernelExit = if (std.mem.eql(u8, config.testname, ""))
    powerDown
else
    @import("test/all.zig").exitSuccess;

export fn kernelInit(core_id: usize) noreturn {
    // State: one core, no interrupts, no MMU, no heap Allocator, no
    // display, serial
    arch.cpu.init(core_id);

    if (core_id == 0) {
        if (debug.init()) {
            debug.kernelMessage("init");
            message_ring_valid = true;
        } else |_| {
            // not much we can do here
        }

        if (Heap.init()) {
            debug.kernelMessage("heap init");
        } else |err| {
            debug.kernelError("heap init error", err);
        }
        kernel_allocator = os.heap.page_allocator;

        if (HAL.init(kernel_allocator)) |h| {
            debug.kernelMessage("hal init");
            hal = h;
            uart_valid = true;
        } else |err| {
            debug.kernelError("hal init error", err);
        }

        // State: one core, interrupts, MMU, heap Allocator, no
        // display, serial

        // State: one core, interrupts, MMU, heap Allocator, no display,
        // serial
        if (FrameBuffer.init(kernel_allocator, hal)) |buf| {
            debug.kernelMessage("frame buffer init");
            fb = buf;
        } else |err| {
            debug.kernelError("frame buffer init error", err);
        }

        if (CharBuffer.init(kernel_allocator, fb)) |cb| {
            debug.kernelMessage("char buffer init");
            char_buffer = cb;
        } else |err| {
            debug.kernelError("char buffer init error", err);
        }

        if (CharBufferConsole.init(kernel_allocator, char_buffer)) |cbc| {
            debug.kernelMessage("fbcons init");
            char_buffer_console = cbc;
            char_buffer_console_valid = true;
        } else |err| {
            debug.kernelError("fbcons init error", err);
        }

        if (MainConsole.init(kernel_allocator, char_buffer_console)) |c| {
            debug.kernelMessage("console init");
            main_console = c;
            main_console_valid = true;
        } else |err| {
            debug.kernelError("console init error", err);
        }

        // State: one core, interrupts, MMU, heap Allocator, display,
        // serial
        if (diagnostics.init(kernel_allocator)) {
            debug.kernelMessage("diagnostics init");
        } else |err| {
            debug.kernelError("diagnostics init error", err);
        }

        // if (Usb.init(heap.allocator)) |_| {
        //     debug.kernelMessage("USB core init");
        // } else |err| {
        //     debug.kernelError("USB core init error", err);
        // }

        // State: one core, interrupts, MMU, heap Allocator, display,
        // serial, logging available, exception recovery available

        // Allow other cores to start. They will begin at _start (from
        // boot.S) which will take them from EL2 to EL1 back to the
        // start of this function. This all has to happen _after_
        // we've initialized page tables and zeroed bss
        HAL.releaseSecondaryCores(@intFromPtr(&_start));

        schedule2.init() catch {};

        if (schedule2.create(@intFromPtr(&proc0), schedule2.INITIAL_STACK_SIZE, schedule2.DEFAULT_PRIORITY, "init", @intFromPtr(&.{}))) |tid0| {
            // _ = printf("tid0 = %d\n", tid0);
            schedule2.ready(tid0, true) catch {};
        } else |err| {
            debug.kernelError("thread create error", err);
        }
    } else {
        secondaryCore(core_id);
    }
    unreachable;
}

fn startForty() void {
    if (interpreter.init(kernel_allocator, main_console, char_buffer)) {
        debug.kernelMessage("Forth init");
    } else |err| {
        debug.kernelError("Forth init error", err);
    }

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

    Event.defineModule(&interpreter) catch |err| {
        debug.kernelError("Event queue define module", err);
    };

    Disassemble.defineModule(&interpreter) catch |err| {
        debug.kernelError("Disassembler define module", err);
    };

    if (schedule.init()) {
        debug.kernelMessage("schedule init");
    } else |err| {
        debug.kernelMessage("schedule init error", err);
    }

    arch.cpu.exceptions.markUnwindPoint(&global_unwind_point);
    global_unwind_point.pc = @as(u64, @intFromPtr(&repl));

    repl();
}

fn repl() callconv(.C) noreturn {
    while (true) {
        interpreter.repl() catch |err| {
            std.log.err("REPL error: {any}\n\nABORT.\n", .{err});
        };
    }
}

extern fn spinDelay(ticks: u64) void;

export fn secondaryCore(core_id: u64) noreturn {
    while (true) {
        spinDelay(100_000_000 * (core_id + 1));
        Event.enqueue(.{ .type = Event.EventType.Core, .subtype = @truncate(core_id & 0xf) });
    }
}

pub fn powerDown() noreturn {
    // last thread has exited. we need to power down.
    // eventually, we can use power control registers.
    // for now, loop infintely
    while (true) {
        arch.cpu.wfe();
    }
}
