# Small_SoC C run-time start-up.
# Reset vector is 0x0, so this section is placed first by the linker script.
    .section .text.init
    .globl  _start
_start:
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop
    la      sp, _stack_top

    # trap vector (interrupts stay disabled until main() enables them)
    la      t0, _trap_vector
    csrw    mtvec, t0

    # zero .bss
    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    call    main

    # main returned: park here (a0 holds its return value for the debugger)
3:  j       3b
