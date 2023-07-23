/// Architectural Feature Access Control Register
/// See https://developer.arm.com/documentation/ddi0595/2021-06/AArch64-Registers/CPACR-EL1--Architectural-Feature-Access-Control-Register?lang=en
const types = @import("../system_register.zig");

pub const Layout = packed struct {
    _unused_reserved_0: u16 = 0,
    // ZCR_EL1 trap enable
    zen: enum(u2) {
        trap_all = 0b00,
        trap_el0 = 0b01,
        trap_el1_and_el0 = 0b10,
        trap_none = 0b11,
    } = .trap_none,
    _unused_reserved_1: u2 = 0,
    // Advanced SIMD and floating point access trap
    fpen: enum(u2) {
        trap_all = 0b00,
        trap_el0 = 0b01,
        trap_el1_and_el0 = 0b10,
        trap_none = 0b11,
    } = .trap_none,
    _unused_reserved_2: u6 = 0,
    // Trace register trap enable
    tta: types.TrapEnableBitP = .trap_disable,
    _unused_reserved_3: u35 = 0,
};
