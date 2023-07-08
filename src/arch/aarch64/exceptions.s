        // Exception vector code for Cortex-A53 and Cortex-A72
        //

        // ----------------------------------------------------------------------
        // Constants
        // ----------------------------------------------------------------------

        CONST_ESR_EL1_EC_SHIFT       = 26
        CONST_ESR_EL1_EC_VALUE_SVC64 = 0x15

        // ----------------------------------------------------------------------
        // Macros
        // ----------------------------------------------------------------------

        // Insert a small routine to halt the processor on receipt of
        // a fast interrupt request (FIQ).
.macro FIQ_SUSPEND offset, label
        .org \offset
        .type __fiq_suspend_\label, @function
__fiq_suspend_\label:
1:      wfe
        b 1b
.endm

        // Define a common structure for all exception handlers. Each
        // one must:
        // - Save context
        // - Call the "real" handler
        // - Restore context
        // - Return from exception
        //
        // Arguments:
        //   handler:    symbol for the "real" handler
        //   from_lower: true when this handler should be configured
        //               for an EL-raising exception
        //   is_sync:    true when this handler should be configured
        //               for the synchronous exceptions
.macro EXC_HANDLER offset, handler, from_lower, is_sync
        .org \offset
        .type __handle_\handler, @function
__handle_\handler:
        sub sp, sp, #16 * 18          // Make room in the stack for the
                                      // exception context. (See exceptions.s)
        stp x0, x1,   [sp, #16 * 0]   // Save general purpose registers
        stp x2, x3,   [sp, #16 * 1]   //
        stp x4, x5,   [sp, #16 * 2]
        stp x6, x7,   [sp, #16 * 3]
        stp x8, x9,   [sp, #16 * 4]
        stp x10, x11, [sp, #16 * 5]
        stp x12, x13, [sp, #16 * 6]
        stp x14, x15, [sp, #16 * 7]
        stp x16, x17, [sp, #16 * 8]
        stp x18, x19, [sp, #16 * 9]
        stp x20, x21, [sp, #16 * 10]
        stp x22, x23, [sp, #16 * 11]
        stp x24, x25, [sp, #16 * 12]
        stp x26, x27, [sp, #16 * 13]
        stp x28, x29, [sp, #16 * 14]

        mrs x1, ELR_EL1               // Get the exception link
        mrs x2, SPSR_EL1              // Get the saved program status
        mrs x3, ESR_EL1               // Get the exception syndrome
        stp lr, x1, [sp, #16 * 15]    // Save them all on the stack
        stp x2, x3, [sp, #16 * 16]

        // Build a stack frame for backtracing
.if \from_lower == 1
        stp xzr, xzr, [sp, #16 * 17]  // Fake a root frame to stop the
                                      // kernel from backtracing into
                                      // user space
.else
.if \is_sync == 1
        // tricky stuff here... see "ARM Architecture Reference Manual
        // for ARMv8-A", section "Preferred exception return address"
        //
        // the net effect is to point to the instruction after the
        // exception by doing some math on the program counter, except
        // when the exception was caused by an exception-generating
        // instruction
        lsr w3, w3, #CONST_ESR_EL1_EC_SHIFT
        cmp w3, #CONST_ESR_EL1_EC_VALUE_SVC64
        b.eq 1f
.endif
        add x1, x1, #4
1:      stp x29, x1, [sp, #16 * 17]
.endif

        add x29, sp, #16 * 17         // Set frame pointer to the
                                      // stack frame
        mov x0, sp                    // Provide exception context to
                                      // the function we're about to
                                      // call
        bl \handler
        b  __restore_context          // Unconditionally do the
                                      // handler function return
        .size __handle_\handler, . - __handle_\handler
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
        // The handlers are directly in the table; these are not
        // vectors for the CPU to follow. Therefore, each handler must
        // fit inside its $80 byte space. Mostly this means saving
        // registers then branching to a higher-level function.
        .global __exception_handler_table
__exception_handler_table:
        // From EL0 to EL0
        EXC_HANDLER 0x000, current_el0_synchronous, 0, 1
        EXC_HANDLER 0x080, current_el0_irq, 0, 0
        FIQ_SUSPEND 0x100, current_el0
        EXC_HANDLER 0x180, current_el0_serror, 0, 0

        // From ELx to ELx (x > 0)
        EXC_HANDLER 0x200, current_elx_synchronous, 0, 1
        EXC_HANDLER 0x280, current_elx_irq, 0, 0
        FIQ_SUSPEND 0x300, current_elx
        EXC_HANDLER 0x380, current_elx_serror, 0, 0

        // From lower EL, where the level immediately lower than
        // target is using AArch64
        EXC_HANDLER 0x400, lower_aarch64_synchronous, 1, 1
        EXC_HANDLER 0x480, lower_aarch64_irq, 1, 0
        FIQ_SUSPEND 0x500, lower_aarch64
        EXC_HANDLER 0x580, lower_aarch64_serror, 1, 0

        // From lower EL, where the level immediatley lower than
        // target is using AArch32
        EXC_HANDLER 0x600, lower_aarch32_synchronous, 1, 1
        EXC_HANDLER 0x680, lower_aarch32_irq, 1, 0
        FIQ_SUSPEND 0x700, lower_aarch32
        EXC_HANDLER 0x780, lower_aarch32_serror, 1, 0

        // ----------------------------------------------------------------------
        // Restore context and return from exception.
        //
        // NOTE: This must be the reverse of the context save code in
        // the macro `EXC_HANDLER`
        // ----------------------------------------------------------------------
        .type __restore_context, function
__restore_context:
        ldr w19, [sp, #16 * 16]
        ldp lr, x20, [sp, #16 * 15]

        msr SPSR_EL1, x19
        msr ELR_EL1, x20

        ldp x0, x1, [sp, #16 * 0]
        ldp x2, x3, [sp, #16 * 1]
        ldp x4, x5, [sp, #16 * 2]
        ldp x6, x7, [sp, #16 * 3]
        ldp x8, x9, [sp, #16 * 4]
        ldp x10, x11, [sp, #16 * 5]
        ldp x12, x13, [sp, #16 * 6]
        ldp x14, x15, [sp, #16 * 7]
        ldp x16, x17, [sp, #16 * 8]
        ldp x18, x19, [sp, #16 * 9]
        ldp x20, x21, [sp, #16 * 10]
        ldp x22, x23, [sp, #16 * 11]
        ldp x24, x25, [sp, #16 * 12]
        ldp x26, x27, [sp, #16 * 13]
        ldp x28, x29, [sp, #16 * 14]

        add sp, sp, #16 * 18

        eret
        .size __restore_context, . - __restore_context
