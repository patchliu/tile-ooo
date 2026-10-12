# ============================================================================
# tests/test_lsu.py — 标量 LSU（LD/ST）差分测试
#
# 每条用例：用同一份机器字序列同时喂给参考模型与 RTL 仿真，比对最终寄存器。
# 数据存储器（dmem）在 RTL 与参考模型中均上电清零，由程序本身 ST → LD 自洽验证。
# ============================================================================

from tools.assembler import addi, ld, st, halt
from tools.model import ScalarCore
from tools.harness import run_rtl


def _diff(words):
    expected = ScalarCore().run(words)
    actual = run_rtl(words)
    assert actual == expected


def test_st_then_ld():
    # ST x1(=5) 到 mem[8]，LD x3 = mem[8] = 5，验证访存数据通路。
    _diff([
        addi(1, 0, 5),
        addi(2, 0, 8),
        st(1, 2, 0),
        ld(3, 2, 0),
        halt(),
    ])


def test_ld_zero_init():
    # LD 未写入位置读到 0（dmem 上电清零）。
    _diff([addi(1, 0, 4), ld(2, 1, 0), halt()])


def test_st_no_writeback():
    # ST 不写回任何寄存器：最终仅 x1=5、x2=9。
    _diff([addi(1, 0, 5), addi(2, 0, 9), st(1, 2, 0), halt()])


def test_ld_use_dependency():
    # LD x3 后紧跟 addi 使用 x3：结果下一拍可用，验证无 load-use 冒险。
    # mem[0]=5 -> x3=5 -> x4=6。
    _diff([
        addi(1, 0, 5),
        addi(2, 0, 0),
        st(1, 2, 0),
        ld(3, 2, 0),
        addi(4, 3, 1),
        halt(),
    ])


def test_negative_offset():
    # 负偏移：base=10, offset=-3 -> addr 7；ST mem[7]=99，LD x3=99。
    _diff([
        addi(1, 0, 10),
        addi(2, 0, 99),
        st(2, 1, -3),
        ld(3, 1, -3),
        halt(),
    ])


def test_addr_wrap():
    # 地址取低 6 位：base=64 -> addr 0；ST mem[0]=77，LD x3=mem[0]=77。
    _diff([
        addi(1, 0, 64),
        addi(2, 0, 77),
        st(2, 1, 0),
        ld(3, 0, 0),
        halt(),
    ])


def test_ld_write_x0_ignored():
    # LD x0, ... 的写回被忽略，x0 恒 0。
    _diff([
        addi(1, 0, 5),
        addi(2, 0, 0),
        st(1, 2, 0),
        ld(0, 2, 0),
        halt(),
    ])