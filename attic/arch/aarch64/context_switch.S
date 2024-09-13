#include <asm/macro.h>
#include <asm/mmu.h>

// ----------------------------------------------------------------------
// fn context_switch
//
// Switch CPU to a thread's context.
// Interrupts MUST be masked on entry here
//
// Alignment:
//
// Arguments:
//   x0 - address where old thread's stack pointer will be saved
//   x1 - address where new thread's stack pointer will be loaded
// Returns: nothing
// Clobbers: all registers
// ----------------------------------------------------------------------
        ENTRY(context_switch)
        // save old context
        stp     x30, xzr, [sp, #-16]!            // save lr as future value of pc
        stp     x29, x30, [sp, #-16]!           // save fp and lr
        stp     x16, x17, [sp, #-16]!           // save callee-saved gprs
        stp     x14, x15, [sp, #-16]!
        stp     x12, x13, [sp, #-16]!
        stp     x10, x11, [sp, #-16]!
        stp     x8,  x9,  [sp, #-16]!
        stp     x6,  x7,  [sp, #-16]!
        stp     x4,  x5,  [sp, #-16]!
        stp     x2,  x3,  [sp, #-16]!
        stp     x0,  x1,  [sp, #-16]!
        mrs     x3,  nzcv                       // save pstate condition flags
        mrs     x2,  daif                       // save interrupt mask flags
        stp     x2,  x3,  [sp, #-16]!
        mov     x19, sp
        str     x19, [x0]

        // switch into new context
        ldr     x19, [x1]
        mov     sp,  x19
        ldp     x2,  x3,  [sp], #16
        msr     nzcv, x3                         // restore pstate condition flags
        msr     daif, x2                         // restore interrupt mask flags
        ldp     x0,  x1,  [sp], #16              // restore GPRs
        ldp     x2,  x3,  [sp], #16
        ldp     x4,  x5,  [sp], #16
        ldp     x6,  x7,  [sp], #16
        ldp     x8,  x9,  [sp], #16
        ldp     x10, x11, [sp], #16
        ldp     x12, x13, [sp], #16
        ldp     x14, x15, [sp], #16
        ldp     x16, x17, [sp], #16
        ldp     x29, x30, [sp], #16             // restore frame pointer and link register

        ldp     x20, xzr, [sp], #16
        br      x20

        END(context_switch)
