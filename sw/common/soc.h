/* Small_SoC memory map and peripheral registers.
 *
 *   0x0000_0000  BRAM   32 KB, code + data + stack
 *   0x1000_0000  GPIO   +0 OUT (LEDs)   +4 IN (switches)
 *   0x2000_0000  UART   +0 TX/DATA      +4 RX          +8 STATUS {bit1 rx_valid, bit0 tx_busy}
 *   0x3000_0000  TIMER  +0 COUNT        +4 COMPARE     +8 CTRL   {bit1 irq_en, bit0 enable}
 *                       +C STATUS {bit0 pending, W1C}
 */
#ifndef SOC_H
#define SOC_H
#include <stdint.h>

#define REG32(a)        (*(volatile uint32_t *)(a))

#define GPIO_BASE       0x10000000u
#define GPIO_OUT        REG32(GPIO_BASE + 0x0)
#define GPIO_IN         REG32(GPIO_BASE + 0x4)

#define UART_BASE       0x20000000u
#define UART_TX         REG32(UART_BASE + 0x0)
#define UART_RX         REG32(UART_BASE + 0x4)
#define UART_STATUS     REG32(UART_BASE + 0x8)
#define UART_TX_BUSY    (1u << 0)
#define UART_RX_VALID   (1u << 1)

#define TIMER_BASE      0x30000000u
#define TIMER_COUNT     REG32(TIMER_BASE + 0x0)
#define TIMER_COMPARE   REG32(TIMER_BASE + 0x4)
#define TIMER_CTRL      REG32(TIMER_BASE + 0x8)
#define TIMER_STATUS    REG32(TIMER_BASE + 0xC)
#define TIMER_ENABLE    (1u << 0)
#define TIMER_IRQ_EN    (1u << 1)
#define TIMER_PENDING   (1u << 0)

/* ---- CSR access ---- */
#define csr_read(csr)        ({ uint32_t v; __asm__ volatile ("csrr %0, " #csr : "=r"(v)); v; })
#define csr_write(csr, val)  __asm__ volatile ("csrw " #csr ", %0" :: "r"((uint32_t)(val)))
#define csr_set(csr, mask)   __asm__ volatile ("csrs " #csr ", %0" :: "r"((uint32_t)(mask)))
#define csr_clear(csr, mask) __asm__ volatile ("csrc " #csr ", %0" :: "r"((uint32_t)(mask)))

#define MSTATUS_MIE     (1u << 3)
#define MIE_MTIE        (1u << 7)
#define MCAUSE_IRQ      (1u << 31)
#define MCAUSE_TIMER    7u
#define MCAUSE_ECALL    11u
#define MCAUSE_EBREAK   3u

static inline void irq_global_enable(void)  { csr_set(mstatus, MSTATUS_MIE); }
static inline void irq_global_disable(void) { csr_clear(mstatus, MSTATUS_MIE); }
static inline void timer_irq_enable(void)   { csr_set(mie, MIE_MTIE); }

/* Called from the trap vector (trap.S). Returns the address to resume at.
 * Weak default: acknowledges nothing and spins; programs override it. */
uint32_t trap_handler(uint32_t mcause, uint32_t mepc);

#ifndef CPU_HZ
#define CPU_HZ          100000000u
#endif

/* Result code convention used by the simulation testbench (tests/tb/tb_isa.v). */
#define SIM_PASS_CODE   0x0000600Du
#define SIM_FAIL_CODE   0xBAD00000u

/* uart.c */
void     uart_putc(char c);
void     uart_puts(const char *s);
void     uart_puthex(uint32_t v);
void     uart_putdec(uint32_t v);
int      uart_rx_ready(void);
char     uart_getc(void);

/* timer.c */
void     timer_start(uint32_t period_cycles);   /* free-running, wraps at COMPARE */
uint32_t timer_count(void);
void     delay_cycles(uint32_t n);

#endif
