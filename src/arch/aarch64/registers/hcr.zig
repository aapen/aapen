const types = @import("../system_register.zig");

/// See
/// https://developer.arm.com/documentation/ddi0595/2021-12/AArch64-Registers/HCR-EL2--Hypervisor-Configuration-Register
pub const Layout = packed struct {
    // virtualization enable
    vm: enum(u1) {
        disable = 0,
        enable = 1,
    },
    // Set/way invalidation override
    swio: enum(u1) {
        no_effect = 0,
        clean_and_invalidate = 1,
    },
    // Protected table walk
    ptw: enum(u1) {
        normal = 0,
        permission_fault = 1,
    },
    // Physical FIQ routing
    fmo: u1,
    // Physical IRQ routing
    imo: u1,
    // Physical SError interrupt routing
    amo: u1,
    // Virtual FIQ interrupt
    vf: u1,
    // Virtual IRQ interrupt
    vi: u1,
    // Virtual SError interrupt
    vse: u1,
    // Force broadcast
    fb: u1,
    // Barrier shareability upgrade
    bsu: enum(u2) {
        no_effect = 0b00,
        inner_shareable = 0b01,
        outer_shareable = 0b10,
        full_system = 0b11,
    },
    // Default cacheability
    dc: u1,
    // Trap WFI instructions
    twi: types.TrapEnableBitP,
    // Trap WFE instructions
    twe: types.TrapEnableBitP,
    // Trap ID group 0
    tid0: types.TrapEnableBitP,
    // Trap ID group 1
    tid1: types.TrapEnableBitP,
    // Trap ID group 2
    tid2: types.TrapEnableBitP,
    // Trap ID group 3
    tid3: types.TrapEnableBitP,
    // Trap SMC instructions
    tsc: types.TrapEnableBitP,
    // Trap implementation defined functionality
    tidcp: types.TrapEnableBitP,
    // Trap auxiliary control registers
    tacr: types.TrapEnableBitP,
    // Trap Set/Way cache maintenance instructions
    tsw: types.TrapEnableBitP,
    // Trap Point of Coherency cache maintenance instructions
    // NOTE: if FEAT_DBP is implemented this field controls TPCP (Trap
    // Point of Coherency or Persistence) instead of TPC. Same bit,
    // two meanings depending on feature set.
    tpc: types.TrapEnableBitP,
    // Trap Point of Unification cache maintenance instructions
    tpu: types.TrapEnableBitP,
    // Trap TLB maintenance instructions
    ttlb: types.TrapEnableBitP,
    // Trap virtual memory controls
    tvm: types.TrapEnableBitP,
    // Trap general exceptions
    tge: types.TrapEnableBitP,
    // Trap data cache zero by virtual address instructions
    tdz: types.TrapEnableBitP,
    // HVC instruction disable
    hcd: enum(u1) { enabled = 0, trap_as_undefined = 1 },
    // Trap reads of virtual memory controls
    trvm: types.TrapEnableBitP,
    // RW (?)
    rw: enum(u1) {
        el1_is_aarch32 = 0,
        el1_is_aarch64 = 1,
    },
    // Cache disable
    cd: enum(u1) {
        no_effect = 0,
        dont_cache_data_access = 1,
    },
    // Instruction access cacheability disable
    id: enum(u1) {
        no_effect = 0,
        dont_cache_instruction_access = 1,
    },
    // EL2 Host
    e2h: enum(u1) {
        disable_host_at_el2 = 0,
        enable_host_at_el2 = 1,
    },
    // Trap LOR registers
    tlor: types.TrapEnableBitP,
    // Trap error record access
    terr: types.TrapEnableBitP,
    // Trap external abort exceptions to EL2
    tea: types.TrapEnableBitP,
    // Mismatched inner/outer cacheable non-coherency enable
    miocnce: u1,
    _unused_reserved_0: u1 = 0,
    // Trap pointer authentication registers
    apk: types.TrapEnableBitN,
    // Trap pointer authentication instructions
    api: types.TrapEnableBitN,
    // Nested virtualization
    nv: u1,
    // Nested virtualization 1
    nv1: u1,
    // Address translation
    at: types.TrapEnableBitP,
    // Nested virtualization 2 (?!)
    nv2: u1,
    // Forced write-back
    fwb: u1,
    // Fault injection enable
    fien: types.TrapEnableBitN,
    _unused_reserved_1: u1 = 0,
    // Trap ID group 4
    tid4: types.TrapEnableBitP,
    // Trap ICIALLUIS/IC IALLUIS cache instructions
    ticab: types.TrapEnableBitP,
    // Activity monitor virtual offsets enable
    amvoffen: enum(u1) {
        disable = 0,
        enable = 1,
    },
    // Trap Point of Unification cache maintenance instructions
    tocu: types.TrapEnableBitP,
    // Enable access to SCXTNUM_EL1 and SCXTNUM_EL0 registers
    enscxt: types.TrapEnableBitN,
    // Trap TLB maintenance instructions on inner shareable domain
    ttlbis: types.TrapEnableBitP,
    // Trap TLB maintenance instructions on outer shareable domain
    ttlbos: types.TrapEnableBitP,
    // Trap allocation tag accesses
    ata: types.TrapEnableBitN,
    // Default cacheability tagging
    dct: enum(u1) {
        treat_as_untagged = 0,
        treat_as_tagged = 1,
    },
    // Trap ID group 5
    tid5: types.TrapEnableBitP,
    // Trap TWE delay enable
    tweden: enum(u1) {
        implementation_defined = 0,
        delay_by_twedel_cycles = 1,
    },
    // TWE delay
    twedel: u4,
};
