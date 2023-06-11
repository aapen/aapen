        // boot code for Cortex-A53 and Cortex-A72
        // Applies to 3B, 3B+, 4B, 400, CM4

        .section ".text.boot"

CONST_CORE_ID_MASK = 0b11
BOOT_CORE_ID       =    0

        .globl _start
        .type  _start,@function
_start:
        // Check we are on the main core
        //
        // References:
        // https://developer.arm.com/documentation/ddi0500/j/System-Control/AArch64-register-descriptions/Multiprocessor-Affinity-Register?lang=en
        mrs x0, MPIDR_EL1
        and x0, x0, #CONST_CORE_ID_MASK
        ldr x1, =BOOT_CORE_ID
        cmp x0, x1
        b.ne .L_parking_loop

        // On main core

        // Initialize BSS section to zero
        ldr x0, =__bss_start
        ldr w1, =__bss_end_exclusive

.L_bss_init_loop:
        cmp x0, x1
        b.eq .L_initialize_stack
        stp xzr, xzr, [x0], #16
        b .L_bss_init_loop

.L_initialize_stack:
        // Initialize stack
        adrp x0, __boot_core_stack_end_exclusive
        add  x0, x0, #:lo12:__boot_core_stack_end_exclusive
        mov sp, x0

        // Jump to main()
        bl kernel_main

        // TEMP: tell QEMU to quit
        // Use the return value from kernel_main as the exit code
        mov x2,x0
        bl _qemu_exit

        // Park the core
.L_parking_loop:
        wfe
        b .L_parking_loop

        .size _start, . - _start
        .type _start, function
        .global _start
