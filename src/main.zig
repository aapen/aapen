const io = @import("io");

export fn kernel_main() callconv(.C) u8 {
    io.pl011_uart_init();
    io.pl011_uart_write_text("Hello, world!\n");
    return 0;
}
