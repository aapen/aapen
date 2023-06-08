        // boot code for Cortex-A53 and Cortex-A72
        // Applies to 3B, 3B+, 4B, 400, CM4

        .section ".text.boot"

CONST_CORE_ID_MASK = 0b11
BOOT_CORE_ID       =    0

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
        ldr w1, =__bss_end

.L_bss_init_loop:
        cmp x0, x1
        b.eq .L_initialize_stack
        stp xzr, xzr, [x0], #16
        b .L_bss_init_loop

.L_initialize_stack:
        // Initialize stack
        // (for now) the stack starts at _start and grows downward.
        // this is limiting... once we're in kernel space we will
        // reset this
        ldr x1, =_start
        mov sp, x1

        // Jump to main()
        b main

        // if main returns, fall through to park the core

        // Park the core
.L_parking_loop:
        wfe
        b .L_parking_loop

        .size _start, . - _start
        .type _start, function
        .global _start
