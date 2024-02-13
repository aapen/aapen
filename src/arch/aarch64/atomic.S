#include <asm/macro.h>

// ----------------------------------------------------------------------
// fn __arch_atomic_fetch
//
// Return the value of an atomic, using Aarch64 exclusives to ensure
// currency and atomicity
//
// Alignment: none
//
// Arguments:
// x0 - address of the value
//
// Returns:
// Value of the atomic
//
// Clobbers:
// ----------------------------------------------------------------------
        ENTRY(__arch_atomic_fetch)
        stp     x29, x30, [sp, -32]!            // prepare stack frame
        mov     x29, sp                         // link frame pointer
        ldar    x0, [x0]                        // load the value, with memory-ordering __ATOMIC_RELEASE
        ldp     x29, x30, [sp], 32              // tear down frame
        ret
        END(__arch_atomic_fetch)

// ----------------------------------------------------------------------
// fn __arch_atomic_fetch_add
//
// Add to a 64-bit value, returning the _prior_ value
//
// Alignment: none
//
// Arguments:
// x0 - address of the value
// x1 - value to add
//
// Returns:
// Previous value of the atomic
//
// Clobbers: x2, x3, x4
// ----------------------------------------------------------------------

        ENTRY(__arch_atomic_fetch_add)
        stp     x29, x30, [sp, -32]!            // prepare stack frame
        mov     x29, sp                         // link frame pointer
1:
        ldaxr   x2, [x0]                        // load-exclusive the current value
        add     x3, x2, x1                      // add the amount
        stlxr   w4, x3, [x0]                    // attempt to store exclusive
        cbnz    w4, 1b                          // zero means store-excl failed, loop
        mov     x0, x2                          // return the original value
        ldp     x29, x30, [sp], 32              // destroy stack frame
        ret
        END(__arch_atomic_fetch_add)


// ----------------------------------------------------------------------
// fn __arch_atomic_add_fetch
//
// Add to a 64-bit value, returning the _posterior_ value
//
// Alignment: none
//
// Arguments:
// x0 - address of the value
// x1 - value to add
//
// Returns:
// Resulting value of the atomic
//
// Clobbers: x2, x3, x4
// ----------------------------------------------------------------------

        ENTRY(__arch_atomic_add_fetch)
        stp     x29, x30, [sp, -32]!            // prepare stack frame
        mov     x29, sp                         // link frame pointer
1:
        ldaxr   x2, [x0]                        // load-exclusive the current value
        add     x3, x2, x1                      // add the amount
        stlxr   w4, x3, [x0]                    // attempt to store exclusive
        cbnz    w4, 1b                          // zero means store-excl failed, loop
        mov     x0, x3                          // return the new value
        ldp     x29, x30, [sp], 32              // destroy stack frame
        ret

        END(__arch_atomic_add_fetch)

// ----------------------------------------------------------------------
// fn __arch_atomic_fetch_sub
//
// Subtract from a 64-bit value, returning the _prior_ value
//
// Alignment: none
//
// Arguments:
// x0 - address of the value to subtract from
// x1 - value to subtract
//
// Returns:
// Previous value of the atomic
//
// Clobbers: x2, x3, x4
// ----------------------------------------------------------------------

        ENTRY(__arch_atomic_fetch_sub)
        stp     x29, x30, [sp, -32]!            // prepare stack frame
        mov     x29, sp                         // link frame pointer
1:
        ldaxr   x2, [x0]                        // load-exclusive the current value
        sub     x3, x2, x1                      // subtract the amount
        stlxr   w4, x3, [x0]                    // attempt to store exclusive
        cbnz    w4, 1b                          // zero means store-excl failed, loop
        mov     x0, x2                          // return the original value
        ldp     x29, x30, [sp], 32              // destroy stack frame
        ret
        END(__arch_atomic_fetch_sub)


// ----------------------------------------------------------------------
// fn __arch_atomic_sub_fetch
//
// Subtract from a 64-bit value, returning the _posterior_ value
//
// Alignment: none
//
// Arguments:
// x0 - address of the value to subtract from
// x1 - value to subtract
//
// Returns:
// Resulting value of the atomic
//
// Clobbers: x2, x3, x4
// ----------------------------------------------------------------------

        ENTRY(__arch_atomic_sub_fetch)
        stp     x29, x30, [sp, -32]!            // prepare stack frame
        mov     x29, sp                         // link frame pointer
1:
        ldaxr   x2, [x0]                        // load-exclusive the current value
        sub     x3, x2, x1                      // sub the amount
        stlxr   w4, x3, [x0]                    // attempt to store exclusive
        cbnz    w4, 1b                          // zero means store-excl failed, loop
        mov     x0, x3                          // return the new value
        ldp     x29, x30, [sp], 32              // destroy stack frame
        ret

        END(__arch_atomic_sub_fetch)

// ----------------------------------------------------------------------
// fn __arch_atomic_reset
//
// Reset a 64-bit value, return the _prior_ value
//
// Alignment: none
//
// Arguments:
// x0 - address of the value
// x1 - value to set
//
// Returns:
// Resulting value of the atomic
//
// Clobbers: x2, x3, x4
// ----------------------------------------------------------------------

        ENTRY(__arch_atomic_reset)
        stp     x29, x30, [sp, -32]!            // prepare stack frame
        mov     x29, sp                         // link frame pointer
1:
        ldaxr   x2, [x0]                        // load-exclusive the current value
        stlxr   w4, x1, [x0]                    // attempt to store exclusive the new value
        cbnz    w4, 1b                          // zero means store-excl failed, loop
        mov     x0, x2                          // return the old value
        ldp     x29, x30, [sp], 32              // destroy stack frame
        ret

        END(__arch_atomic_reset)
