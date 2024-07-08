// Boot code for Cortex-A53 and Cortex-A72
//
// Requires a 64-bit architecture
//
// This applies to Raspberry Pi 3B, 3B+, 4B, 400, CM4

#include <asm/macro.h>
#include <asm/boot.h>

// ----------------------------------------------------------------------
// Constants
// ----------------------------------------------------------------------

// ----------------------------------------------------------------------
// Macros
// ----------------------------------------------------------------------

// ----------------------------------------------------------------------
// fn _start()
//
// Arguments: none
// Returns: none
// Clobbers: x0, x1
// ----------------------------------------------------------------------

        .section .text._start

        ENTRY(_start)

        // At boot time, the core should be executing in EL2 (high
        // privilege). If it is not, we are in a strange state and
        // should not proceed
        mrs       x0, CurrentEL                 // Get execution level from CPU into x0
        cmp       x0, 0x08                      // It should be EL2 at boot time
        b.ne      pe_hang                       // If not, something is wrong, park the core

        // All cores boot from the same image. We're going to have one
        // core handle system initialization. It will later activate
        // the other cores which will start executing at _start.
        mrs       x5, MPIDR_EL1                 // Get the core ID from the CPU's
                                                // multiprocessor affinity register
        and       x5, x5, #0x3                  // The lower 8 bits hold the core number

        // Calculate the stack top according to the core ID.
        //
        // x5: core ID
        // x19: stack top (note this is a callee-saved register)
        LDR_IMM64 x2, STACK_SIZE
        mul       x19, x5, x2                   // Bottom of each stack is core # * stack_size
        add       x19, x19, x2                  // But the stack pointer needs to be the top
        mov       sp, x19                       // Use this stack pointer on this core
        cbnz      x5, skip_bss_init             // Are we on the boot core? Only init BSS on the boot core.

        // We're on the main core. Zero out the BSS.
        ldr      x0, =__bss_start
        ldr      x1, =__bss_end_exclusive
1:
        stp      xzr, xzr, [x0], #16
        cmp      x0, x1
        bne      1b

        // Enable the UART - do this only once from the boot core
        bl      _uart_init

skip_bss_init:
        // Prepare for the transition to EL1
        LDR_IMM64 x0, SCTLR_EL1_VALUE
        msr       sctlr_el1, x0

        LDR_IMM64 x0, CNTHCTL_EL2_VALUE
        msr       cnthctl_el2, x0

        LDR_IMM64 x0, CPACR_EL1_VALUE
        msr       cpacr_el1, x0

        mov       x0, #0
        msr       cntvoff_el2, x0

        LDR_IMM64 x0, HCR_EL2_VALUE
        msr       hcr_el2, x0

        LDR_IMM64 x0, SPSR_EL1_TRANSITION_VALUE
        msr       spsr_el2, x0

        // Prepare for the drop to EL1, make a null stack frame
        movz      x29, #0
        movz      x30, #0

        // Use the stack top we computed before
        msr       sp_el1, x19

        mov       x0, x5                        // pass the core id as argument
        LDR_REL   (x1, _forth_start)
        msr       elr_el2, x1
        eret
        // unreachable
        END(_start)

        ENTRY(pe_hang)                          // park the PE
        wfe                                     // wait for an event
        b         pe_hang                       // if one arrives, loop and wait some more
        END(pe_hang)

        ENTRY(_forth_error)
        b         pe_hang
        END(_forth_error)
