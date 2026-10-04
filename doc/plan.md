# TileFlow：OoO 张量处理器学习项目方案

## 1. 项目目标与边界

实现一个可在 Verilator 上运行的小型、面向 tile 的张量处理器，借它理解乱序执行、张量 ISA、局部存储、数据搬运、同步与软硬件协同。最终运行小规模 GEMM，并可选实现简化版 attention；重点是可解释的周期行为和架构实验，不追求流片、商业性能或复刻 NVIDIA/Ascend 未公开微架构。

**设计定位**：单核、双发射、标量控制前端 + Cube/MMA + Vector + Tile LSU，配小型共享 scratchpad。第一版采用显式同步；后续实验硬件 tile 重命名和自动依赖调度。

**范围约束**：
- V1 是单核单硬件上下文；不做多核一致性、虚拟内存、缓存一致性、精确异常、复杂分支预测或完整 OS 支持。
- 用自定义教学 ISA，而不是声称兼容 RISC-V。该取舍允许把重点放在 tensor/tile 指令与 OoO 机制；若后续要复用 RISC-V 软件生态，再考虑采用 RISC-V 标量子集 + 自定义协处理器扩展。
- 256B scratchpad 是首个参数点，不是充分支撑通用 GEMM/FlashAttention 的最终容量。容量参数化为 256B、1KiB、4KiB 做敏感性实验。
- 以 Verilog/SystemVerilog RTL 与 Verilator 仿真为核心。暂不写编译器；先用汇编文本与 Python 参考模型产生/核对程序和结果。

## 2. 目标微架构

```text
             +---------------------------+
             | Fetch / Decode / Dispatch |
             +-------------+-------------+
                           |
          +----------------+----------------+
          |                                 |
  Scalar OoO pipe                    Tensor command pipe
  ALU / branch / scalar LSU          Cube / Vector / Tile LSU
          |                                 |
   Scalar PRF + ROB + IQ       Scoreboard / event state / queues
          |                                 |
          +-------------+-------------------+
                        |
       256B banked shared scratchpad (configurable)
                        |
            External memory model / DMA
```

### V1 的明确选择

- **前端与发射**：顺序取指/译码，最多每周期发射两条：至多一条标量指令，及至多一条 tensor/vector/搬运命令。冲突时只发射一条。先实现顺序完成的 in-order 基线，再加 ROB/重命名/乱序发射，保持同一 ISA 以做对照。
- **乱序边界**：V1 OoO 只对标量指令与独立的 tile 命令做有限窗口调度。Cube/Vector 操作先在队列中等待源 tile 就绪；不做推测性外部内存 load，不做复杂 replay。写回和提交语义从简，规格明确标注不支持精确异常。
- **执行单元**：一个简单 Scalar ALU/branch；一个 Cube 单元先实现 4×4 INT8 点积/矩阵乘累加（INT32 累加）；一个 Vector 单元支持 add、mul、relu、简化 GELU；一个 Tile LSU 执行主存与 scratchpad 间 tile load/store。Tile LSU 接受 stride/shape 描述，实际搬运独立于 scalar ALU。
- **存储**：标量整数寄存器独立；Cube/Vector 共享 scratchpad，而不是将 256B 当作二者各自的寄存器文件。V1 定义 4 个 64B bank、每 bank 每周期最多一个访问；冲突时仲裁/排队并计数。可用参数改变 bank 数与容量，比较端口压力。
- **同步**：使用显式 `SET` / `WAIT` event。语义必须定义 event 作用域、复用/代际、完成点（命令完成且 scratchpad 写入可见）、超时诊断与 OoO 等待行为。`SET` 在关联命令完成且 scratchpad 写入可见后发布 event。event 不代替数据依赖；每条 tensor 指令仍明确指定源/目的 tile。
- **可观测性**：逐周期 trace、ROB/队列占用、Cube/Vector busy、scratchpad bank stall、event stall、命令延迟与总周期数。

## 3. 教学 ISA 草案

