const types = @import("../system_register.zig");

/// See
/// https://developer.arm.com/documentation/ddi0595/2021-12/AArch64-Registers/HCR-EL2--Hypervisor-Configuration-Register
pub const layout = packed struct {
    // virtualization enable
    VM: enum(u1) {
        disable = 0,
        enable = 1,
    },
    // Set/way invalidation override
    SWIO: enum(u1) {
        no_effect = 0,
        clean_and_invalidate = 1,
    },
    // Protected table walk
    PTW: enum(u1) {
        normal = 0,
        permission_fault = 1,
    },
    // Physical FIQ routing
    FMO: u1,
    // Physical IRQ routing
    IMO: u1,
    // Physical SError interrupt routing
    AMO: u1,
    // Virtual FIQ interrupt
    VF: u1,
    // Virtual IRQ interrupt
    VI: u1,
    // Virtual SError interrupt
    VSE: u1,
    // Force broadcast
    FB: u1,
    // Barrier shareability upgrade
    BSU: enum(u2) {
        no_effect = 0b00,
        inner_shareable = 0b01,
        outer_shareable = 0b10,
        full_system = 0b11,
    },
    // Default cacheability
    DC: u1,
    // Trap WFI instructions
    TWI: types.TrapEnableBitP,
    // Trap WFE instructions
    TWE: types.TrapEnableBitP,
    // Trap ID group 0
    TID0: types.TrapEnableBitP,
    // Trap ID group 1
    TID1: types.TrapEnableBitP,
    // Trap ID group 2
    TID2: types.TrapEnableBitP,
    // Trap ID group 3
    TID3: types.TrapEnableBitP,
    // Trap SMC instructions
    TSC: types.TrapEnableBitP,
    // Trap implementation defined functionality
    TIDCP: types.TrapEnableBitP,
    // Trap auxiliary control registers
    TACR: types.TrapEnableBitP,
    // Trap Set/Way cache maintenance instructions
    TSW: types.TrapEnableBitP,
    // Trap Point of Coherency cache maintenance instructions
    // NOTE: if FEAT_DBP is implemented this field controls TPCP (Trap
    // Point of Coherency or Persistence) instead of TPC. Same bit,
    // two meanings depending on feature set.
    TPC: types.TrapEnableBitP,
    // Trap Point of Unification cache maintenance instructions
    TPU: types.TrapEnableBitP,
    // Trap TLB maintenance instructions
    TTLB: types.TrapEnableBitP,
    // Trap virtual memory controls
    TVM: types.TrapEnableBitP,
    // Trap general exceptions
    TGE: types.TrapEnableBitP,
    // Trap data cache zero by virtual address instructions
    TDZ: types.TrapEnableBitP,
    // HVC instruction disable
    HCD: enum(u1) { enabled = 0, trap_as_undefined = 1 },
    // Trap reads of virtual memory controls
    TRVM: types.TrapEnableBitP,
    // RW (?)
    RW: enum(u1) {
        el1_is_aarch32 = 0,
        el1_is_aarch64 = 1,
    },
    // Cache disable
    CD: enum(u1) {
        no_effect = 0,
        dont_cache_data_access = 1,
    },
    // Instruction access cacheability disable
    ID: enum(u1) {
        no_effect = 0,
        dont_cache_instruction_access = 1,
    },
    // EL2 Host
    E2H: enum(u1) {
        disable_host_at_el2 = 0,
        enable_host_at_el2 = 1,
    },
    // Trap LOR registers
    TLOR: types.TrapEnableBitP,
    // Trap error record access
    TERR: types.TrapEnableBitP,
    // Trap external abort exceptions to EL2
    TEA: types.TrapEnableBitP,
    // Mismatched inner/outer cacheable non-coherency enable
    MIOCNCE: u1,
    _unused_reserved_0: u1,
    // Trap pointer authentication registers
    APK: types.TrapEnableBitN,
    // Trap pointer authentication instructions
    API: types.TrapEnableBitN,
    // Nested virtualization
    NV: u1,
    // Nested virtualization 1
    NV1: u1,
    // Address translation
    AT: types.TrapEnableBitP,
    // Nested virtualization 2 (?!)
    NV2: u1,
    // Forced write-back
    FWB: u1,
    // Fault injection enable
    FIEN: types.TrapEnableBitN,
    _unused_reserved_1: u1,
    // Trap ID group 4
    TID4: types.TrapEnableBitP,
    // Trap ICIALLUIS/IC IALLUIS cache instructions
    TICAB: types.TrapEnableBitP,
    // Activity monitor virtual offsets enable
    AMVOFFEN: enum(u1) {
        disable = 0,
        enable = 1,
    },
    // Trap Point of Unification cache maintenance instructions
    TOCU: types.TrapEnableBitP,
    // Enable access to SCXTNUM_EL1 and SCXTNUM_EL0 registers
    EnSCXT: types.TrapEnableBitN,
    // Trap TLB maintenance instructions on inner shareable domain
    TTLBIS: types.TrapEnableBitP,
    // Trap TLB maintenance instructions on outer shareable domain
    TTLBOS: types.TrapEnableBitP,
    // Trap allocation tag accesses
    ATA: types.TrapEnableBitN,
    // Default cacheability tagging
    DCT: enum(u1) {
        treat_as_untagged = 0,
        treat_as_tagged = 1,
    },
    // Trap ID group 5
    TID5: types.TrapEnableBitP,
    // Trap TWE delay enable
    TWEDEn: enum(u1) {
        implementation_defined = 0,
        delay_by_twedel_cycles = 1,
    },
    // TWE delay
    TWEDEL: u4,
};
