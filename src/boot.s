// Boot code for Cortex-A53 and Cortex-A72
//
// Requires a 64-bit architecture
//
// This applies to Raspberry Pi 3B, 3B+, 4B, 400, CM4

// ----------------------------------------------------------------------
// Constants
// ----------------------------------------------------------------------

CONST_CURRENTEL_EL2 = 0x08
CONST_CORE_ID_MASK  = 0xff
BOOT_CORE_ID        = 0x00

// ----------------------------------------------------------------------
// Macros
// ----------------------------------------------------------------------

// Load address of a symbol in a register.
//
// The symbol can be at most +/- 4 GiB of the PC
.macro LDR_REL register, symbol
        adrp \register, \symbol
        add  \register, \register, #:lo12:\symbol
.endm

// ----------------------------------------------------------------------
// fn _start()
//
// Arguments: none
// Returns: none
// Clobbers: x0, x1
// ----------------------------------------------------------------------

        .section ".text.boot"

        .global _start
        .type   _start, @function
_start:
        // At boot time, the core should be executing in EL2 (low
        // privilege). If it is not, we are in a strange state and
        // should not proceed

        mrs x0, CurrentEL                     // Get execution level from CPU into x0
        cmp x0, #CONST_CURRENTEL_EL2          // It should be EL2 at boot time
        b.ne L_parking_loop                   // If not, something is wrong, park the core

        // All cores boot from the same image. We're going to have one core
        // handle system initialization. It will later activate the other cores.

        mrs x0, MPIDR_EL1                     // Get the core ID from the CPU's multiprocessor affinity register
        and x0, x0, #CONST_CORE_ID_MASK       // The lower 8 bits hold the core number
        ldr x1, =BOOT_CORE_ID                 // The boot core is core 0
        cmp x0, x1                            // Are we on the boot core?
        b.ne L_parking_loop                   // If not, park the core

        // We're on the main core. Initialize memory and stack.
        //
        // The BSS symbols are provided by the linker script, which computes
        // them from the object files produced by the compiler.
        //
        // BSS is never loaded from the program image// only the addresses
        // are specified. We're required to zero out that range of memory.

        LDR_REL x0, __bss_start               // Put the starting address in x0
        LDR_REL x1, __bss_end_exclusive       // Put the last addres + 1 in x1

L_bss_init_loop:
        cmp x0, x1                            // Has x0 reached __bss_end_exclusive?
        b.eq L_initialize_stack               // If so, we're done
        stp xzr, xzr, [x0], #16               // Otherwise, store 64 bits of zeros and
                                              // post-increment x0
        b L_bss_init_loop                     // Repeat until done

        // Set up the stack.
        //
        // __boot_core_stack_end_exclusive is provided by the linker
        // script which puts it right below _start itself

L_initialize_stack:
        LDR_REL x0, __boot_core_stack_end_exclusive
        mov sp, x0

        bl kernel_main                        // Jump to function provided by main.zig

        bl _qemu_exit                         // TEMP: Tell qemu to quit

        // Park the core
L_parking_loop:
        wfe                                   // wait for an event
        b L_parking_loop                      // if one arrives, loop and wait some more

        .size _start, . - _start              // Tell the assembler how big this symbol is
