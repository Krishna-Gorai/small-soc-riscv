# Results

All numbers below are from the reports in `fpga/reports/` produced by
`fpga/build.tcl` (Vivado 2025.1, non-project flow, default directives) for
`zcu104_top` on the xczu7ev-ffvc1156-2-e, and from the xsim runs described
in `tests/`.

## Verification

| Check | Result |
|---|---|
| riscv-tests rv32ui (41 programs; `ma_data` excluded, needs misaligned-access traps) | 41 / 41 PASS |
| `sw/hello` (`make sim`): banner, switch report, UART RX echo, LED chase | PASS |
| `sw/irq_demo` (`make sim`): `ecall` trap, 3 timer interrupts via `mtvec`/`mret`, `mcycle`/`minstret` | PASS |
| Harness sanity: SUB replaced by ADD in the ALU | `sub` fails at test 3, every other test unaffected |
| Post-implementation functional simulation of the routed netlist (`fpga/write_netlist.tcl` + `scripts/run_postimpl.py`): real 300 MHz clock through `IBUFDS`/`BUFGCE_DIV`, BRAM initialised from the bitstream image, UART decoded at 115200 baud | PASS: `Hello` received at t = 610 us (about 35 s of xsim) |

The full ISA suite takes about 2 minutes on the development laptop (one
`xelab`, 41 `xsim` runs).

## FPGA implementation (ZCU104, 100 MHz)

Timing: **all constraints met**, WNS = +5.358 ns on the 100 MHz SoC clock
(2 225 endpoints), WHS = +0.015 ns, pulse width +2.262 ns. The slowest path
leaves 5.4 ns of the 10 ns period unused, so the design would close at
roughly 200 MHz without changes; 100 MHz was chosen to keep the UART divider
and the timer numbers round.

| Instance | Module | LUTs | of which LUTRAM | FFs | RAMB36 | DSP |
|---|---|---:|---:|---:|---:|---:|
| `zcu104_top` | board wrapper (clock, reset) + SoC | 1 526 | 40 | 766 | 8 | 0 |
| `u_soc` | `soc_top` (everything below) | 1 519 | 40 | 756 | 8 | 0 |
| `u_core` | `riscv_core` incl. register file and CSRs | 1 377 | 40 | 488 | 0 | 0 |
| `u_uart` | `axilite_uart` + `uart_tx` + `uart_rx` | 72 | 0 | 87 | 0 | 0 |
| `u_timer` | `axilite_timer` | 66 | 0 | 103 | 0 | 0 |
| `u_gpio` | `axilite_gpio` | 0 | 0 | 72 | 0 | 0 |
| - | BRAM controller + interconnect (flattened into `u_soc`) | ~4 | 0 | ~6 | 8 | 0 |

The whole SoC uses 0.66 % of the xczu7ev's LUTs and 2.6 % of its block RAM.
Power (vectorless estimate): 0.630 W total, of which 0.015 W dynamic and
0.615 W device static. DRC: clean.

Flow: `synth_design` -> `opt_design` -> `place_design` -> `phys_opt_design`
-> `route_design` -> `write_bitstream`, default directives, about 25 minutes
on an 8 GB laptop (placement dominates, swap-bound).

## Instruction timing

Measured with `mcycle`/`minstret` from `irq_demo` (simulation build):
between two timer ticks 20 000 cycles apart the core retired about 3 600
instructions, i.e. roughly 5.6 cycles per instruction for that code mix
(5 for ALU/branch/jump/CSR, 7 for loads and stores, plus interrupt entry
and exit). The multicycle controller, not the memory, sets the IPC: every
bus access in this SoC completes with zero wait states.
