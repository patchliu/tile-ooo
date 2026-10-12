# ============================================================================
# tools/harness.py — 驱动 RTL 仿真二进制并解析寄存器 dump
#
# 把机器字序列写成临时 .hex，交给 Verilator harness 运行，解析其打印的
# `REG[n]=0x...` 行，返回 32 个寄存器的 Python 整数列表。
# ============================================================================

import os
import re
import subprocess
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SIM_BIN = REPO_ROOT / "build" / "sim" / "verilator" / "tile_ooo_sim"

_REG_RE = re.compile(r"REG\[(\d+)\]=0x([0-9a-fA-F]+)")
NUM_REG = 32


def write_hex(words, path):
    with open(path, "w") as f:
        for w in words:
            f.write("%08x\n" % (w & 0xFFFFFFFF))


def parse_regdump(text):
    regs = [None] * NUM_REG
    for m in _REG_RE.finditer(text):
        idx = int(m.group(1))
        regs[idx] = int(m.group(2), 16)
    if any(r is None for r in regs):
        raise RuntimeError("未能完整解析寄存器 dump：\n" + text)
    return regs


def run_rtl(words):
    """运行 RTL 仿真，返回 32 个寄存器的最终值。"""
    if not SIM_BIN.exists():
        raise RuntimeError("RTL 仿真二进制未构建，请先运行：cmake --build build")

    fd, hex_path = tempfile.mkstemp(suffix=".hex")
    os.close(fd)
    try:
        write_hex(words, hex_path)
        proc = subprocess.run(
            [str(SIM_BIN), hex_path], capture_output=True, text=True
        )
        if proc.returncode != 0:
            raise RuntimeError("RTL 仿真非零退出：\n%s\n%s" % (proc.stdout, proc.stderr))
        return parse_regdump(proc.stdout)
    finally:
        os.unlink(hex_path)