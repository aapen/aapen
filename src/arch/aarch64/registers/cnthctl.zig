/// Counter-timer hypervisor control register
///
/// See
/// https://developer.arm.com/documentation/ddi0595/2021-12/AArch64-Registers/CNTHCTL-EL2--Counter-timer-Hypervisor-Control-register
const types = @import("../system_register.zig");

pub const Layout = packed struct {
    // Physical counter trap enable
    el1pcten: types.TrapEnableBitN = .trap_enable,
    // Physical timer trap enable
    el1pcen: types.TrapEnableBitN = .trap_enable,
    // Event stream enable
    evnten: enum(u1) {
        disable = 0,
        enable = 1,
    } = .disable,
    // Event stream trigger
    evntdir: enum(u1) {
        rising_edge = 0,
        falling_edge = 1,
    } = .rising_edge,
    // Event index
    evnti: u4 = 0,
    _unused_reserved_0: u4 = 0,
    // Enhanced counter virtualization
    ECV: enum(u1) {
        disable = 0,
        enable = 1,
    } = .disable,
    // Trap virtual timer register access
    el1tvt: types.TrapEnableBitP = .trap_disable,
    // Trap virtual counter register access
    el1tvctl: types.TrapEnableBitP = .trap_disable,
    // Trap physical timer register access
    el1nvpct: types.TrapEnableBitP = .trap_disable,
    // Trap virtual timer register access
    el1nvvct: types.TrapEnableBitP = .trap_disable,
    // Event stream scale
    evntis: enum(u1) {
        low_bits = 0, // CNTHCTL_EL2.EVNTI applies to CNTPCT_EL0[15:0]
        high_bits = 1, // CNTHCTL_EL2.EVNTI applies to CNTPCT_EL0[23:8]
    } = .low_bits,
    _unused_reserved_1: u46 = 0,
};
