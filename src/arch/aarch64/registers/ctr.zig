/// Cache type register
///
/// See https://developer.arm.com/documentation/ddi0595/2021-12/AArch64-Registers/CTR-EL0--Cache-Type-Register?lang=en
const types = @import("../system_register.zig");

pub const Layout = packed struct {
    // log2 of the number of words in the smallest cache line of all
    // the instruction caches controlled by the PE
    imin_line: u4 = 0,
    _unused_reserved: u9 = 0,
    // level 1 instruction cache policy
    l1ip: enum(u2) {
        vmid_aware_physical_tag = 0b00,
        asid_tagged_virtual_index = 0b01,
        virtual_index_physical_tag = 0b10,
        physical_index_physical_tag = 0b11,
    } = .physical_index_physical_tag,
    // log2 of the number of words in the smallest cache line of all
    // the data caches controlled by the PE
    dmin_line: u4 = 0,
    // exclusives reservation granule
    // log2 of the number of words of the maximum size of the
    // reservation granule that has been implemented for the
    // Load-Exclusive and Store-Exclusive instructions
    erg: u4 = 0b0010,
    // Cache writeback granule
    // log2 of the number of words of the maximum size of memory that
    // can be overwritten as a result of the eviction of a cache entry
    // that has had a memory location in it modified.
    cwg: u4 = 0b0001,
    // Data cache clean requirements for instruction to data
    // coherence.
    idc: enum(u1) {
        point_of_unification_required = 0b0,
        point_of_unification_not_required = 0b1,
    } = .point_of_unification_not_required,
    // Instruction cache invalidation requirements for data to
    // instruction coherence
    dic: enum(u1) {
        point_of_unification_required = 0b0,
        point_of_unification_not_required = 0b1,
    } = .point_of_unification_not_required,
    _unused_reserved_1: u1 = 0,
    _unused_reserved_2: u1 = 1,
};
