pub const memory_map = @import("../../bsp/raspi3/memory_map.zig");

// Assumptions
//
// - Translation granule is 4KB
// - Physical addresses are all RAM until the devices, then it's only
//   devices above that

// These are fundamental to the processor
pub const page_shift: u8 = 12;
pub const table_shift: u8 = 9;
pub const section_shift: u8 = page_shift + table_shift;

pub const entries_per_table: u16 = 1 << table_shift;
pub const page_size: u64 = 1 << page_shift;
pub const section_size: u64 = 1 << section_shift;

// These are choices about memory layout
// pub const VA_START = 0xffff000000000000;
pub const block_size: u64 = 0x40000000;
pub const device_start: u64 = memory_map.device_start;

// These are choices about memory protection
pub const mair_device_ng_nr_ne: u8 = 0x0;
pub const mair_device_ng_nr_ne_index: u2 = 0;

pub const mair_normal_nc: u8 = 0x44;
pub const mair_normal_nc_INDEX: u2 = 1;

pub const mair_value: u64 = (mair_normal_nc << (8 * mair_normal_nc_INDEX)) | (mair_device_ng_nr_ne << (8 * mair_device_ng_nr_ne_index));

pub const table_descriptor_valid: u64 = (1 << 0);
pub const table_descriptor_is_table: u64 = (1 << 1);
pub const table_descriptor_access: u64 = (1 << 10);
pub const table_descriptor_kernel_perms: u64 = (1 << 54);
pub const table_descriptor_inner_shareable: u64 = (3 << 8);

pub const kernel_table_flags: u64 = (table_descriptor_is_table | table_descriptor_valid);
pub const kernel_block_flags: u64 = (table_descriptor_access | table_descriptor_inner_shareable | table_descriptor_kernel_perms | (@as(u8, mair_normal_nc_INDEX) << 2) | table_descriptor_valid);
pub const device_block_flags: u64 = (table_descriptor_access | table_descriptor_inner_shareable | table_descriptor_kernel_perms | (@as(u8, mair_device_ng_nr_ne_index) << 2) | table_descriptor_valid);

// AArch64 address translation
// Assumes 4KB translation granule
//
//                             Virtual address                                                                 Physical Memory
//  +-----------------------------------------------------------------------+                                +------------------+
//  |         | PGD Index | PUD Index | PMD Index | PTE Index | Page offset |                                |                  |
//  +-----------------------------------------------------------------------+                                |                  |
//  63        47     |    38      |   29     |    20    |     11      |     0                                |     Page N       |
//                   |            |          |          |             +--------------------+           +---->+------------------+
//                   |            |          |          +---------------------+            |           |     |                  |
//            +------+            |          |                                |            |           |     |                  |
//            |                   |          +----------+                     |            |           |     |------------------|
//  +------+  |        PGD        |                     |                     |            +---------------->| Physical address |
//  | ttbr |---->+-------------+  |           PUD       |                     |                        |     |------------------|
//  +------+  |  |             |  | +->+-------------+  |          PMD        |                        |     |                  |
//            |  +-------------+  | |  |             |  | +->+-------------+  |          PTE           |     +------------------+
//            +->| PUD address |----+  +-------------+  | |  |             |  | +->+--------------+    |     |                  |
//               +-------------+  +--->| PMD address |----+  +-------------+  | |  |              |    |     |                  |
//               |             |       +-------------+  +--->| PTE address |----+  +-------------_+    |     |                  |
//               +-------------+       |             |       +-------------+  +--->| Page address |----+     |                  |
//                                     +-------------+       |             |       +--------------+          |                  |
//                                                           +-------------+       |              |          |                  |
//                                                                                 +--------------+          +------------------+
//
// PGD := Page Global Directory, level 0 translation table
// PUD := Page Upper Directory, level 1 translation table
// PMD := Page Middle Directory, level 2 translation table
// PTE := Page Table Entry, level 3 translation table
//
// For RPi3 we can use just 1 PGD, and 1 PUD. These will cover the 1GB
// address space.

pub const page_global_directory_shift: u8 = page_shift + 3 * table_shift;
pub const page_upper_directory_shift: u8 = page_shift + 2 * table_shift;
pub const page_middle_directory_shift: u8 = page_shift + table_shift;
pub const page_upper_directory_entry_map_size: u64 = 1 << page_upper_directory_shift;

// The tables we need will fit in 6 memory pages.
// Make sure this matches the section allocation in kernel.ld
pub const page_table_size: u64 = 6 * page_size;

extern fn mmu_on() void;

pub fn init() void {
    pageTablesCreate();
    // pagetable_init();
    mmu_on();
}

extern const __page_tables_start: u64;

extern fn memzero(begin: u64, end_exclusive: u64) void;

fn tableEntryCreate(table: u64, next_level_table: u64, virtual_address: u64, chosen_table_shift: u6, flags: u64) void {
    var table_index = virtual_address >> chosen_table_shift;
    table_index &= (entries_per_table - 1);
    var descriptor: u64 = next_level_table | flags;
    var word: *u64 = @ptrFromInt(table + (table_index << 3));
    word.* = descriptor;
}

fn blockMappingCreate(page_middle_directory: u64, virtual_addr_start: u64, virtual_addr_end: u64, phys_addr_start: u64) void {
    var vstart = virtual_addr_start >> section_shift;
    vstart &= (entries_per_table - 1);

    var vend = virtual_addr_end >> section_shift;
    vend -= 1;
    vend &= (entries_per_table - 1);

    var pa = phys_addr_start >> section_shift;
    pa <<= section_shift;

    while (vstart <= vend) {
        var entry: u64 = pa;
        if (pa >= device_start) {
            entry |= device_block_flags;
        } else {
            entry |= kernel_block_flags;
        }

        var word: *u64 = @ptrFromInt(page_middle_directory + (vstart << 3));
        word.* = entry;
        var ss = section_size;
        pa += ss;
        vstart += 1;
    }
}

fn pageTablesStart() u64 {
    // the symbol is provided by the linker script
    return @intFromPtr(&__page_tables_start);
}

/// Define an identity-mapped set of page tables
fn pageTablesCreate() void {
    var tables = pageTablesStart();

    memzero(tables, tables + page_table_size);

    var map_base: u64 = 0;
    var table: u64 = tables;
    var next_level_table: u64 = table + page_size;

    // Level 0
    tableEntryCreate(table, next_level_table, map_base, page_global_directory_shift, kernel_table_flags);

    table += page_size;
    next_level_table += page_size;

    var block_table: u64 = table;

    for (0..4) |i| {
        // Level 1
        tableEntryCreate(table, next_level_table, map_base, page_upper_directory_shift, kernel_table_flags);

        next_level_table += page_size;
        map_base += page_upper_directory_entry_map_size;

        block_table += page_size;
        var offset: u64 = block_size * i;

        // Level 2
        blockMappingCreate(block_table, offset, offset + block_size, offset);
    }
}
