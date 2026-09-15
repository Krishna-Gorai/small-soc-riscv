"""Shared helpers for driving Vivado xsim on the Small_SoC RTL.

Tools are looked up on PATH, or via VIVADO_BIN / RISCV_PREFIX environment
variables. Default Vivado location is the one used on the development host.
"""
import os, re, shutil, subprocess, sys
from pathlib import Path

ROOT    = Path(__file__).resolve().parents[1]
RTL_DIR = ROOT / "rtl"
TB      = ROOT / "tests" / "tb" / "tb_isa.v"
BIN2HEX = ROOT / "scripts" / "bin2hex.py"
PREFIX  = os.environ.get("RISCV_PREFIX", "riscv-none-elf-")

def vivado_tool(name):
    vb = os.environ.get("VIVADO_BIN")
    if vb:
        return str(Path(vb) / f"{name}.bat")
    for cand in (f"{name}.bat", name):
        if shutil.which(cand):
            return shutil.which(cand)
    default = Path(r"C:\Xilinx\xic\2025.1\Vivado\bin") / f"{name}.bat"
    if default.exists():
        return str(default)
    sys.exit(f"cannot find {name}; put Vivado bin on PATH or set VIVADO_BIN")

def run(cmd, cwd=None, log=None, check=True):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if log:
        Path(log).write_text(p.stdout + p.stderr)
    if check and p.returncode != 0:
        print(p.stdout + p.stderr)
        raise SystemExit(f"command failed: {' '.join(map(str, cmd))}")
    return p.stdout

def compile_rtl(build):
    """xvlog + xelab the RTL and tb_isa into <build>/xsim.dir (once)."""
    build.mkdir(parents=True, exist_ok=True)
    srcs = sorted(RTL_DIR.glob("*.v")) + [TB]
    stamp = build / "rtl.stamp"
    newest = max(p.stat().st_mtime for p in srcs)
    if stamp.exists() and stamp.stat().st_mtime >= newest:
        return
    run([vivado_tool("xvlog"), *map(str, srcs)], cwd=build, log=build / "xvlog.log")
    run([vivado_tool("xelab"), "tb_isa", "-s", "tb_isa", "--timescale", "1ns/1ps"],
        cwd=build, log=build / "xelab.log")
    stamp.touch()

def run_hex(build, hex_path, log=None, uart_stim=False, timeout=None):
    """Simulate one program image; returns (result_line, full_stdout)."""
    # The Vivado .bat wrappers on Windows split arguments at '=', so plusargs
    # cannot carry a path; the testbench reads a fixed "prog.hex" instead.
    shutil.copyfile(hex_path, build / "prog.hex")
    cmd = [vivado_tool("xsim"), "tb_isa", "-R"]
    if uart_stim:
        cmd += ["--testplusarg", "UART_STIM"]
    if timeout:
        (build / "timeout.txt").write_text(str(timeout))
    else:
        (build / "timeout.txt").unlink(missing_ok=True)
    out = run(cmd, cwd=build, log=log)
    m = re.search(r"RESULT: (PASS|FAIL test \d+|TIMEOUT)[^\n]*", out)
    return (m.group(0) if m else "RESULT: ??? (no result line)"), out

def uart_text(sim_stdout):
    """Extract what the program printed on the UART from the xsim console."""
    lines = sim_stdout.splitlines()
    # console output starts after the "Time resolution" banner line
    for i, l in enumerate(lines):
        if l.startswith("Time resolution"):
            lines = lines[i + 1:]
            break
    skip = ("RESULT:", "$finish", "exit", "INFO:", "run -all", "run all")
    return "\n".join(l for l in lines if not l.startswith(skip)).strip("\n")

def elf_to_hex(elf, hex_path):
    bin_ = Path(str(hex_path).rsplit(".", 1)[0] + ".bin")
    run([PREFIX + "objcopy", "-O", "binary", str(elf), str(bin_)])
    run([sys.executable, str(BIN2HEX), str(bin_), str(hex_path)])
