        // boot code for Cortex-A53 and Cortex-A72
        // Applies to 3B, 3B+, 4B, 400, CM4

        .section ".text.boot"

        .global _start

_start:
        // Check we are on the main core
        //
        // References:
        // https://developer.arm.com/documentation/ddi0500/j/System-Control/AArch64-register-descriptions/Multiprocessor-Affinity-Register?lang=en
        mrs x1, mpidr_el1
        and x1, x1, #3
        cbz x1, 2f

1:
        // Not on main core, wait forever
        wfe
        b 1b

2:
        // On main core

        // Initialize stack
        ldr x1, _start
        mov sp, x1

        // Clean BSS section
        ldr x1, __bss_start
        ldr w2, __bss_size
3:
        cbz w2, 4f
        str xzr, [x1], #8
        sub w2, w2, #1
        cbnz w2, 3b

4:
        // Jump to main()
        bl main

        // In case main() returns, spinloop
        b 1b
