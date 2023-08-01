pub const cnthctl = @import("registers/cnthctl.zig");
pub const cntp_ctl = @import("registers/cntp_ctl.zig");
pub const cntv_ctl = @import("registers/cntv_ctl.zig");
pub const cpacr = @import("registers/cpacr.zig");
pub const ctr = @import("registers/ctr.zig");
pub const esr = @import("registers/esr.zig");
pub const hcr = @import("registers/hcr.zig");
pub const sctlr = @import("registers/sctlr.zig");
pub const spsr = @import("registers/spsr.zig");

pub const EC = esr.ErrorCode;

const R = @import("system_register.zig").UniformSystemRegister;

// ----------------------------------------------------------------------
// EL3 (Secure monitor)
// ----------------------------------------------------------------------

/// Exception Syndrome Register (EL3)
pub const esr_el3 = R("ESR_EL3", esr.Layout);

/// System Control Register (EL3)
pub const sctlr_el3 = R("SCTLR_EL3", sctlr.LayoutEl3);

/// Vector Base Address Register (EL3)
/// Pointer to the exception vector table for this EL
pub const vbar_el3 = R("VBAR_EL3", u64);

// ----------------------------------------------------------------------
// EL2 (Hypervisor)
// ----------------------------------------------------------------------

/// Counter-timer Hypervisor Control Register
pub const cnthctl_el2 = R("CNTHCTL_EL2", cnthctl.Layout);

/// Counter-timer Virtual Offset
pub const cntvoff_el2 = R("CNTVOFF_EL2", u64);

/// Exception Link Register
pub const elr_el2 = R("ELR_EL2", u64);

/// Exception Syndrome Register (EL2)
pub const esr_el2 = R("ESR_EL2", esr.Layout);

/// Hypervisor Control Register
pub const hcr_el2 = R("HCR_EL2", hcr.Layout);

/// System Control Register (EL2)
pub const sctlr_el2 = R("SCTLR_EL2", sctlr.LayoutEl2);

/// Stack Pointer (EL2)
pub const sp_el2 = R("SP_EL2", u64);

/// Saved Program Status Register (EL2)
pub const spsr_el2 = R("SPSR_EL2", spsr.Layout);

/// Vector Base Address Register (EL2)
/// Pointer to the exception vector table for this EL
pub const vbar_el2 = R("VBAR_EL2", u64);

// ----------------------------------------------------------------------
// EL1 (Kernel)
// ----------------------------------------------------------------------

/// Architectural Feature Access Control Register (EL1)
pub const cpacr_el1 = R("CPACR_EL1", cpacr.Layout);

/// Exception Link Register (EL1)
pub const elr_el1 = R("ELR_EL1", u64);

/// Exception Syndrome Register (EL1)
pub const esr_el1 = R("ESR_EL1", esr.Layout);

/// System Control Register (EL1)
pub const sctlr_el1 = R("SCTLR_EL1", sctlr.LayoutEl1);

/// Stack Pointer (EL1)
pub const sp_el1 = R("SP_EL1", u64);

/// Saved Program Status Register (EL1)
pub const spsr_el1 = R("SPSR_EL1", spsr.layout);

/// Vector Base Address Register (EL1)
/// Pointer to the exception vector table for this EL
pub const vbar_el1 = R("VBAR_EL1", u64);

// ----------------------------------------------------------------------
// EL0 (Application)
// ----------------------------------------------------------------------

/// System clock frequency (in Hz)
// TODO: technically this is a read only register. Should we have a
// separate type for that?
pub const cntfrq_el0 = R("CNTFRQ_EL0", u64);

/// Physical count value
pub const cntpct_el0 = R("CNTPCT_EL0", u64);

/// Counter-timer physical control register
pub const cntp_ctl_el0 = R("CNTP_CTL_EL0", cntp_ctl.Layout);

/// Counter-timer physical compare value register
pub const cntp_cval_el0 = R("CNTP_CVAL_EL0", u64);

/// Counter-timer physical timer value register
/// This is a 64-bit register but only the bottom 32 bits will ever
/// have a value.
pub const cntp_tval_el0 = R("CNTP_TVAL_EL0", u64);

/// Counter-timer virtual timer control register
pub const cntv_ctl_el0 = R("CNTV_CTL_EL0", cntv_ctl.Layout);

/// Counter-timer virtual timer register
pub const cntv_cval_el0 = R("CNTV_CVAL_EL0", u64);

/// Counter-timer virtual timer value register
/// This is a 64-bit register but only the bottom 32 bits will ever
/// have a value.
pub const cntv_tval_el0 = R("CNTV_TVAL_EL0", u64);

// TODO: another read-only register
pub const cntvct_el0 = R("CNTVCT_EL0", u64);

/// Cache type register
pub const ctr_el0 = R("CTR_EL0", ctr.Layout);

/// Stack Pointer (EL0)
pub const sp_el0 = R("SP_EL0", u64);
