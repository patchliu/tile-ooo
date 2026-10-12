// programs/hello/hello.s — 阶段 1（里程碑 HALT）
// 仅一条 HALT 指令，验证「取指 → 译码 → 停止」链路。
// 阶段 2 会改为 ADDI + ST 经 memory-mapped UART 输出 "Hello, tile-ooo!"。
//
// 临时 ISA 编码（待 isa-v0.1.md 冻结）：
//   HALT: 32'h0000_007F
//
// 本阶段尚无 assembler，机器码由手工写入 hello.hex。

    HALT