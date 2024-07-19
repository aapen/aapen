// -*- asm -*-

// ----------------------------------------------------------------------
// Hardware Constants
// ----------------------------------------------------------------------

        .set PERIPH_BASE , 0x3f000000

// ----------------------------------------------------------------------
// PL011 UART
// ----------------------------------------------------------------------

        .set UART_BASE   , PERIPH_BASE + 0x201000
        .set UART_DR     , UART_BASE
        .set UART_RSRECR , UART_BASE + 0x04
        .set UART_FR     , UART_BASE + 0x18
        .set UART_IBRD   , UART_BASE + 0x24
        .set UART_FBRD   , UART_BASE + 0x28
        .set UART_LCRH   , UART_BASE + 0x2c
        .set UART_CR     , UART_BASE + 0x30
        .set UART_IMSC   , UART_BASE + 0x38
        .set UART_ICR    , UART_BASE + 0x44

// ----------------------------------------------------------------------
// GPIO
// ----------------------------------------------------------------------
        .set GPIO_BASE   , PERIPH_BASE + 0x200000
        .set GPFSEL1     , GPIO_BASE + 0x04
        .set GPPUD       , GPIO_BASE + 0x94
        .set GPPUDCLK0   , GPIO_BASE + 0x98

// ----------------------------------------------------------------------
// Mailbox
// ----------------------------------------------------------------------
        .set MAIL_BASE   , PERIPH_BASE + 0xB880
        .set MBOX0_READ  , MAIL_BASE + 0x00
        .set MBOX0_PEEK  , MAIL_BASE + 0x10
        .set MBOX0_STATUS, MAIL_BASE + 0x18
        .set MBOX0_WRITE , MAIL_BASE + 0x20
