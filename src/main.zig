const std = @import("std");

const atomic = @import("atomic.zig");
const arch = @import("architecture.zig");

pub const debug = @import("debug.zig");
pub const printf = MainConsole.printf;
pub const panic = debug.panic;

const disassemble = @import("disassemble.zig");
const event = @import("event.zig");
const heap = @import("heap.zig");
const time = @import("time.zig");

const FrameBuffer = @import("frame_buffer.zig");
const CharBuffer = @import("char_buffer.zig");
const CharBufferConsole = @import("char_buffer_console.zig");
const MainConsole = @import("main_console.zig");

const forty = @import("forty/forth.zig");
const Forth = forty.Forth;

const Serial = @import("serial.zig"); //TBD
const schedule = @import("schedule.zig");
const semaphore = @import("semaphore.zig");
const Usb = @import("usb.zig");

const config = @import("config");
pub const HAL = switch (config.board) {
    .pi3 => @import("hal/raspi3.zig"),
    inline else => @compileError("Unsupported board " ++ @tagName(config.board)),
};
const diagnostics = @import("hal/diagnostics.zig");

// Supply debug options to Zig's stdlib.
pub const std_options = debug.options;

// Present an "operating system" interface layer to Zig's stdlib.
pub const os = @import("os.zig");

pub var hal: *HAL = undefined;
pub var fb: *FrameBuffer = undefined;
pub var char_buffer_console: *CharBufferConsole = undefined;
pub var char_buffer: *CharBuffer = undefined;
pub var main_console: *MainConsole = undefined;
pub var kernel_allocator: std.mem.Allocator = undefined;

pub var interpreter: Forth = Forth{};
pub var global_unwind_point = arch.cpu.exceptions.UnwindPoint{
    .sp = undefined,
    .pc = undefined,
    .fp = undefined,
    .lr = undefined,
};

pub var uart_valid = false;
pub var char_buffer_console_valid = false;
pub var main_console_valid = false;

extern fn _start() noreturn;

const KernelHooks = struct {
    thread1: schedule.ThreadFunction,
    kernel_exit: *const fn () void,
};

const test_mode = if (std.mem.eql(u8, config.testname, "")) false else true;

pub const kernel_hooks = switch (test_mode) {
    false => .{
        .thread1 = startForty,
        .kernel_exit = powerDown,
    },
    true => .{
        .thread1 = @import("test/all.zig").locateTest(config.testname),
        .kernel_exit = @import("test/all.zig").exit,
    },
};

export fn kernelInit(core_id: usize) noreturn {
    arch.cpu.init(core_id);

    if (core_id != 0) {
        secondaryCore(core_id); // noreturn
    }

    debug.init();

    schedule.init() catch |err| {
        debug.kernelError("scheduler init error", err);
        arch.cpu.park();
    };

    semaphore.init() catch |err| {
        debug.kernelError("semaphore init error", err);
        arch.cpu.park();
    };

    heap.init();

    kernel_allocator = os.heap.page_allocator;

    // configure this as thread 0
    schedule.becomeThread0(0x20000, 0x20000);

    hardwareInit() catch |err| {
        debug.kernelError("hardware init error", err);
    };

    displayInit() catch |err| {
        debug.kernelError("display init error", err);
    };

    diagnosticsInit() catch |err| {
        debug.kernelError("diagnostics init error", err);
    };

    // Allow other cores to start. They will begin at _start (from
    // boot.S) which will take them from EL2 to EL1 back to the
    // start of this function. This all has to happen _after_
    // we've initialized page tables and zeroed bss
    HAL.releaseSecondaryCores(@intFromPtr(&_start));

    time.init();
    arch.cpu.enable();

    // start main thread
    _ = schedule.spawn(kernel_hooks.thread1, "init", &.{}) catch |err| {
        debug.kernelError("thread create error", err);
    };

    // from here, other threads do the work. this one is invoked only
    // when all other threads are sleeping or waiting.
    while (true) {
        arch.cpu.wfi();
    }
}

fn startForty(_: *anyopaque) void {
    const heartbeat = @import("heartbeat.zig");

    _ = schedule.spawn(heartbeat.heartbeat, "hb", &.{}) catch |err| {
        debug.kernelError("heartbeat init error", err);
    };

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

    time.defineModule(&interpreter) catch |err| {
        debug.kernelError("time define module", err);
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

    event.defineModule(&interpreter) catch |err| {
        debug.kernelError("Event queue define module", err);
    };

    disassemble.defineModule(&interpreter) catch |err| {
        debug.kernelError("Disassembler define module", err);
    };

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
    arch.cpu.enable(); // interrupts on
    while (true) {
        spinDelay(100_000_000 * (core_id + 1));
        event.enqueue(.{ .type = event.EventType.Core, .subtype = @truncate(core_id & 0xf) });
    }
}

pub fn powerDown() void {
    // last thread has exited. we need to power down.
    // eventually, we can use power control registers.
    // for now, loop infintely
    arch.cpu.park();
}

fn hardwareInit() !void {
    hal = try HAL.init(kernel_allocator);
    uart_valid = true;
}

fn displayInit() !void {
    fb = try FrameBuffer.init(kernel_allocator, hal);

    char_buffer = try CharBuffer.init(kernel_allocator, fb);

    char_buffer_console = try CharBufferConsole.init(kernel_allocator, char_buffer);
    char_buffer_console_valid = true;

    main_console = try MainConsole.init(kernel_allocator, char_buffer_console);
    main_console_valid = true;
}

fn diagnosticsInit() !void {
    try diagnostics.init(kernel_allocator);
}

fn usbInit() !void {
    // if (Usb.init(heap.allocator)) |_| {
    //     debug.kernelMessage("USB core init");
    // } else |err| {
    //     debug.kernelError("USB core init error", err);
    // }
}
