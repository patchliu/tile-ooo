// ============================================================================
// scalar_pipeline.sv — 标量执行级（阶段 2：ADDI/ADD/SUB + 分支 + 标量 LSU）
//
// 职责边界：
//   * 根据译码结果判定指令语义与写回使能；
//   * ALU / 地址计算：ADDI（rs1 + imm）、ADD（rs1 + rs2）、SUB（rs1 - rs2），
//     LD/ST 复用同一加法路径计算访存地址（rs1 + imm）；
//   * 分支判定：BEQ / BLT（有符号）/ JMP，向 fetch 反馈 branch_taken / branch_target；
//   * 标量 LSU：LD 经 mem_rdata 写回 rd；ST 经 mem_addr / mem_wdata / mem_we 写数据存储；
//   * 产生反向压停信号 halted。
//
// 数据存储采用「组合读 + 同步写」（与 imem / regfile 同一风格），因此 LD 与 ADD 同构：
// 周期 N 组合算出结果、周期 N posedge 写回、下一拍即可读，无 load-use 冒险，
// 也无需 stall / bypass。后续升级为同步读 SRAM 或多周期访存时才需要引入 load-use stall。
// ============================================================================

`default_nettype none

module scalar_pipeline #(
    parameter int ADDR_W     = 8,   // 指令存储器地址宽度（分支目标）
    parameter int MEM_ADDR_W = 6    // 数据存储器地址宽度（LD/ST 地址）
) (
    input  logic                 clk,
    input  logic                 rst_n,
    // 译码输入（来自 fetch_decode 的结构化译码）
    input  logic [6:0]           dec_opcode,
    input  logic [4:0]           dec_rd,
    input  logic [2:0]           dec_funct3,
    input  logic [6:0]           dec_funct7,
    input  logic [31:0]          dec_imm_i,
    input  logic [ADDR_W-1:0]    pc_dec,      // inst 指令的地址（分支基址）
    // 寄存器读口
    input  logic [31:0]          rs1_data,
    input  logic [31:0]          rs2_data,
    // 数据存储读口（组合读回，LD 用）
    input  logic [31:0]          mem_rdata,
    // 写回
    output logic                 rf_we,
    output logic [4:0]           rf_waddr,
    output logic [31:0]          rf_wdata,
    // 数据存储写口（ST 用）
    output logic [MEM_ADDR_W-1:0] mem_addr,
    output logic [31:0]          mem_wdata,
    output logic                 mem_we,
    // 控制反馈给前端
    output logic                 branch_taken,
    output logic [ADDR_W-1:0]    branch_target,
    output logic                 halted
);

    import isa_pkg::*;

    logic is_halt, is_addi, is_add, is_sub, is_load, is_store, is_branch, is_jal;
    assign is_halt   = (dec_opcode == OP_HALT);
    assign is_addi   = (dec_opcode == OP_OPIMM) && (dec_funct3 == FUNCT3_ADD);
    assign is_add    = (dec_opcode == OP_OP) && (dec_funct7 == FUNCT7_ADD);
    assign is_sub    = (dec_opcode == OP_OP) && (dec_funct7 == FUNCT7_SUB);
    assign is_load   = (dec_opcode == OP_LOAD);
    assign is_store  = (dec_opcode == OP_STORE);
    assign is_branch = (dec_opcode == OP_BRANCH);
    assign is_jal    = (dec_opcode == OP_JAL);

    // ---- ALU / 地址计算：ADD/SUB 依 funct7；ADDI/LD/ST 统一走 rs1 + imm ----
    logic [31:0] alu_result;
    always_comb begin
        if (is_sub)
            alu_result = rs1_data - rs2_data;
        else if (is_add)
            alu_result = rs1_data + rs2_data;
        else if (is_addi || is_load || is_store)
            alu_result = rs1_data + dec_imm_i;
        else
            alu_result = '0;
    end

    // ---- 写回：ADDI/ADD/SUB/LD 写 rd；对 x0 的写入由 regfile 忽略 ----
    assign rf_wdata = is_load ? mem_rdata : alu_result;
    assign rf_we    = is_addi || is_add || is_sub || is_load;
    assign rf_waddr = dec_rd;

    // ---- 标量 LSU 数据存储口 ----
    assign mem_addr  = alu_result[MEM_ADDR_W-1:0];
    assign mem_wdata = rs2_data;
    assign mem_we    = is_store;

    // ---- 分支判定 ----
    logic rs_eq, rs_lt;
    assign rs_eq = (rs1_data == rs2_data);
    assign rs_lt = $signed(rs1_data) < $signed(rs2_data);

    assign branch_taken = is_jal ||
                          (is_branch && ( (dec_funct3 == FUNCT3_BEQ && rs_eq) ||
                                          (dec_funct3 == FUNCT3_BLT && rs_lt) ));

    // 目标 = 当前指令地址 + 符号扩展立即数（立即数已在 [31:20] 段统一）。
    assign branch_target = pc_dec + dec_imm_i[ADDR_W-1:0];

    // ---- 停止标志 ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            halted <= 1'b0;
        else
            halted <= is_halt;
    end

endmodule

`default_nettype wire