采用固定 32-bit 指令作为基础，复杂 tile 描述放在后续 64-bit 扩展或描述符内存中。以下是语义草案，编码位段在实现前单独冻结。

### 3.1 标量与控制

| 指令 | 语义 |
| --- | --- |
| `ADDI rd, rs1, imm` / `ADD` / `SUB` | 地址、循环和简单整数运算 |
| `MULI` | 小型索引计算（可延后） |
| `LD rd, [rs1+imm]` / `ST rs2, [rs1+imm]` | 标量内存访问 |
| `BEQ` / `BLT` / `JMP` | 条件与无条件控制流 |
| `HALT` | 结束程序 |

### 3.2 Tile 搬运和张量计算

| 指令 | 语义 |
| --- | --- |
| `TLOAD t, [base], shape, stride` | Tile LSU 将外存数据搬至 scratchpad tile 槽；异步启动，返回 event/token |
| `TSTORE [base], t, shape, stride` | 将 scratchpad tile 写回外存；完成后 event 可见 |
| `MMAC td, ta, tb, flags` | `td += ta × tb`；初始仅 4×4 INT8、INT32 累加 |
| `VADD td, ta, tb` / `VMUL` | 向量化 tile 运算 |
| `VRELU td, ta` / `VGELU td, ta` | 常用激活；首版 GELU 可用明确标注的定点近似 |
| `WAIT e` / `SET e` | 等待/发布本地 event；语义含可见性与完成点 |
| `FENCE` | 明确排序普通内存与 tile 搬运（仅在需要时加入） |

**操作数模型**：第一版使用显式 scratchpad 槽编号（`t` 是槽号，不是自动重命名的逻辑 tile register）。这样可以先验证 ISA、共享存储端口和同步语义。之后的实验版本再把逻辑 tile 名称映射到物理槽位，并加入 tile RAT/free list；不得把这项自动管理能力假定为 V1 已有。

**编码建议**：保留 opcode、通用寄存器、tile 槽、event 和小立即数；shape/stride 先使用紧凑限制（如固定 tile 形状、stride 寄存器），或者由 `TLOAD/TSTORE` 引用描述符。避免为了完整表达任意 rank tensor 而让每条指令超宽。ISA 单独有版本号与非法编码规则。

## 4. 实验工作负载和正确性

1. **标量冒烟测试**：计数器、分支、load/store、HALT，验证 PC 和寄存器状态。
2. **Cube 微测**：4×4 INT8 GEMM，随机输入，对比 Python/NumPy 参考结果；覆盖 signedness、溢出/饱和策略（先选定一种）和累加精度。
3. **流水线重叠**：双缓冲式 A/B tile 搬运与 MMA，使用显式 SET/WAIT，测 Cube busy 和等待周期。
4. **Vector 后处理**：MMA 后接 ReLU，再扩展 GELU 定点近似，检查各阶段数据可见性。
5. **小型 attention（可选最终挑战）**：固定小序列/头维度的 QKᵀ、softmax 近似、PV；先做单 tile 版本，不把完整 FlashAttention 当 V1 验收条件。

每个工作负载需同时给出：汇编、参考输入/输出、逐周期或关键事件 trace、总周期数和单元利用率。先验证结果正确，再讨论性能。

## 5. 实验环境与工具

### 必需

- Linux 开发环境优先；macOS 可作为宿主，但以 Linux 容器/CI 固定工具版本，减少平台差异。
- **Verilog/SystemVerilog**：RTL 语言。建议先限制到 Verilator 支持良好的可综合子集；全项目统一语言标准与时序约定。
- **Verilator**：周期仿真与 lint，生成 C++ 仿真模型。
- **CMake + Ninja + C++ 编译器（Clang 或 GCC）**：构建仿真器和测试程序。
- **Python 3 + pytest + NumPy**：汇编器原型、参考模型、随机测试和 golden compare。
- **GTKWave**：查看 VCD/FST 波形。仿真默认输出 FST，失败时保留最小复现波形。
- **Git**：记录阶段里程碑和参数实验；不把生成的二进制、海量波形提交进仓库。

