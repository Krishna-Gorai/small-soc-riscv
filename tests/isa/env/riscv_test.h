// Target environment for riscv-tests on the Small_SoC RV32I core.
//
// The stock "p" environment relies on CSRs and trap handling that this core
// does not implement, so the test result is reported through the GPIO output
// register instead of the `tohost` mechanism:
//     PASS : GPIO_OUT <= 0x0000600D
//     FAIL : GPIO_OUT <= 0xBAD00000 | TESTNUM
// The simulation testbench (tests/tb/tb_isa.v) watches for those values.
#ifndef _ENV_SMALLSOC_TEST_H
#define _ENV_SMALLSOC_TEST_H

#define GPIO_BASE 0x10000000

#define RVTEST_RV32U
#define RVTEST_RV64U
#define TESTNUM gp

#define RVTEST_CODE_BEGIN            \
        .section .text.init;         \
        .align  2;                   \
        .globl  _start;              \
_start:

#define RVTEST_CODE_END

#define RVTEST_PASS                  \
        li   a0, GPIO_BASE;          \
        li   a1, 0x600D;             \
        sw   a1, 0(a0);              \
1:      j    1b;

#define RVTEST_FAIL                  \
        li   a0, GPIO_BASE;          \
        lui  a1, 0xBAD00;            \
        or   a1, a1, TESTNUM;        \
        sw   a1, 0(a0);              \
1:      j    1b;

#define RVTEST_DATA_BEGIN  .align 4;
#define RVTEST_DATA_END

#endif
