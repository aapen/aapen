#include "io.h"


// GPIO

enum {
  //  PERIPHERAL_BASE = 0xFE000000,   // RPi 4
  PERIPHERAL_BASE = 0x3F000000, // RPi 3
  GPFSEL0 = PERIPHERAL_BASE + 0x200000,
  GPSET0 = PERIPHERAL_BASE + 0x20001C,
  GPCLR0 = PERIPHERAL_BASE + 0x200028,
  GPPUPPDN0 = PERIPHERAL_BASE + 0x2000E4
};

enum {
  GPIO_MAX_PIN = 53,
  GPIO_FUNCTION_ALT5 = 2,
};

enum {
  Pull_None = 0,
};

void mmio_write(long reg, unsigned int val) {
  *(volatile unsigned int *)reg = val;
}

unsigned int mmio_read(long reg) {
  return *(volatile unsigned int *)reg;
}

unsigned int gpio_call(unsigned int pin_number, unsigned int value,
                       unsigned int base, unsigned int field_size,
                       unsigned int field_max) {
  unsigned int field_mask = (1 << field_size) - 1;

  if (pin_number > field_max)
    return 0;

  if (value > field_mask)
    return 0;

  unsigned int num_fields = 32 / field_size;
  unsigned int reg = base + ((pin_number / num_fields) * 4);
  unsigned int shift = (pin_number % num_fields) * field_size;

  unsigned int curval = mmio_read(reg);
  curval &= ~(field_mask << shift);
  curval |= value << shift;
  mmio_write(reg, curval);

  return 1;
}

unsigned int gpio_set(unsigned int pin_number, unsigned int value) {
  return gpio_call(pin_number, value, GPSET0, 1, GPIO_MAX_PIN);
}
unsigned int gpio_clear(unsigned int pin_number, unsigned int value) {
  return gpio_call(pin_number, value, GPCLR0, 1, GPIO_MAX_PIN);
}
unsigned int gpio_pull(unsigned int pin_number, unsigned int value) {
  return gpio_call(pin_number, value, GPPUPPDN0, 2, GPIO_MAX_PIN);
}
unsigned int gpio_function(unsigned int pin_number, unsigned int value) {
  return gpio_call(pin_number, value, GPFSEL0, 3, GPIO_MAX_PIN);
}

void gpio_useAsAlt5(unsigned int pin_number) {
  gpio_pull(pin_number, Pull_None);
  gpio_function(pin_number, GPIO_FUNCTION_ALT5);
}

// Mini-UART

enum {
  AUX_BASE = PERIPHERAL_BASE + 0x215000,
  AUX_ENABLES = AUX_BASE + 0x04,
  AUX_MU_IO_REG = AUX_BASE + 0x40,
  AUX_MU_IER_REG = AUX_BASE + 0x44,
  AUX_MU_IIR_REG = AUX_BASE + 0x48,
  AUX_MU_LCR_REG = AUX_BASE + 0x4c,
  AUX_MU_MCR_REG = AUX_BASE + 0x50,
  AUX_MU_LSR_REG = AUX_BASE + 0x54,
  AUX_MU_CNTL_REG = AUX_BASE + 0x60,
  AUX_MU_BAUD_REG = AUX_BASE + 0x68,
  AUX_UART_CLOCK = 500000000,
  UART_MAX_QUEUE = 16 * 1024
};

#define AUX_MU_BAUD(baud) ((AUX_UART_CLOCK / (baud * 8)) - 1)

/* void uart_init() { */
/*   mmio_write(AUX_ENABLES, 1); // enable UART1 */
/*   mmio_write(AUX_MU_IER_REG, 0); */
/*   mmio_write(AUX_MU_CNTL_REG, 0); */
/*   mmio_write(AUX_MU_LCR_REG, 3); // 8 bits */
/*   mmio_write(AUX_MU_MCR_REG, 0); */
/*   mmio_write(AUX_MU_IER_REG, 0); */
/*   mmio_write(AUX_MU_IIR_REG, 0xC6); // disable interrupts */
/*   mmio_write(AUX_MU_BAUD_REG, AUX_MU_BAUD(115200)); */
/*   gpio_useAsAlt5(14); */
/*   gpio_useAsAlt5(15); */
/*   mmio_write(AUX_MU_CNTL_REG, 3); // enable RX/TX */
/* } */

