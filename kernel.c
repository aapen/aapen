#include "io.h"

void main() {
  pl011_uart_init();
  pl011_uart_writeText("Hello, world!\n");

  while (1)
    ;
}
