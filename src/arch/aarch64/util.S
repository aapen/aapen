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
