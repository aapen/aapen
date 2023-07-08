        // Exception vector code for Cortex-A53 and Cortex-A72
        //

        // ----------------------------------------------------------------------
        // Constants
        // ----------------------------------------------------------------------

        EC_VALUE_SVC64                  = 0x15
        EC_VALUE_BKPT                   = 0x3C
        KERNEL_ENTRY_FRAME_SIZE         = 0x120

        SYNCHRONOUS_INVALID_EL1T        = 0b0000
        IRQ_INVALID_EL1T                = 0b0001
        FIQ_INVALID_EL1T                = 0b0010
        ERROR_INVALID_EL1T              = 0b0011
        SYNCHRONOUS_INVALID_EL1H        = 0b0100
        // IRQ_EL1H
        FIQ_INVALID_EL1H                = 0b0110
        ERROR_INVALID_EL1H              = 0b0111
        SYNCHRONOUS_INVALID_EL0_64      = 0b1000
        IRQ_INVALID_EL0_64              = 0b1001
        FIQ_INVALID_EL0_64              = 0b1010
        ERROR_INVALID_EL0_64            = 0b1011
        SYNCHRONOUS_INVALID_EL0_32      = 0b1100
        IRQ_INVALID_EL0_32              = 0b1101
        FIQ_INVALID_EL0_32              = 0b1110
        ERROR_INVALID_EL0_32            = 0b1111

        // ----------------------------------------------------------------------
        // Macros
        // ----------------------------------------------------------------------

        // Create an entry for the vector table, it immediately jumps
        // to the real handler
        .macro VENTRY label
        .align 7
        b \label
        .endm

        // For entries that we don't handle, call a routine to report
        // the exception
        .macro HANDLE_INVALID_ENTRY type
        KERNEL_ENTRY
        stp     x29, x30, [sp, -16]!    // save FP (x29) and LR (x30)
        mov     x29, sp                 // update frame pointer
        mov     x0, #\type
        mrs     x1, esr_el1
        mrs     x2, elr_el1
        bl      show_invalid_entry_message
        b       err_hang
        .endm

        // Save registers on the stack before entering kernel space
        .macro KERNEL_ENTRY
        stp     x29, x30, [sp, -16]!    // save FP (x29) and LR (x30)
        mov     x29, sp                 // update frame pointer
        sub     sp, sp, #KERNEL_ENTRY_FRAME_SIZE  // build a struct
        stp	x0, x1, [sp, #16 * 0]             // save GP registers
	stp	x2, x3, [sp, #16 * 1]
	stp	x4, x5, [sp, #16 * 2]
	stp	x6, x7, [sp, #16 * 3]
	stp	x8, x9, [sp, #16 * 4]
	stp	x10, x11, [sp, #16 * 5]
	stp	x12, x13, [sp, #16 * 6]
	stp	x14, x15, [sp, #16 * 7]
	stp	x16, x17, [sp, #16 * 8]
	stp	x18, x19, [sp, #16 * 9]
	stp	x20, x21, [sp, #16 * 10]
	stp	x22, x23, [sp, #16 * 11]
	stp	x24, x25, [sp, #16 * 12]
	stp	x26, x27, [sp, #16 * 13]
	stp	x28, x29, [sp, #16 * 14]
        mrs     x0, elr_el1             // save ELR
	stp	x30, x0,  [sp, #16 * 15]
        mrs     x1, spsr_el1            // save SPSR
        mrs     x2, esr_el1             // save ESR
        stp     x1, x2,   [sp, #16 * 16]
        mov     x0, sp
        .endm

        // Restore registers on exit from kernel space
        .macro KERNEL_EXIT

        // this is a little bit out of order so we can restore ELR_EL1
        // and SPSR_EL1, which requires using x0 before we restore
        // x0's original value. x1 also gets clobbered then restored.
        ldp     x0, x1, [sp, #16 * 16]
        msr     spsr_el1, x0
        ldp     x30, x0, [sp, #16 * 15]
        msr     elr_el1, x0

        ldp	x0, x1, [sp, #16 * 0]
	ldp	x2, x3, [sp, #16 * 1]
	ldp	x4, x5, [sp, #16 * 2]
	ldp	x6, x7, [sp, #16 * 3]
	ldp	x8, x9, [sp, #16 * 4]
	ldp	x10, x11, [sp, #16 * 5]
	ldp	x12, x13, [sp, #16 * 6]
	ldp	x14, x15, [sp, #16 * 7]
	ldp	x16, x17, [sp, #16 * 8]
	ldp	x18, x19, [sp, #16 * 9]
	ldp	x20, x21, [sp, #16 * 10]
	ldp	x22, x23, [sp, #16 * 11]
	ldp	x24, x25, [sp, #16 * 12]
	ldp	x26, x27, [sp, #16 * 13]
	ldp	x28, x29, [sp, #16 * 14]

	add	sp, sp, #KERNEL_ENTRY_FRAME_SIZE
        ldp     x29, x30, [sp], 16
	eret
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
        VENTRY          synchronous_invalid_el1t
        VENTRY          irq_invalid_el1t
        VENTRY          fiq_invalid_el1t
        VENTRY          error_invalid_el1t

        // From ELx to ELx (x > 0)
        VENTRY          synchronous_invalid_el1h
        VENTRY          irq_el1h
        VENTRY          fiq_invalid_el1h
        VENTRY          error_invalid_el1h

        // From lower EL, where the level immediately lower than
        // target is using AArch64
        VENTRY          synchronous_invalid_el0_64
        VENTRY          irq_invalid_el0_64
        VENTRY          fiq_invalid_el0_64
        VENTRY          error_invalid_el0_64

        // From lower EL, where the level immediatley lower than
        // target is using AArch32
        VENTRY          synchronous_invalid_el0_32
        VENTRY          irq_invalid_el0_32
        VENTRY          fiq_invalid_el0_32
        VENTRY          error_invalid_el0_32

irq_el1h:
        KERNEL_ENTRY
        bl              current_elx_irq
        KERNEL_EXIT

synchronous_invalid_el1t:
        HANDLE_INVALID_ENTRY    SYNCHRONOUS_INVALID_EL1T

irq_invalid_el1t:
        HANDLE_INVALID_ENTRY    IRQ_INVALID_EL1T

fiq_invalid_el1t:
        HANDLE_INVALID_ENTRY    FIQ_INVALID_EL1T

error_invalid_el1t:
        HANDLE_INVALID_ENTRY    ERROR_INVALID_EL1T

synchronous_invalid_el1h:
        HANDLE_INVALID_ENTRY    SYNCHRONOUS_INVALID_EL1H

fiq_invalid_el1h:
        HANDLE_INVALID_ENTRY    FIQ_INVALID_EL1H

error_invalid_el1h:
        HANDLE_INVALID_ENTRY    ERROR_INVALID_EL1H

synchronous_invalid_el0_64:
        HANDLE_INVALID_ENTRY    SYNCHRONOUS_INVALID_EL0_64

irq_invalid_el0_64:
        HANDLE_INVALID_ENTRY    IRQ_INVALID_EL0_64

fiq_invalid_el0_64:
        HANDLE_INVALID_ENTRY    FIQ_INVALID_EL0_64

error_invalid_el0_64:
        HANDLE_INVALID_ENTRY    ERROR_INVALID_EL0_64

synchronous_invalid_el0_32:
        HANDLE_INVALID_ENTRY    SYNCHRONOUS_INVALID_EL0_32

irq_invalid_el0_32:
        HANDLE_INVALID_ENTRY    IRQ_INVALID_EL0_32

fiq_invalid_el0_32:
        HANDLE_INVALID_ENTRY    FIQ_INVALID_EL0_32

error_invalid_el0_32:
        HANDLE_INVALID_ENTRY    ERROR_INVALID_EL0_32

        .global err_hang
err_hang:
        b err_hang
