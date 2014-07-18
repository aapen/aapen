/*
 * timer.c -- Raspberry Pi timer routines written in C
 *
 * Some of this code was inspired by bare-metal examples
 * from David Welch at https://github.com/dwelch67/raspberrypi
 */
#include "timer.h"

#define TIMER           ((volatile u32*)0x2000b400)
#define T_CONTROL       0x08
#define T_COUNTER       0x20

/*
 * Initialize 1Mhz timer
 */
void
timer_init()
{
    TIMER[T_CONTROL] = 0x00F90000;    // 0xF9+1 = 250
    TIMER[T_CONTROL] = 0x00F90200;    // 250MHz/250 = 1MHz
}

/*
 * Get 1Mhz timer tick count (microseconds)
 */
int
timer_usecs()
{
    return TIMER[T_COUNTER];
}

/*
 * Delay loop (microseconds)
 */
int
timer_wait(int dt)
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
