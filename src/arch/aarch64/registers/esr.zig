/// Exception Syndrome Register
pub const types = @import("../system_register.zig");

pub const ErrorCodes = struct {
    pub const unknown = 0b000000;
    pub const trapped_wfi_or_wfe = 0b000001; // Trapped WF*
    pub const trapped_mcr_or_mrc = 0b000011; // Trapped MCR or MRC
    pub const trapped_mcrr_or_mrrc = 0b000100; // Trapped MCRR or MRRC
    pub const trapped_mcr_or_mrc_2 = 0b000101; // Trapped MCR or MRC
    pub const trapped_ldc_or_stc = 0b000110; // Trapped LDC or STC
    pub const trapped_simd = 0b000111; // Trapped SIMD
    pub const trapped_vmrs = 0b001000; // Trapped VMRS
    pub const trapped_pointer_auth = 0b001001; // Trapped pointer authentication
    pub const trapped_ld64b_or_st64b = 0b001010; // Trapped LD64B or ST64B*
    pub const trapped_mrrc = 0b001100; // Trapped MRRC
    pub const branch_target_exception = 0b001101; // Branch target exception
    pub const illegal_execution_state = 0b001110; // Illegal execution state
    pub const trapped_svc_aarch32 = 0b010001; // SVC instruction
    pub const trapped_hvc_aarch32 = 0b010010; // HVC instruction
    pub const trapped_smc_aarch32 = 0b010011; // SMC instruction
    pub const trapped_svc_aarch64 = 0b010101; // SVC instruction
    pub const trapped_hvc_aarch64 = 0b010110; // HVC instruction
    pub const trapped_smc_aarch64 = 0b010111; // SMC instruction
    pub const trapped_mrs_aarch64 = 0b011000; // Trapped MRS; MSR; or system instruction
    pub const trapped_sve = 0b011001; // Trapped SVE
    pub const trapped_eret = 0b011010; // Trapped ERET
    pub const pointer_auth_failed = 0b011100; // Failed pointer authentication
    pub const trapped_sme = 0b011101;
    pub const instruction_abort_from_lower = 0b100000; // Instruction abort from lower level
    pub const instruction_abort_from_same = 0b100001; // Instruction abort from same level
    pub const pc_alignment = 0b100010; // PC alignment failure
    pub const data_abort_from_lower = 0b100100; // Data abort from lower level
    pub const data_abort_from_same = 0b100101; // Data abort from same level
    pub const sp_alignment = 0b100110; // SP alignment fault
    pub const fpe_32 = 0b101000; // 32-bit floating point exception
    pub const fpe_64 = 0b101100; // 64-bit floating point exception
    pub const serror = 0b101111; // SError interrupt
    pub const breakpoint_from_lower = 0b110000; // Breakpoint from lower level
    pub const breakpoint_from_same = 0b110001; // Breakpoint from same level
    pub const software_step_from_lower = 0b110010; // Software step from lower level
    pub const software_step_from_same = 0b110011; // Software step from same level
    pub const watchpoint_from_lower = 0b110100; // Watch point from same level
    pub const watchpoint_from_same = 0b110101; // Watch point from lower level
    pub const breakpoint_from_aarch32 = 0b111000; // Breakpoint in aarch32 mode
    pub const brk = 0b111100; // BRK instruction in aarch64
};

pub fn errorCodeName(ec: u6) []const u8 {
    return switch (ec) {
        ErrorCodes.unknown => "unknown",
        ErrorCodes.trapped_wfi_or_wfe => "Trapped WF*",
        ErrorCodes.trapped_mcr_or_mrc => "Trapped MCR or MRC",
        ErrorCodes.trapped_mcrr_or_mrrc => "Trapped MCRR or MRRC",
        ErrorCodes.trapped_mcr_or_mrc_2 => "Trapped MCR or MRC",
        ErrorCodes.trapped_ldc_or_stc => "Trapped LDC or STC",
        ErrorCodes.trapped_simd => "Trapped SIMD",
        ErrorCodes.trapped_vmrs => "Trapped VMRS",
        ErrorCodes.trapped_pointer_auth => "Trapped pointer authentication",
        ErrorCodes.trapped_ld64b_or_st64b => "Trapped LD64B or ST64B*",
        ErrorCodes.trapped_mrrc => "Trapped MRRC",
        ErrorCodes.branch_target_exception => "Branch target exception",
        ErrorCodes.illegal_execution_state => "Illegal execution state",
        ErrorCodes.trapped_svc_aarch32 => "SVC instruction",
        ErrorCodes.trapped_hvc_aarch32 => "HVC instruction",
        ErrorCodes.trapped_smc_aarch32 => "SMC instruction",
        ErrorCodes.trapped_svc_aarch64 => "SVC instruction",
        ErrorCodes.trapped_hvc_aarch64 => "HVC instruction",
        ErrorCodes.trapped_smc_aarch64 => "SMC instruction",
        ErrorCodes.trapped_mrs_aarch64 => "Trapped MRS; MSR; or system instruction",
        ErrorCodes.trapped_sve => "Trapped SVE",
        ErrorCodes.trapped_eret => "Trapped ERET",
        ErrorCodes.pointer_auth_failed => "Failed pointer authentication",
        ErrorCodes.trapped_sme => "Trapped SME",
        ErrorCodes.instruction_abort_from_lower => "Instruction abort from lower level",
        ErrorCodes.instruction_abort_from_same => "Instruction abort from same level",
        ErrorCodes.pc_alignment => "PC alignment failure",
        ErrorCodes.data_abort_from_lower => "Data abort from lower level",
        ErrorCodes.data_abort_from_same => "Data abort from same level",
        ErrorCodes.sp_alignment => "SP alignment fault",
        ErrorCodes.fpe_32 => "32-bit floating point exception",
        ErrorCodes.fpe_64 => "64-bit floating point exception",
        ErrorCodes.serror => "SError interrupt",
        ErrorCodes.breakpoint_from_lower => "Breakpoint from lower level",
        ErrorCodes.breakpoint_from_same => "Breakpoint from same level",
        ErrorCodes.software_step_from_lower => "Software step from lower level",
        ErrorCodes.software_step_from_same => "Software step from same level",
        ErrorCodes.watchpoint_from_lower => "Watch point from same level",
        ErrorCodes.watchpoint_from_same => "Watch point from lower level",
        ErrorCodes.breakpoint_from_aarch32 => "Breakpoint in aarch32 mode",
        ErrorCodes.brk => "BRK instruction in aarch64",
        else => "unknown",
    };
}

pub const Layout = packed struct {
    iss: u25,
    il: u1,
    ec: u6,
    iss2: u24,
    _unused_reserved: u8,
};
