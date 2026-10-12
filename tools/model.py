# ============================================================================
# tools/model.py — 标量核参考模型（golden oracle，供差分测试）
#
# 独立于 RTL，从同一份 32-bit 机器字序列译码并执行，输出最终寄存器状态。
# 与 RTL 保持相同的语义约束：x0 恒 0、写入 x0 被忽略、BLT 为有符号比较。
# ============================================================================

from tools.isa import (
    opcode, rd, rs1, funct3, funct7, imm_i, rs2_r, rs2_b,
    OP_HALT, OP_OPIMM, OP_OP, OP_LOAD, OP_STORE, OP_BRANCH, OP_JAL,
    FUNCT3_BEQ, FUNCT3_BLT, FUNCT7_SUB,
)

NUM_REG = 32
MASK32 = 0xFFFFFFFF
# 数据存储器（与 rtl/core/tile_ooo_top.sv 的 DMEM_DEPTH 保持一致）。
DMEM_DEPTH = 64
DMEM_MASK = DMEM_DEPTH - 1


def _to_signed(v):
    return v - 0x100000000 if v >= 0x80000000 else v


class ScalarCore:
    def __init__(self):
        self.regs = [0] * NUM_REG
        self.mem = [0] * DMEM_DEPTH

    def run(self, words):
        """顺序执行机器字序列，返回最终寄存器值列表（含 x0，恒 0）。"""
        regs = self.regs
        pc = 0
        while pc < len(words):
            w = words[pc]
            op = opcode(w)

            if op == OP_HALT:
                break

            elif op == OP_OPIMM:              # ADDI
                d, s = rd(w), rs1(w)
                v = (regs[s] + imm_i(w)) & MASK32
                if d:
                    regs[d] = v
                pc += 1

            elif op == OP_OP:                 # ADD / SUB
                d, s1, s2 = rd(w), rs1(w), rs2_r(w)
                v = regs[s1] - regs[s2] if funct7(w) == FUNCT7_SUB else regs[s1] + regs[s2]
                v &= MASK32
                if d:
                    regs[d] = v
                pc += 1

            elif op == OP_LOAD:               # LD rd, imm(rs1)
                d, s = rd(w), rs1(w)
                a = (regs[s] + imm_i(w)) & DMEM_MASK
                if d:
                    regs[d] = self.mem[a]
                pc += 1

            elif op == OP_STORE:              # ST rs2, imm(rs1)
                s1, s2 = rs1(w), rs2_b(w)
                a = (regs[s1] + imm_i(w)) & DMEM_MASK
                self.mem[a] = regs[s2]
                pc += 1

            elif op == OP_BRANCH:             # BEQ / BLT
                s1, s2 = rs1(w), rs2_b(w)
                f3 = funct3(w)
                taken = (f3 == FUNCT3_BEQ and regs[s1] == regs[s2]) or \
                        (f3 == FUNCT3_BLT and _to_signed(regs[s1]) < _to_signed(regs[s2]))
                pc = pc + imm_i(w) if taken else pc + 1

            elif op == OP_JAL:                # JMP
                pc = pc + imm_i(w)

            else:
                raise ValueError("未实现或非法指令：0x%08x" % w)

        return list(regs)