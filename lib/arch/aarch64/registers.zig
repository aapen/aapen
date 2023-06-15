pub const cntp_ctl = @import("registers/cntp_ctl.zig");
pub const cnthctl_el2 = @import("registers/cnthctl_el2.zig");
pub const hcr_el2 = @import("registers/hcr_el2.zig");
pub const sctlr_el1 = @import("registers/sctlr_el1.zig");
pub const spsr = @import("registers/spsr.zig");

const R = @import("system_register.zig").UniformSystemRegister;
//
// Registers with less detailed explanations are here
//

// ----------------------------------------------------------------------
// EL2 (Hypervisor)
// ----------------------------------------------------------------------

/// Counter-timer Hypervisor Control Register
pub const CNTHCTL_EL2 = R("CNTHCTL_EL2", cnthctl_el2.layout);

/// Counter-timer Virtual Offset
pub const CNTVOFF_EL2 = R("CNTVOFF_EL2", u64);

/// Exception Link Register
pub const ELR_EL2 = R("ELR_EL2", u64);

/// Hypervisor Control Register
pub const HCR_EL2 = R("HCR_EL2", hcr_el2.layout);

/// Stack Pointer (EL2)
// TODO: Should this be a pointer to some larger size to enforce stack
// pointer alignment?
pub const SP_EL2 = R("SP_EL2", *u8);

/// Saved Program Status Register (EL2)
pub const SPSR_EL2 = R("SPSR_EL2", spsr.layout);

// ----------------------------------------------------------------------
// EL1 (Kernel)
// ----------------------------------------------------------------------

/// Exception Link Register (EL1)
pub const ELR_EL1 = R("ELR_EL1", u64);

/// System Control Register (EL1)
pub const SCTLR_EL1 = R("SCTLR_EL1", sctlr_el1.layout);

/// Stack Pointer (EL1)
pub const SP_EL1 = R("SP_EL1", *u8);

// ----------------------------------------------------------------------
// EL0 (Application)
// ----------------------------------------------------------------------

// Counter-timer physical control register
pub const CNTP_CTL_EL0 = R("CNTP_CTL_EL0", cntp_ctl.layout);

// Counter-timer physical compare value register
pub const CNTP_CVAL_EL0 = R("CNTP_CVAL_EL0", u64);

// Counter-timer timer value register
pub const CNTP_TVAL_EL0 = R("CNTP_TVAL_EL0", u64);

// System clock frequency (in Hz)
// TODO: technically this is a read only register. Should we have a
// separate type for that?
pub const CNTFRQ_EL0 = R("CNTFRQ_EL0", u64);

// Physical count value
pub const CNTPCT_EL0 = R("CNTPCT_EL0", u64);

// TODO: another read-only register
pub const CNTVCT_EL0 = R("CNTVCT_EL0", u64);

/// Saved Program Status Register (EL1)
pub const SPSR_EL1 = R("SPSR_EL1", spsr.layout);
