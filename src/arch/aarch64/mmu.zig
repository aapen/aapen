const root = @import("root");
const HAL = root.HAL;

const cortex_a = @import("../cortex-a.zig");

const mmu_h = @cImport({
    @cInclude("asm/mmu.h");
});

// Assumptions
//
// - Translation granule is 4KB
// - Physical addresses are all RAM until the devices, then it's only
//   devices above that

// These are fundamental to the processor
pub const PAGE_SHIFT: u8 = mmu_h.PAGE_SHIFT;
pub const TABLE_SHIFT: u8 = mmu_h.TABLE_SHIFT;
pub const SECTION_SHIFT: u8 = mmu_h.SECTION_SHIFT;

pub const PTRS_PER_TABLE: u16 = mmu_h.PTRS_PER_TABLE;
pub const PAGE_SIZE: u64 = mmu_h.PAGE_SIZE;
pub const SECTION_SIZE: u64 = mmu_h.SECTION_SIZE;

// These are choices about memory layout
pub const VA_START = mmu_h.VA_START;

// TODO: How to reconcile this with the PHYS_MEMORY_SIZE from the
// include file?
pub const BLOCK_SIZE: u64 = 0x40000000;

// TODO: How to reconcile the include file with the build-time Zig module?
pub const DEVICE_START: u64 = HAL.device_start;

// These are choices about memory protection
// These must match the value written to MAIR_EL1 in mmu.S
pub const MT_DEVICE_nGnRnE: u8 = mmu_h.MT_DEVICE_nGnRnE;
pub const MT_NORMAL_NC: u8 = mmu_h.MT_NORMAL_NC;
pub const MT_NORMAL: u8 = mmu_h.MT_NORMAL;

pub const MM_ACCESS: u64 = mmu_h.MM_ACCESS;
pub const MM_ACCESS_PERMISSION = mmu_h.MM_ACCESS_PERMISSION;
pub const MM_KERNEL_PERMISSION: u64 = mmu_h.MM_KERNEL_PERMISSION;
pub const MM_INNER_SHAREABLE: u64 = mmu_h.MM_INNER_SHAREABLE;

pub const MM_TYPE_PAGE_TABLE: u8 = mmu_h.MM_TYPE_PAGE_TABLE;
pub const MM_TYPE_PAGE: u8 = mmu_h.MM_TYPE_PAGE;
pub const MM_TYPE_BLOCK: u8 = mmu_h.MM_TYPE_BLOCK;

pub const MMU_PTE_FLAGS = mmu_h.MMU_PTE_FLAGS;

pub const MMU_BLOCK_FLAGS: u64 = mmu_h.MMU_BLOCK_FLAGS;
pub const MMU_DEVICE_FLAGS: u64 = mmu_h.MMU_DEVICE_FLAGS;

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

pub const PGD_SHIFT: u8 = mmu_h.PGD_SHIFT;
pub const PUD_SHIFT: u8 = mmu_h.PUD_SHIFT;
pub const PMD_SHIFT: u8 = mmu_h.PMD_SHIFT;
pub const PUD_ENTRY_MAP_SIZE: u64 = mmu_h.PUD_ENTRY_MAP_SIZE;

// The tables we need will fit in 6 memory pages.
// Make sure this matches the section allocation in kernel.ld
pub const PG_DIR_SIZE: u64 = mmu_h.PG_DIR_SIZE;

extern fn mmu_on() void;

pub fn init() void {
    pageTablesCreate();
    // pagetable_init();
    mmu_on();
}

pub fn enable() void {
    // use the assembly routine from mmu.S
    mmu_on();
}

// initialization for secondary cores. for now, this does not create
// its own set of page tables, but _does_ write the address of the
// page tables to its own TTBR0 and TTBR1
pub fn initSecondary() void {
    mmu_on();
}

fn tableEntryCreate(table: [*]u64, next_level_table: [*]u64, virtual_address: u64, chosen_table_shift: u6, flags: u64) void {
    const table_index = (virtual_address >> chosen_table_shift) & (PTRS_PER_TABLE - 1);
    table[table_index] = @intFromPtr(next_level_table) | flags;
}

fn blockMappingCreate(page_middle_directory: [*]u64, virtual_addr_start: u64, virtual_addr_end: u64, phys_addr_start: u64) void {
    var vstart = virtual_addr_start >> SECTION_SHIFT;
    vstart &= (PTRS_PER_TABLE - 1);

    var vend = virtual_addr_end >> SECTION_SHIFT;
    vend -= 1;
    vend &= (PTRS_PER_TABLE - 1);

    // zero out the bottom `section_shift` bits of the address, to
    // turn it into a table entry
    var pa = phys_addr_start >> SECTION_SHIFT;
    pa <<= SECTION_SHIFT;

    while (vstart <= vend) {
        var entry: u64 = pa;
        if (pa >= DEVICE_START) {
            entry |= MMU_DEVICE_FLAGS;
        } else {
            entry |= MMU_BLOCK_FLAGS;
        }

        page_middle_directory[vstart] = entry;
        const ss = SECTION_SIZE;
        pa += ss;
        vstart += 1;
    }
}

/// Define an identity-mapped set of page tables
pub fn pageTablesCreate() void {
    const table_size_dwords = PG_DIR_SIZE / 8;
    const page_size_dwords = PAGE_SIZE / 8;

    const tables_start: [*]u64 = @alignCast(@ptrCast(&cortex_a.Sections.__page_tables_start));
    @memset(tables_start[0..table_size_dwords], 0);

    var map_base: u64 = 0;
    var table: [*]u64 = tables_start;
    var next_level_table: [*]u64 = table + page_size_dwords;

    // Level 0
    tableEntryCreate(table, next_level_table, map_base, PGD_SHIFT, MMU_PTE_FLAGS);

    table += page_size_dwords;
    next_level_table += page_size_dwords;

    var block_table: [*]u64 = table;

    for (0..4) |i| {
        // Level 1
        tableEntryCreate(table, next_level_table, map_base, PUD_SHIFT, MMU_PTE_FLAGS);

        next_level_table += page_size_dwords;
        map_base += PUD_ENTRY_MAP_SIZE;

        block_table += page_size_dwords;
        const offset: u64 = BLOCK_SIZE * i;

        // Level 2
        blockMappingCreate(block_table, offset, offset + BLOCK_SIZE, offset);
    }
}
