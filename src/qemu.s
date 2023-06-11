        // Semihosting interface to QEMU
        // See https://github.com/ARM-software/abi-aa/blob/main/semihosting/semihosting.rst#65sys_exit-0x18

        .section ".text.qemu"

        .globl _qemu_exit

        // Parameters:
        // x2 - the exit code to signal
        //
        // Clobbers:
        // x0, x1
        //
        // Does not return.
_qemu_exit:
        // x1 should have the address of a 2 word structure
        ldr x1, =__qemu_exit_struct

        // Place the exit code in the struct
        str x2, [x1, #8]

        // w0 contains the operation number
        // 0x18 says we want to invoke SYS_EXIT
        ldr x0, =0x18

        // For aarch64, #0xF000 indicates SYS_EXIT
        hlt #0xF000

        // If for some reason, this returns (maybe we're not actually
        // running under QEMU) just spinloop the processor
L_forever:
        wfe
        b L_forever

__qemu_exit_struct:
        .dword 0x20026  // 0x20026 indicates ADP_Stopped_ApplicationExit
        .dword 0        // This will be filled in with the status code
