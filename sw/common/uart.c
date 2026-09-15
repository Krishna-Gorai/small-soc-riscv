#include "soc.h"

void uart_putc(char c)
{
    while (UART_STATUS & UART_TX_BUSY)
        ;
    UART_TX = (uint32_t)(uint8_t)c;
}

void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

void uart_puthex(uint32_t v)
{
    static const char hex[] = "0123456789abcdef";
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4)
        uart_putc(hex[(v >> i) & 0xF]);
}

void uart_putdec(uint32_t v)
{
    char buf[11];
    int  i = 10;
    buf[i] = '\0';
    do {
        buf[--i] = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    uart_puts(&buf[i]);
}

int uart_rx_ready(void)
{
    return (UART_STATUS & UART_RX_VALID) != 0;
}

char uart_getc(void)
{
    while (!uart_rx_ready())
        ;
    return (char)UART_RX;      /* read clears rx_valid */
}
