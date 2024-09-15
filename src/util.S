#include <asm/macro.h>

        .section .text.util
        
// ----------------------------------------------------------------------
// fn spinDelay()
//
// Loop for (roughly) a number of CPU cycles
//
// Arguments:
//      x0 - number of iterations to spin for
// Returns: none
// Clobbers: x0
// ----------------------------------------------------------------------

        ENTRY(spinDelay)
        subs    x0, x0, #1
        bne     spinDelay
        ret
        END(spinDelay)


// ----------------------------------------------------------------------
// fn print_hex
//
// Print a 32-bit unsigned hex value
//
// Alignment:
// Arguments:
//      x1 - value
// Returns: none
// Clobbers: x3, x0, x1
// ----------------------------------------------------------------------
	ENTRY(print_hex)
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
        END(print_hex)


