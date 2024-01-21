/// System Control Register (EL1)
/// See
/// https://developer.arm.com/documentation/ddi0595/2021-12/AArch64-Registers/SCTLR-EL1--System-Control-Register--EL1-?lang=en
const types = @import("../system_register.zig");

pub const LayoutEl1 = packed struct {
    mmu_enable: enum(u1) {
        disable = 0,
        enable = 1,
    }, // 0
    // Alignment check enable
    a: enum(u1) {
        disable = 0,
        enable = 1,
    }, // 1
    // Cacheability control
    d_cache: enum(u1) {
        disabled = 0,
        enabled = 1,
    } = .disabled, // 2
    // Stack pointer alignment check enable
    sa: u1, // 3
    // Stack pointer alignment check for EL0
    sa0: u1, // 4
    // System instruction memory barrier enable (when EL0 capable of using AArch32)
    cp15ben: u1 = 0, // 5
    // Non-aligned access trap
    naa: types.TrapEnableBitN = .trap_enable, // 6
    // IT instruction disable at EL0 in AArch32
    itd: u1 = 0, // 7
    // SETEND instruction disable (when EL0 capable of using AArch32)
    sed: u1 = 1, // 8
    // User mask access
    uma: u1 = 0, // 9
    // Enable EL0 Access to CTX instructions (requires FEAT_SPECRES)
    enrctx: u1 = 0, // 10
    // Exception Exit is Context Synchronizing
    eos: u1 = 0, // 11
    // Stage 1 instruction access cacheability control
    i_cache: enum(u1) {
        disabled = 0,
        enabled = 1,
    } = .disabled,// 12
    // Enable pointer authentication
    endb: u1 = 0, // 13
    // Trap EL0 execution of DC ZVA instructions
    dze: types.TrapEnableBitN = .trap_disable, // 14
    // Trap EL0 access to CTR_EL0
    uct: types.TrapEnableBitN = .trap_disable, // 15
    // Trap EL0 execution of WFI
    ntwi: types.TrapEnableBitN = .trap_disable, // 16
    _unused_reserved_0: u1 = 0, // 17
    // Trap EL0 execution of WFE
    ntwe: types.TrapEnableBitN = .trap_disable, // 18
    // Write permission implies execute-never (NX)
    wxn: u1, // 19
    // Trap EL0 access to SCXTNUM_EL0
    tscxt: types.TrapEnableBitP = .trap_enable, // 20
    // Implicit error synchronization event enable
    iesb: u1 = 0, // 21
    // Exception Entry is Context Switching
    eis: u1 = 1, // 22
    // Set Privileged Access Never
    span: u1 = 1, // 23
    // Endianness at EL0
    e0e: enum(u1) {
        little_endian = 0,
        big_endian = 1,
    } = .little_endian, // 24
    // Endianness at EL1
    ee: enum(u1) {
        little_endian = 0,
        big_endian = 1,
    } = .little_endian, // 25
    // Trap EL0 cache maintenance instructions
    uci: types.TrapEnableBitN = .trap_enable, // 26
    // Enable pointer authentication using APDAKey_EL1
    enda: u1 = 0, // 27
    // No trap load multiple and store multiple
    ntlsmd: u1 = 1, // 28
    // Load multiple and store multiple atomicity and ordering
    lsmaoe: u1 = 1, // 29
    // Enable pointer auth using APIBKey_EL1
    enib: u1 = 0, // 30
    // Enable pointer auth using APIAKey_EL1 of instr addresses
    enia: u1 = 0, //31
    // Cache maintenince instruction permission
    cmow: u1 = 0, // 32
    // Memory ocpy and memory set instructions enable
    mscen: u1 = 0, // 33
    _unused_reserved_1: u1 = 0, // 34
    // PAC branch type compatibility at EL0
    bt0: u1 = 0, // 35
    // PAC branch type compatibility at EL1
    bt1: u1 = 0, // 36
    // Instuction tag fault synchronization bit
    itfsb: u1 = 0, // 37
    // Tag check fault in EL0
    tcf0: enum(u2) {
        no_effect = 0b00,
        synchronous_exception = 0b01,
        asynchronous_accumulate = 0b10,
        exception_on_read_accumulate_on_writes = 0b11,
    } = .no_effect, // 38..39
    // Tag check fault in EL1
    tcf: enum(u2) {
        no_effect = 0b00,
        synchronous_exception = 0b01,
        asynchronous_accumulate = 0b10,
        exception_on_read_accumulate_on_writes = 0b11,
    } = .no_effect, // 40..41
    // Allocation tag access in EL0
    ata0: enum(u1) {
        not_allowed = 0,
        allowed = 1,
    } = .not_allowed, // 42
    // Allocation tag access in EL1
    ata: enum(u1) {
        not_allowed = 0,
        allowed = 1,
    } = .not_allowed, // 43
    // Default SSBS value on exception entry
    dssbs: u1 = 0, // 44
    // TWE delay enable
    tweden: u1 = 0, // 45
    // TWE Delay
    twedel: u4 = 0, // 46..49
    _unused_reserved_2: u4 = 0, // 50..53
    // Trap execution of ST64BV instructions
    enasr: types.TrapEnableBitN = .trap_disable, // 54
    // Trap execution of ST64BV0
    enas0: types.TrapEnableBitN = .trap_disable, // 55
    // Trap execution of LD64B or ST64B
    enals: types.TrapEnableBitN = .trap_disable, // 56
    // Enhanced privileged access never
    epan: u1 = 0, // 57
    _unused_reserved_3: u3 = 0, // 58..60
    // Non-maskable interrupt enable
    nmi: u1 = 0, // 61
    // SP interrupt mask enable
    spintmask: u1 = 0, // 62
    // Trap "implementation defined" functionality
    tidcp: u1 = 0, // 63
};