/* unsigned int uart_isWriteByteReady() { */
/*   return mmio_read(AUX_MU_LSR_REG) & 0x20; */
/* } */

/* void uart_writeByteBlockingActual(unsigned char ch) { */
/*   while (!uart_isWriteByteReady()) */
/*     ; */
/*   mmio_write(AUX_MU_IO_REG, (unsigned int)ch); */
/* } */

/* void uart_writeText(char *buffer) { */
/*   while (*buffer) { */
/*     if (*buffer == '\n') */
/*       uart_writeByteBlockingActual('\r'); */
/*     uart_writeByteBlockingActual(*buffer++); */
/*   } */
/* } */

// PL011 UART
// See https://datasheetspdf.com/pdf-file/1461568/Broadcom/BCM2837/1,
// pg 175

enum {
  PL011_UART_BASE   = PERIPHERAL_BASE + 0x00201000, // RPi 3
  PL011_UART_DR     = PL011_UART_BASE,
  PL011_UART_RSRECR = PL011_UART_BASE + 0x04,
  PL011_UART_FR     = PL011_UART_BASE + 0x18,
  PL011_UART_IBRD   = PL011_UART_BASE + 0x24,
  PL011_UART_FBRD   = PL011_UART_BASE + 0x28,
  PL011_UART_LCRH   = PL011_UART_BASE + 0x2C,
  PL011_UART_CR     = PL011_UART_BASE + 0x30,
  PL011_UART_IFLS   = PL011_UART_BASE + 0x34,
  PL011_UART_IMSC   = PL011_UART_BASE + 0x38,
  PL011_UART_RIS    = PL011_UART_BASE + 0x3C,
  PL011_UART_MIS    = PL011_UART_BASE + 0x40,
  PL011_UART_ICR    = PL011_UART_BASE + 0x44,
  PL011_UART_DMACR  = PL011_UART_BASE + 0x48,
  PL011_UART_ITCR   = PL011_UART_BASE + 0x80,
  PL011_UART_ITIP   = PL011_UART_BASE + 0x84,
  PL011_UART_ITOP   = PL011_UART_BASE + 0x88,
  PL011_UART_TDR    = PL011_UART_BASE + 0x8C,
};

// Values for PL011_UART_LCRH (line control register)
enum {
  // FIFO enable is bit 4
  PL011_UART_LCRH_FIFO_DISABLED = 0b0000,
  PL011_UART_LCRH_FIFO_ENABLED = 0b1000,

  // Word len is bits 6 & 5
  PL011_UART_LCRH_WORD_LEN_5 = 0b000000,
  PL011_UART_LCRH_WORD_LEN_6 = 0b010000,
  PL011_UART_LCRH_WORD_LEN_7 = 0b100000,
  PL011_UART_LCRH_WORD_LEN_8 = 0b110000
};

// Values of PL011_UART_CR (control register)
enum {
  PL011_UART_CR_DISABLE = 0b0,
  PL011_UART_CR_ENABLE  = 0b1,

  PL011_UART_CR_TX_DISABLE = 0b000000000,
  PL011_UART_CR_TX_ENABLE  = 0b100000000,

  PL011_UART_CR_RX_DISABLE = 0b0000000000,
  PL011_UART_CR_RX_ENABLE  = 0b1000000000,
};

// Values of PL011_UART_FR (flags register)
enum {
  PL011_UART_FR_TX_BUSY       = 0b000001,
  PL011_UART_FR_RX_FIFO_EMPTY = 0b000010,
  PL011_UART_FR_TX_FIFO_FULL  = 0b000100,
  PL011_UART_FR_RX_FIFO_FULL  = 0b001000,
  PL011_UART_FR_TX_FIFO_EMPTY = 0b010000,
  PL011_UART_FR_RX_BUSY       = 0b100000,
};

