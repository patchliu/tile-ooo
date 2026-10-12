# ============================================================================
# tests/test_alu_branch.py — ADD/SUB 与分支差分测试
#
# 每条用例：用同一份机器字序列同时喂给参考模型与 RTL 仿真，比对最终寄存器。
# 注意：分支/跳转的立即数是「字偏移」，相对该指令自身下标。
# ============================================================================

from tools.assembler import addi, add, sub, beq, blt, jmp, halt
from tools.model import ScalarCore
from tools.harness import run_rtl


def _diff(words):
    expected = ScalarCore().run(words)
    actual = run_rtl(words)
    assert actual == expected


def test_add():
    _diff([addi(1, 0, 7), addi(2, 0, 5), add(3, 1, 2), halt()])      # x3 = 12


def test_sub():
    _diff([addi(1, 0, 10), addi(2, 0, 3), sub(3, 1, 2), halt()])     # x3 = 7


def test_sub_negative():
    _diff([addi(1, 0, 3), sub(2, 0, 1), halt()])                      # x2 = -3


def test_beq_taken():
    # x1 == x2 == 5 -> BEQ 命中，跳到下标 4（跳过下标 3 的 addi）
    _diff([
        addi(1, 0, 5),
        addi(2, 0, 5),
        beq(1, 2, 2),
        addi(3, 0, 1),   # 应被跳过
        addi(3, 0, 9),   # x3 = 9
        halt(),
    ])


def test_beq_not_taken():
    # x1 != x2 -> 不跳，顺序落到 x3 = 1
    _diff([
        addi(1, 0, 5),
        addi(2, 0, 6),
        beq(1, 2, 2),
        addi(3, 0, 1),
        halt(),
    ])


def test_blt_taken():
    # x1 = -1 < x2 = 5（有符号）-> 命中，跳到下标 4 -> x3 = 9
    _diff([
        addi(1, 0, -1),
        addi(2, 0, 5),
        blt(1, 2, 2),
        addi(3, 0, 1),   # 应被跳过
        addi(3, 0, 9),
        halt(),
    ])


def test_jmp_over():
    # JMP 无条件跳到下标 2，跳过下标 1 的 addi -> x1 = 9
    _diff([jmp(2), addi(1, 0, 5), addi(1, 0, 9), halt()])