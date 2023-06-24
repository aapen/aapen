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

pub const Granule = enum {
    _4KB,
    _16KB,
    _64KB,
};

pub const Stage = enum {
    Stage1,
    Stage2,
};

pub const Level = enum {
    Level1,
    Level2,
};

/// This function builds a struct type for a table descriptor. That is
/// an entry in one translation table that points to another,
/// next-level translation table.
///
/// See Section D8.3 - "Translation table descriptor formats"
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
            ignored: IgnoredBits,
            next_level_table: AddressBits,
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
            ignored: IgnoredBits,
            next_level_table: AddressBits,
            _unused_reserved_0: u4 = 0,
            _unused_ignored: u7 = 0,
            _unused_reserved_1: u5 = 0,
        },
    };
}

/// This function builds a struct type for a block descriptor. That is
/// an entry in a translation table that points to an actual page or
/// block of memory
///
/// See Section D8.3 - "Translation table descriptor formats"
pub fn BlockDescriptor(comptime level: Level, comptime granule: Granule) type {
    const block_bits_needed = switch (granule) {
        ._4KB => switch (level) {
            .Level1 => 18,
            .Level2 => 27,
        },
        ._16KB => 23,
        ._64KB => 19,
    };

    const AddressBits = @Type(std.builtin.Type{ .Int = .{ .signedness = .unsigned, .bits = block_bits_needed } });
    const IgnoredBits = @Type(std.builtin.Type{ .Int = .{ .signedness = .unsigned, .bits = 36 - block_bits_needed } });

    return packed struct {
        descriptor_valid: enum(u1) {
            invalid = 0,
            valid = 1,
        } = .valid,
        descriptor_type: enum(u1) {
            block = 0,
        } = .block,
        memory_attributes_index: u3,
        nonsecure: u1,
        access_permissions: enum(u2) {
            ReadWrite_EL1 = 0b00,
            ReadWrite_EL1_EL0 = 0b01,
            ReadOnly_EL1 = 0b10,
            ReadOnly_EL1_EL0 = 0b11,
        },
        shareability: enum(u2) {
            OuterShareable = 0b10,
            InnerShareable = 0b11,
        },
        access_flag: u1,
        not_global: u1,
        reserved: IgnoredBits,
        output_address: AddressBits,
        _unused_reserved_0: u4 = 0,
        _undefined_upper_block_attributes: u10,
        privileged_execute_never: u1,
        unprivileged_execute_never: u1,
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

test "block descriptors are all 64 bits" {
    const expect = @import("std").testing.expect;

    try expect(@bitSizeOf(BlockDescriptor(Level.Level1, Granule._64KB)) == 64);
}
