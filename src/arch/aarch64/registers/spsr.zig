/// Saved Program Status Register
/// See
/// https://developer.arm.com/documentation/ddi0595/2021-12/AArch64-Registers/SPSR-EL2--Saved-Program-Status-Register--EL2-
/// and
/// https://developer.arm.com/documentation/ddi0595/2021-12/AArch64-Registers/SPSR-EL1--Saved-Program-Status-Register--EL1-?lang=en
pub const types = @import("../system_register.zig");

const InterruptMask = enum(u1) {
    not_masked = 0,
    masked = 1,
};

pub const Layout = packed struct {
    // Mode (prior EL and security state)
    m: enum(u4) {
        el0t = 0b0000,
        el1t = 0b0100,
        el1h = 0b0101,
    },
    es: u1 = 0,
    _unused_reserved_0: u1 = 0,
    // FIQ interrupt mask
    f: InterruptMask,
    // IRQ interrupt mask
    i: InterruptMask,
    // SError interrupt mask
    a: InterruptMask,
    // Debug exception mask
    d: InterruptMask,
    // Branch type indicator
    btype: u2 = 0,
    // Speculative store bypass
    ssbs: u1 = 0,
    // All IRQ or FIQ interrupts mask
    allint: u1 = 0,
    _unused_reserved_1: u6 = 0,
    // Illegal execution state
    il: u1 = 0,
    // Software step
    ss: u1 = 0,
    // Privileged access never
    pan: u1 = 0,
    // User access override
    uao: u1 = 0,
    // Data independent timing
    dit: u1 = 0,
    // Tag check override
    tco: u1 = 0,
    _unused_reserved_2: u2 = 0,
    // Overflow condition flag
    v: u1 = 0,
    // Carry condition flag
    c: u1 = 0,
    // Zero condition flag
    z: u1 = 0,
    // Negative condition flag
    n: u1 = 0,
    _unused_reserved_3: u32 = 0,
};
