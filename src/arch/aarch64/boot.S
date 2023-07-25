// Boot code for Cortex-A53 and Cortex-A72
//
// Requires a 64-bit architecture
//
// This applies to Raspberry Pi 3B, 3B+, 4B, 400, CM4

#include <asm/macro.h>

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

        mrs x0, CurrentEL                     // Get execution level from CPU into x0
        cmp x0, 0x08                          // It should be EL2 at boot time
        b.ne pe_hang                          // If not, something is wrong, park the core

        // All cores boot from the same image. We're going to have one core
        // handle system initialization. It will later activate the other cores.

        mrs x0, MPIDR_EL1                     // Get the core ID from the CPU's
                                              // multiprocessor affinity register
        and x0, x0, #0xff                     // The lower 8 bits hold the core number
        cbnz x0, pe_hang                      // Are we on the boot core?  If not, park
                                              // the core

        // We're on the main core. Initialize memory and stack.
        //
        // The BSS symbols are provided by the linker script, which computes
        // them from the object files produced by the compiler.
        //
        // BSS is never loaded from the program image// only the addresses
        // are specified. We're required to zero out that range of memory.

        LDR_REL(x0, __bss_start)               // Put the starting address in x0
        LDR_REL(x1, __bss_end_exclusive)       // Put the last address + 1 in x1
        bl memzero

        // Set up the stack.
        //
        // __boot_core_stack_end_exclusive is provided by the linker
        // script which puts it right below _start itself
        LDR_REL(x0, __boot_core_stack_end_exclusive)
        mov sp, x0

        // Jump to Zig code, with x0, x1, and x2 as function arguments
        b _start_zig

        // unreachable

        .global pe_hang
        .type pe_hang, @function
        // Park the PE
pe_hang:
        wfe                                   // wait for an event
        b pe_hang                             // if one arrives, loop and wait some more

        END(_start)
