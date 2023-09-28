#include <asm/macro.h>

        .section .text.util
        
// ----------------------------------------------------------------------
// fn spin_delay()
//
// Loop for (roughly) a number of CPU cycles
//
// Arguments:
//      x0 - number of iterations to spin for
// Returns: none
// Clobbers: x0
// ----------------------------------------------------------------------

        ENTRY(spinDelay)
        subs    x0, x0, #1
        bne     spinDelay
        ret
        END(spinDelay)

// ----------------------------------------------------------------------
// fn memzero()
//
// Alignment: x0 must be 8-byte aligned. x1 must be 8-byte aligned.
//
// Arguments:
//      x0 - low address (inclusive)
//      x1 - high address (exclusive)
// Returns: none
// Clobbers: x0
// ----------------------------------------------------------------------

        ENTRY(memzero)
        cmp     x0, x1                  // Has x0 reached x1?
        b.eq    1f                      // If so, we're done
        stp     xzr, xzr, [x0], #16     // Otherwise, store 16 bits of zeros and
                                        // post-increment x0 by 16
        b       memzero                 // Repeat until done
1:
        ret
        END(memzero)


// ----------------------------------------------------------------------
// fn init_bss
//
// Zero out the BSS memory
//
// Alignment:
//
// Arguments:
// Returns: none
// Clobbers: x0, x1
// ----------------------------------------------------------------------
        ENTRY(init_bss)
        sub     sp, sp, #0x10
        stp     x29, x30, [sp]
        mov     x29, sp
        LDR_REL(x0, __bss_start)
        LDR_REL(x1, __bss_end_exclusive)
        bl      memzero
        ldp     x29, x30, [sp]
        add     sp, sp, #0x10
        ret
        END(init_bss)

// ----------------------------------------------------------------------
// fn soft_reset
//
// Jump back to an entry point, resetting the call stack. Note that this
// does not change EL.
//
// Alignment:
//
// Arguments:
//      x0 - target fn address
// Returns: none
// Clobbers: x1, x3, x8
// ----------------------------------------------------------------------

        ENTRY(_soft_reset)
        // Reset the stack
        LDR_REL(x1, __boot_core_stack_end_exclusive)
        mov     sp, x1

        // Turn off the MMU
        bl      mmu_off

        // Re-zero the BSS (but save x0 first since it gets clobbered)
        mov     x8, x0
        bl      init_bss
        mov     x0, x8

        // Reset the call frames
        mov     x29, xzr
        mov     x30, xzr

        br      x0
        END(soft_reset)
