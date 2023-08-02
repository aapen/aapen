#include <asm/macro.h>

/*
 * Set translation table and enable MMU
 */
        ENTRY(mmu_on)

	adrp    x6, __page_tables_start	// address of first table
	msr     ttbr0_el1, x6		//
	.if 1 == 1			//
	msr     ttbr1_el1,xzr		//
	.endif				//

        // Set up memory attributes
        //
        // This equates to:
        // 0 = b00000000 = Device-nGnRnE
        // 1 = b01000100 = Normal, Inner/Outer Non-Cacheable
        // 2 = b11111111 = Normal, Inner/Outer WB/WA/RA
        // 3 = b10111011 = Normal, Inner/Outer WT/WA/RA
        //
        // This must match the definitions in arch/aarch64/mmu.zig

	LDR_IMM64 x1, 0xbbff4400        // program mair on this CPU
	msr     mair_el1, x1		//
	LDR_IMM64 x1, 0x200803518       // program tcr on this CPU
	msr     tcr_el1, x1		//
	isb				//
	mrs     x2, tcr_el1		// verify CPU supports desired config
	cmp     x2, x1			//
	b.ne    .			//
//      LDR_IMM64(x1, 0x1005)		// program sctlr on this CPU
//      msr     sctlr_el1, x1		//
        mrs     x1, sctlr_el1           // get the control register
        orr     x1, x1, #1              // turn on the MMU enable bit
	msr     sctlr_el1, x1		// and make it so
	isb				// synchronize context on this CPU
	ret				//
        END(mmu_on)
