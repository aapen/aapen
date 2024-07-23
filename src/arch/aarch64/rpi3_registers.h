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
        .set GPIO_BASE       , PERIPH_BASE + 0x200000
        .set GPFSEL1         , GPIO_BASE + 0x04
        .set GPPUD           , GPIO_BASE + 0x94
        .set GPPUDCLK0       , GPIO_BASE + 0x98

// ----------------------------------------------------------------------
// Mailbox
// ----------------------------------------------------------------------
        .set MAIL_BASE       , PERIPH_BASE + 0xB880
        .set MBOX0_READ      , MAIL_BASE + 0x00
        .set MBOX0_PEEK      , MAIL_BASE + 0x10
        .set MBOX0_STATUS    , MAIL_BASE + 0x18
        .set MBOX0_WRITE     , MAIL_BASE + 0x20

// ----------------------------------------------------------------------
// eMMC / SD card
// ----------------------------------------------------------------------
        .set EMMC_BASE       , PERIPH_BASE + 0x300000

        .set EMMC_BLKSIZECNT , EMMC_BASE + 0x04 // block_size_count
        .set EMMC_ARG1       , EMMC_BASE + 0x08 // arg1
        .set EMMC_CMDTM      , EMMC_BASE + 0x0c // cmd_xfer_mode
        .set EMMC_RESP0      , EMMC_BASE + 0x10 // response[0]
        .set EMMC_RESP1      , EMMC_BASE + 0x14 // response[1]
        .set EMMC_RESP2      , EMMC_BASE + 0x18 // response[2]
        .set EMMC_RESP3      , EMMC_BASE + 0x1c // response[3]
        .set EMMC_DATA       , EMMC_BASE + 0x20 // data
        .set EMMC_STATUS     , EMMC_BASE + 0x24 // status
        .set EMMC_CONTROL0   , EMMC_BASE + 0x28 // control[0]
        .set EMMC_CONTROL1   , EMMC_BASE + 0x2c // control[1]
        .set EMMC_INTERRUPT  , EMMC_BASE + 0x30 // int_flags
        .set EMMC_IRPT_MASK  , EMMC_BASE + 0x34 // int_mask
        .set EMMC_IRPT_EN    , EMMC_BASE + 0x38 // int_enable
        .set EMMC_CONTROL2   , EMMC_BASE + 0x3c // control2
