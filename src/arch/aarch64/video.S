// Boot code for Cortex-A53 and Cortex-A72
//
// Requires a 64-bit architecture
//
// This applies to Raspberry Pi 3B, 3B+, 4B, 400, CM4

#include <asm/macro.h>
#include <asm/registers.h>

// ----------------------------------------------------------------------
// Constants
// ----------------------------------------------------------------------
        CACHE_LINE      = 64

// ----------------------------------------------------------------------
// Macros
// ----------------------------------------------------------------------

// ----------------------------------------------------------------------
// Functions
// ----------------------------------------------------------------------

// ----------------------------------------------------------------------
// fn _clean_cache_region
//
// Arguments:
//      x0 - address of region
//      x1 - length of region
// Returns: none
// Clobbers: none
// ----------------------------------------------------------------------
        ENTRY(_clean_cache_region)
        // Function prologue, create invocation frame
        stp	x29, x30, [sp, #-16]!
        stp	x1,  x2,  [sp, #-16]!
        mov	x29, sp

        // initialize loop
        mov	x2, x0
        add	x1, x1, x0

1:	// Clean data cache line by address
        dc	cvac, x2

        // Increment to the next cache line
        add	x2, x2, #CACHE_LINE
        cmp	x2, x1
        b.lt	1b

        // Function epilogue, restore stack and registers
        ldp	x1,  x2,  [sp], #16
        ldp	x29, x30, [sp], #16
        ret
        END(_clean_cache_region)

// ----------------------------------------------------------------------
// fn _clean_cache_region
//
// Arguments:
//      x0 - address of region
//      x1 - length of region
// Returns: none
// Clobbers: none
// ----------------------------------------------------------------------
        ENTRY(_invalidate_cache_region)
        // Function prologue, create invocation frame
        stp	x29, x30, [sp, #-16]!
        stp	x1,  x2,  [sp, #-16]!
        mov	x29, sp

        // initialize loop
        mov	x2, x0
        add	x1, x1, x0

1:	// Invalidate data cache line by address
        dc	ivac, x2

        // Increment to the next cache line
        add	x2, x2, #CACHE_LINE
        cmp	x2, x1
        b.lt	1b

        // Function epilogue, restore stack and registers
        ldp	x1,  x2,  [sp], #16
        ldp	x29, x30, [sp], #16
        ret
        END(_invalidate_cache_region)

// ----------------------------------------------------------------------
// fn _mailbox_send
//
// Arguments:
//      x0 - location of message
//      x1 - length of message
// Returns: none
// Clobbers:
// ----------------------------------------------------------------------
        ENTRY(_mailbox_send)
        // Function prologue, create invocation frame
        stp     x29, x30, [sp, #-16]!
        stp     x5,  x4,  [sp, #-16]!
        mov     x29, sp

        // wait until space available
        LDR_IMM64 x5, MBOX0_STATUS
1:      ldr     w4, [x5]                // get mailbox status
        tbnz    w4, #31, 1b             // mailbox full? then loop

        // make sure message is visible to videocore
        dmb     st                      // memory barrier
        bl      _clean_cache_region

        // set channel 8 "property arm to videocore"
        bic     x0, x0, #0xf            // x0 &= ~(0xf)
        orr     x0, x0, #0x8            // x0 |= 0x8

        // write the message addr to mailbox
        LDR_IMM64 x5, MBOX0_WRITE
        str     w0, [x5]                // note: lower 32 bits only

        // wait for reply
        LDR_IMM64 x5, MBOX0_STATUS
2:      ldr     w4, [x5]                // get mailbox status
        tbnz    w4, #30, 2b             // mailbox empty? then loop

        // read reply
        LDR_IMM64 x5, MBOX0_READ
        ldr     w0, [x5]

        // mask off channel
        bic     x0, x0, #0xf

        // make sure message is visible to CPU
        bl      _invalidate_cache_region
        dmb     st

        //
        // TODO - extract FB address, size, and pitch. Store in
        // variables.
        //


        // Function epilogue, restore stack
        ldp     x5,  x4,  [sp], #16
        ldp     x29, x30, [sp], #16
        ret
        END(_mailbox_send)

// ----------------------------------------------------------------------
// fn _video_init
//
// Arguments: none
// Returns: none
// Clobbers:
// ----------------------------------------------------------------------
        ENTRY(_video_init)
        // Function prologue, create invocation frame
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

        ldr     x0, =fb_init_message
        ldr     x1, =fb_init_message_end-fb_init_message
        bl      _mailbox_send

        ldr     x3, =fb_parameters
        add     x2, x0, #5*4            // locn of xresolution in msg

        ldr     w1, [x2], #4            // read xres, advance ptr to yres
        str     x1, [x3], #8            // write xres
        ldr     w1, [x2], #80           // read yres, advance ptr to fb addr
        str     x1, [x3], #8            // write yres
        ldr     w1, [x2], #4            // read fb addr, advance ptr to fb size
        str     x1, [x3], #8            // write fb addr to fb struct
        ldr     w1, [x2], #16           // read fb size, advance ptr to fb pitch
        str     x1, [x3], #8            // write fb size to fb struct
        ldr     w1, [x2]                // read fb pitch
        str     x1, [x3], #8            // write fb pitch to fb struct

        // Function epilogue, restore stack
        ldp     x29, x30, [sp], #16
        ret
        END(_video_init)

// ----------------------------------------------------------------------
// fn draw_char
//
// Arguments:
//      x0 - character code
// Register assignments
//      x1 - row pitch
//      x2 - fgcolor
//      x3 - bgcolor
//      x4 - addr of top-left corner
// Returns: none
// Clobbers:
// ----------------------------------------------------------------------
        ENTRY(draw_char)
        // Function prologue, create invocation frame
        stp     x29, x30, [sp, #-16]!
        stp     x0,  x1,  [sp, #-16]!
        stp     x2,  x3,  [sp, #-16]!
        stp     x4,  x5,  [sp, #-16]!
        stp     x9,  x11, [sp, #-16]!
        stp     x12, xzr, [sp, #-16]!
        mov     x29, sp

        // set up parameters
        ldr     x5, =fb_parameters
        add     x5, x5, #16
        ldr     x4, [x5], #16           // x4 <- fb.addr
        ldr     x1, [x5], #8            // x1 <- fb.pitch
        ldr     x3, [x5], #8            // x3 <- fb.bgcolor
        ldr     x2, [x5], #8            // x2 <- fb.fgcolor
        ldr     x9, [x5], #8            // x9 <- fb.cursorx
        ldr     x11, [x5], #8           // x11 <- fb.cursory

        mul     x11, x11, x1            // addr += cursory * pitch * 16
        add     x4, x4, x11, lsl #4
        add     x4, x4, x9, lsl #3       // addr += cursorx * 8

        // convert ascii to char rom index
        sub     x0, x0, #32

        // bounds check on last byte of the proposed char
        lsl     x0, x0, #4              // charoff = char*16
        cmp     x0, #char_rom_end-char_rom-16
        b.hi    1f                      // if charoff > sizeof(char_rom)-16 then exit

        sub     x1, x1, #8              // reduce stride by char width

        ldr     x5, =char_rom           // romptr = char_rom
        add     x5, x5, x0              // romptr += charoff
        add     x9, x5, #16             // x9 = last loc to use from char rom

loop:
        ldrb    w12, [x5], 1            // row = *romptr++

        // unrolled loop over bits in the row
        tst     w12, #0x80              // row & 0x80
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x4], 1            // *fbptr++ = w13

        tst     w12, #0x40              // row & 0x40
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x4], 1            // *fbptr++ = w13

        tst     w12, #0x20              // row & 0x20
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x4], 1            // *fbptr++ = w13

        tst     w12, #0x10              // row & 0x10
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x4], 1            // *fbptr++ = w13

        tst     w12, #0x08              // row & 0x08
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x4], 1            // *fbptr++ = w13

        tst     w12, #0x04              // row & 0x04
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x4], 1            // *fbptr++ = w13

        tst     w12, #0x02              // row & 0x02
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x4], 1            // *fbptr++ = w13

        tst     w12, #0x01              // row & 0x01
        csel    w13, w2, w3, ne         // if NZ w13 = fg else w13 = bg
        strb    w13, [x4], 1            // *fbptr++ = w13

        add     x4, x4, x1              // fbptr += row pitch
        cmp     x5, x9                  // while romptr < last loc
        b.ne    loop                    // do next row

1:      // Function epilogue, restore stack and registers
        ldp     x12, xzr, [sp], #16
        ldp     x9,  x11, [sp], #16
        ldp     x4,  x5,  [sp], #16
        ldp     x2,  x3,  [sp], #16
        ldp     x0,  x1,  [sp], #16
        ldp     x29, x30, [sp], #16
        ret
        END(draw_char)


// ----------------------------------------------------------------------
// fn erase_char - erase character under the cursor
//
// Arguments: none
// Register assignments
//      x1 - row pitch
//      x2 - fgcolor
//      x3 - bgcolor
//      x4 - addr of top-left corner
// Returns: none
// Clobbers:
// ----------------------------------------------------------------------
        ENTRY(erase_char)
        // Function prologue, create invocation frame
        stp     x29, x30, [sp, #-16]!
        stp     x0,  x1,  [sp, #-16]!
        stp     x2,  x3,  [sp, #-16]!
        stp     x4,  x5,  [sp, #-16]!
        stp     x9,  x11, [sp, #-16]!
        stp     x12, xzr, [sp, #-16]!
        mov     x29, sp

        // set up parameters
        ldr     x5, =fb_parameters
        add     x5, x5, #16
        ldr     x4, [x5], #16           // x4 <- fb.addr
        ldr     x1, [x5], #8            // x1 <- fb.pitch
        ldr     x3, [x5], #8            // x3 <- fb.bgcolor
        ldr     x2, [x5], #8            // x2 <- fb.fgcolor
        ldr     x9, [x5], #8            // x9 <- fb.cursorx
        ldr     x11, [x5], #8           // x11 <- fb.cursory

        mul     x11, x11, x1            // addr += cursory * pitch * 16
        add     x4, x4, x11, lsl #4
        add     x4, x4, x9, lsl #3      // addr += cursorx * 8

        sub     x1, x1, #8              // reduce stride by char width

        mov     x9, #16                 // 16 rows to draw with bgcolor

1:
        // unrolled loop over bits in the row
        strb    w3, [x4], 1             // *fbptr++ = w3
        strb    w3, [x4], 1             // *fbptr++ = w3
        strb    w3, [x4], 1             // *fbptr++ = w3
        strb    w3, [x4], 1             // *fbptr++ = w3
        strb    w3, [x4], 1             // *fbptr++ = w3
        strb    w3, [x4], 1             // *fbptr++ = w3
        strb    w3, [x4], 1             // *fbptr++ = w3
        strb    w3, [x4], 1             // *fbptr++ = w3

        add     x4, x4, x1              // fbptr += row pitch
        subs    x9, x9, #1
        b.ne    1b                      // do next row

        // Function epilogue, restore stack and registers
        ldp     x12, xzr, [sp], #16
        ldp     x9,  x11, [sp], #16
        ldp     x4,  x5,  [sp], #16
        ldp     x2,  x3,  [sp], #16
        ldp     x0,  x1,  [sp], #16
        ldp     x29, x30, [sp], #16
        ret
        END(erase_char)


// ----------------------------------------------------------------------
// fn advance_cursor
//
// Moves cursor forward by x0 positions
//
// Arguments: x0 - positions to advance
// Returns: none
// Clobbers: none
// ----------------------------------------------------------------------
        ENTRY(advance_cursor)
        // Function prologue, create invocation frame
        stp     x29, x30, [sp, #-16]!
        stp     x0,  x1,  [sp, #-16]!
        stp     x2,  x3,  [sp, #-16]!
        mov     x29, sp

        // get current cursor position
        ldr     x3, =fb_parameters      // addr of param block
        add     x3, x3, #56             // addr of cursor-x
        ldr     x1, [x3], #8            // get cursor-x, advance ptr to cursor-y
        ldr     x2, [x3]                // get cursor-y

        add     x1, x1, x0
        cmp     x1, #128                // cursor-x >= 128?
        b.lt    1f                      // no, go ahead and write the value

        and     x1, x1, #127            // cursor-x & 127
        add     x2, x2, #1              // cursor-y += 1
2:      cmp     x2, #48                 // cursor-y >= 47?
        b.lt    1f                      // no, go ahead and write the value
        sub     x2, x2, #48             // cursor-y -= 48 (wrap to top of screen)
        b       2b

        // write new cursor position
1:      str     x2, [x3], #-8           // write cursor-y, retreat ptr to cursor-x
        str     x1, [x3]

        // Function epilogue, restore stack and registers
        ldp     x2,  x3,  [sp], 16
        ldp     x0,  x1,  [sp], 16
        ldp     x29, x30, [sp], 16
        ret
        END(advance_cursor)

// ----------------------------------------------------------------------
// fn newline_cursor
//
// Moves cursor to column 0 in the next row
//
// Arguments: none
// Returns: none
// Clobbers: none
// ----------------------------------------------------------------------
        ENTRY(newline_cursor)
        // Function prologue, create invocation frame
        stp     x29, x30, [sp, #-16]!
        stp     x0,  x1,  [sp, #-16]!
        stp     x2,  x3,  [sp, #-16]!
        mov     x29, sp

        // get current cursor position
        ldr     x3, =fb_parameters      // addr of param block
        add     x3, x3, #64             // addr of cursor-y
        ldr     x2, [x3]                // get cursor-y

        add     x2, x2, #1              // cursor-y += 1
2:      cmp     x2, #47                 // cursor-y >= 47?
        b.lt    1f                      // no, go ahead and write the value
        sub     x2, x2, #48             // cursor-y -= 48 (wrap to top of screen)
        b       2b

        // write new cursor position
1:      str     x2, [x3], #-8           // write cursor-y, retreat ptr to cursor-x
        str     xzr, [x3]               // set cursor-x to 0

        // Function epilogue, restore stack and registers
        ldp     x2,  x3,  [sp], 16
        ldp     x0,  x1,  [sp], 16
        ldp     x29, x30, [sp], 16
        ret
        END(advance_cursor)

// ----------------------------------------------------------------------
// Data
// ----------------------------------------------------------------------
        .section .rodata
        .global char_rom
char_rom:
        .incbin "data/character_rom.bin"
char_rom_end:

        .align  3
        .global fb_parameters
fb_parameters:
        .quad   0                       // 0: xresolution
        .quad   0                       // 8: yresolution
        .quad   0                       // 16: addr
        .quad   0                       // 24: size
        .quad   0                       // 32: pitch
        .quad   0                       // 40: bgcolor
        .quad   1                       // 48: fgcolor
        .quad   0                       // 56: cursor-x
        .quad   0                       // 64: cursor-y

        .align  5
        .global fb_init_message
fb_init_message:
        .word 0x00000118
        .word 0x00000000
        .word 0x00048003                // set physical size
        .word 0x00000008
        .word 0x00000008
        .word 0x00000400                // 1024 pixels
        .word 0x00000300                // 768 pixels
        .word 0x00048004                // set virtual size
        .word 0x00000008
        .word 0x00000008
        .word 0x00000400                // 1024 pixels
        .word 0x00000300                // 768 pixels
        .word 0x00048005                // set depth
        .word 0x00000004
        .word 0x00000004
        .word 0x00000008                // 8 bits per pixel
        .word 0x0004800a                // set overscan
        .word 0x00000010
        .word 0x00000010
        .word 0x00000000                // 0
        .word 0x00000000                // 0
        .word 0x00000000                // 0
        .word 0x00000000                // 0
        .word 0x00040001                // allocate framebuffer
        .word 0x00000008
        .word 0x00000008
        .word 0x00000000                // space for base address
        .word 0x00000010                // address alignment in bytes
        .word 0x00040008                // get pitch
        .word 0x00000004
        .word 0x00000004
        .word 0x00000000                // space for pitch
        .word 0x0004800b                // set palette
        .word 0x00000088
        .word 0x00000088
        .word 0x00000000                // offset 0
        .word 0x00000020                // 32 entries follow
        .word 0x00000000                // black
        .word 0x00ffffff                // white
        .word 0x000000ff                // etc.
        .word 0x00eeffaa
        .word 0x00cc44cc
        .word 0x0055cc00
        .word 0x00e44140
        .word 0x0077eeee
        .word 0x005588dd
        .word 0x00004466
        .word 0x007777ff
        .word 0x00333333
        .word 0x00777777
        .word 0x0066ffaa
        .word 0x00f3afaf
        .word 0x00bbbbbb
        .word 0x00ffffff                // currently unassigned colors
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00ffffff
        .word 0x00000000
fb_init_message_end:
