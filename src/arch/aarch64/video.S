// Boot code for Cortex-A53 and Cortex-A72
//
// Requires a 64-bit architecture
//
// This applies to Raspberry Pi 3B, 3B+, 4B, 400, CM4

#include <asm/macro.h>

// ----------------------------------------------------------------------
// Constants
// ----------------------------------------------------------------------

// ----------------------------------------------------------------------
// Macros
// ----------------------------------------------------------------------

// ----------------------------------------------------------------------
// Functions
// ----------------------------------------------------------------------

// ----------------------------------------------------------------------
// fn draw_char
//
// Arguments:
//      x0 - base address to draw at
//      x1 - row pitch
//      x2 - fgcolor
//      x3 - bgcolor
//      x4 - character code
// Returns: none
// Clobbers: x9, x11, x12
// ----------------------------------------------------------------------
        ENTRY(draw_char)
        stp     x29, x30, [sp, -16]!

        // convert ascii to char rom index
        sub     x4, x4, #32

        // bounds check on last byte of the proposed char
        lsl     x4, x4, #4              // charoff = char*16
        cmp     x4, #char_rom_end-char_rom-16
        b.hi    1f                      // if charoff > sizeof(char_rom)-16 then exit

        sub     x1, x1, #8              // reduce stride by char width

        ldr     x5, =char_rom           // romptr = char_rom
        add     x5, x5, x4              // romptr += charoff
        add     x9, x5, #16             // x9 = last loc to use from char rom

loop:
        ldrb    w12, [x5], 1            // row = *romptr++

        // unrolled loop over bits in the row
        tst     w12, #0x80              // row & 0x80
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x0], 1            // *fbptr++ = w13

        tst     w12, #0x40              // row & 0x40
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x0], 1            // *fbptr++ = w13

        tst     w12, #0x20              // row & 0x20
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x0], 1            // *fbptr++ = w13

        tst     w12, #0x10              // row & 0x10
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x0], 1            // *fbptr++ = w13

        tst     w12, #0x08              // row & 0x08
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x0], 1            // *fbptr++ = w13

        tst     w12, #0x04              // row & 0x04
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x0], 1            // *fbptr++ = w13

        tst     w12, #0x02              // row & 0x02
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x0], 1            // *fbptr++ = w13

        tst     w12, #0x01              // row & 0x01
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x0], 1            // *fbptr++ = w13

        add     x0, x0, x1              // fbptr += row pitch
        cmp     x5, x9                  // while romptr < last loc
        b.ne    loop                    // do next row

1:
        ldp     x29, x30, [sp], 16
        ret
        END(draw_char)


// ----------------------------------------------------------------------
// Data
// ----------------------------------------------------------------------
        .rodata
        .global char_rom
char_rom:
        .incbin "data/character_rom.bin"
char_rom_end:
