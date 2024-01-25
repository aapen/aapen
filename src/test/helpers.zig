const qemu = @import("qemu.zig");

pub fn exit(status: u8) noreturn {
    qemu.exit(status);
    unreachable;
}
