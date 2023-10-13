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

        // Save the flattened device tree for later use
        LDR_REL(x8, __fdt_address)            // Address of the pointer
        str     x0, [x8]                      // Store the
                                              // firmware-supplied
                                              // location of the FDT
                                              // into that pointer.

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
        // __boot_core_stack_end_exclusive is provided by the linker
        // script which puts it right below _start itself
        LDR_REL(x0, __boot_core_stack_end_exclusive)
        mov sp, x0

        // The BSS symbols are provided by the linker script, which computes
        // them from the object files produced by the compiler.
        //
        // BSS is never loaded from the program image// only the addresses
        // are specified. We're required to zero out that range of
        // memory.
        mov     x19, x0                       // Save the stack top
        bl      bssInit
        mov     x0, x19                       // Restore stack top as arg

        // Jump to Zig code, with x0 (stack top) as a function
        // argument
        movz    x29, #0
        movz    x30, #0

        b       _start_zig

        // unreachable

        .global pe_hang
        .type pe_hang, @function
        // Park the PE
pe_hang:
        wfe                                   // wait for an event
        b pe_hang                             // if one arrives, loop and wait some more

        END(_start)

        .section .data.boot

        .align 8
        .global __fdt_address
__fdt_address:
        .quad   0
