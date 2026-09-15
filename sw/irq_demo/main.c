/* irq_demo: timer interrupt + ecall on Small_SoC.
 *
 * The timer raises a machine timer interrupt every TICK cycles. The ISR
 * acknowledges it, toggles LED0 and counts ticks; main() sleeps in WFI and
 * prints every tick. An ecall is issued once to show synchronous traps.
 * With -DSIM_BUILD the period is short and the program reports PASS after a
 * few ticks so it can run as a regression test.
 */
#include "soc.h"

#ifdef SIM_BUILD
#define TICK       20000u            /* cycles */
#define TICKS_END  3
#else
#define TICK       (CPU_HZ / 2)      /* 500 ms */
#endif

static volatile uint32_t ticks;
static volatile uint32_t ecalls;

uint32_t trap_handler(uint32_t mcause, uint32_t mepc)
{
    if (mcause == (MCAUSE_IRQ | MCAUSE_TIMER)) {
        TIMER_STATUS = TIMER_PENDING;          /* acknowledge (W1C) */
        ticks++;
        GPIO_OUT ^= 1u;                        /* toggle LED0 */
        return mepc;                           /* resume interrupted instruction */
    }
    if (mcause == MCAUSE_ECALL) {
        ecalls++;
        return mepc + 4;                       /* skip the ecall itself */
    }
    uart_puts("\r\nunexpected trap mcause=");
    uart_puthex(mcause);
    uart_puts("\r\n");
    for (;;)
        ;
}

int main(void)
{
    uint32_t last = 0;

    uart_puts("\r\nirq_demo: timer interrupt every ");
    uart_putdec(TICK);
    uart_puts(" cycles\r\n");

    /* synchronous trap */
    __asm__ volatile ("ecall");
    uart_puts(ecalls == 1 ? "ecall ok\r\n" : "ecall FAILED\r\n");

    /* timer -> mie.MTIE -> mstatus.MIE */
    TIMER_STATUS  = TIMER_PENDING;
    TIMER_COMPARE = TICK - 1;
    TIMER_CTRL    = TIMER_ENABLE | TIMER_IRQ_EN;
    timer_irq_enable();
    irq_global_enable();

    for (;;) {
        __asm__ volatile ("wfi");              /* no-op on this core: just a polite spin */
        if (ticks != last) {
            last = ticks;
            uart_puts("tick ");
            uart_putdec(last);
            uart_puts("  cycle=");
            uart_putdec(csr_read(mcycle));
            uart_puts("  instret=");
            uart_putdec(csr_read(minstret));
            uart_puts("\r\n");
#ifdef SIM_BUILD
            if (last >= TICKS_END) {
                irq_global_disable();
                uart_puts("sim done\r\n");
                GPIO_OUT = SIM_PASS_CODE;
            }
#endif
        }
    }
}
