#!/usr/bin/env python3
"""Post-implementation functional (gate-level) simulation of the ZCU104 build.

    python run_postimpl.py        # needs fpga/build/zcu104_top_funcsim.v
                                  # (fpga/write_netlist.tcl, after fpga/build.tcl)

Simulates the routed netlist with Vivado's UltraScale primitive models under
tests/tb/tb_zcu104_post.v, which drives the real 300 MHz board clock and
decodes the UART at 115200 baud. Passes when the banner starts to appear.
"""
import os, shutil, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import simlib

def main():
    root    = simlib.ROOT
    netlist = root / "fpga" / "build" / "zcu104_top_funcsim.v"
    if not netlist.exists():
        sys.exit(f"{netlist} not found: run fpga/build.tcl then fpga/write_netlist.tcl")
    build = root / "sim" / "postimpl"
    build.mkdir(parents=True, exist_ok=True)
    vivado_data = Path(simlib.vivado_tool("xvlog")).resolve().parents[1] / "data" / "verilog" / "src" / "glbl.v"
    if not (build / "glbl.v").exists():
        shutil.copyfile(vivado_data, build / "glbl.v")   # read-only in the Vivado tree
    simlib.run([simlib.vivado_tool("xvlog"), str(netlist), str(root / "tests" / "tb" / "tb_zcu104_post.v"), "glbl.v"],
               cwd=build, log=build / "xvlog.log")
    simlib.run([simlib.vivado_tool("xelab"), "--relax", "-L", "unisims_ver", "-L", "secureip",
                "--snapshot", "post", "tb_zcu104_post", "glbl"], cwd=build, log=build / "xelab.log")
    out = simlib.run([simlib.vivado_tool("xsim"), "post", "-R"], cwd=build, log=build / "xsim.log")
    print(simlib.uart_text(out))
    sys.exit(0 if "PASS" in out else 1)

if __name__ == "__main__":
    main()
