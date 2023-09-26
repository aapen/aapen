const types = @import("../system_register.zig");

pub const Cacheability = enum(u2) {
    noncacheable = 0b00,
    wb_ra_wa_cacheable = 0b01,
    wt_ra_nwa_cacheable = 0b10,
    wb_ra_nwa_cacheable = 0b11,
};

pub const Shareability = enum(u2) {
    non_shareable = 0b00,
    outer_shareable = 0b10,
    inner_shareable = 0b11,
};

pub const TranslationGranule = enum(u2) {
    granule_4kb = 0b00,
    granule_64kb = 0b01,
    granule_16kb = 0b10,
};
pub const TopByteUsed = enum(u1) {
    top_byte_used = 0b0,
    top_byte_ignored = 0b1,
};

pub const HierarchicalPermissions = enum(u1) {
    hierarchical_permissions_enabled = 0b0,
    hierarchical_permissions_disabled = 0b1,
};

// 0x200803518 (value used in mmu.S)

//    6    5    5    4    4    4    3    3    2    2    2    1    1
//    0    6    2    8    4    0    6    2    8    4    0    6    2    8    4    0
// 0000 0000 0000 0000 0000 0000 0000 0010 0000 0000 1000 0000 0011 0101 0001 1000

pub const Layout = packed struct {
    t0sz: u6 = 0x18,
    _reserved_0: u1 = 0,
    epd0: u1 = 0,
    irgn0: Cacheability = .wt_ra_nwa_cacheable,
    orgn0: Cacheability = .wt_ra_nwa_cacheable,
    sh0: Shareability = .inner_shareable,
    tg0: TranslationGranule = .granule_4kb,
    t1sz: u6 = 0,
    a1: enum(u1) {
        ttbr0_defines_asid = 0b0,
        ttbr1_defines_asid = 0b1,
    } = .ttbr0_defines_asid,
    epd1: enum(u1) {
        perform_table_walk_on_tlb_miss = 0b0,
        translation_fault_on_tlb_miss = 0b1,
    } = .translation_fault_on_tlb_miss,
    irgn1: Cacheability = .noncacheable,
    orgn1: Cacheability = .noncacheable,
    sh1: Shareability = .non_shareable,
    tg1: TranslationGranule = .granule_4kb,
    ips: enum(u3) {
        as_4gb = 0b000, // 32 bits
        as_64gb = 0b001, // 36 bits
        as_1tb = 0b010, // 40 bits
        as_4tb = 0b011, // 42 bits
        as_16tb = 0b100, // 44 bits
        as_256tb = 0b101, // 48 bits
        as_4pb = 0b111, // 52 bits
    } = .as_1tb,
    _reserved_1: u1 = 0,
    as: enum(u1) {
        asid_8bit = 0b0,
        asid_16bit = 0b1,
    } = .asid_8bit,
    tbi0: TopByteUsed = .top_byte_used,
    tbi1: TopByteUsed = .top_byte_used,
    ha: enum(u1) {
        stage1_access_flag_update_disabled = 0b0,
        stage1_access_flag_update_enabled = 0b1,
    } = .stage1_access_flag_update_disabled,
    hd: enum(u1) {
        stage1_dirty_flag_hw_mgmt_disabled = 0b0,
        stage1_dirty_flag_hw_mgmt_enabled = 0b1,
    } = .stage1_dirty_flag_hw_mgmt_disabled,
    hpd0: HierarchicalPermissions = .hierarchical_permissions_enabled,
    hpd1: HierarchicalPermissions = .hierarchical_permissions_enabled,
    hwu059: u1 = 0,
    hwu060: u1 = 0,
    hwu061: u1 = 0,
    hwu062: u1 = 0,
    hwu159: u1 = 0,
    hwu160: u1 = 0,
    hwu161: u1 = 0,
    hwu162: u1 = 0,
    tbid0: enum(u1) {
        instruction_and_data = 0b0,
        data_only = 0b1,
    } = .instruction_and_data,
    tbid1: enum(u1) {
        instruction_and_data = 0b0,
        data_only = 0b1,
    } = .instruction_and_data,
    nfd0: u1 = 0,
    nfd1: u1 = 0,
    e0pd0: u1 = 0,
    e0pd1: u1 = 0,
    tcma0: u1 = 0,
    tcma1: u1 = 0,
    ds: u1 = 0,
    _reserved_2: u4 = 0,
};
