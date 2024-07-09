// Serial UART interface from low-level assembly

#include <asm/macro.h>

// ----------------------------------------------------------------------
// Constants
// ----------------------------------------------------------------------
        .set PERIPH_BASE, 0x3f000000

        .set PL011_BASE , PERIPH_BASE + 0x201000
        .set DR         , PL011_BASE
        .set RSRECR     , PL011_BASE + 0x04
        .set FR         , PL011_BASE + 0x18
        .set IBRD       , PL011_BASE + 0x24
        .set FBRD       , PL011_BASE + 0x28
        .set LCRH       , PL011_BASE + 0x2c
        .set CR         , PL011_BASE + 0x30
        .set IMSC       , PL011_BASE + 0x38
        .set ICR        , PL011_BASE + 0x44

        .set GPIO_BASE  , PERIPH_BASE + 0x200000
        .set GPFSEL1    , GPIO_BASE + 0x04
        .set GPPUD      , GPIO_BASE + 0x94
        .set GPPUDCLK0  , GPIO_BASE + 0x98

// ----------------------------------------------------------------------
// Macros
// ----------------------------------------------------------------------

// ----------------------------------------------------------------------
// Functions
// ----------------------------------------------------------------------

// ----------------------------------------------------------------------
// fn _uart_init()
//
// Arguments: none
// Returns: none
// Clobbers: x0, x1, x2
// ----------------------------------------------------------------------

        ENTRY(_uart_init)
        stp     x29, x30, [sp, -16]!
        mov     x29, sp

        // set GPIO 14 & 15 to output
        LDR_IMM64 x1, GPFSEL1   // Address of GPFSEL1 register
        movz    w0, #0x9000     // FSEL output for pins 14 & 15
        str     w0, [x1]        // write the register

        // enable GPIO 14 & 15
        LDR_IMM64 x1, GPPUD     // Address of GPPUD register
        str     wzr, [x1]       // zero it
        movz    x0, #150        // we need to spin 150 cycles
1:      subs    x0, x0, #1
        bne     1b

        LDR_IMM64 x2, GPPUDCLK0 // Address of GPPUDCLK0 register
        movz    w0, #0xc000      // (1 << 14) | (1 << 15)
        str     w0, [x2]        // clock in the 'enable' for pins 14 & 15
        movz    x0, #150        // we need to spin another 150 cycles
2:      subs    x0, x0, #1
        bne     2b

        str     wzr, [x1]       // deassert the PU/PD enable
        str     wzr, [x2]       // deassert the CLK

        // turn off uart while initializing
        LDR_IMM64 x1, CR        // Address of CR
        str     wzr, [x1]       // zero it

        // flush the xmit fifo
        LDR_IMM64 x2, LCRH      // Address of LCHR (in x2 so we can use it later)
        str     wzr, [x2]       // zero it (disables fifos)

        // clear all pending interrupts
        LDR_IMM64 x1, ICR       // Address of ICR
        str     wzr, [x1]       // zero it

        // set the baud rate, 8N1 and FIFO disabled.
        // use clock divisor 26.0417 to get 115,200 baud
        LDR_IMM64 x1, IBRD      // Address of IBRD
        movz    w0, #0x1a       // integer part of 26.0417 - the clock divisor
        str     w0, [x1]        // set integer part
        LDR_IMM64 x1, FBRD      // Address of FBRD
        movz    w0, #0x1b       // fractional part of clock divisor
        str     w0, [x1]        // set fractional part
        movz    w0, #0xc0       // 8 bits word, no stop bits, even parity
        str     w0, [x2]        // set LCRH

        // disable interrupts
        LDR_IMM64 x1, IMSC      // Address of IMSC register
        str     wzr, [x1]       // zero it

        // enable the uart
        LDR_IMM64 x1, CR        // Address of control register
        movz    w0, #0x301      // xmit enable, recv enable, uart enable
        str     w0, [x1]        // enable the uart

        ldp     x29, x30, [sp], 16
        ret
        END(_uart_init)

// ----------------------------------------------------------------------
// fn _forth_getch()
//
// Arguments: none
// Returns: x0 - data byte
// Clobbers: x1
// ----------------------------------------------------------------------

        // TODO: check for serial line errors

        ENTRY(_forth_getch)

        // wait for data available
        LDR_IMM64 x1, FR
1:      ldr     w0, [x1]        // get flags
        ands    w0, w0, #0x10   // check receive_fifo_empty bit
        bne     1b              // empty bit -> no data is available, loop

        // data is available
        LDR_IMM64 x1, DR
        ldr     w0, [x1]        // get data
        and     w0, w0, #0xff   // keep lower byte

        // return it
        ret
        END(_forth_getch)


// ----------------------------------------------------------------------
// fn _forth_putch()
//
// Arguments: x0 - byte
// Returns: nothing
// Clobbers: x1, x2
// ----------------------------------------------------------------------

        ENTRY(_forth_putch)
        // wait for space available
        LDR_IMM64 x1, FR
1:      ldr     w2, [x1]        // get flags
        ands    w2, w2, #0x20   // check transmit_fifo_full bit
        bne     1b              // full bit -> no space to send, loop

        // space is available
        LDR_IMM64 x1, DR
        str     w0, [x1]        // write the data byte
        ret
        END(_forth_putch)
