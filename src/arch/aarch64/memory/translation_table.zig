/// AArch64 MMU translation table types
///
/// This is full of magic numbers and constants
///
/// They come from Part D of
/// [Arm Architecture Reference Manual for A-profile
/// architecture](https://developer.arm.com/documentation/ddi0487/ja/?lang=en)
///
/// Section and page references are from the revision dated 21 April
/// 2023
const std = @import("std");
//const memory = @import("../memory");
//const raspi = @import("../../../bsp/raspi3/memory");

/// The enum value is the "shift" implied by the granule size. This is
/// the number of bits to right shift a byte address to get a page
/// table index.
pub const Granule = enum(u32) {
    _4KB = 4 * 1024,
    _16KB = 16 * 1024,
    _64KB = 64 * 1024,
};

pub const Stage = enum {
    Stage1,
    Stage2,
};

pub const Level = enum {
    Level1,
    Level2,
};

/// From a "block size" (could be a page, a table, or a translation
/// granule), compute how many bits to right-shift an address to be a
/// multiple of that block.
///
/// Defensive programming: this should never be called on
/// smaller-than-page-size blocks. (I.e., the minimum block size is
/// 4096.) Anything else is probably a programming error.
fn memoryBlockShift(block_size: u64) u8 {
    var trailing_zeroes = @ctz(block_size);
    std.debug.assert(trailing_zeroes > 11);
    return trailing_zeroes;
}

pub fn FixedSizeTranslationTable(comptime table_count: u32) type {
    return struct {
        const Self = @This();

        level2: [table_count]TableDescriptor,
        level3: [table_count][8192]PageDescriptor,
    };
}

/// This function builds a struct type for a table descriptor. That is
/// an entry in one translation table that points to another,
/// next-level translation table.
///
/// See Section D8.3 - "Translation table descriptor formats", page D8-5856
pub fn TableDescriptor(comptime stage: Stage, comptime granule: Granule) type {
    const table_bits_needed = switch (granule) {
        ._4KB => 36,
        ._16KB => 34,
        ._64KB => 32,
    };

    const AddressBits = @Type(std.builtin.Type{ .Int = .{ .signedness = .unsigned, .bits = table_bits_needed } });
    const IgnoredBits = @Type(std.builtin.Type{ .Int = .{ .signedness = .unsigned, .bits = 46 - table_bits_needed } });

    return switch (stage) {
        .Stage1 => packed struct {
            descriptor_valid: enum(u1) {
                invalid = 0,
                valid = 1,
            } = .valid,
            descriptor_type: enum(u1) {
                table = 1,
            } = .table,
            ignored: IgnoredBits = 0,
            next_level_table: AddressBits = 0,
            _unused_reserved_0: u4 = 0,
            _unused_reserved_1: u7 = 0,
            pxn_table: u1 = 0,
            xn_table: u1 = 0,
            ap_table: u2 = 0,
            ns_table: u1 = 0,
        },
        .Stage2 => packed struct {
            descriptor_valid: enum(u1) {
                invalid = 0,
                valid = 1,
            } = .valid,
            descriptor_type: enum(u1) {
                block = 0,
                table = 1,
            } = .table,
            ignored: IgnoredBits = 0,
            next_level_table: AddressBits = 0,
            _unused_reserved_0: u4 = 0,
            _unused_ignored: u7 = 0,
            _unused_reserved_1: u5 = 0,
        },
    };
}

