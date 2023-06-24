/// Counter-timer hypervisor control register
///
/// See
/// https://developer.arm.com/documentation/ddi0595/2021-12/AArch64-Registers/CNTHCTL-EL2--Counter-timer-Hypervisor-Control-register
const types = @import("../system_register.zig");

// This version of the layout applies if the CPU has FEAT_VHE _and_
// HCR_EL2.E2H is set.
pub const VHE_layout = packed struct {
    /// EL0 physical counter trap enable
    EL0PCTENL: types.TrapEnableBitN,
    // EL0 virtual counter trap enable
    EL0VCTEN: types.TrapEnableBitN,
    // Event enable
    EVNTEN: enum(u1) {
        event_disable = 0,
        event_enable = 1,
    },
    // Event direction
    EVNTDIR: enum(u1) {
        rising_edge = 0,
        falling_edge = 1,
    },
    // Event index
    EVNTI: u4,
    // EL0 virtual timer trap enable
    EL0VTEN: types.TrapEnableBitN,
    // EL0 physical timer trap enable
    EL0PTEN: types.TrapEnableBitN,
    // EL0 and EL1 physical counter register access trap enable
    EL1PCTEN: types.TrapEnableBitN,
    // EL0 and EL1 physical timer access trap enable
    EL1PTEN: types.TrapEnableBitN,
    // Enhanced counter virtualization enable
    ECV: enum(u1) {
        disable = 0,
        enable = 1,
    },
    // EL1 virtual timer trap enable
    EL1TVT: types.TrapEnableBitP,
    // EL1 virtual counter register access trap
    EL1TVCT: types.TrapEnableBitP,
    // EL1 physical timer register access trap
    EL1NVPCT: types.TrapEnableBitP,
    // EL1 virtual timer register access trap
    EL1NVVCT: types.TrapEnableBitP,
    // EVNTI scale
    EVNTIS: enum(u1) {
        low_bits = 0, // CNTHCTL_EL2.EVNTI applies to CNTPCT_EL0[15:0]
        high_bits = 1, // CNTHCTL_EL2.EVNTI applies to CNTPCT_EL0[23:8]
    },
    _unused_reserved: u46 = 0,
};

// This version of the layout applies if either the CPU lacks FEAT_VHE _or_
// HCR_EL2.E2H is not set.
pub const layout = packed struct {
    // Physical counter trap enable
    EL1PCTEN: types.TrapEnableBitN = .trap_enable,
    // Physical timer trap enable
    EL1PCEN: types.TrapEnableBitN = .trap_enable,
    // Event stream enable
    EVNTEN: enum(u1) {
        disable = 0,
        enable = 1,
    } = .disable,
    // Event stream trigger
    EVNTDIR: enum(u1) {
        rising_edge = 0,
        falling_edge = 1,
    } = .rising_edge,
    // Event index
    EVNTI: u4 = 0,
    _unused_reserved_0: u4 = 0,
    // Enhanced counter virtualization
    ECV: enum(u1) {
        disable = 0,
        enable = 1,
    } = .disable,
    // Trap virtual timer register access
    EL1TVT: types.TrapEnableBitP = .trap_disable,
    // Trap virtual counter register access
    EL1TVCTL: types.TrapEnableBitP = .trap_disable,
    // Trap physical timer register access
    EL1NVPCT: types.TrapEnableBitP = .trap_disable,
    // Trap virtual timer register access
    EL1NVVCT: types.TrapEnableBitP = .trap_disable,
    // Event stream scale
    EVNTIS: enum(u1) {
        low_bits = 0, // CNTHCTL_EL2.EVNTI applies to CNTPCT_EL0[15:0]
        high_bits = 1, // CNTHCTL_EL2.EVNTI applies to CNTPCT_EL0[23:8]
    } = .low_bits,
    _unused_reserved_1: u46 = 0,
};
