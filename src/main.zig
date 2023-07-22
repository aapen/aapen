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

    fn underbar(self: *FrameBufferConsole, color: u8) void {
        var x: u16 = self.xpos;
        x *= 8;
        var y: u16 = self.ypos + 1;
        y *= 16;

        for (0..8) |i| {
            self.frame_buffer.draw_pixel(x + i, y, color);
        }
    }

    fn erase_cursor(self: *FrameBufferConsole) void {
        self.underbar(bsp.video.FrameBuffer.COLOR_BACKGROUND);
    }

    fn draw_cursor(self: *FrameBufferConsole) void {
        self.underbar(bsp.video.FrameBuffer.COLOR_FOREGROUND);
    }

    fn backspace(self: *FrameBufferConsole) void {
        if (self.xpos > 0) {
            self.xpos -= 1;
        }
        self.frame_buffer.erase_char(@as(u16, self.xpos) * 8, @as(u16, self.ypos) * 16);
    }

    fn isPrintable(ch: u8) bool {
        return ch >= 32;
    }

    pub fn emit(self: *FrameBufferConsole, ch: u8) void {
        self.erase_cursor();
        defer self.draw_cursor();

        switch (ch) {
            0x7f => self.backspace(),
            '\n' => self.next_line(),
            else => if (isPrintable(ch)) {
                self.frame_buffer.draw_char(@as(u16, self.xpos) * 8, @as(u16, self.ypos) * 16, ch);
                self.next();
            },
        }
    }

    pub fn emit_string(self: *FrameBufferConsole, str: []const u8) void {
        self.erase_cursor();
        defer self.draw_cursor();

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

    var heap_allocator = heap.allocator();
    os.page_allocator = heap_allocator.allocator();

    var fb = bsp.video.FrameBuffer{};
    try fb.set_resolution(1024, 768, 8);

    var fb_console = FrameBufferConsole.init(&fb, 1024, 768);

    console = fb_console.writer();

    var board = bsp.mailbox.BoardInfo{};

    try board.read();

    try console.print("Booted...\n", .{});
    try console.print("Running on {s} (a {s}) with {?}MB\n\n", .{ board.model.name, board.model.processor, board.model.memory });
    try console.print("    MAC address: {?}\n", .{board.device.mac_address});
    try console.print("  Serial number: {?}\n", .{board.device.serial_number});
    try console.print("Manufactured by: {?s}\n\n", .{board.device.manufacturer});

    try board.arm_memory.print(console);
    try board.videocore_memory.print(console);
    try heap.memory.print(console);

    try print_clock_rate(console, .uart);
    try print_clock_rate(console, .emmc);
    try print_clock_rate(console, .core);
    try print_clock_rate(console, .arm);

    fb_console.emit_string("READY.\n");

    while (true) {
        var ch: u8 = bsp.io.receive();

        bsp.io.send(ch);
        if (ch == '\r') {
            // my serial emulator needs a \r\n sequence
            bsp.io.send('\n');
            // but the video framebuffer uses ordinary \n
            ch = '\n';
        }

        // TODO: cursor movement? (requires multibyte sequences from UART)
        fb_console.emit(ch);
    }

    // Does not return
    qemu.exit(0);

    unreachable;
}

fn print_clock_rate(fb_console: FrameBufferConsole.Writer, clock_type: bsp.mailbox.ClockRate.Clock) !void {
    if (bsp.mailbox.get_clock_rate(clock_type)) |clock| {
        var clock_mhz = clock[1] / 1_000_000;
        try fb_console.print("{s:>14} clock: {} MHz\r\n", .{ @tagName(clock_type), clock_mhz });
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
