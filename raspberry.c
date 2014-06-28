/*
 * raspberry.c -- Raspberry Pi support routines written in C
 *
 * Some of this code was inspired by bare-metal examples
 * from David Welch at https://github.com/dwelch67/raspberrypi
 */

typedef unsigned char u8;
typedef unsigned int u32;

/* Declare ARM assembly-language helper functions */
extern void PUT_32(u32 addr, u32 data);
extern u32 GET_32(u32 addr);
extern void NO_OP();

/* Use external declarations to force full register discipline */
extern void c_start(u32 sp);
extern int putchar(int c);
extern int getchar();

#define GPFSEL1         0x20200004
#define GPSET0          0x2020001c
#define GPCLR0          0x20200028
#define GPPUD           0x20200094
#define GPPUDCLK0       0x20200098

#define AUX_ENABLES     0x20215004
#define AUX_MU_IO_REG   0x20215040
#define AUX_MU_IER_REG  0x20215044
#define AUX_MU_IIR_REG  0x20215048
#define AUX_MU_LCR_REG  0x2021504c
#define AUX_MU_MCR_REG  0x20215050
#define AUX_MU_LSR_REG  0x20215054
#define AUX_MU_MSR_REG  0x20215058
#define AUX_MU_SCRATCH  0x2021505c
#define AUX_MU_CNTL_REG 0x20215060
#define AUX_MU_STAT_REG 0x20215064
#define AUX_MU_BAUD_REG 0x20215068

/* Private data structures */
int linepos = 0;  // read position
int linelen = 0;  // write position
static char linebuf[1024];  // line editing buffer
static char* hex = "0123456789abcdef";  // hexadecimal map
    

/*
 * Initialize mini UART to use GPIO pins 14 and 15
 */
void uart1_init()
{
    u32 r0;
    int n;

    PUT_32(AUX_ENABLES, 1);
    PUT_32(AUX_MU_IER_REG, 0);
    PUT_32(AUX_MU_CNTL_REG, 0);
    PUT_32(AUX_MU_LCR_REG, 3);
    PUT_32(AUX_MU_MCR_REG, 0);
    PUT_32(AUX_MU_IER_REG, 0);
    PUT_32(AUX_MU_IIR_REG, 0xc6);
    PUT_32(AUX_MU_BAUD_REG, 270);  // ((250,000,000/115200)/8)-1 = 270

    // GPIO14: TXD0 and TXD1
    // GPIO15: RXD0 and RXD1
    // alt function 5 for uart1 (mini UART)
    // alt function 0 for uart0 (full UART)

    r0 = GET_32(GPFSEL1);
    r0 &= ~(7 << 12); // gpio14
    r0 |= 2 << 12;    //   alt5
    r0 &= ~(7 << 15); // gpio15
    r0 |= 2 << 15;    //   alt5
    PUT_32(GPFSEL1, r0);

    PUT_32(GPPUD, 0);
    n = 150;
    while (n-- > 0) {  // wait for (at least) 150 clock cycles
        NO_OP();
    }

    r0 = (1 << 14) | (1 << 15);
    PUT_32(GPPUDCLK0, r0);
    n = 150;
    while (n-- > 0) {  // wait for (at least) 150 clock cycles
        NO_OP();
    }

    PUT_32(GPPUDCLK0, 0);

    PUT_32(AUX_MU_CNTL_REG, 3);
}

/*
 * Output a single character to mini UART
 */
void uart1_putc(int c)
{
    while ((GET_32(AUX_MU_LSR_REG) & 0x20) == 0)
        ;
    PUT_32(AUX_MU_IO_REG, c);
}

/*
 * Input a single character from mini UART
 */
int uart1_getc()
{
    while ((GET_32(AUX_MU_LSR_REG) & 0x01) == 0)
        ;
    return GET_32(AUX_MU_IO_REG);
}

/*
 * Output a C-string, character-by-character, to mini UART
 */
void uart1_puts(char* s)
{
    int c;

    while ((c = *s++) != '\0') {
        uart1_putc(c);
    }
}

/*
 * Output u32 in hexadecimal to mini UART
 */
void uart1_hex32(u32 w) {
    uart1_putc(hex[0xF & (w >> 28)]);
    uart1_putc(hex[0xF & (w >> 24)]);
    uart1_putc(hex[0xF & (w >> 20)]);
    uart1_putc(hex[0xF & (w >> 16)]);
    uart1_putc(hex[0xF & (w >> 12)]);
    uart1_putc(hex[0xF & (w >> 8)]);
    uart1_putc(hex[0xF & (w >> 4)]);
    uart1_putc(hex[0xF & w]);
}

/*
 * Output u8 in hexadecimal to mini UART
 */
void uart1_hex8(u8 b) {
    uart1_putc(hex[0xF & (b >> 4)]);
    uart1_putc(hex[0xF & b]);
}

/*
 * Traditional single-character output
 */
int putchar(int c) {
    if (c == '\n') {
        uart1_puts("\r\n");
    } else {
        uart1_putc(c);
    }
    return c;
}

/*
 * Traditional single-character input
 */
static int _getchar() {  // unbuffered
    int c;

    c = uart1_getc();
    if (c == '\r') {
        c = '\n';
    }
    return c;
}
int getchar() {  // buffered
    while (linepos >= linelen) {
        editline();
    }
    return linebuf[linepos++];
}

/*
 * Get single line of edited input
 */
char* editline() {
    int c;

    linelen = 0;  // reset write position
    while (linelen < (sizeof(linebuf) - 1)) {
        c = _getchar();
        if (c == '\b') {
            if (--linelen < 0) {
                linelen = 0;
                continue;  // no echo
            }
        } else {
            linebuf[linelen++] = c;
        }
        putchar(c);  // echo input
        if (c == '\n') {
            break;  // end-of-line
        }
    }
    linebuf[linelen] = '\0';  // ensure NUL termination
    linepos = 0;  // reset read position
    return linebuf;
}

/*
 * Entry point for C code
 */
void c_start(u32 sp)
{
    u32 buf[16];  // stack space preceeds kernel entry-point
    int c;
    int z = 0;

    uart1_init();

    // wait for first whitespace character
    for (;;) {
        c = uart1_getc();
        if ((c == '\r') || (c == '\n') || (c == ' ')) {
            break;
        }
    }
    
    // display banner
    uart1_puts("\r\n");
    uart1_puts("pijFORTHos 0.1.2");
//    uart1_puts(" sp=");
//    uart1_hex32(sp);
    uart1_puts(" buf=");
    uart1_hex32((u32)buf);
    uart1_puts("\r\n");
    
    // echo console input to output
    for (;;) {
        if (z) {  // "raw" mode
            c = uart1_getc();
            uart1_hex8(c);  // display as hexadecimal value
            uart1_putc('=');
            if ((c > 0x20) && (c < 0x7F)) {  // echo printables
                uart1_putc(c);
            } else {
                uart1_putc(' ');
            }
            uart1_putc(' ');
        } else {  // "cooked" mode
            c = getchar();  // buffered input also echos
//            putchar(c);
        }
        if (c == 0x04) {  // ^D to exit loop
            break;
        }
        if (c == 0x1A) {  // ^Z toggle hexadecimal substitution
            z = !z;
        }
    }
    uart1_puts("\r\nOK ");
}
