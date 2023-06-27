/// AArch64-specific memory subsystem
const AddressSpace = @import("memory/address_space.zig");
const TranslationTable = @import("memory/translation_table.zig");

const Memory = @This();

const AddressType = AddressSpace.AddressType;

// TODO: surely this should be determined at runtime?
pub const TableDescriptor = TranslationTable.TableDescriptor(TranslationTable.Stage.Stage1, TranslationTable.Granule._64KB);
pub const PageDescriptor = TranslationTable.PageDescriptor(TranslationTable.Stage.Stage1, TranslationTable.Granule._64KB);

// TODO: surely this should be supplied at runtime by the board
// itself? Anyway, 4096 table entries, each covering a 512MB range
// covers the 4GB of RAM found on a Raspberry Pi 3.
//
// Table count is ((max address) >> block_shift_512_mb) + 1
// block shift for 512MB is 28 bits (28 trailing zeros on 512 * 1024 * 1024)
pub const level_2_table_count = 4;

// these "work" (they compile and I can access the words)
const level2: [4]u64 = [_]u64{0} ** 4;
const level3: [4][8192]u64 = [_]([8192]u64){[_]u64{0} ** 8192} ** 4;

// these wedge the compiler (100% CPU forever)
// const level2: [4]TableDescriptor = [_]TableDescriptor{.{}} ** 4;
// const level3: [4][8192]PageDescriptor = [_]([8192]PageDescriptor){[_]PageDescriptor{.{}} ** 8192} ** 4;

test "printf debugging" {
    const print = @import("std").debug.print;

    print("\n", .{});
    for (level2, 0..) |_, index| {
        print("*level2[{}]: {x}\n", .{ index, &level2[index] });
    }

    // for (level3, 0..) |_, row_index| {
    //     for (level3[row_index], 0..) |_, col_index| {
    //         print("*level3[{}][{}]: {x}\n", .{ row_index, col_index, &level3[row_index][col_index] });
    //     }
    // }
}