pub const LayoutEl2 = packed struct {
    mmu_enable: enum(u1) {
        disable = 0,
        enable = 1,
    },
    // Alignment check enable
    a: enum(u1) {
        disable = 0,
        enable = 1,
    },
    // Cacheability control
    c: u1,
    // Stack pointer alignment check enable
    sa: u1,
    // Stack pointer alignment check for EL0
    sa0: u1,
    // System instruction memory barrier enable (when EL0 capable of using AArch32)
    cp15ben: u1 = 0,
    // Non-aligned access trap
    naa: types.TrapEnableBitN,
    // IT instruction disable at EL0 in AArch32
    itd: u1 = 0,
    // SETEND instruction disable (when EL0 capable of using AArch32)
    sed: u1 = 1,
    // User mask access
    _unused_reserved_0: u1 = 0,
    // Enable EL0 Access to CTX instructions (requires FEAT_SPECRES)
    enrctx: u1 = 0,
    // Exception Exit is Context Synchronizing
    eos: u1,
    // Stage 1 instruction access cacheability control
    i: u1 = 0,
    // Enable pointer authentication
    endb: u1 = 0,
    // Trap EL0 execution of DC ZVA instructions
    dze: types.TrapEnableBitN,
    // Trap EL0 access to CTR_EL0
    uct: types.TrapEnableBitN,
    // Trap EL0 execution of WFI
    ntwi: types.TrapEnableBitN,
    _unused_reserved_1: u1 = 0,
    // Trap EL0 execution of WFE
    ntwe: types.TrapEnableBitN = 0,
    // Write permission implies execute-never (NX)
    wxn: u1,
    // Trap EL0 access to SCXTNUM_EL0
    tscxt: types.TrapEnableBitP = .enabled,
    // Implicit error synchronization event enable
    iesb: u1 = 0,
    // Exception Entry is Context Switching
    eis: u1 = 1,
    // Set Privileged Access Never
    span: u1 = 1,
    // Endianness at EL0
    e0e: u1 = 0,
    // Endianness at EL1
    ee: enum(u1) {
        little_endian = 0,
        big_endian = 1,
    },
    // Trap EL0 cache maintenance instructions
    uci: types.TrapEnableBitN,
    // Enable pointer authentication using APDAKey_EL1
    enda: u1 = 0,
    // No trap load multiple and store multiple
    ntlsmd: u1 = 1,
    // Load multiple and store multiple atomicity and ordering
    lsmaoe: u1 = 1,
    // Enable pointer auth using APIBKey_EL1
    enib: u1 = 0,
    // Enable pointer auth using APIAKey_EL1 of instr addresses
    enia: u1 = 0,
    // Cache maintenince instruction permission
    cmow: u1 = 0,
    // Memory ocpy and memory set instructions enable
    mscen: u1 = 0,
    _unused_reserved_2: u1 = 0,
    // PAC branch type compatibility at EL0
    bt0: u1 = 0,
    // PAC branch type compatibility at EL1
    bt: u1 = 0,
    // Instuction tag fault synchronization bit
    itfsb: u1 = 0,
    // Tag check fault in EL0
    tcf0: enum(u2) {
        no_effect = 0b00,
        synchronous_exception = 0b01,
        asynchronous_accumulate = 0b10,
        exception_on_read_accumulate_on_writes = 0b11,
    } = .no_effect,
    // Tag check fault in EL1
    tcf: enum(u2) {
        no_effect = 0b00,
        synchronous_exception = 0b01,
        asynchronous_accumulate = 0b10,
        exception_on_read_accumulate_on_writes = 0b11,
    } = .no_effect,
    // Allocation tag access in EL0
    ata0: enum(u1) {
        not_allowed = 0,
        allowed = 1,
    } = 0,
    // Allocation tag access in EL1
    ata: enum(u1) {
        not_allowed = 0,
        allowed = 1,
    } = 0,
    // Default SSBS value on exception entry
    dssbs: u1 = 0,
    // TWE delay enable
    tweden: u1 = 0,
    // TWE Delay
    twedel: u4 = 0,
    _unused_reserved_3: u4 = 0,
    // Trap execution of ST64BV instructions
    enasr: types.TrapEnableBitN,
    // Trap execution of ST64BV0
    enas0: types.TrapEnableBitN,
    // Trap execution of LD64B or ST64B
    enals: types.TrapEnableBitN,
    // Enhanced privileged access never
    epan: u1 = 0,
    _unused_reserved_4: u3 = 0,
    // Non-maskable interrupt enable
    nmi: u1 = 0,
    // SP interrupt mask enable
    spintmask: u1 = 0,
    // Trap "implementation defined" functionality
    tidcp: u1 = 0,
};

