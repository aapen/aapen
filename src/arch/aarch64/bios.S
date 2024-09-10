// Basic I/O System
//
// Contains a vector table pointing to routines for input and output.
//

#include <asm/macro.h>
#include <asm/registers.h>

// ----------------------------------------------------------------------
// Constants
// ----------------------------------------------------------------------

// ----------------------------------------------------------------------
// Macros
// ----------------------------------------------------------------------

// ----------------------------------------------------------------------
// Functions
// ----------------------------------------------------------------------

        .section .text

// ----------------------------------------------------------------------
// fn __bios_init()
//
// Initialize all parts of BIOS (currently this is only the serial console)
//
// Arguments: none
// Returns: none
// Clobbers: x0
// ----------------------------------------------------------------------
        ENTRY(_bios_init)
        // Function prologue, create invocation frame
        stp     x29, x30, [sp, #-16]!
        stp     x0, x1, [sp, #-16]!
        mov     x29, sp

        ldr     x1, =_init_done
        ldr     x0, [x1]
        cmp     x0, #0
        bne     1f

        bl      _con_init
        bl      _video_init

        LDR_IMM64 x3, 0x10000
        ldr     x2, =_con_in            // BIOS vector 0
        str     x2, [x3], #8
        ldr     x2, =_con_out           // BIOS vector 1
        str     x2, [x3], #8
        ldr     x2, =_vid_out           // BIOS vector 2
        str     x2, [x3], #8
        ldr     x2, =_outch             // BIOS vector 3
        str     x2, [x3], #8

        mov     x0, #'F'
        BIOS(3)

        orr     x0, xzr, #1
        str     x0, [x1]

        // Function epilogue, restore stack
1:      ldp     x0, x1, [sp], #16
        ldp     x29, x30, [sp], #16
        ret
        END(_bios_init)

// ----------------------------------------------------------------------
// fn _con_init()
//
// Initialize the UART for serial console use
//
// Arguments: none
// Returns: none
// Clobbers: x0, x1
// ----------------------------------------------------------------------

        ENTRY(_con_init)

        // Function prologue, create invocation frame, save x0 and x1
        stp     x29, x30, [sp, #-16]!
        stp     x0, x1, [sp, #-16]!
        mov     x29, sp

        // set GPIO 14 & 15 to output
        ldr     x1, =GPFSEL1            // Address of GPFSEL1 register
        ldr     w0, [x1]
        bic     w0, w0, #(7 << 12)      // clear bits 12 - 14 (fsel for pin 14)
        bic     w0, w0, #(7 << 15)      // clear bits 15 - 17 (fsel for pin 15)
        orr     w0, w0, #(4 << 12)      // 0b100 = Alt0 for pin 14
        orr     w0, w0, #(4 << 15)      // 0b100 = Alt0 for pin 15
        str     w0, [x1]                // write the register

        // enable GPIO 14 & 15
        ldr     x1, =GPPUD              // Address of GPPUD register
        str     wzr, [x1]               // zero it to set "float" status

        movz    x0, #150                // we need to spin 150 cycles
1:      subs    x0, x0, #1
        bne     1b

        ldr     x2, =GPPUDCLK0          // Address of GPPUDCLK0 register
        mov     w0, #(1 << 14) | (1 << 15)
        str     w0, [x2]                // clock in the 'float' for pins 14 & 15

        movz    x0, #150                // we need to spin another 150 cycles
2:      subs    x0, x0, #1
        bne     2b

        str     wzr, [x2]               // deassert all in GPPUDCLK0

        // turn off uart while initializing
        ldr     x1, =UART_CR            // Address of CR
        str     wzr, [x1]               // zero it

        // flush the xmit fifo
        ldr     x2, =UART_LCRH          // Address of LCHR (in x2 so we can use it later)
        str     wzr, [x2]               // zero it (disables fifos)

        // clear all pending interrupts
        ldr     x1, =UART_ICR           // Address of ICR
        str     wzr, [x1]               // zero it

        // set the baud rate, 8N1 and FIFO disabled.
        // use clock divisor 26.0417 to get 115,200 baud
        ldr     x1, =UART_IBRD          // Address of IBRD
        movz    w0, #0x001a             // integer part of 26.0417 - the clock divisor
        str     w0, [x1]                // set integer part
        ldr     x1, =UART_FBRD          // Address of FBRD
        movz    w0, #0x001b             // fractional part of clock divisor
        str     w0, [x1]                // set fractional part
        movz    w0, #(3 << 5)           // 8 bits word, no stop bits, even parity
        str     w0, [x2]                // set LCRH

        // disable interrupts
        ldr     x1, =UART_IMSC          // Address of IMSC register
        str     wzr, [x1]               // zero it

        // enable the uart
        ldr     x1, =UART_CR            // Address of control register
        movz    w0, #0x301              // xmit enable, recv enable, uart enable
        str     w0, [x1]                // enable the uart

        // function epilogue, restore saved registers and stack
        ldp     x0, x1, [sp], #16
        ldp     x29, x30, [sp], #16
        ret
        END(_con_init)


// ----------------------------------------------------------------------
// fn _con_out(x0: u8)
//
// Write a byte to UART
//
// Arguments: none
// Returns: none
// Clobbers: none
// ----------------------------------------------------------------------

        ENTRY(_con_out)
        // Function prologue, create invocation frame, save x1, x2
        stp     x29, x30, [sp, #-16]!
        stp     x1,  x2,  [sp, #-16]!
        mov     x29, sp

        // wait for space available
        ldr     x1, =UART_FR            // address of flags register
1:      ldr     w2, [x1]                // get flags
        ands    w2, w2, #(1<<5)         // check transmit_fifo_full bit
        bne     1b

        // space is available
        ldr     x1, =UART_DR            // address of data register
        str     w0, [x1]                // write the data byte

        // function epilogue, restore saved registers and stack
        ldp     x1,  x2,  [sp], #16
        ldp     x29, x30, [sp], #16
        ret
        END(_con_out)



// ----------------------------------------------------------------------
// fn _con_in() -> x0:u8
//
// Read a byte from UART
//
// Arguments: none
// Returns: none
// Clobbers: none
// ----------------------------------------------------------------------

        ENTRY(_con_in)
        // Function prologue, create invocation frame, save x0, x1, x2
        stp     x29, x30, [sp, #-16]!
        stp     x0,  x1,  [sp, #-16]!
        mov     x29, sp

        // wait for data available
        ldr     x1, =UART_FR            // address of flags register
1:      ldr     w0, [x1]                // get flags
        ands    w0, w0, #(1<<4)         // check receive_fifo_empty bit
        bne     1b

        // data is available
        ldr     x1, =UART_DR            // address of data register
        ldr     w0, [x1]                // get data
        and     w0, w0, #0xff           // keep lower byte
        ret

        // function epilogue, restore saved registers and stack
        ldp     x0,  x1,  [sp], #16
        ldp     x29, x30, [sp], #16
        ret
        END(_con_in)

// ----------------------------------------------------------------------
// fn _vid_out()
//
// Write a character to the display
//
// Arguments: x0 - ASCII code of the character to draw
// Returns: none
// Clobbers: none
// ----------------------------------------------------------------------
        ENTRY(_vid_out)
        // Function prologue, create invocation frame, save x0, x1, x2
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

        bl      draw_char
        mov     x0, #1
        bl      advance_cursor

        // Function epilogue, restore saved registers and stack
        ldp     x29, x30, [sp], #16
        ret
        END(_vid_out)

// ----------------------------------------------------------------------
// fn _outch()
//
// Write a character to the UART and display. Handles some special
// characters correctly for each device:
//	Character	UART effect	Display effect
//	0x0a		\r\n		cursor-x = 0, cursor-y += 1
//      0x08            ' ' \b ' '	cursor-x -= 1, draw_char(' ')
//
// Arguments: x0 - ASCII code of the character to draw
// Returns: none
// Clobbers: none
// ----------------------------------------------------------------------
        ENTRY(_outch)
        // Function prologue, create invocation frame, save x0, x1, x2
        stp     x29, x30, [sp, #-16]!
        stp     x0,  xzr, [sp, #-16]!
        mov     x29, sp

        cmp     x0, #0x0a
        b.eq    _outch_nl
        cmp     x0, #0x0d
        b.eq    _outch_nl
        cmp     x0, #0x08
        b.eq    _outch_bs
        cmp     x0, #0x7f
        b.eq    _outch_bs

        // not special, just draw it
        bl      _con_out
        bl      _vid_out
        b       1f

_outch_nl:
        // newline
        mov     x0, #'\r'
        bl      _con_out
        mov     x0, #'\n'
        bl      _con_out
        bl      newline_cursor
        b       1f

_outch_bs:
        // backspace
        mov     x0, #'\b'
        bl      _con_out
        mov     x0, #' '
        bl      _con_out
        mov     x0, #'\b'
        bl      _con_out
        mov     x0, #-1
        bl      advance_cursor
        bl      erase_char

1:      // Function epilogue, restore saved registers and stack
        ldp     x0,  xzr, [sp], #16
        ldp     x29, x30, [sp], #16
        ret
        END(_outch)


// ----------------------------------------------------------------------
// Data
// ----------------------------------------------------------------------
        .data

_init_done:
        .quad 0

