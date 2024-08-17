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
        bl      bsod
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



        // ----------------------------------------------------------------------
        // Debug display
        // ----------------------------------------------------------------------
        // Using _con_out from armforth.S, displays certain key
        // registers when handling a core abort.

        .macro emit c
        mov     w0, \c
        bl      _con_out
        .endm

        .macro nl
        emit #'\r'
        emit #'\n'
        .endm

        .macro outsysr reg,lbl
        mrs     x2, \reg
        ldr     x3, =\lbl
        bl      print_register
        .endm

        .macro outreg reg,lbl
        mov     x2, \reg
        ldr     x3, =\lbl
        bl      print_register
        .endm

        .macro outval lbl
        ldr     x3, =\lbl
        bl      print_register
        .endm

        .global bsod

bsod:
        // Save link register on stack
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

        nl
        outsysr ESR_EL1, esr_label
        outsysr FAR_EL1, far_label
        outreg  x28, x28_label
        outreg  x29, x29_label
        outreg  x10, x10_label
        ldr     x2, [x27]
        outval  irf_label
        ldr     x2, [x27, 8]
        outval  icx_label

        // Restore link register and return
        ldp     x29, x30, [sp], #16
        ret

print_register:
        // Save registers on stack
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

1:      // Print the label
        ldrb    w0, [x3], #1      // Load the next byte of the label
        cbz     w0, 2f            // If the byte is null, end the loop
        bl      _con_out          // Print the character
        b       1b                // Continue the loop

2:      // Print the register value
        mov     x1, x2
        bl      print_hex         // Call the print_hex routine to print x0 as hex

        nl

        // Restore registers and return
        ldp     x29, x30, [sp], #16
        ret

print_hex:
        // Save registers on stack
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

        // Prepare for hex conversion
        mov     w2, #8             // We have 8 hex digits to print
        mov     w3, #0xF           // Mask for extracting 4 bits

1:
        // Shift the value left to extract the highest 4 bits
        lsr     x0, x1, #28        // Move the top 4 bits into w1

        // Mask and convert to hex character
        and     w0, w0, w3         // Mask the top 4 bits
        add     w0, w0, #'0'       // Convert to ASCII ('0' to '9')
        cmp     w0, #'9'           // Compare with ASCII 9
        ble     2f
        add     w0, w0, #39        // Diff between ':' (ASCII '9' + 1) and 'a'
2:
        // Call _con_out to print the character
        bl      _con_out

        // Prepare for next hex digit
        lsl     x1, x1, #4         // Shift the value left by 4 bits
        sub     w2, w2, #1         // Decrease the counter
        cbnz    w2, 1b             // Repeat if there are digits left

        // Restore registers and return
        ldp     x29, x30, [sp], #16
        ret

        .section .data
// Data section for register labels
esr_label:      .asciz "ESR_EL1: 0x"
far_label:      .asciz "FAR_EL1: 0x"
x28_label:      .asciz "PSP x28: 0x"
x29_label:      .asciz "RSP x29: 0x"
x10_label:      .asciz "NIP x10: 0x"
irf_label:      .asciz "IRF    : 0x"
icx_label:      .asciz "IRF ctx: 0x"
