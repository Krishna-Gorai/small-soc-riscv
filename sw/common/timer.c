#include "soc.h"

void timer_start(uint32_t period_cycles)
{
    TIMER_CTRL    = 0;
    TIMER_COMPARE = period_cycles;
    TIMER_CTRL    = TIMER_ENABLE;
}

uint32_t timer_count(void)
{
    return TIMER_COUNT;
}

/* Busy-wait using the free-running timer. Requires timer_start() with a
 * period larger than n; handles one wrap of COUNT. */
void delay_cycles(uint32_t n)
{
    uint32_t period = TIMER_COMPARE;
    uint32_t start  = TIMER_COUNT;
    uint32_t now;
    do {
        now = TIMER_COUNT;
        if (now < start)          /* wrapped at COMPARE */
            now += period;
    } while (now - start < n);
}
