// ============================================================================
// isa_pkg.sv — 共享 ISA 编码常量
//
// 集中定义 opcode / funct3 / funct7 等编码常量，供 fetch_decode、scalar_pipeline
// 等模块统一引用，避免魔数散落各处。
//
// 编码采用「RISC-V 风格固定位段 + 自定义 opcode」，并为教学刻意简化立即数：
//   * opcode   [6:0]    固定
//   * rd       [11:7]   写回目的（分支/跳转无写回，此位段被分支复用为 rs2）
//   * funct3   [14:12]  子操作码 / 分支条件
//   * rs1      [19:15]  第一源操作数
//   * 立即数   [31:20]  所有带立即数指令（I/B/J）统一用此 12-bit 符号扩展段
//   * R 型（ADD/SUB）另用 [24:20]=rs2、[31:25]=funct7
//
// 字段布局：
//   I 型（ADDI/LD）: imm[11:0] | rs1 | funct3 | rd  | opcode
//   R 型（ADD/SUB）: funct7    | rs2 | rs1    | funct3 | rd | opcode
//   B 型（BEQ/BLT）: imm[11:0] | rs1 | funct3 | rs2 | opcode   (rs2 复用 rd 位段)
//   ST             : imm[11:0] | rs1 | funct3 | rs2 | opcode   (rs2 复用 rd 位段，不写回)
//   J 型（JMP）    : imm[11:0] | 0   | 0      | 0   | opcode
//
// 相比 RISC-V 原版的 B/J 型「立即数打散」编码，这里让所有立即数都落在 [31:20]，
// 代价是分支的 rs2 挪到 [11:7]（分支本来就不写回，rd 位段空置）。代价很小，
// 换来译码与理解上的统一。
// ============================================================================

package isa_pkg;

    // ---- opcode（bit[6:0]）----
    parameter logic [6:0] OP_OPIMM  = 7'h13;   // I 型立即数 ALU（ADDI）
    parameter logic [6:0] OP_OP     = 7'h33;   // R 型寄存器 ALU（ADD/SUB）
    parameter logic [6:0] OP_LOAD   = 7'h03;   // I 型 load（LD rd, imm(rs1)）
    parameter logic [6:0] OP_STORE  = 7'h23;   // store（ST rs2, imm(rs1)）
    parameter logic [6:0] OP_BRANCH = 7'h63;   // B 型条件分支（BEQ/BLT）
    parameter logic [6:0] OP_JAL    = 7'h6F;   // J 型无条件跳转（JMP）
    parameter logic [6:0] OP_HALT   = 7'h7F;   // 程序终止（自定义，暂定）

    // ---- funct3（bit[14:12]）----
    parameter logic [2:0] FUNCT3_ADD = 3'h0;   // add 族（ADDI/ADD/SUB，靠 opcode+funct7 区分）
    parameter logic [2:0] FUNCT3_BEQ = 3'h0;
    parameter logic [2:0] FUNCT3_BLT = 3'h4;

    // ---- funct7（bit[31:25]，仅 R 型）----
    parameter logic [6:0] FUNCT7_ADD = 7'h00;
    parameter logic [6:0] FUNCT7_SUB = 7'h20;

endpackage
