// ============================================================================
// regfile.sv — 标量整数寄存器文件（阶段 2）
//
// 32 个 XLEN 位寄存器；x0 恒为 0（读恒 0，写被忽略）。
// 提供：2 读口（rs1/rs2）、1 写口（同步）、1 调试读口（组合，供 harness/pytest 对拍）。
// ============================================================================

`default_nettype none

module regfile #(
    parameter int XLEN    = 32,
    parameter int NUM_REG = 32
) (
    input  logic                          clk,
    input  logic                          rst_n,
    // 读口（组合读出）
    input  logic [$clog2(NUM_REG)-1:0]    rs1_addr,
    input  logic [$clog2(NUM_REG)-1:0]    rs2_addr,
    output logic [XLEN-1:0]               rs1_data,
    output logic [XLEN-1:0]               rs2_data,
    // 写口（同步）
    input  logic                          we,
    input  logic [$clog2(NUM_REG)-1:0]    waddr,
    input  logic [XLEN-1:0]               wdata,
    // 调试读口（组合，任意寄存器）
    input  logic [$clog2(NUM_REG)-1:0]    dbg_addr,
    output logic [XLEN-1:0]               dbg_data
);

    logic [XLEN-1:0] rf [0:NUM_REG-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_REG; i = i + 1)
                rf[i] <= '0;
        end else if (we && (waddr != '0)) begin
            rf[waddr] <= wdata;
        end
    end

    // x0 恒 0：读地址为 0 时直接返回 0，不读底层存储。
    assign rs1_data = (rs1_addr == '0) ? '0 : rf[rs1_addr];
    assign rs2_data = (rs2_addr == '0) ? '0 : rf[rs2_addr];
    assign dbg_data = (dbg_addr == '0) ? '0 : rf[dbg_addr];

endmodule

`default_nettype wire