// Values for PL011_UART_IFLS
enum {
  // Rx FIFO level select is bits 5:3
  PL011_UART_IFLS_RXIFLSEL_ONE_EIGHTH    = 0b000000,
  PL011_UART_IFLS_RXIFLSEL_ONE_FOURTH    = 0b001000,
  PL011_UART_IFLS_RXIFLSEL_ONE_HALF      = 0b010000,
  PL011_UART_IFLS_RXIFLSEL_THREE_FOURTHS = 0b011000,
  PL011_UART_IFLS_RXIFLSEL_SEVEN_EIGHTHS = 0b100000,
};

// Values for PL011_UART_IMSC
enum {
  PL011_UART_IMSC_RXIM_DISABLED = 0b00000,
  PL011_UART_IMSC_RXIM_ENABLED  = 0b10000,

  PL011_UART_IMSC_RTIM_DISABLED = 0b000000,
  PL011_UART_IMSC_RTIM_ENABLED  = 0b100000,

};

/// Set up baud rate and characteristics.
///
/// This results in 8N1 and 921_600 baud.
///
/// The calculation for the BRD is (we set the clock to 48 MHz in config.txt):
/// `(48_000_000 / 16) / 921_600 = 3.2552083`.
///
/// This means the integer part is `3` and goes into the `IBRD`.
/// The fractional part is `0.2552083`.
///
/// `FBRD` calculation according to the PL011 Technical Reference Manual:
/// `INTEGER((0.2552083 * 64) + 0.5) = 16`.
///
/// Therefore, the generated baud rate divider is: `3 + 16/64 = 3.25`. Which results in a
/// genrated baud rate of `48_000_000 / (16 * 3.25) = 923_077`.
///
/// Error = `((923_077 - 921_600) / 921_600) * 100 = 0.16%`.
void pl011_uart_init() {
  // Turn UART off while initializing
  mmio_write(PL011_UART_CR, 0x0);

  // Clear any pending interrupts
  mmio_write(PL011_UART_ICR, 0x0);

  // From the PL011 Technical Reference Manual:
  //
  // The LCR_H, IBRD, and FBRD registers form the single 30-bit wide LCR Register that is
  // updated on a single write strobe generated by a LCR_H write. So, to internally update the
  // contents of IBRD or FBRD, a LCR_H write must always be performed at the end.
  //
  // Set the baud rate, 8N1 and FIFO enabled.
  mmio_write(PL011_UART_IBRD, 0x03);
  mmio_write(PL011_UART_FBRD, 0x10);
  mmio_write(PL011_UART_LCRH, PL011_UART_LCRH_WORD_LEN_8 | PL011_UART_LCRH_FIFO_ENABLED);

  // Set Rx FIFO fill at 1/8
  mmio_write(PL011_UART_IFLS, PL011_UART_IFLS_RXIFLSEL_ONE_EIGHTH);

  // Enable Rx Interrupt and Rx timeout Interrupt
  mmio_write(PL011_UART_IMSC, PL011_UART_IMSC_RXIM_ENABLED | PL011_UART_IMSC_RTIM_ENABLED);

  // Turn the UART on
  mmio_write(PL011_UART_CR, PL011_UART_CR_ENABLE | PL011_UART_CR_TX_ENABLE | PL011_UART_CR_RX_ENABLE);
}

// Spin while FIFO full status is set
unsigned int pl011_uart_isWriteByteReady() {
  return !(mmio_read(PL011_UART_FR) & PL011_UART_FR_TX_FIFO_FULL);
}

void pl011_uart_writeByteBlockingActual(unsigned char ch) {
  while (!pl011_uart_isWriteByteReady())
    ;
  mmio_write(PL011_UART_DR, (unsigned int) ch);
}

void pl011_uart_writeText(char *buffer) {
  while (*buffer) {
    if (*buffer == '\n')
      pl011_uart_writeByteBlockingActual('\r');
    pl011_uart_writeByteBlockingActual(*buffer++);
  }
}
