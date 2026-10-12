# ============================================================================
# tools/isa.py — ISA 编码常量与字段提取（与 rtl/core/isa_pkg.sv 保持一致）
#
# 位段布局（RISC-V 风格 + 自定义 opcode，立即数统一在 [31:20]）：
#   I 型（ADDI/LD）: imm[11:0] | rs1 | funct3 | rd  | opcode
#   R 型（ADD/SUB）: funct7    | rs2 | rs1    | funct3 | rd | opcode
#   B 型（BEQ/BLT）: imm[11:0] | rs1 | funct3 | rs2 | opcode   (rs2 复用 rd 位段)
#   ST             : imm[11:0] | rs1 | funct3 | rs2 | opcode   (rs2 复用 rd 位段，不写回)
#   J 型（JMP）    : imm[11:0] | 0   | 0      | 0   | opcode
# ============================================================================

# opcode（bit[6:0]）
OP_OPIMM  = 0x13
OP_OP     = 0x33
OP_LOAD   = 0x03
OP_STORE  = 0x23
OP_BRANCH = 0x63
OP_JAL    = 0x6F
OP_HALT   = 0x7F

# funct3（bit[14:12]）
FUNCT3_ADD = 0x0   # add 族（ADDI/ADD/SUB，靠 opcode+funct7 区分）
FUNCT3_BEQ = 0x0
FUNCT3_BLT = 0x4

# funct7（bit[31:25]，仅 R 型）
FUNCT7_ADD = 0x00
FUNCT7_SUB = 0x20


def opcode(word):
    return (word >> 0) & 0x7F


def rd(word):
    return (word >> 7) & 0x1F


def funct3(word):
    return (word >> 12) & 0x7


def rs1(word):
    return (word >> 15) & 0x1F


def funct7(word):
    return (word >> 25) & 0x7F


def rs2_r(word):
    """R 型第二源操作数（位于 [24:20]）。"""
    return (word >> 20) & 0x1F


def rs2_b(word):
    """B 型第二源操作数（复用 rd 位段 [11:7]）。"""
    return (word >> 7) & 0x1F


def imm_i(word):
    """I/B/J 型 12-bit 立即数（位于 [31:20]），符号扩展。"""
    v = (word >> 20) & 0xFFF
    if v & 0x800:
        v -= 0x1000
    return v