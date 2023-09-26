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
        subs x0, x0, #1
        bne  spinDelay
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
        cmp x0, x1                      // Has x0 reached x1?
        b.eq 1f                         // If so, we're done
        stp xzr, xzr, [x0], #16         // Otherwise, store 16 bits of zeros and
                                        // post-increment x0 by 16
        b memzero                       // Repeat until done
1:
        ret
        END(memzero)

// ----------------------------------------------------------------------
// fn soft_reset
//
// Jump back to an entry point, resetting the stack. Note that this
// does not change EL.
//
// Alignment:
//
// Arguments:
//      x0 - argument to target fn
//      x1 - target fn address
// Returns: none
// Clobbers: x1
// ----------------------------------------------------------------------

        ENTRY(soft_reset)
        mov x29, xzr                    // Clear the frame pointer
        mov x30, xzr                    // Clear the link register

        mrs x2, sctlr_el1               // Get control register
        mov x3, 1
        bic x2, x2, x3                  // Turn off the MMU enable bit
        msr sctlr_el1, x2               // Make it so
        isb

        LDR_REL(x2, __boot_core_stack_end_exclusive)
        mov sp, x2
        br x1
        END(soft_reset)
