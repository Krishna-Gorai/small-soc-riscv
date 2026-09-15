#!/usr/bin/env python3
"""Build and run the riscv-tests rv32ui suite on the Small_SoC RTL in xsim.

    python run_isa.py            # all tests
    python run_isa.py add lw     # a subset
    python run_isa.py --list

Requires riscv-none-elf-gcc on PATH (or RISCV_PREFIX set) and Vivado's
xvlog/xelab/xsim on PATH (or VIVADO_BIN set).
"""
import os, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import simlib
from simlib import run, PREFIX, BIN2HEX

HERE      = Path(__file__).resolve().parent
BUILD     = HERE / "build"
TESTS_DIR = HERE / "riscv-tests" / "rv32ui"

# ma_data needs misaligned-access traps, which the core does not implement.
SKIP = {"ma_data"}

CFLAGS  = ["-march=rv32i_zicsr_zifencei", "-mabi=ilp32", "-mcmodel=medany",
           "-static", "-nostdlib", "-nostartfiles", "-fvisibility=hidden",
           "-I", str(HERE / "env"), "-I", str(HERE / "riscv-tests" / "macros" / "scalar"),
           "-T", str(HERE / "env" / "link.ld")]

def build_test(name):
    elf = BUILD / f"{name}.elf"
    hex_ = BUILD / f"{name}.hex"
    run([PREFIX + "gcc", *CFLAGS, str(TESTS_DIR / f"{name}.S"), "-o", str(elf)])
    simlib.elf_to_hex(elf, hex_)
    return hex_

def sim_test(name, hex_):
    result, _ = simlib.run_hex(BUILD, hex_, log=BUILD / f"{name}.sim.log")
    return result

def main():
    args = sys.argv[1:]
    all_tests = sorted(p.stem for p in TESTS_DIR.glob("*.S"))
    if "--list" in args:
        print("\n".join(all_tests)); return
    tests = args or [t for t in all_tests if t not in SKIP]
    BUILD.mkdir(exist_ok=True)

    print(f"Building {len(tests)} tests ...")
    hexes = {t: build_test(t) for t in tests}
    print("Compiling RTL + testbench ...")
    simlib.compile_rtl(BUILD)

    results, t0 = {}, time.time()
    for t in tests:
        r = sim_test(t, hexes[t])
        results[t] = r
        print(f"  {t:10s} {r}")
    npass = sum(r.startswith("RESULT: PASS") for r in results.values())
    summary = f"\n{npass}/{len(tests)} passed  ({time.time()-t0:.0f} s)"
    print(summary)
    (BUILD / "results.txt").write_text(
        "\n".join(f"{t:10s} {r}" for t, r in results.items()) + summary + "\n")
    sys.exit(0 if npass == len(tests) else 1)

if __name__ == "__main__":
    main()
