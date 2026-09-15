# Small_SoC — a from-scratch RV32I microcontroller SoC on the ZCU104

A complete, self-contained system-on-chip written in plain Verilog-2001 with
no vendor IP: a 32-bit RISC-V core, an AXI-Lite interconnect, on-chip memory
and three peripherals, running C programs built with GCC and deployed on a
Xilinx Zynq UltraScale+ ZCU104 board.

```
                        ┌─────────────────────────┐
                        │        riscv_core       │  RV32I + Zicsr, multicycle
                        │  M-mode CSRs, traps,    │  (5–6 cycles / instruction)
                        │  timer interrupt        │
                        └───────────┬─────────────┘
                                    │ AXI4-Lite master (fetch + data)
                     ┌──────────────┴──────────────┐
                     │    axi_lite_interconnect    │  decode on addr[29:28]
                     └──┬────────┬────────┬────────┬┘
                        │        │        │        │
                  ┌─────┴──┐ ┌───┴───┐ ┌──┴───┐ ┌──┴────┐
                  │  BRAM  │ │ GPIO  │ │ UART │ │ TIMER │──irq──▶ core
                  │ 32 KB  │ │LED/SW │ │115200│ │+IRQ   │
                  └────────┘ └───────┘ └──────┘ └───────┘
                 0x0000_0000 0x1000_0000 0x2000_0000 0x3000_0000
```

## Highlights

| | |
|---|---|
| ISA | RV32I base + Zicsr; `ecall`, `ebreak`, `mret`, `fence`/`fence.i`/`wfi` accepted; machine-mode CSRs (`mstatus`, `mie`, `mip`, `mtvec`, `mepc`, `mcause`, `mscratch`, `mcycle`, `minstret`, …) |
| Verification | **41 / 41** tests of the official `riscv-tests` rv32ui suite pass bit-exactly in xsim (`ma_data` skipped: no misaligned-access traps); harness verified to catch injected bugs |
| Bus | Hand-written AXI4-Lite master (core) and four AXI4-Lite slaves, single-outstanding |
| Software | GCC 15 (xPack `riscv-none-elf`), custom linker script + `crt0`, trap vector, board-support library; `hello` and `irq_demo` programs |
| FPGA | ZCU104 (xczu7ev), 100 MHz from the 300 MHz board clock via `BUFGCE_DIV`, no MMCM / no IP; see [Results](#results) |
| Size | ~1.1 k lines of RTL; the whole SoC is 1.5 k LUTs / 8 BRAMs and closes timing at 100 MHz with 5.4 ns to spare |

## Repository layout

```
rtl/                 SoC RTL (Verilog-2001), one module per file, program.hex = BRAM image
fpga/                zcu104_top.v wrapper, zcu104.xdc, build.tcl (non-project flow → .bit)
sw/common/           link.ld, crt0.S, trap.S, soc.h (memory map + CSR helpers), uart.c, timer.c
sw/hello/            banner + LED chase + switch report + UART echo
sw/irq_demo/         timer interrupt via mtvec/mret, ecall, cycle/instret counters
tests/isa/           riscv-tests rv32ui (vendored) + SoC test environment + run_isa.py
tests/tb/            tb_isa.v: generic program runner with UART decode, PASS/FAIL detection
scripts/             simlib.py (xsim driver), run_prog.py, bin2hex.py
docs/                architecture, memory map, register maps, results
```

## Memory map

| Base | Peripheral | Registers |
|---|---|---|
| `0x0000_0000` | BRAM, 32 KB | code, data, stack; initialised from `program.hex` in the bitstream |
| `0x1000_0000` | GPIO | `+0` OUT (LEDs, RW) · `+4` IN (switches, RO) |
| `0x2000_0000` | UART 115200 8N1 | `+0` TX (W) / last TX byte (R) · `+4` RX (R, clears valid) · `+8` STATUS {bit1 rx_valid, bit0 tx_busy} |
| `0x3000_0000` | Timer | `+0` COUNT · `+4` COMPARE · `+8` CTRL {bit1 irq_en, bit0 enable} · `+C` STATUS {bit0 pending, W1C} |

The interconnect decodes on address bits `[29:28]`; each slave then decodes
`[3:2]`. Details and timing diagrams: [docs/architecture.md](docs/architecture.md).

## Quick start

Prerequisites: Vivado 2025.1 (xsim), xPack `riscv-none-elf-gcc`, Python 3,
GNU make (`mingw32-make` on Windows). Tool locations can be given with
`VIVADO_BIN`, `RISCV_PREFIX` and `PYTHON`.

```sh
# 1. ISA regression: builds all rv32ui tests, simulates each, prints a table
cd tests/isa && python run_isa.py

# 2. Build a program and run it in simulation (UART output shown on the console)
cd sw/hello && make sim
cd sw/irq_demo && make sim

# 3. Put a program into the hardware image and build the ZCU104 bitstream
cd sw/hello && make install          # -> rtl/program.hex
cd fpga && vivado -mode batch -source build.tcl     # -> fpga/build/zcu104_top.bit

# 4. Regenerate the Vivado GUI project (optional)
cd fpga && vivado -mode batch -source create_project.tcl
```

On the board: connect the USB-UART, open a terminal at 115200 8N1 on the
third CP2108 channel (the PL UART), programme the bitstream. The banner
appears, the LEDs chase, the DIP switches are reported when changed and typed
characters are echoed.

## Results

ZCU104 (xczu7ev-ffvc1156-2-e), Vivado 2025.1, 100 MHz, default flow
([reports](fpga/reports/), details in [docs/results.md](docs/results.md)):

| | LUTs | FFs | RAMB36 | DSP | Timing | Power (est.) |
|---|---:|---:|---:|---:|---|---|
| whole SoC (`soc_top`) | 1 519 | 756 | 8 | 0 | met, WNS +5.36 ns | 0.63 W (0.015 W dynamic) |
| of which core (`riscv_core`) | 1 377 | 488 | 0 | 0 | | |

Verification: 41 / 41 riscv-tests rv32ui, plus the `hello` and `irq_demo`
programs as self-checking simulations.

## Core micro-architecture in one paragraph

The core is a six-state controller (`IF_ADDR → IF_DATA → EXEC → [MEM_ADDR →
MEM_DATA] → WB`) over a single shared AXI-Lite master port, so instruction
fetch and data access use the same bus and the same memory — there are no
caches and no separate instruction port. All decode, the ALU, branch
resolution and load/store byte-lane steering are combinational from the
instruction register; the register file is a 31×32 LUT-RAM. Traps are taken
in `WB`: synchronous (`ecall`/`ebreak`) first, then `mret`, then a pending
timer interrupt at the instruction boundary, then normal flow. This keeps the
control path simple enough to read in one sitting while still being a
correct, interrupt-capable machine-mode RISC-V implementation.

## Licence

RTL, software and scripts: MIT. `tests/isa/riscv-tests` is vendored from
[riscv-software-src/riscv-tests](https://github.com/riscv-software-src/riscv-tests)
under its BSD licence.
