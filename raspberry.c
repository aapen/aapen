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
extern void asm_stack(u32* buf);
extern void asm_copy32(u32* dst, u32* src, int len);
extern u32 asm_himem(u32 id);
extern u32 asm_safe(u32 id);
extern void BOOT(int len);
extern u32 XBOOT(u32 dst, u32 src, u32 len);

/* Use external declarations to force full register discipline */
extern void c_start(u32 sp);
extern u32 timer_usecs();
extern u32 busy_wait(int dt);
extern int putchar(int c);
extern int getchar();
extern void hexdump(const u8* p, int n);
extern void dump256(const u8* p);
extern int rcv_xmodem(u8* buf, int size);

#define ARM_TIMER_CTL   0x2000B408
#define ARM_TIMER_CNT   0x2000B420

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
static char linebuf[256];  // line editing buffer
static int linepos = 0;  // read position
static int linelen = 0;  // write position
static const char* hex = "0123456789abcdef";  // hexadecimal map
static char* error = "";  // error message


#define usec /* 1e-6 seconds */
#define msec * 1000 usec
#define sec  * 1000 msec

/*
 * Initialize 1Mhz timer
 */
void timer_init()
{
    PUT_32(ARM_TIMER_CTL, 0x00F90000);  // 0xF9+1 = 250
    PUT_32(ARM_TIMER_CTL, 0x00F90200);  // 250MHz/250 = 1MHz
}

/*
 * Get 1Mhz timer tick count (microseconds)
 */
u32 timer_usecs()
{
    return GET_32(ARM_TIMER_CNT);
}

/*
 * Delay loop (microseconds)
 */
u32 busy_wait(int dt)
{
    int t0;
    int t1;

    t0 = timer_usecs();
    t1 = t0 + dt;
    for (;;) {
        t0 = timer_usecs();
        if ((t0 - t1) >= 0) {  // timeout
            return t0;
        }
    }
}

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

#define uart1_transmitter_idle()    (GET_32(AUX_MU_LSR_REG) & 0x20)
#define uart1_write_data(c)         PUT_32(AUX_MU_IO_REG, (c))
#define uart1_data_ready()          (GET_32(AUX_MU_LSR_REG) & 0x01)
#define uart1_read_data()           GET_32(AUX_MU_IO_REG)

/*
 * Output a single character to mini UART (blocking)
 */
void uart1_putc(int c)
{
    while (!uart1_transmitter_idle())
        ;
    uart1_write_data(c);
}

/*
 * Input a single character from mini UART (blocking)
 */
