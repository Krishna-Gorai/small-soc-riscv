#!/usr/bin/env python3
"""JTAG debug-port test: halt the core, load a program over JTAG, run it.

    python run_jtag.py [image.hex]     default: sw/hello/hello_sim.hex (make it first)

Simulates tests/tb/tb_jtag.v, whose bus-functional model drives IEEE 1149.1
TMS/TDI sequences into rtl/jtag_tap.v -> rtl/jtag_dbg.v.
"""
import shutil, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import simlib

def main():
    root  = simlib.ROOT
    hex_  = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "sw" / "hello" / "hello_sim.hex"
    if not hex_.exists():
        sys.exit(f"{hex_} not found (cd sw/hello && make hello_sim.hex)")
    build = root / "sim" / "jtag"
    build.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(hex_, build / "prog.hex")
    srcs = sorted((root / "rtl").glob("*.v")) + [root / "tests" / "tb" / "tb_jtag.v"]
    simlib.run([simlib.vivado_tool("xvlog"), *map(str, srcs)], cwd=build, log=build / "xvlog.log")
    simlib.run([simlib.vivado_tool("xelab"), "tb_jtag", "-s", "tb_jtag"], cwd=build, log=build / "xelab.log")
    out = simlib.run([simlib.vivado_tool("xsim"), "tb_jtag", "-R"], cwd=build, log=build / "xsim.log")
    print(simlib.uart_text(out))
    sys.exit(0 if "RESULT: PASS" in out else 1)

if __name__ == "__main__":
    main()
