// ============================================================================
// fetch_decode.sv — 顺序取指 + 结构化译码（阶段 2：标量 in-order）
//
// 职责边界：
//   * 取指：驱动 PC、锁存当前指令 inst，仅在 stall 解除时推进；根据执行级
//     反馈的 branch_taken / branch_target 做分支重定向；
//   * 译码：从 inst 抽出统一的操作数（opcode/rd/funct3/funct7/rs1/rs2/imm），
//     把「编码上的位段差异」收敛在此，执行级见到的是一致接口；
//   * 停顿：stall 来自执行级（halted 反向压停）；取到 HALT 时提早停住，
//     使 halted 后 pc 仍指向 HALT 指令。
// ============================================================================

`default_nettype none

module fetch_decode #(
    parameter int ADDR_W = 8                  // 指令存储器地址宽度
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 stall,          // 执行级反压（halted）
    input  logic                 branch_taken,   // 执行级判定分支/跳转命中
    input  logic [ADDR_W-1:0]    branch_target,  // 分支目标（字地址）
    input  logic [31:0]          imem_rdata,     // 当前 pc 指向的指令
    output logic [ADDR_W-1:0]    pc,             // 当前取指地址
    output logic [ADDR_W-1:0]    pc_dec,         // inst 指令的地址（分支基址）
    output logic [31:0]          inst,           // F/D 锁存后的当前指令
    // 结构化译码输出（仅供标量执行级使用）
    output logic [6:0]           dec_opcode,
    output logic [4:0]           dec_rd,
    output logic [2:0]           dec_funct3,
    output logic [6:0]           dec_funct7,
    output logic [4:0]           dec_rs1,
    output logic [4:0]           dec_rs2,
    output logic [31:0]          dec_imm_i     // I/B/J 型 12-bit 立即数符号扩展
);

    import isa_pkg::*;

    logic [ADDR_W-1:0] pc_r;
    logic [ADDR_W-1:0] pc_dec_r;
    logic [31:0]       inst_r;

    // 下一条要取的地址：分支命中则跳转；取到 HALT 则停住；否则顺序 +1。
    logic [ADDR_W-1:0] next_pc;
    assign next_pc = branch_taken                 ? branch_target :
                     (imem_rdata[6:0] == OP_HALT) ? pc_r :
                     (pc_r + 1'b1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_r     <= '0;
            pc_dec_r <= '0;
            inst_r   <= '0;
        end else if (!stall) begin
            pc_r     <= next_pc;
            pc_dec_r <= pc_r;                         // 记录本周期所取指令的地址
            // 分支命中时，同周期已取到的「顺序后一条」指令作废 -> 冲刷为 NOP。
            inst_r   <= branch_taken ? 32'h0 : imem_rdata;
        end
    end

    assign pc     = pc_r;
    assign pc_dec = pc_dec_r;
    assign inst   = inst_r;

    // 结构化译码：把编码差异收敛在此，执行级只看到统一操作数。
    assign dec_opcode = inst_r[6:0];
    assign dec_rd     = inst_r[11:7];
    assign dec_funct3 = inst_r[14:12];
    assign dec_funct7 = inst_r[31:25];
    assign dec_rs1    = inst_r[19:15];
    // rs2 位置依指令类型而变：R 型在 [24:20]，分支在 [11:7]（复用 rd 位段）。
    assign dec_rs2    = (dec_opcode == OP_OP) ? inst_r[24:20] : inst_r[11:7];
    assign dec_imm_i  = {{20{inst_r[31]}}, inst_r[31:20]};

endmodule

`default_nettype wire
