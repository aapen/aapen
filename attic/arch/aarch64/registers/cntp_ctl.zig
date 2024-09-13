/// Counter-timer physical timer control register
/// See
/// https://developer.arm.com/documentation/ddi0595/2021-12/AArch64-Registers/CNTP-CTL-EL0--Counter-timer-Physical-Timer-Control-register?lang=en
const types = @import("../system_register.zig");

pub const Layout = packed struct {
    enable: enum(u1) {
        disable = 0b0,
        enable = 0b1,
    },
    imask: enum(u1) {
        not_masked = 0b0,
        masked = 0b1,
    },
    istatus: enum(u1) {
        not_met = 0b0,
        met = 0b1,
    },
    _unused_reserved: u61 = 0,
};