int uart1_getc()
{
    while (!uart1_data_ready())
        ;
    return uart1_read_data();
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

#define uart1_eol()                 uart1_puts("\r\n")

void uart1_rep(int c, int n)
{
    while (n-- > 0) {
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
 * Pretty-printed memory dump
 */
void hexdump(const u8* p, int n)
{
    int i;
    int c;

    while (n > 0) {
        uart1_hex32((u32)p);
        uart1_putc(' ');
        for (i = 0; i < 16; ++i) {
            if (i == 8) {
                uart1_putc(' ');
            }
            if (i < n) {
                uart1_putc(' ');
                uart1_hex8(p[i]);
            } else {
                uart1_rep(' ', 3);
            }
        }
        uart1_rep(' ', 2);
        uart1_putc('|');
        for (i = 0; i < 16; ++i) {
            if (i < n) {
                c = p[i];
                if ((c >= ' ') && (c < 0x7F)) {
                    uart1_putc(c);
                } else {
                    uart1_putc('.');
                }
            } else {
                uart1_putc(' ');
            }
        }
        uart1_putc('|');
        uart1_eol();
        p += 16;
        n -= 16;
    }
}
void dump256(const u8* p) {  // handy for asm debugging, just load r0
    hexdump(p, 256);
}

/*
 * Traditional single-character output
 */
int putchar(int c) {
    if (c == '\n') {
        uart1_eol();
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
    char* editline();

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
 * XMODEM file transfer
 */

#define SOH (0x01)  // Start of Header
#define ACK (0x06)  // Acknowledge
#define NAK (0x15)  // Negative Ack
#define EOT (0x04)  // End of Transmission
#define CAN (0x18)  // Cancel

int rcv_timeout(int timeout) {
    int t0;
    int t1;

    t0 = timer_usecs();
    t1 = t0 + timeout;
    for (;;) {
        if (uart1_data_ready()) {
            return uart1_read_data();
        }
        t0 = timer_usecs();
        if ((t0 - t1) >= 0) {  // timeout
            return -1;
        }
    }
}

#define CHAR_TIME   (250 msec)  // wait 0.25 sec per character

void rcv_flush() {
    while (rcv_timeout(CHAR_TIME) >= 0)
        ;
}

int rcv_xmodem(u8* buf, int limit) {
    int data;
    int rem;
    int len = 0;
    int chk;
    int blk = 0;
    int try = 0;
    int ok = NAK;

    limit -= 128;
    while (len <= limit) {  // make sure there is room to receive block
        if (ok == ACK) {
            try = 0;  // reset retry counter
        } else {
            rcv_flush();  // clear input
        }
        if (++try > 10) {  // retry 10 times on all errors
            error = "TIMEOUT";
            break;  // FAIL!
        }
        uart1_putc(ok);
        ok = NAK;

        /* receive start-of-header (SOH) */
        data = rcv_timeout(3 sec);  // send NAK every 3 seconds 
        if (data < 0) {
            continue;  // retry
        } else if (data == EOT) {  // end-of-transmission
            uart1_putc(ACK);
            error = "";
            return len;  // SUCCESS! return total length of data in buffer
        } else if (data != SOH) {  // start-of-header
            continue;  // reject
        }

        /* receive block number */
        data = rcv_timeout(CHAR_TIME);
        if (data < 0) {
            continue;  // reject
        }
        if (data == (blk & 0xFF)) {  // previous block #
            rcv_flush();  // ignore duplicate block
            ok = ACK;  // acknowledge block
            continue;
        }
        if (data != ((blk + 1) & 0xFF)) {  // unexpected block
            rcv_flush();  // ignore unexpected block
            error = "UNEXPECTED BLOCK #";
            break;  // FAIL!
        }

        /* receive inverse block number */
        data = rcv_timeout(CHAR_TIME);
        if (data < 0) {
            continue;  // reject
        }
        if (data != (~(blk + 1) & 0xFF)) {  // block # mismatch
            continue;  // reject
        }

        /* receive block data (128 bytes) */
        chk = 0;  // checksum
        rem = 128;  // remaining count
        do {
            data = rcv_timeout(CHAR_TIME);
            if (data < 0) {
                break;  // timeout
            }
            buf[len++] = data;  // store data in buffer
            chk += data;  // accumulate checksum
        } while (--rem > 0);
        if (rem > 0) {  // incomplete block
            len -= (128 - rem);  // ignore partial block data
            continue;  // reject
        }

        /* receive checksum */
        data = rcv_timeout(CHAR_TIME);
        if ((data < 0) || (data != (chk & 0xFF))) {  // bad checksum
            len -= 128;  // ignore bad block data
            continue;  // reject
        }

        /* acknowledge good block */
        ok = ACK;
        ++blk;  // update expected block #
    }
    uart1_putc(CAN);  // I tell you three times...
    uart1_putc(CAN);
    uart1_putc(CAN);
    return -1;  // FAIL!
}

/*
 * Wait for whitespace character from keyboard
 */
int wait_for_kb()
{
    int c;

    for (;;) {
        c = _getchar();
        if ((c == '\r') || (c == '\n') || (c == ' ')) {
            return c;
        }
    }
}

#define	KERNEL_ADDR	(0x8000)
#define	UPLOAD_ADDR	(0x10000)
#define	UPLOAD_LIMIT	(0x8000)

static const u8 src[256] = {
0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F,
0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,0x19,0x1A,0x1B,0x1C,0x1D,0x1E,0x1F,
0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x29,0x2A,0x2B,0x2C,0x2D,0x2E,0x2F,
0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B,0x3C,0x3D,0x3E,0x3F,
0x40,0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4A,0x4B,0x4C,0x4D,0x4E,0x4F,
0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A,0x5B,0x5C,0x5D,0x5E,0x5F,
0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6A,0x6B,0x6C,0x6D,0x6E,0x6F,
0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B,0x7C,0x7D,0x7E,0x7F,
0x80,0x81,0x82,0x83,0x84,0x85,0x86,0x87,0x88,0x89,0x8A,0x8B,0x8C,0x8D,0x8E,0x8F,
0x90,0x91,0x92,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9A,0x9B,0x9C,0x9D,0x9E,0x9F,
0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0xA6,0xA7,0xA8,0xA9,0xAA,0xAB,0xAC,0xAD,0xAE,0xAF,
0xB0,0xB1,0xB2,0xB3,0xB4,0xB5,0xB6,0xB7,0xB8,0xB9,0xBA,0xBB,0xBC,0xBD,0xBE,0xBF,
0xC0,0xC1,0xC2,0xC3,0xC4,0xC5,0xC6,0xC7,0xC8,0xC9,0xCA,0xCB,0xCC,0xCD,0xCE,0xCF,
0xD0,0xD1,0xD2,0xD3,0xD4,0xD5,0xD6,0xD7,0xD8,0xD9,0xDA,0xDB,0xDC,0xDD,0xDE,0xDF,
0xE0,0xE1,0xE2,0xE3,0xE4,0xE5,0xE6,0xE7,0xE8,0xE9,0xEA,0xEB,0xEC,0xED,0xEE,0xEF,
0xF0,0xF1,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,0xF8,0xF9,0xFA,0xFB,0xFC,0xFD,0xFE,0xFF,
};

static char dst[256] = 
"Don't Tread on Bees!\r\nTHE QUICK BROWN FOX JUMPED OVER THE LAZY DOG.\n\0";

/*
 * Entry point for C code
 */
void c_start(u32 sp)
{
    int c;
    int z = 0;
    int len = 0;

    timer_init();
    uart1_init();

    uart1_puts(";-) ");
    putchar(wait_for_kb());
    
    // display banner
    uart1_puts("pijFORTHos 0.1.3");
//    uart1_puts(" sp=0x");
//    uart1_hex32(sp);
    uart1_eol();
    uart1_puts("^D=exit-monitor ^Z=toggle-hexadecimal ^L=xmodem-upload");
    uart1_eol();
    
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
            c = _getchar();
            putchar(c);
        }
        if (c == 0x04) {  // ^D to exit monitor loop
            break;
        }
        if (c == 0x1A) {  // ^Z toggle hexadecimal substitution
            z = !z;
        }
        if (c == 0x0C) {  // ^L xmodem file upload
            uart1_eol();
            uart1_puts("START XMODEM...");
            len = rcv_xmodem((u8*)UPLOAD_ADDR, UPLOAD_LIMIT);
            putchar(wait_for_kb());
            if (len < 0) {
                uart1_puts("UPLOAD FAILED! ");
                uart1_puts(error);
                uart1_eol();
            } else {
                uart1_puts("0x");
                uart1_hex32(len);
                uart1_puts(" BYTES RECEIVED.");
                uart1_eol();
                uart1_puts("^W=boot-uploaded-image");
                uart1_eol();
            }
        }
        if ((c == 0x17)/* && (len > 0)*/) {  // ^W copy upload and boot
            uart1_eol();
            BOOT(len);
//            hexdump((u8*)src, sizeof(src));
            hexdump((u8*)dst, sizeof(dst)+3);
            putchar(wait_for_kb());
            asm_stack((u32*)dst);
            hexdump((u8*)dst, sizeof(dst)+2);
            putchar(wait_for_kb());
            asm_copy32((u32*)(dst + 128), (u32*)src, 128);
            hexdump((u8*)dst, sizeof(dst)+1);
            putchar(wait_for_kb());
            uart1_hex32(asm_safe(0xDEADBEEF));
//            uart1_hex32(asm_himem(0xDEADBEEF));
            putchar(wait_for_kb());
            hexdump((u8*)(UPLOAD_ADDR - 128), 256);
//            XBOOT(KERNEL_ADDR, UPLOAD_ADDR, len);
/*
            XBOOT((u32)dst, (u32)src, (u32)sizeof(dst));
            uart1_eol();
            hexdump((u8*)src, sizeof(src));
            uart1_eol();
            hexdump((u8*)dst, sizeof(dst));
*/
        }
    }
    uart1_eol();
    uart1_puts("OK ");
}
