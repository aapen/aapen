const types = @import("../system_register.zig");

/// See
/// https://developer.arm.com/documentation/ddi0595/2021-12/AArch64-Registers/HCR-EL2--Hypervisor-Configuration-Register
pub const Layout = packed struct {
    // virtualization enable
    vm: enum(u1) {
        disable = 0,
        enable = 1,
    }, // 0
    // Set/way invalidation override
    swio: enum(u1) {
        no_effect = 0,
        clean_and_invalidate = 1,
    }, // 1
    // Protected table walk
    ptw: enum(u1) {
        normal = 0,
        permission_fault = 1,
    }, // 2
    // Physical FIQ routing
    fmo: u1, // 3
    // Physical IRQ routing
    imo: u1, // 4
    // Physical SError interrupt routing
    amo: u1, // 5
    // Virtual FIQ interrupt
    vf: u1, // 6
    // Virtual IRQ interrupt
    vi: u1, // 7
    // Virtual SError interrupt
    vse: u1, // 8
    // Force broadcast
    fb: u1, // 9
    // Barrier shareability upgrade
    bsu: enum(u2) {
        no_effect = 0b00,
        inner_shareable = 0b01,
        outer_shareable = 0b10,
        full_system = 0b11,
    }, // 10..11
    // Default cacheability
    dc: u1, // 12
    // Trap WFI instructions
    twi: types.TrapEnableBitP, // 13
    // Trap WFE instructions
    twe: types.TrapEnableBitP, // 14
    // Trap ID group 0
    tid0: types.TrapEnableBitP, // 15
    // Trap ID group 1
    tid1: types.TrapEnableBitP, // 16
    // Trap ID group 2
    tid2: types.TrapEnableBitP, // 17
    // Trap ID group 3
    tid3: types.TrapEnableBitP, // 18
    // Trap SMC instructions
    tsc: types.TrapEnableBitP, // 19
    // Trap implementation defined functionality
    tidcp: types.TrapEnableBitP, // 20
    // Trap auxiliary control registers
    tacr: types.TrapEnableBitP, // 21
    // Trap Set/Way cache maintenance instructions
    tsw: types.TrapEnableBitP, // 22
    // Trap Point of Coherency cache maintenance instructions
    // NOTE: if FEAT_DBP is implemented this field controls TPCP (Trap
    // Point of Coherency or Persistence) instead of TPC. Same bit,
    // two meanings depending on feature set.
    tpc: types.TrapEnableBitP, // 23
    // Trap Point of Unification cache maintenance instructions
    tpu: types.TrapEnableBitP, // 24
    // Trap TLB maintenance instructions
    ttlb: types.TrapEnableBitP, // 25
    // Trap virtual memory controls
    tvm: types.TrapEnableBitP, // 26
    // Trap general exceptions
    tge: types.TrapEnableBitP, // 27
    // Trap data cache zero by virtual address instructions
    tdz: types.TrapEnableBitP, // 28
    // HVC instruction disable
    hcd: enum(u1) { enabled = 0, trap_as_undefined = 1 }, // 29
    // Trap reads of virtual memory controls
    trvm: types.TrapEnableBitP, // 30
    // RW (?)
    rw: enum(u1) {
        el1_is_aarch32 = 0,
        el1_is_aarch64 = 1,
    }, // 31
    // Cache disable
    cd: enum(u1) {
        no_effect = 0,
        dont_cache_data_access = 1,
    }, // 32
    // Instruction access cacheability disable
    id: enum(u1) {
        no_effect = 0,
        dont_cache_instruction_access = 1,
    }, // 33
    // EL2 Host
    e2h: enum(u1) {
        disable_host_at_el2 = 0,
        enable_host_at_el2 = 1,
    }, // 34
    // Trap LOR registers
    tlor: types.TrapEnableBitP, // 35
    // Trap error record access
    terr: types.TrapEnableBitP, // 36
    // Trap external abort exceptions to EL2
    tea: types.TrapEnableBitP, // 37
    // Mismatched inner/outer cacheable non-coherency enable
    miocnce: u1, // 38
    _unused_reserved_0: u1 = 0, // 39
    // Trap pointer authentication registers
    apk: types.TrapEnableBitN, // 40
    // Trap pointer authentication instructions
    api: types.TrapEnableBitN, // 41
    // Nested virtualization
    nv: u1, // 42
    // Nested virtualization 1
    nv1: u1, // 43
    // Address translation
    at: types.TrapEnableBitP, // 44
    // Nested virtualization 2 (?!)
    nv2: u1, // 45
    // Forced write-back
    fwb: u1, // 46
    // Fault injection enable
    fien: types.TrapEnableBitN, // 47
    _unused_reserved_1: u1 = 0, // 48
    // Trap ID group 4
    tid4: types.TrapEnableBitP, // 49
    // Trap ICIALLUIS/IC IALLUIS cache instructions
    ticab: types.TrapEnableBitP, // 50
    // Activity monitor virtual offsets enable
    amvoffen: enum(u1) {
        disable = 0,
        enable = 1,
    }, // 51
    // Trap Point of Unification cache maintenance instructions
    tocu: types.TrapEnableBitP, // 52
    // Enable access to SCXTNUM_EL1 and SCXTNUM_EL0 registers
    enscxt: types.TrapEnableBitN, // 53
    // Trap TLB maintenance instructions on inner shareable domain
    ttlbis: types.TrapEnableBitP, // 54
    // Trap TLB maintenance instructions on outer shareable domain
    ttlbos: types.TrapEnableBitP, // 55
    // Trap allocation tag accesses
    ata: types.TrapEnableBitN, // 56
    // Default cacheability tagging
    dct: enum(u1) {
        treat_as_untagged = 0,
        treat_as_tagged = 1,
    }, // 57
    // Trap ID group 5
    tid5: types.TrapEnableBitP, // 58
    // Trap TWE delay enable
    tweden: enum(u1) {
        implementation_defined = 0,
        delay_by_twedel_cycles = 1,
    }, // 59
    // TWE delay
    twedel: u4, // 60..63
};