pub const LayoutEl3 = packed struct {
    mmu_enable: enum(u1) {
        disable = 0,
        enable = 1,
    },
    // Alignment check enable
    a: enum(u1) {
        disable = 0,
        enable = 1,
    },
    // Cacheability control
    c: u1,
    // Stack pointer alignment check enable
    sa: u1,
    _unused_reserved_0: u2 = 0b11,
    // Non-aligned access trap
    naa: types.TrapEnableBitN,
    _unused_reserved_1: u4 = 0,
    eos: u1,
    // Stage 1 instruction access cacheability control
    i: u1 = 0,
    // Enable pointer authentication
    endb: u1 = 0,
    _unused_reserved_2: u2 = 0,
    _unused_reserved_3: u1 = 1,
    _unused_reserved_4: u1 = 0,
    _unused_reserved_5: u1 = 1,
    // Write permission implies execute-never (NX)
    wxn: u1,
    _unused_reserved_6: u1 = 0,
    // Implicit error synchronization event enable
    iesb: u1 = 0,
    // Exception Entry is Context Switching
    eis: u1 = 1,
    _unused_reserved_7: u1 = 1,
    _unused_reserved_8: u1 = 0,
    // Endianness at EL3
    ee: enum(u1) {
        little_endian = 0,
        big_endian = 1,
    },
    _unused_reserved_9: u1 = 0,
    // Enable pointer authentication using APDAKey_EL1
    enda: u1 = 0,
    _unused_reserved_10: u2 = 0b11,
    // Enable pointer auth using APIBKey_EL1
    enib: u1 = 0,
    // Enable pointer auth using APIAKey_EL1 of instr addresses
    enia: u1 = 0,
    _unused_reserved_11: u4 = 0,
    // PAC branch type compatibility at EL3
    bt: u1 = 0,
    // Instuction tag fault synchronization bit
    itfsb: u1 = 0,
    _unused_reserved_12: u2 = 0,
    // Tag check fault in EL3
    tcf: enum(u2) {
        no_effect = 0b00,
        synchronous_exception = 0b01,
        asynchronous_accumulate = 0b10,
        exception_on_read_accumulate_on_writes = 0b11,
    } = .no_effect,
    _unused_reserved_13: u1 = 0,
    // Allocation tag access in EL1
    ata: enum(u1) {
        not_allowed = 0,
        allowed = 1,
    } = 0,
    // Default SSBS value on exception entry
    dssbs: u1 = 0,
    _unused_reserved_14: u20 = 0,
};
