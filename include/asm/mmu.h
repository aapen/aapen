#ifndef _MMU_H
#define _MMU_H

/* Define how aarch64 MMU works */

#define MM_TYPE_PAGE_TABLE		0x3
#define MM_TYPE_PAGE 			0x3
#define MM_TYPE_BLOCK			0x1
#define MM_ACCESS			(0x1ul << 10)
#define MM_ACCESS_PERMISSION		(0x1ul << 6)
#define MM_KERNEL_PERMISSION            (0x1ul << 54)
#define MM_INNER_SHAREABLE              (0x3ul << 8)

/*
 * Memory region attributes:
 *
 *   n = AttrIndx[2:0]
 *			n	MAIR
 *   DEVICE_nGnRnE	000	00000000
 *   NORMAL_NC          001     01000100
 *   NORMAL		002	11111111
 *   NORMAL_WT          003     10111011
 */
#define MT_DEVICE_nGnRnE 		0x0
#define MT_NORMAL_NC			0x1
#define MT_NORMAL                       0x2
#define MT_NORMAL_WT                    0x3
#define MT_DEVICE_nGnRnE_FLAGS		0x00
#define MT_NORMAL_NC_FLAGS  		0x44
#define MT_NORMAL_FLAGS                 0xff
#define MT_NORMAL_WT_FLAGS              0xbb

#define MAIR_VALUE			(MT_DEVICE_nGnRnE_FLAGS << (8 * MT_DEVICE_nGnRnE)) |\
                                        (MT_NORMAL_NC_FLAGS << (8 * MT_NORMAL_NC)) |\
                                        (MT_NORMAL_FLAGS << (8 * MT_NORMAL)) |\
                                        (MT_NORMAL_WT_FLAGS << (8 * MT_NORMAL_WT))

#define MMU_BLOCK_FLAGS	 		(MM_TYPE_BLOCK | MM_KERNEL_PERMISSION | MM_INNER_SHAREABLE | (MT_NORMAL << 2) | MM_ACCESS)
#define MMU_DEVICE_FLAGS		(MM_TYPE_BLOCK | MM_KERNEL_PERMISSION | (MT_DEVICE_nGnRnE << 2) | MM_ACCESS)
#define MMU_PTE_FLAGS			(MM_TYPE_PAGE | (MT_NORMAL << 2) | MM_ACCESS | MM_ACCESS_PERMISSION)

#define TCR_T0SZ			(64 - 48)
#define TCR_IRGN0_WB_RA_WA_CACHE        (0b01 << 8)
#define TCR_ORGN0_WB_RA_WA_CACHE        (0b01 << 10)
#define TCR_SH0_INNER_SHARE             (0b11 << 12)
#define TCR_TG0_4K			(0 << 14)
#define TCR_T1SZ			((64 - 48) << 16)
#define TCR_EPD1_FAULT_ON_TLB_MISS      (1 << 23)
#define TCR_TG1_4K			(2 << 30)
#define TCR_VALUE			(TCR_T0SZ | TCR_IRGN0_WB_RA_WA_CACHE | TCR_T1SZ | TCR_ORGN0_WB_RA_WA_CACHE | TCR_SH0_INNER_SHARE | TCR_T1SZ | TCR_EPD1_FAULT_ON_TLB_MISS | TCR_TG0_4K | TCR_TG1_4K)

/* Define the memory map */

#define DEVICE_BASE 		        0x3F000000
#define PBASE 			        (VA_START + DEVICE_BASE)

#define VA_START 			0xffff000000000000

#define PHYS_MEMORY_SIZE 		0x40000000

#define PAGE_MASK			0xfffffffffffff000
#define PAGE_SHIFT	 		12
#define TABLE_SHIFT 			9
#define SECTION_SHIFT			(PAGE_SHIFT + TABLE_SHIFT)

#define PAGE_SIZE   			(1 << PAGE_SHIFT)
#define SECTION_SIZE			(1 << SECTION_SHIFT)

#define LOW_MEMORY              	(2 * SECTION_SIZE)
#define HIGH_MEMORY             	DEVICE_BASE

#define PAGING_MEMORY 			(HIGH_MEMORY - LOW_MEMORY)
#define PAGING_PAGES 			(PAGING_MEMORY/PAGE_SIZE)

#define PTRS_PER_TABLE			(1 << TABLE_SHIFT)

#define PGD_SHIFT			PAGE_SHIFT + 3*TABLE_SHIFT
#define PUD_SHIFT			PAGE_SHIFT + 2*TABLE_SHIFT
#define PMD_SHIFT			PAGE_SHIFT + TABLE_SHIFT

#define PUD_ENTRY_MAP_SIZE              (1 << PUD_SHIFT)

/* The tables we need will fit in 6 memory pages.  Make sure this
 matches the section allocation in kernel.ld */
#define PG_DIR_SIZE			(6 * PAGE_SIZE)

#endif