### 后续可选

- **Yosys**：综合统计逻辑规模、寄存器与存储资源趋势；不把其统计当作真实 PPA 或可流片结论。
- **SymbiYosys / formal 工具**：验证 FIFO、ROB、event 状态机等局部不变量；确认工具支持范围后再引入。
- **Verible**：SystemVerilog 格式与 lint 辅助，可选。
- 不需要先安装 MLIR、LLVM pass 工具链或完整 RISC-V GCC/LLVM，因为本项目阶段不包含编译器，也不采用 RISC-V ISA。

建议把版本固定在 `toolchain.lock` 或容器定义中；CI 执行 lint、单元测试、端到端汇编运行和参考结果比对。

## 6. 独立代码仓库结构

```text
tileforge/
├── README.md
├── docs/
│   ├── architecture.md
│   ├── isa-v0.1.md
│   ├── memory-and-sync.md
│   ├── experiments.md
│   └── decisions/                 # 简短 ADR：为何选定同步/编码/端口策略
├── rtl/
│   ├── core/                      # fetch_decode, dispatch, scalar_pipe
│   ├── ooo/                       # rob, rename, issue_queue, scoreboard (后续阶段)
│   ├── tensor/                    # cube, vector, tile_lsu
│   ├── memory/                    # scratchpad, bank_arbiter, memory_model
│   └── top.sv
├── sim/
│   ├── verilator/                  # 仿真顶层、C++ harness、trace 输出
│   └── tests/                     # 端到端程序与 cycle assertions
├── tools/
│   ├── assembler/                  # 小型 Python 汇编器
│   ├── reference/                  # 定点数与 GEMM/attention 参考模型
│   └── trace/                      # trace 汇总/性能计数器分析
├── programs/
│   ├── smoke/
│   ├── gemm4x4/
│   └── attention_tiny/             # 后期
├── tests/
│   ├── unit/                       # FIFO、ROB、bank arbiter 等
│   └── random/                     # 随机指令/矩阵差分测试
├── scripts/
├── CMakeLists.txt
└── toolchain.lock
```

RTL 模块尽量采用 ready/valid 请求响应边界；对每个模块分别写单元测试。仿真 harness 负责加载程序、初始化外存、读取结果与导出统计。不要让 Python 参考模型直接驱动内部 RTL 信号，以免绕过真实接口语义。

## 7. 里程碑计划

| 阶段 | 目标 | 验收标准 |
| --- | --- | --- |
| 0. 规格冻结 | 寄存器/内存/算术语义、ISA 编码、stall/reset 约定、scratchpad 端口仲裁 | `isa-v0.1.md` 有指令表、编码、非法编码和小程序示例 |
| 1. 仿真骨架 | Verilator + CMake/Ninja + harness + 波形 | 一条 HALT 程序端到端运行，CI 可复现 |
| 2. 标量 in-order | ALU、branch、标量 LSU、scratchpad、简单外存模型 | 汇编冒烟程序结果正确，load-use 和 backpressure 测试通过 |
| 3. Cube/Vector/Tile LSU | 固定 4×4 INT8 MMAC、基础 vector、tile 搬运、event | GEMM + ReLU 正确，能观察显式同步与 bank 冲突 |
| 4. 计量基线 | 性能计数器与程序参数扫描 | 报告基线周期、Cube 利用率、event/stall/bank 冲突 |
| 5. OoO 标量核 | RAT/PRF、ROB、issue queue、按序提交，先只支持安全子集 | 对同 ISA 程序与 in-order 结果完全一致；hazard 与 flush 有测试 |
| 6. tensor command OoO | tensor 命令队列/scoreboard，在独立 tile 上重排 | 相对显式顺序基线给出周期和利用率差异；RAW 仍正确阻塞 |
| 7. tile 重命名实验 | 逻辑 tile -> 物理槽 RAT/free list、版本/回收和依赖追踪 | 多迭代 GEMM 自动复用不同物理槽，断言无过早回收/覆盖 |
| 8. attention 与报告 | 小型 attention、容量/端口/窗口参数研究 | 输出正确性、性能曲线、局限性与可复现实验脚本 |

