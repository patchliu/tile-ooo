# ============================================================================
# tools/assembler.py — 最小汇编器（把指令编码为 32-bit 机器字）
#
# 覆盖阶段 2 的标量指令：ADDI / ADD / SUB / BEQ / BLT / JMP / HALT。
# 分支与跳转的立即数为「字偏移」，相对于该指令自身地址（与 RTL 的 pc_dec 基址一致）。
# ============================================================================

from tools.isa import (
    OP_OPIMM, OP_OP, OP_LOAD, OP_STORE, OP_BRANCH, OP_JAL, OP_HALT,
    FUNCT3_ADD, FUNCT3_BEQ, FUNCT3_BLT, FUNCT7_ADD, FUNCT7_SUB,
)

_MASK12 = 0xFFF


def addi(rd_num, rs1_num, imm):
    """ADDI rd, rs1, imm ：rd = rs1 + sign_extend(imm[11:0])"""
    imm &= _MASK12
    return (imm << 20) | (rs1_num << 15) | (FUNCT3_ADD << 12) | (rd_num << 7) | OP_OPIMM


def add(rd_num, rs1_num, rs2_num):
    """ADD rd, rs1, rs2 ：rd = rs1 + rs2"""
    return (FUNCT7_ADD << 25) | (rs2_num << 20) | (rs1_num << 15) | (FUNCT3_ADD << 12) | (rd_num << 7) | OP_OP


def sub(rd_num, rs1_num, rs2_num):
    """SUB rd, rs1, rs2 ：rd = rs1 - rs2"""
    return (FUNCT7_SUB << 25) | (rs2_num << 20) | (rs1_num << 15) | (FUNCT3_ADD << 12) | (rd_num << 7) | OP_OP


def ld(rd_num, rs1_num, imm):
    """LD rd, imm(rs1) ：rd = mem[rs1 + sign_extend(imm[11:0])]（funct3 固定 0）"""
    imm &= _MASK12
    return (imm << 20) | (rs1_num << 15) | (FUNCT3_ADD << 12) | (rd_num << 7) | OP_LOAD


def st(rs2_num, rs1_num, imm):
    """ST rs2, imm(rs1) ：mem[rs1 + sign_extend(imm[11:0])] = rs2（rs2 复用 rd 位段 [11:7]）"""
    imm &= _MASK12
    return (imm << 20) | (rs1_num << 15) | (FUNCT3_ADD << 12) | (rs2_num << 7) | OP_STORE


def beq(rs1_num, rs2_num, imm):
    """BEQ rs1, rs2, imm ：若 rs1 == rs2 则 pc += imm"""
    imm &= _MASK12
    return (imm << 20) | (rs1_num << 15) | (FUNCT3_BEQ << 12) | (rs2_num << 7) | OP_BRANCH


def blt(rs1_num, rs2_num, imm):
    """BLT rs1, rs2, imm ：若 rs1 < rs2（有符号）则 pc += imm"""
    imm &= _MASK12
    return (imm << 20) | (rs1_num << 15) | (FUNCT3_BLT << 12) | (rs2_num << 7) | OP_BRANCH


def jmp(imm):
    """JMP imm ：pc += imm（无条件）"""
    imm &= _MASK12
    return (imm << 20) | OP_JAL


def halt():
    """HALT：程序终止。"""
    return OP_HALT