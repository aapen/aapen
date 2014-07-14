/*
 * timer.c -- Raspberry Pi timer routines written in C
 *
 * Some of this code was inspired by bare-metal examples
 * from David Welch at https://github.com/dwelch67/raspberrypi
 */
#include "timer.h"

#define ARM_TIMER_CTL   0x2000B408
#define ARM_TIMER_CNT   0x2000B420

/*
 * Initialize 1Mhz timer
 */
void
timer_init()
{
    PUT_32(ARM_TIMER_CTL, 0x00F90000);  // 0xF9+1 = 250
    PUT_32(ARM_TIMER_CTL, 0x00F90200);  // 250MHz/250 = 1MHz
}

/*
 * Get 1Mhz timer tick count (microseconds)
 */
int
timer_usecs()
{
    return GET_32(ARM_TIMER_CNT);
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
