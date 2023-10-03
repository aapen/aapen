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

// ----------------------------------------------------------------------
// fn soft_reset()
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
        mov     x19, x0
        bl      bssInit
        mov     x0, x19

        // Reset the call frames
        mov     x29, xzr
        mov     x30, xzr

        br      x0
        END(soft_reset)
