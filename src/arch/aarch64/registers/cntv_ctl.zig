/// Counter-timer Virtual Timer Control register
const types = @import("../system_register.zig");

pub const Layout = packed struct {
    enable: enum(u1) {
        disable = 0,
        enable = 1,
    },
    imask: enum(u1) {
        not_masked = 0,
        masked = 1,
    },
    istatus: enum(u1) {
        not_met = 0,
        met = 1,
    },
    _unused_reserved: u61 = 0,
};
