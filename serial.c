/*
 * serial.c -- Raspberry Pi serial i/o (UART) routines written in C
 *
 * Some of this code was inspired by bare-metal examples
 * from David Welch at https://github.com/dwelch67/raspberrypi
 */
#include "serial.h"

#define USE_SERIAL_UART0    /* select full UART for serial i/o */
//#define USE_SERIAL_UART1    /* select mini UART for serial i/o */

#define GPIO            ((volatile u32*)0x20200000)
#define GPFSEL1         0x04
#define GPSET0          0x1c
#define GPCLR0          0x28
#define GPPUD           0x94
#define GPPUDCLK0       0x98

#define UART0           ((volatile u32*)0x20201000)
#define FU_DR           0x00
#define FU_RSRECR       0x04
#define FU_FR           0x18
#define FU_ILPR         0x20
#define FU_IBRD         0x24
#define FU_FBRD         0x28
#define FU_LCRH         0x2c
#define FU_CR           0x30
#define FU_IFLS         0x34
#define FU_IMSC         0x38
#define FU_RIS          0x3c
#define FU_MIS          0x40
#define FU_ICR          0x44
#define FU_DMACR        0x48

#define UART1           ((volatile u32*)0x20215000)
#define AUX_ENABLES     0x04
#define MU_IO           0x40
#define MU_IER          0x44
#define MU_IIR          0x48
#define MU_LCR          0x4c
#define MU_MCR          0x50
#define MU_LSR          0x54
#define MU_MSR          0x58
#define MU_CNTL         0x60
#define MU_STAT         0x64
#define MU_BAUD         0x68

/*
 * Initialize serial UART to use GPIO pins 14 (TX) and 15 (RX)
 */
void
serial_init()
{
#ifdef USE_SERIAL_UART0
    u32 r0;

    UART0[FU_CR] = 0;

    r0 = GPIO[GPFSEL1];
    r0 &= ~(7 << 12);           // gpio pin 14
    r0 |= 4 << 12;              //   alt0 = full UART transmit (TX)
    r0 &= ~(7 << 15);           // gpio pin 15
    r0 |= 4 << 15;              //   alt0 = full UART receive (RX)
    GPIO[GPFSEL1] = r0;

    GPIO[GPPUD] = 0;
    SPIN(150);                  // wait for (at least) 150 clock cycles
    r0 = (1 << 14) | (1 << 15);
    GPIO[GPPUDCLK0] = r0;
    SPIN(150);                  // wait for (at least) 150 clock cycles
    GPIO[GPPUDCLK0] = 0;

    UART0[FU_ICR] = 0x7FF;
    UART0[FU_IBRD] = 1;
    UART0[FU_FBRD] = 40;
    UART0[FU_LCRH] = 0x70;
    UART0[FU_CR] = 0x301;
#endif /* USE_SERIAL_UART0 */
#ifdef USE_SERIAL_UART1
    u32 r0;

    UART1[AUX_ENABLES] = 1;
    UART1[MU_IER] = 0;
    UART1[MU_CNTL] = 0;
    UART1[MU_LCR] = 3;
    UART1[MU_MCR] = 0;
    UART1[MU_IER] = 0;
    UART1[MU_IIR] = 0xc6;
    /* ((250,000,000 / 115200) / 8) - 1 = 270 */
    UART1[MU_BAUD] = 270;

    r0 = GPIO[GPFSEL1];
    r0 &= ~(7 << 12);           // gpio pin 14
    r0 |= 2 << 12;              //   alt5 = mini UART transmit (TX)
    r0 &= ~(7 << 15);           // gpio pin 15
    r0 |= 2 << 15;              //   alt5 = mini UART receive (RX)
    GPIO[GPFSEL1] = r0;

    GPIO[GPPUD] = 0;
    SPIN(150);                  // wait for (at least) 150 clock cycles
    r0 = (1 << 14) | (1 << 15);
    GPIO[GPPUDCLK0] = r0;
    SPIN(150);                  // wait for (at least) 150 clock cycles
    GPIO[GPPUDCLK0] = 0;

    UART1[MU_CNTL] = 3;
#endif /* USE_SERIAL_UART1 */
}

/*
 * Serial input ready != 0, wait == 0
 */
int
serial_in_ready()
{
#ifdef USE_SERIAL_UART0
    return (UART0[FU_FR] & 0x10) == 0;
#endif /* USE_SERIAL_UART0 */
#ifdef USE_SERIAL_UART1
    return (UART1[MU_LSR] & 0x01) != 0;
#endif /* USE_SERIAL_UART1 */
}

/*
 * Raw input from serial port
 */
int
serial_in()
{
#ifdef USE_SERIAL_UART0
    return UART0[FU_DR] & 0xff;
#endif /* USE_SERIAL_UART0 */
#ifdef USE_SERIAL_UART1
    return UART1[MU_IO] & 0xff;
#endif /* USE_SERIAL_UART1 */
}

/*
 * Serial output ready != 0, wait == 0
 */
int
serial_out_ready()
{
#ifdef USE_SERIAL_UART0
    return (UART0[FU_FR] & 0x20) == 0;
#endif /* USE_SERIAL_UART0 */
#ifdef USE_SERIAL_UART1
    return (UART1[MU_LSR] & 0x20) != 0;
#endif /* USE_SERIAL_UART1 */
}

/*
 * Raw output to serial port
 */
int
serial_out(u8 data)
{
#ifdef USE_SERIAL_UART0
    UART0[FU_DR] = (u32)data;
    return (int)data;
#endif /* USE_SERIAL_UART0 */
#ifdef USE_SERIAL_UART1
    UART1[MU_IO] = (u32)data);
    return (int)data;
#endif /* USE_SERIAL_UART1 */
}

/*
 * Blocking read from serial port
 */
int
serial_read()
{
    while (!serial_in_ready())
        ;
    return serial_in();
}

/*
 * Blocking write to serial port
 */
int
serial_write(u8 data)
{
    while (!serial_out_ready())
        ;
    return serial_out(data);
}

/*
 * Print a C-string, character-by-character
 */
void
serial_puts(char* s)
{
    int c;

    while ((c = *s++) != '\0') {
        serial_write((u8)c);
    }
}

/*
 * Print n repetitions of character c
 */
void
serial_rep(int c, int n)
{
    while (n-- > 0) {
        serial_write((u8)c);
    }
}
