.macro  FUNC64 name
    .section .text.\name
    .type    \name, @function
    .global  \name
\name:
.endm

.macro  ENDFUNC name
    .align  3
    .pool
    .global \name\()_end
\name\()_end:
    .size   \name,.-\name
.endm

.macro  MOV64 reg,value
    .if \value & 0xffff || (\value == 0)
    movz    \reg,#\value & 0xffff
    .endif
    .if \value > 0xffff && ((\value>>16) & 0xffff) != 0
    .if \value & 0xffff
    movk    \reg,#(\value>>16) & 0xffff,lsl #16
    .else
    movz    \reg,#(\value>>16) & 0xffff,lsl #16
    .endif
    .endif
    .if \value > 0xffffffff && ((\value>>32) & 0xffff) != 0
    .if \value & 0xffffffff
    movk    \reg,#(\value>>32) & 0xffff,lsl #32
    .else
    movz    \reg,#(\value>>32) & 0xffff,lsl #32
    .endif
    .endif
    .if \value > 0xffffffffffff && ((\value>>48) & 0xffff) != 0
    .if \value & 0xffffffffffff
    movk    \reg,#(\value>>48) & 0xffff,lsl #48
    .else
    movz    \reg,#(\value>>48) & 0xffff,lsl #48
    .endif
    .endif
.endm

/*
 * Set translation table and enable MMU
 */
	FUNC64 mmu_on			//

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
        // This must match the definitions in arch/aarch64/mmu2.zig

	MOV64   x1, 0xbbff4400		// program mair on this CPU
	msr     mair_el1, x1		//
	MOV64   x1, 0x200803518		// program tcr on this CPU
	msr     tcr_el1, x1		//
	isb				//
	mrs     x2, tcr_el1		// verify CPU supports desired config
	cmp     x2, x1			//
	b.ne    .			//
	MOV64   x1, 0x1005		// program sctlr on this CPU
	msr     sctlr_el1, x1		//
	isb				// synchronize context on this CPU
	ret				//
        ENDFUNC mmu_on
