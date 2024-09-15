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
        mov     x0, #\type
        mrs     x1, esr_el1
        mrs     x2, far_el1
        b       _forth_restart
        END(__\type)
        .endm

        // ----------------------------------------------------------------------
        // Vector table
        // ----------------------------------------------------------------------

        .section .text


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

        // Align to 2^11 (2048) bytes, as required by ARMv8-A
        .align 11
        .global __exception_handler_table
        .type __exception_handler_table,%object
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

        .macro puts lbl
        ldr     x3, =\lbl
        bl      _puts
        .endm

        .macro outsysr reg,lbl
        puts    \lbl
        mrs     x1, \reg
        bl      print_hex
        puts    nl
        .endm

        .macro outreg reg,lbl
        puts    \lbl
        mov     x1, \reg
        bl      print_hex
        puts    nl
        .endm

        .macro outval lbl
        puts    \lbl
        bl      print_hex
        puts    nl
        .endm

        // ----------------------------------------------------------------------
        // fn bsod
        //
        // Display a summary of important registers
        //
        // Alignment:
        // Arguments: none
        // Returns: none
        // Clobbers: none
        // ----------------------------------------------------------------------
        ENTRY(bsod)
        // Save link register on stack
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

        puts    nl
        puts    abort_msg
        outsysr ESR_EL1, esr_label
        outsysr FAR_EL1, far_label
        outsysr ELR_EL1, elr_label
        outreg  x28, x28_label
        outreg  x29, x29_label
        outreg  x10, x10_label

        puts    inp_label
        ldr     x3, =var_inbuf
        ldr     x3, [x3]
        ldr     x4, =var_to_in
        ldr     x4, [x4]
        cmp     x4, #100
        ble     2f
        add     x3, x3, x4              // only show the last 100 characters
        mov     x4, #100
        sub     x3, x3, #100
2:      bl      _nputs
        puts    inp_end

        // Restore link register and return
        ldp     x29, x30, [sp], #16
        ret
        END(bsod)
        // ----------------------------------------------------------------------
        // fn _puts
        //
        // Print a zstring to serial using _con_out
        //
        // Alignment:
        // Arguments:
        //      x3 - addr of zstring
        // Returns: none
        // Clobbers: x0, x1, x2
        // ----------------------------------------------------------------------
        ENTRY(_puts)
        // Save registers on stack
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

1:      // Print the label
        ldrb    w0, [x3], #1      // Load the next byte of the label
        cbz     w0, 2f            // If the byte is null, end the loop
        bl      _con_out          // Print the character
        b       1b                // Continue the loop

2:      // Restore registers and return
        ldp     x29, x30, [sp], #16
        ret
        END(_puts)

        // ----------------------------------------------------------------------
        // fn _nputs
        //
        // Print a string to serial using _con_out. This function uses
        // a len, addr pair to print the string
        //
        // Alignment:
        // Arguments:
        //      x3 - addr of string
        //      x4 - len of string
        // Returns: none
        // Clobbers: x0, x1, x2
        // ----------------------------------------------------------------------
        ENTRY(_nputs)
        // Save registers on stack
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

1:      // Print the label
        ldrb    w0, [x3], #1      // Load the next byte of the label
        bl      _con_out          // Print the character
        subs    x4, x4, 1         // decrement count
        bge     1b                // if count remains, continue the loop

2:      // Restore registers and return
        ldp     x29, x30, [sp], #16
        ret
        END(_nputs)


        .section .rodata
abort_msg:      .asciz "CORE ABORT!\r\n"
// Data section for register labels
esr_label:      .asciz "ESR_EL1: 0x"
far_label:      .asciz "FAR_EL1: 0x"
elr_label:      .asciz "ELR_EL1: 0x"
x28_label:      .asciz "PSP x28: 0x"
x29_label:      .asciz "RSP x29: 0x"
x10_label:      .asciz "NIP x10: 0x"
inp_label:      .asciz "  input: ["
inp_end:        .asciz "]\r\n"
nl:             .asciz "\r\n"
