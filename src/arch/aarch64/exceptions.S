        // Exception vector code for Cortex-A53 and Cortex-A72
        //

        #include <asm/macro.h>

        // ----------------------------------------------------------------------
        // Constants
        // ----------------------------------------------------------------------

        // these are constants so we can display what kind of
        // unhandled exception we received
        SYNCHRONOUS_INVALID_EL1T        = 0
        IRQ_INVALID_EL1T                = 1
        FIQ_INVALID_EL1T                = 2
        ERROR_INVALID_EL1T              = 3
        SYNCHRONOUS_EL1H                = 4
        IRQ_EL1H                        = 5
        FIQ_INVALID_EL1H                = 6
        ERROR_INVALID_EL1H              = 7
        SYNCHRONOUS_INVALID_EL0_64      = 8
        IRQ_INVALID_EL0_64              = 9
        FIQ_INVALID_EL0_64              = 10
        ERROR_INVALID_EL0_64            = 11
        SYNCHRONOUS_INVALID_EL0_32      = 12
        IRQ_INVALID_EL0_32              = 13
        FIQ_INVALID_EL0_32              = 14
        ERROR_INVALID_EL0_32            = 15

        // ----------------------------------------------------------------------
        // Macros
        // ----------------------------------------------------------------------

        // Create an entry for the vector table, it sets a code then
        // goes to restart forth
        .macro VENTRY type
        .align 7
        ENTRY_ALIGN(__\type, 7)
        ldr     x19, =var_exception
        mov     x0, #\type
        str     x0, [x19]
        ldr     x19, =var_excode
        mrs     x0, esr_el1
        str     x0, [x19]
        b       _forth_restart
        END(__\type)
        .endm

        // ----------------------------------------------------------------------
        // Vector table
        // ----------------------------------------------------------------------

        .section .text

        // Align to 2^11 (2048) bytes, as required by ARMv8-A
        .align 11

        // Expose a symbol that the linker will provide to the Zig
        // init code.
        //
        // Exception handlers come in "stanzas". Each stanza has 4
        // handlers, in this order. Each one is 0x80 bytes apart, with
        // the offsets as shown:
        // - Synchronous       (at base + $00)
        // - IRQ or vIRQ       (at base + $80)
        // - FIQ or vFIQ       (at base + $100)
        // - SError or vSError (at base + $180)
        //
        // Each stanza is separated by $200 bytes. The chosen stanza
        // depends on the current EL, the target EL, and whether the
        // EL is elevating from AArch32 or AArch64:
        // - In current level, with EL0        (at base + $00)
        // - In current level, higher than EL0 (at base + $200)
        // - Elevating, from AArch64           (at base + $400)
        // - Elevating, from AArch32           (at base + $600)
        //
        // The handlers are executed directly from the table; these
        // are not vectors for the CPU to follow. Therefore, each
        // handler must fit inside its $80 byte space. Won't be a
        // problem here, since each "handler" is just a quick branch
        // to a symbol.
        .global __exception_handler_table
__exception_handler_table:
        // From EL0 to EL0
        VENTRY          SYNCHRONOUS_INVALID_EL1T
        VENTRY          IRQ_INVALID_EL1T
        VENTRY          FIQ_INVALID_EL1T
        VENTRY          ERROR_INVALID_EL1T

        // From ELx to ELx (x > 0)
        VENTRY          SYNCHRONOUS_EL1H
        VENTRY          IRQ_EL1H
        VENTRY          FIQ_INVALID_EL1H
        VENTRY          ERROR_INVALID_EL1H

        // From lower EL, where the level immediately lower than
        // target is using AArch64
        VENTRY          SYNCHRONOUS_INVALID_EL0_64
        VENTRY          IRQ_INVALID_EL0_64
        VENTRY          FIQ_INVALID_EL0_64
        VENTRY          ERROR_INVALID_EL0_64

        // From lower EL, where the level immediatley lower than
        // target is using AArch32
        VENTRY          SYNCHRONOUS_INVALID_EL0_32
        VENTRY          IRQ_INVALID_EL0_32
        VENTRY          FIQ_INVALID_EL0_32
        VENTRY          ERROR_INVALID_EL0_32
