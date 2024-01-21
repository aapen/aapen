#include <asm/macro.h>

        .section .text.util
        
// ----------------------------------------------------------------------
// fn spinDelay()
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

