#include "soc.h"

/* Default trap handler: report and halt. Programs that use interrupts or
 * ecall define their own trap_handler(), which overrides this weak one. */
__attribute__((weak))
uint32_t trap_handler(uint32_t mcause, uint32_t mepc)
{
    uart_puts("\r\nunhandled trap: mcause=");
    uart_puthex(mcause);
    uart_puts(" mepc=");
    uart_puthex(mepc);
    uart_puts("\r\n");
    for (;;)
        ;
}
