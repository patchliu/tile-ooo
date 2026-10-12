// programs/smoke/addi.s — 阶段 2 冒烟：ADDI 写寄存器后 HALT
//
// 验证「取指 → 译码 → regfile 读 → ALU(ADDI) → regfile 写 → HALT」链路。
// 期望：执行后 x1 = 5，随后 halted = 1。
//
// 编码（RISC-V 风格位段，见 rtl/core/isa_pkg.sv）：
//   ADDI x1, x0, 5 : opcode=0x13, funct3=0, rd=1, rs1=0, imm=5 -> 0x00500093
//   HALT           : opcode=0x7f                                   -> 0x0000007f

    ADDI x1, x0, 5
    HALT