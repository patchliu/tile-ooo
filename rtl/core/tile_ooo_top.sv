// ============================================================================
// tile_ooo_top.sv — 顶层模块（阶段 2：标量 in-order）
//
// 持有指令存储器 imem，实例化取指/译码前端、标量寄存器文件与标量执行级，
// 并把三者互联：fetch 产生的 pc 驱动 imem 读、译码的操作数驱动 regfile 读、
// 执行级的写回与分支反馈回到 regfile 与 fetch。
//
// 程序加载：harness 在复位期间通过 load_en / load_addr / load_data 端口
// 逐字写入 imem，随后释放复位并驱动时钟，直至观察到 halted 置位；再经
// dbg_addr / dbg_data 调试读口 dump 寄存器以对拍。
// ============================================================================

`default_nettype none

module tile_ooo_top #(
    parameter int IMEM_DEPTH = 256       // 指令存储器深度（字）
) (
    input  logic        clk,
    input  logic        rst_n,
    // 程序加载接口（复位期间写入）
    input  logic                             load_en,
    input  logic [$clog2(IMEM_DEPTH)-1:0]    load_addr,
    input  logic [31:0]                      load_data,
    // 观测 / 状态
    output logic        halted,          // 核心已执行 HALT
    output logic [31:0] pc,              // 当前取指地址（观测用，零扩展至 32-bit）
    output logic [31:0] inst,            // 当前指令（观测用）
    // 寄存器调试读口（组合，供 harness / pytest 对拍）
    input  logic [4:0]  dbg_addr,
    output logic [31:0] dbg_data
);

    localparam int ADDR_W  = $clog2(IMEM_DEPTH);
    localparam int XLEN    = 32;
    localparam int NUM_REG = 32;

    // 数据存储器（阶段 2 标量 LSU 的标量 dmem；后续升级为 banked scratchpad）。
    localparam int DMEM_DEPTH  = 64;             // 256B = 64 字
    localparam int DMEM_ADDR_W = $clog2(DMEM_DEPTH);

    // 指令存储器：上电清零。未加载位置读到 0；0x0000_007F 才是 HALT 编码。
    logic [31:0] imem [0:IMEM_DEPTH-1];

    initial begin
        for (int i = 0; i < IMEM_DEPTH; i = i + 1)
            imem[i] = 32'h0;
    end

    // 程序加载写口（与取指读口分时复用：运行前加载，运行时 load_en 拉低）。
    always_ff @(posedge clk) begin
        if (load_en)
            imem[load_addr] <= load_data;
    end

    // 数据存储器：组合读 + 同步写（与 imem / regfile 同一风格）。
    logic [DMEM_ADDR_W-1:0] mem_addr;   // LD/ST 访存地址（字地址）
    logic [31:0]            mem_wdata;
    logic                   mem_we;

    logic [31:0] dmem [0:DMEM_DEPTH-1];

    initial begin
        for (int i = 0; i < DMEM_DEPTH; i = i + 1)
            dmem[i] = 32'h0;
    end

    always_ff @(posedge clk) begin
        if (mem_we)
            dmem[mem_addr] <= mem_wdata;
    end

    // 前端 / 译码 / 执行级互联
    logic [ADDR_W-1:0] pc_w;
    logic [ADDR_W-1:0] pc_dec_w;
    logic [31:0]       inst_w;
    logic              halted_w;       // 反向压停 fetch

    logic [6:0]  dec_opcode;
    logic [4:0]  dec_rd;
    logic [2:0]  dec_funct3;
    logic [6:0]  dec_funct7;
    logic [4:0]  dec_rs1;
    logic [4:0]  dec_rs2;
    logic [31:0] dec_imm_i;

    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic        rf_we;
    logic [4:0]  rf_waddr;
    logic [31:0] rf_wdata;

    logic              branch_taken;
    logic [ADDR_W-1:0] branch_target;

    // 组合读指令存储器 / 数据存储器
    wire [31:0] imem_rdata = imem[pc_w];
    wire [31:0] dmem_rdata = dmem[mem_addr];

    fetch_decode #(
        .ADDR_W(ADDR_W)
    ) u_fetch_decode (
        .clk          (clk),
        .rst_n        (rst_n),
        .stall        (halted_w),
        .branch_taken (branch_taken),
        .branch_target(branch_target),
        .imem_rdata   (imem_rdata),
        .pc           (pc_w),
        .pc_dec       (pc_dec_w),
        .inst         (inst_w),
        .dec_opcode   (dec_opcode),
        .dec_rd       (dec_rd),
        .dec_funct3   (dec_funct3),
        .dec_funct7   (dec_funct7),
        .dec_rs1      (dec_rs1),
        .dec_rs2      (dec_rs2),
        .dec_imm_i    (dec_imm_i)
    );

    regfile #(
        .XLEN    (XLEN),
        .NUM_REG (NUM_REG)
    ) u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (dec_rs1),
        .rs1_data (rs1_data),
        .rs2_addr (dec_rs2),
        .rs2_data (rs2_data),
        .we       (rf_we),
        .waddr    (rf_waddr),
        .wdata    (rf_wdata),
        .dbg_addr (dbg_addr),
        .dbg_data (dbg_data)
    );

    scalar_pipeline #(
        .ADDR_W     (ADDR_W),
        .MEM_ADDR_W (DMEM_ADDR_W)
    ) u_scalar_pipeline (
        .clk          (clk),
        .rst_n        (rst_n),
        .dec_opcode   (dec_opcode),
        .dec_rd       (dec_rd),
        .dec_funct3   (dec_funct3),
        .dec_funct7   (dec_funct7),
        .dec_imm_i    (dec_imm_i),
        .pc_dec       (pc_dec_w),
        .rs1_data     (rs1_data),
        .rs2_data     (rs2_data),
        .mem_rdata    (dmem_rdata),
        .rf_we        (rf_we),
        .rf_waddr     (rf_waddr),
        .rf_wdata     (rf_wdata),
        .mem_addr     (mem_addr),
        .mem_wdata    (mem_wdata),
        .mem_we       (mem_we),
        .branch_taken (branch_taken),
        .branch_target(branch_target),
        .halted       (halted_w)
    );

    assign halted = halted_w;
    assign pc     = {{(32 - ADDR_W){1'b0}}, pc_w};
    assign inst   = inst_w;

endmodule

`default_nettype wire
