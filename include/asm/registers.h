#if defined(BOARD)
#if BOARD == pi3
#include <asm/aarch64/rpi3_registers.h>
#elif BOARD == pi4
#include <asm/aarch64/rpi4_registers.h>
#endif
#endif
