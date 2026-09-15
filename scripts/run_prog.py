#!/usr/bin/env python3
"""Run one program image on the Small_SoC RTL in xsim and show its UART output.

    python run_prog.py prog.hex [--timeout CYCLES] [--uart-stim] [--expect TEXT]

Exit status is 0 when the program reports PASS through the GPIO register
(or, with --expect, when TEXT appears in the UART output).
"""
import argparse, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import simlib

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hex")
    ap.add_argument("--timeout", type=int, default=400000, help="watchdog in clock cycles")
    ap.add_argument("--uart-stim", action="store_true", help='testbench sends "Hi\n" on the UART RX')
    ap.add_argument("--expect", help="text that must appear in the UART output")
    a = ap.parse_args()

    build = simlib.ROOT / "sim" / "build"
    simlib.compile_rtl(build)
    hex_path = Path(a.hex).resolve()
    result, out = simlib.run_hex(build, hex_path, log=build / (hex_path.stem + ".sim.log"),
                                 uart_stim=a.uart_stim, timeout=a.timeout)
    text = simlib.uart_text(out)
    print("---- UART output ----")
    print(text)
    print("---------------------")
    print(result)
    ok = result.startswith("RESULT: PASS")
    if a.expect:
        ok = a.expect in text
        print(f"expect {a.expect!r}: {'found' if ok else 'NOT FOUND'}")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
