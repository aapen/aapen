/// Exception Syndrome Register
pub const types = @import("../system_register.zig");

pub const ErrorCode = enum(u6) {
    unknown = 0b000000,

    trapped_wfi_or_wfe = 0b000001, // Trapped WF*
    trapped_mcr_or_mrc = 0b000011, // Trapped MCR or MRC
    trapped_mcrr_or_mrrc = 0b000100, // Trapped MCRR or MRRC
    trapped_mcr_or_mrc_2 = 0b000101, // Trapped MCR or MRC
    trapped_ldc_or_stc = 0b000110, // Trapped LDC or STC
    trapped_simd = 0b000111, // Trapped SIMD
    trapped_vmrs = 0b001000, // Trapped VMRS
    trapped_pointer_auth = 0b001001, // Trapped pointer authentication
    trapped_ld64b_or_st64b = 0b001010, // Trapped LD64B or ST64B*
    trapped_mrrc = 0b001100, // Trapped MRRC
    branch_target_exception = 0b001101, // Branch target exception
    illegal_execution_state = 0b001110, // Illegal execution state
    trapped_svc_aarch32 = 0b010001, // SVC instruction
    trapped_hvc_aarch32 = 0b010010, // HVC instruction
    trapped_smc_aarch32 = 0b010011, // SMC instruction
    trapped_svc_aarch64 = 0b010101, // SVC instruction
    trapped_hvc_aarch64 = 0b010110, // HVC instruction
    trapped_smc_aarch64 = 0b010111, // SMC instruction
    trapped_mrs_aarch64 = 0b011000, // Trapped MRS, MSR, or system instruction
    trapped_sve = 0b011001, // Trapped SVE
    trapped_eret = 0b011010, // Trapped ERET
    pointer_auth_failed = 0b011100, // Failed pointer authentication
    trapped_sme = 0b011101,
    instruction_abort_from_lower = 0b100000, // Instruction abort from lower level
    instruction_abort_from_same = 0b100001, // Instruction abort from same level
    pc_alignment = 0b100010, // PC alignment failure
    data_abort_from_lower = 0b100100, // Data abort from lower level
    data_abort_from_same = 0b100101, // Data abort from same level
    sp_alignment = 0b100110, // SP alignment fault
    fpe_32 = 0b101000, // 32-bit floating point exception
    fpe_64 = 0b101100, // 64-bit floating point exception
    serror = 0b101111, // SError interrupt
    breakpoint_from_lower = 0b110000, // Breakpoint from lower level
    breakpoint_from_same = 0b110001, // Breakpoint from same level
    software_step_from_lower = 0b110010, // Software step from lower level
    software_step_from_same = 0b110011, // Software step from same level
    watchpoint_from_lower = 0b110100, // Watch point from same level
    watchpoint_from_same = 0b110101, // Watch point from lower level
    breakpoint_from_aarch32 = 0b111000, // Breakpoint in aarch32 mode
    brk = 0b111100, // BRK instruction in aarch64
};

pub const Layout = packed struct {
    iss: u25,
    il: u1,
    ec: ErrorCode,
    iss2: u24,
    _unused_reserved: u8,
};