**预计节奏**：约 12–16 周业余节奏；若每周投入较少，将阶段 5–8 视作扩展目标。不要跳过阶段 2–4 直接从复杂 OoO 开始，否则错误会难以归因。

## 8. 评价指标和实验矩阵

- **正确性**：参考模型逐元素一致；随机种子固定并记录；定点舍入/溢出规则明确。
- **性能**：总周期、IPC/发射利用率、Cube busy%、Vector busy%、Tile LSU 利用率、等待 event 周期。
- **资源与瓶颈**：scratchpad bank conflict、队列满周期、ROB 占用、tile 槽耗尽、外存延迟停顿。
- **对照实验**：in-order vs OoO；单发射 vs 双发射；显式双缓冲 vs tile 重命名；scratchpad 256B/1KiB/4KiB；不同 bank 数；固定与可变外存延迟。
- 每次只改变一个主要参数；结果报告必须说明 OoO 的额外硬件状态和复杂度，不能只展示最快的一次运行。

## 9. 风险与刻意不做的事

- **256B 容量偏小**：保留为第一组教学实验，但参数化容量，避免把小容量造成的限制误认为架构原理。
- **OoO 很容易失控**：先 in-order 形成可信 oracle，再加入有限 OoO；首个 OoO 范围不含推测性内存和精确异常。
- **双发射语义容易含混**：定义两个发射槽类型及每周期带宽上限；Cube/Vector 资源冲突时明确仲裁。
- **同步正确性比算子复杂**：先单元测试 event 世代、写入可见性、deadlock watchdog 与复用规则，再跑 GEMM。
- **不将结果包装为可综合/高性能 NPU**：Verilator 正确运行不代表时序收敛；Yosys 面积估计不代表真实工艺 PPA。

## 10. 名称候选

| 名称 | 含义/风格 |
| --- | --- |
| **TileFlow** | 突出 tile 数据流与调度；简洁，但已有同名研究工具/项目，需确认是否接受命名冲突（当前首选） |
| **TensorWeave** | 交织标量控制、张量执行和数据搬运，偏研究型 |
| **TileFlow OoO** | 突出 tile 生命周期与乱序调度，可作为带后缀的区分方案 |
| **MosaicCore** | 多种执行单元拼接成张量核心，易做视觉品牌 |
| **Kestrel-T** | 短而有辨识度，T 可解释为 tensor；不直接描述实现 |
| **ForgeCube** | 强调 Cube/MMA 实验，名称略偏矩阵单元 |

推荐名称 **TileFlow**，架构描述用 **TileFlow-T1: dual-issue OoO tile processor**。注意已有同名的 TileFlow accelerator dataflow modeling/design-space exploration 项目；GitHub 仓库名或组织前缀可用 `tileflow-ooo`、`tileflow-t1` 等方式区分。发布前仍需检查目标代码托管平台上的仓库名、商标与许可证；本表名称只是候选。

## 11. 第一周的具体任务

1. 在独立目录/仓库初始化工程。
2. 写 1 页 ISA v0.1：寄存器数、tile 槽数、event 数、地址宽度、定点语义、编码格式。
3. 固定 reset/ready-valid/外存延迟模型和仿真命令，提交 HALT 与标量 add 冒烟程序。
4. 建立 Python GEMM 参考脚本与结果 golden 文件。
5. 做 4×4 Cube 面积/数据宽度草算，决定 MMAC 每周期吞吐的教学目标；不预设必须达到某个商业指标。

完成第一周后，再冻结 ISA 位编码与阶段 2 的模块接口；后续 ISA 修改必须有短 ADR 与回归测试。
