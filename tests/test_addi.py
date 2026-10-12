# ============================================================================
# tests/test_addi.py — ADDI 差分测试（RTL 仿真 vs Python 参考模型）
#
# 每条用例：用同一份机器字序列同时喂给参考模型与 RTL 仿真，比对最终寄存器。
# ============================================================================

from tools.assembler import addi, halt
from tools.model import ScalarCore
from tools.harness import run_rtl


def _diff(words):
    expected = ScalarCore().run(words)
    actual = run_rtl(words)
    assert actual == expected


def test_addi_imm_positive():
    # x1 = x0 + 5 = 5
    _diff([addi(1, 0, 5), halt()])


def test_addi_imm_negative():
    # x1 = -5；x2 = x1 + 3 = -2（覆盖负立即数与读回依赖）
    _diff([addi(1, 0, -5), addi(2, 1, 3), halt()])


def test_addi_chain():
    # 多寄存器链式累加
    _diff([addi(1, 0, 10), addi(2, 1, 20), addi(3, 2, -7), halt()])


def test_addi_write_x0_ignored():
    # 写 x0 应被忽略，x0 保持 0
    _diff([addi(0, 0, 123), halt()])