/// This function builds a struct type for a page descriptor. That is
/// an entry in a translation table that points to an actual page of memory
///
/// See Section D8.3 - "Translation table descriptor formats", page
/// D8-5856
///
/// Note this does not (yet?) support 52-bit OAs
pub fn PageDescriptor(comptime stage: Stage, comptime granule: Granule) type {
    const address_bits_needed = switch (granule) {
        ._4KB => 36,
        ._16KB => 34,
        ._64KB => 32,
    };

    const AddressBits = @Type(std.builtin.Type{ .Int = .{ .signedness = .unsigned, .bits = address_bits_needed } });
    const IgnoredBits = @Type(std.builtin.Type{ .Int = .{ .signedness = .unsigned, .bits = 36 - address_bits_needed } });

    return switch (stage) {
        .Stage1 => packed struct {
            // [0]
            descriptor_valid: enum(u1) {
                invalid = 0,
                valid = 1,
            } = .valid,
            // [1]
            descriptor_type: enum(u1) { page = 1 } = .page,
            // [4:2]
            memory_attributes_index: u3 = 0,
            // [5]
            nonsecure: u1 = 0,
            // [7:6]
            access_permissions: enum(u2) {
                ReadWrite_EL1 = 0b00,
                ReadWrite_EL1_EL0 = 0b01,
                ReadOnly_EL1 = 0b10,
                ReadOnly_EL1_EL0 = 0b11,
            } = .ReadWrite_EL1_EL0,
            // [9:8]
            shareability: enum(u2) {
                OuterShareable = 0b10,
                InnerShareable = 0b11,
            } = .OuterShareable,
            // [10]
            access_flag: u1 = 0,
            // [11]
            not_global: u1 = 0,
            // next two fields together are [47:12]
            reserved: IgnoredBits = 0,
            output_address: AddressBits = 0,
            // [49:48]
            _unused_reserved_0: u2 = 0,
            // [50]
            guarded_page: u1 = 0,
            // [51]
            dirty_bit_modifier: u1 = 0,
            // [52]
            contiguous: u1 = 0,
            // [53]
            privileged_execute_never: u1 = 0,
            // [54]
            unprivileged_execute_never: u1 = 0,
            // [58:55]
            _unused_ignored_0: u4 = 0, // Reference manual says "reserved for software use"
            // [62:59]
            _unused_ignored_1: u4 = 0,
            // [63]
            _unused_ignored_2: u1 = 0,
        },
        .Stage2 => packed struct {
            // [0]
            descriptor_valid: enum(u1) {
                invalid = 0,
                valid = 1,
            } = .valid,
            // [1]
            descriptor_type: enum(u1) { page = 1 } = .page,
            // [4:2]
            memory_attributes_index: u3,
            // [5] TODO: check if we need HCR_EL2.FWB false. If so, this is memory attribute index
            // bit 4
            _unused_reserved_0: u1 = 0,
            // [7:6]
            access_permissions: enum(u2) {
                ReadWrite_EL1 = 0b00,
                ReadWrite_EL1_EL0 = 0b01,
                ReadOnly_EL1 = 0b10,
                ReadOnly_EL1_EL0 = 0b11,
            },
            // [9:8]
            shareability: enum(u2) {
                OuterShareable = 0b10,
                InnerShareable = 0b11,
            },
            // [10]
            access_flag: u1,
            // [11]
            not_global: u1,
            // next two fields together are [47:12]
            reserved: IgnoredBits,
            output_address: AddressBits,
            // [49:48]
            _unused_reserved_1: u2 = 0,
            // [50]
            _unused_reserved_2: u1 = 0,
            // [51]
            dirty_bit_modifier: u1 = 0,
            // [52]
            contiguous: u1 = 0,
            // [53]
            _unused_reserved_3: u1 = 0,
            // [54]
            execute_never: u1,
            // [55]
            not_secure: u1,
            // [58:56]
            _unused_ignored_0: u3 = 0, // Reference manual says "reserved for software use"
            // [62:59]
            _unused_ignored_1: u4 = 0,
            // [63]
            _unused_ignored_2: u1 = 0, // Reserved for use by a System MMU
        },
    };
}

test "table descriptors are all 64 bits" {
    const expect = @import("std").testing.expect;
    try expect(@bitSizeOf(TableDescriptor(Stage.Stage1, Granule._4KB)) == 64);
    try expect(@bitSizeOf(TableDescriptor(Stage.Stage2, Granule._4KB)) == 64);
    try expect(@bitSizeOf(TableDescriptor(Stage.Stage1, Granule._16KB)) == 64);
    try expect(@bitSizeOf(TableDescriptor(Stage.Stage2, Granule._16KB)) == 64);
    try expect(@bitSizeOf(TableDescriptor(Stage.Stage1, Granule._64KB)) == 64);
    try expect(@bitSizeOf(TableDescriptor(Stage.Stage2, Granule._64KB)) == 64);
}

test "page descriptors are all 64 bits" {
    const expect = @import("std").testing.expect;
    try expect(@bitSizeOf(PageDescriptor(Stage.Stage1, Granule._4KB)) == 64);
    try expect(@bitSizeOf(PageDescriptor(Stage.Stage2, Granule._4KB)) == 64);
    try expect(@bitSizeOf(PageDescriptor(Stage.Stage1, Granule._16KB)) == 64);
    try expect(@bitSizeOf(PageDescriptor(Stage.Stage2, Granule._16KB)) == 64);
    try expect(@bitSizeOf(PageDescriptor(Stage.Stage1, Granule._64KB)) == 64);
    try expect(@bitSizeOf(PageDescriptor(Stage.Stage2, Granule._64KB)) == 64);
}
