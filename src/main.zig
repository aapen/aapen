const io = @import("io");

export fn kernel_main() callconv(.C) void {
    var foo: u64 = 1234;
    io.mmio_write(&foo, 777);
}
