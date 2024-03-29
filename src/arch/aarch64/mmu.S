#include <asm/macro.h>
#include <asm/mmu.h>

// ----------------------------------------------------------------------
// fn mmu_on
//
// Set translation table and enable MMU
//
// Alignment:
//
// Arguments:
// Returns: none
// Clobbers: x1, x2, x6
// ----------------------------------------------------------------------
        ENTRY(mmu_on)

	adrp    x6, __page_tables_start	// address of first table
	msr     ttbr0_el1, x6		//
	.if 1 == 1			//
	msr     ttbr1_el1,xzr		//
	.endif				//

        // MAIR: Set up memory attributes
        //
        // This equates to:
        // 0 = b00000000 = Device-nGnRnE
        // 1 = b01000100 = Normal, Inner/Outer Non-Cacheable
        // 2 = b11111111 = Normal, Inner/Outer WB/WA/RA
        // 3 = b10111011 = Normal, Inner/Outer WT/WA/RA
        //
        // This must match the definitions in arch/aarch64/mmu.zig

        LDR_IMM64 x1, MAIR_VALUE        // program mair on this PE
	msr     mair_el1, x1		//

        // TCR: Translation control
	LDR_IMM64 x1, TCR_VALUE         // program tcr on this PE
	msr     tcr_el1, x1		//
	isb				//
	mrs     x2, tcr_el1		// verify PE supports desired config
	cmp     x2, x1			//
	b.ne    pe_hang			//

        // SCTLR: System Control Register
        mrs     x1, sctlr_el1           // get the control register
        orr     x1, x1, #1              // turn on the MMU enable bit
	msr     sctlr_el1, x1		// and make it so
	isb				// synchronize context on this PE
	ret				//
        END(mmu_on)

// ----------------------------------------------------------------------
// fn mmu_off
//
// Disable MMU
//
// Alignment:
//
// Arguments:
// Returns: none
// Clobbers: x1, x3
// ----------------------------------------------------------------------

        ENTRY(mmu_off)
        mrs     x1, sctlr_el1            // get the control register
        mov     x3, 1                    //
        bic     x1, x1, x3               // turn off the MMU enable bit
        msr     sctlr_el1, x1            // and make it so
        isb                              // synchronize context on PE
        ret
        END(mmu_off)
