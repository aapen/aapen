const std = @import("std");
const arch = @import("architecture.zig");
const bsp = @import("bsp.zig");
const qemu = @import("qemu.zig");
const mem = @import("mem.zig");

const Freestanding = struct {
    page_allocator: std.mem.Allocator,
};

var os = Freestanding{
    .page_allocator = undefined,
};

const Self = @This();

/// uart console
const UartWriter = std.io.Writer(u32, error{}, uart_send_string);
pub var uart_writer = UartWriter{ .context = 0 };

fn uart_send_string(_: u32, str: []const u8) !usize {
    bsp.io.send_string(str);
    return str.len;
}

/// display console
const FrameBufferConsole = struct {
    xpos: u8 = 0,
    ypos: u8 = 0,
    width: u16 = undefined,
    height: u16 = undefined,
    frame_buffer: *bsp.video.FrameBuffer = undefined,

    pub fn init(frame_buffer: *bsp.video.FrameBuffer, pixel_width: u32, pixel_height: u32) FrameBufferConsole {
        return FrameBufferConsole{
            .frame_buffer = frame_buffer,
            .width = @truncate(pixel_width / 8),
            .height = @truncate(pixel_height / 16),
        };
    }

    fn next(self: *FrameBufferConsole) void {
        self.xpos += 1;
        if (self.xpos >= self.width) {
            self.next_line();
        }
    }

    fn next_line(self: *FrameBufferConsole) void {
        self.xpos = 0;
        self.ypos += 1;
        if (self.ypos >= self.height) {
            self.next_screen();
        }
    }

    fn next_screen(self: *FrameBufferConsole) void {
        self.xpos = 0;
        self.ypos = 0;
        // TODO: clear screen?
    }

    fn isPrintable(ch: u8) bool {
        return ch >= 32;
    }

    pub fn emit(self: *FrameBufferConsole, ch: u8) void {
        switch (ch) {
            '\n' => self.next_line(),
            else => if (isPrintable(ch)) {
                self.frame_buffer.draw_char(@as(u16, self.xpos) * 8, @as(u16, self.ypos) * 16, ch);
                self.next();
            },
        }
    }

    pub fn emit_string(self: *FrameBufferConsole, str: []const u8) void {
        for (str) |ch| {
            self.emit(ch);
        }
    }

    pub const Writer = std.io.Writer(*FrameBufferConsole, error{}, write);

    pub fn write(self: *FrameBufferConsole, bytes: []const u8) !usize {
        for (bytes) |ch| {
            self.emit(ch);
        }
        return bytes.len;
    }

    pub fn writer(self: *FrameBufferConsole) Writer {
        return .{ .context = self };
    }
};

pub var console: FrameBufferConsole.Writer = undefined;

fn kernel_init() !void {
    arch.cpu.mmu2.init();
    arch.cpu.exceptions.init();
    arch.cpu.irq.init();

    bsp.timer.timer_init();
    bsp.io.uart_init();

    var heap = bsp.memory.create_greedy(arch.cpu.mmu2.PAGE_SIZE);

    var heap_allocator = mem.HeapAllocator{
        .first_available = heap.start,
        .last_available = heap.end,
    };
    os.page_allocator = heap_allocator.allocator();

    var fb = bsp.video.FrameBuffer{};
    try fb.set_resolution(1024, 768, 8);

    var fb_console = FrameBufferConsole.init(&fb, 1024, 768);

    console = fb_console.writer();

    var board = bsp.mailbox.BoardInfo{};

    try board.read();
    try console.print("ARM Memory:       0x{x:0>8} .. 0x{x:0>8}\n", .{
        board.arm_memory_base,
        board.arm_memory_size + board.arm_memory_base,
    });
    try console.print("Videocore Memory: 0x{x:0>8} .. 0x{x:0>8}\n", .{
        board.videocore_memory_base,
        board.videocore_memory_size + board.videocore_memory_base,
    });

    try console.print("Kernel Heap:      0x{x:0>8} .. 0x{x:0>8}\n", .{
        @intFromPtr(heap_allocator.first_available),
        @intFromPtr(heap_allocator.last_available),
    });

    try print_clock_rate(console, .uart);

    fb_console.emit_string("READY.");
    fb_console.next_line();

    fb_console.emit(0);

    while (true) {
        var ch: u8 = bsp.io.receive();

        bsp.io.send(ch);
        if (ch == '\r') {
            // my serial emulator needs a \r\n sequence
            bsp.io.send('\n');
            // but the video framebuffer uses ordinary \n
            ch = '\n';
        }

        // TODO: backspace? cursor movement? (requires multibyte
        // sequences from UART)
        fb_console.emit(ch);
    }

    // Does not return
    qemu.exit(0);

    unreachable;
}

fn print_clock_rate(fb_console: FrameBufferConsole.Writer, clock_type: bsp.mailbox.ClockRate.Clock) !void {
    if (bsp.mailbox.get_clock_rate(clock_type)) |clock| {
        try fb_console.print("{s} clock: {}\r\n", .{ @tagName(clock_type), clock[1] });
    } else |err| {
        try fb_console.print("Error getting clock: {}\r\n", .{err});
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

// TODO: re-enable this when
// https://github.com/ziglang/zig/issues/16327 is fixed.

// pub fn panic(msg: []const u8, stack: ?*std.builtin.StackTrace, return_addr: ?usize) noreturn {
//     _ = stack;
//     _ = return_addr;

//     console.print(msg, .{}) catch {};
//     while (true) {}

//     unreachable;
// }
