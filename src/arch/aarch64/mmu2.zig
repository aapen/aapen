pub const memory_map = @import("../../bsp/raspi3/memory_map.zig");
pub const device_start = memory_map.device_start;

// Assumptions
//
// - Translation granule is 4KB
// - Physical addresses are all RAM until the devices, then it's only
//   devices above that

// These are fundamental to the processor
pub const PAGE_SHIFT: u8 = 12;
pub const TABLE_SHIFT: u8 = 9;
pub const SECTION_SHIFT: u8 = PAGE_SHIFT + TABLE_SHIFT;

pub const ENTRIES_PER_TABLE: u16 = 1 << TABLE_SHIFT;
pub const PAGE_SIZE: u64 = 1 << PAGE_SHIFT;
pub const SECTION_SIZE: u64 = 1 << SECTION_SHIFT;

// These are choices about memory layout
// pub const VA_START = 0xffff000000000000;
pub const BLOCK_SIZE: u64 = 0x40000000;
pub const DEVICE_START: u64 = device_start;

// These are choices about memory protection
pub const MAIR_DEVICE_nGnRnE: u8 = 0x0;
pub const MAIR_DEVICE_nGnRnE_INDEX: u2 = 0;

pub const MAIR_NORMAL_NC: u8 = 0x44;
pub const MAIR_NORMAL_NC_INDEX: u2 = 1;

pub const MAIR_VALUE: u64 = (MAIR_NORMAL_NC << (8 * MAIR_NORMAL_NC_INDEX)) | (MAIR_DEVICE_nGnRnE << (8 * MAIR_DEVICE_nGnRnE_INDEX));

pub const TABLE_DESCRIPTOR_VALID: u64 = (1 << 0);
pub const TABLE_DESCRIPTOR_IS_TABLE: u64 = (1 << 1);
pub const TABLE_DESCRIPTOR_ACCESS: u64 = (1 << 10);
pub const TABLE_DESCRIPTOR_KERNEL_PERMS: u64 = (1 << 54);
pub const TABLE_DESCRIPTOR_INNER_SHAREABLE: u64 = (3 << 8);

pub const KERNEL_TABLE_FLAGS: u64 = (TABLE_DESCRIPTOR_IS_TABLE | TABLE_DESCRIPTOR_VALID);
pub const KERNEL_BLOCK_FLAGS: u64 = (TABLE_DESCRIPTOR_ACCESS | TABLE_DESCRIPTOR_INNER_SHAREABLE | TABLE_DESCRIPTOR_KERNEL_PERMS | (@as(u8, MAIR_NORMAL_NC_INDEX) << 2) | TABLE_DESCRIPTOR_VALID);
pub const DEVICE_BLOCK_FLAGS: u64 = (TABLE_DESCRIPTOR_ACCESS | TABLE_DESCRIPTOR_INNER_SHAREABLE | TABLE_DESCRIPTOR_KERNEL_PERMS | (@as(u8, MAIR_DEVICE_nGnRnE_INDEX) << 2) | TABLE_DESCRIPTOR_VALID);

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

pub const PAGE_GLOBAL_DIRECTORY_SHIFT: u8 = PAGE_SHIFT + 3 * TABLE_SHIFT;
pub const PAGE_UPPER_DIRECTORY_SHIFT: u8 = PAGE_SHIFT + 2 * TABLE_SHIFT;
pub const PAGE_MIDDLE_DIRECTORY_SHIFT: u8 = PAGE_SHIFT + TABLE_SHIFT;
pub const PAGE_UPPER_DIRECTORY_ENTRY_MAP_SIZE: u64 = 1 << PAGE_UPPER_DIRECTORY_SHIFT;

// The tables we need will fit in 6 memory pages
pub const PAGE_TABLE_SIZE: u64 = 6 * PAGE_SIZE;

extern fn mmu_on() void;

pub fn init() void {
    create_page_tables();
    // pagetable_init();
    mmu_on();
}

extern const __page_tables_start: u64;

extern fn memzero(begin: u64, end_exclusive: u64) void;

fn create_table_entry(table: u64, next_level_table: u64, virtual_address: u64, table_shift: u6, flags: u64) void {
    var table_index = virtual_address >> table_shift;
    table_index &= (ENTRIES_PER_TABLE - 1);
    var descriptor: u64 = next_level_table | flags;
    var word: *u64 = @ptrFromInt(table + (table_index << 3));
    word.* = descriptor;
}

fn create_block_map(page_middle_directory: u64, virtual_addr_start: u64, virtual_addr_end: u64, phys_addr_start: u64) void {
    var vstart = virtual_addr_start >> SECTION_SHIFT;
    vstart &= (ENTRIES_PER_TABLE - 1);

    var vend = virtual_addr_end >> SECTION_SHIFT;
    vend -= 1;
    vend &= (ENTRIES_PER_TABLE - 1);

    var pa = phys_addr_start >> SECTION_SHIFT;
    pa <<= SECTION_SHIFT;

    while (vstart <= vend) {
        var entry: u64 = pa;
        if (pa >= DEVICE_START) {
            entry |= DEVICE_BLOCK_FLAGS;
        } else {
            entry |= KERNEL_BLOCK_FLAGS;
        }

        var word: *u64 = @ptrFromInt(page_middle_directory + (vstart << 3));
        word.* = entry;
        var ss = SECTION_SIZE;
        pa += ss;
        vstart += 1;
    }
}

fn page_tables_start() u64 {
    // the symbol is provided by the linker script
    return @intFromPtr(&__page_tables_start);
}

/// Define an identity-mapped set of page tables
fn create_page_tables() void {
    var tables = page_tables_start();

    memzero(tables, tables + PAGE_TABLE_SIZE);

    var map_base: u64 = 0;
    var table: u64 = tables;
    var next_level_table: u64 = table + PAGE_SIZE;

    // Level 0
    create_table_entry(table, next_level_table, map_base, PAGE_GLOBAL_DIRECTORY_SHIFT, KERNEL_TABLE_FLAGS);

    table += PAGE_SIZE;
    next_level_table += PAGE_SIZE;

    var block_table: u64 = table;

    for (0..4) |i| {
        // Level 1
        create_table_entry(table, next_level_table, map_base, PAGE_UPPER_DIRECTORY_SHIFT, KERNEL_TABLE_FLAGS);

        next_level_table += PAGE_SIZE;
        map_base += PAGE_UPPER_DIRECTORY_ENTRY_MAP_SIZE;

        block_table += PAGE_SIZE;
        var offset: u64 = BLOCK_SIZE * i;

        // Level 2
        create_block_map(block_table, offset, offset + BLOCK_SIZE, offset);
    }
}
