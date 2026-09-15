/* hello: bring-up program for Small_SoC.
 *
 * - prints a banner and the memory map on the UART (115200 8N1)
 * - walks a pattern across the LEDs, paced by the hardware timer
 * - reports the switch value whenever it changes
 * - echoes any character received on the UART
 *
 * Built with -DSIM_BUILD (make sim) the LED period is shortened and the
 * program signals PASS to the testbench after a few iterations.
 */
#include "soc.h"

#ifdef SIM_BUILD
#define LED_PERIOD   2000u             /* cycles between LED steps */
#define SIM_STEPS    16                /* stop after this many steps */
#else
#define LED_PERIOD   (CPU_HZ / 4)      /* 250 ms */
#endif

int main(void)
{
    uint32_t sw_last = ~GPIO_IN;
    uint32_t pattern = 1;
    uint32_t steps   = 0;
    uint32_t t_last  = 0;

    timer_start(LED_PERIOD);

    uart_puts("\r\nHello from Small_SoC (RV32I @ ");
    uart_putdec(CPU_HZ / 1000000u);
    uart_puts(" MHz)\r\n");
    uart_puts("  BRAM  0x00000000  32 KB\r\n");
    uart_puts("  GPIO  0x10000000  LEDs / switches\r\n");
    uart_puts("  UART  0x20000000  115200 8N1\r\n");
    uart_puts("  TIMER 0x30000000\r\n");
    uart_puts("Type characters to echo them.\r\n");

    for (;;) {
        /* LED chase: advance one step each time the timer wraps */
        uint32_t t = timer_count();
        if (t < t_last) {
            GPIO_OUT = pattern;
            pattern  = ((pattern << 1) | (pattern >> 3)) & 0xFu;   /* rotate over 4 LEDs */
            steps++;
        }
        t_last = t;

        /* switches */
        uint32_t sw = GPIO_IN;
        if (sw != sw_last) {
            sw_last = sw;
            uart_puts("switches = ");
            uart_puthex(sw);
            uart_puts("\r\n");
        }

        /* UART echo */
        if (uart_rx_ready()) {
            char c = uart_getc();
            uart_putc(c);
            if (c == '\r')
                uart_putc('\n');
        }

#ifdef SIM_BUILD
        if (steps >= SIM_STEPS) {
            uart_puts("sim done\r\n");
            GPIO_OUT = SIM_PASS_CODE;
        }
#endif
    }
}
