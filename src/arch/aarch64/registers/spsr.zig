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

pub const layout = packed struct {
    // Mode (prior EL and security state)
    M: enum(u4) {
        el0t = 0b0000,
        el1t = 0b0100,
        el1h = 0b0101,
    },
    ES: u1 = 0,
    _unused_reserved_0: u1 = 0,
    // FIQ interrupt mask
    F: InterruptMask,
    // IRQ interrupt mask
    I: InterruptMask,
    // SError interrupt mask
    A: InterruptMask,
    // Debug exception mask
    D: InterruptMask,
    // Branch type indicator
    BTYPE: u2 = 0,
    // Speculative store bypass
    SSBS: u1 = 0,
    // All IRQ or FIQ interrupts mask
    ALLINT: u1 = 0,
    _unused_reserved_1: u6 = 0,
    // Illegal execution state
    IL: u1 = 0,
    // Software step
    SS: u1 = 0,
    // Privileged access never
    PAN: u1 = 0,
    // User access override
    UAO: u1 = 0,
    // Data independent timing
    DIT: u1 = 0,
    // Tag check override
    TCO: u1 = 0,
    _unused_reserved_2: u2 = 0,
    // Overflow condition flag
    V: u1 = 0,
    // Carry condition flag
    C: u1 = 0,
    // Zero condition flag
    Z: u1 = 0,
    // Negative condition flag
    N: u1 = 0,
    _unused_reserved_3: u32 = 0,
};
