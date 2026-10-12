// ============================================================================
// main.cpp — Verilator 仿真 harness（阶段 1：跑通 HALT）
//
// 职责：
//   1. 复位期间通过 load_en / load_addr / load_data 端口加载程序；
//   2. 从 .hex 文件（或内置单条 HALT）读取程序；
//   3. 释放复位并逐周期驱动时钟，逐周期打印 pc / inst / halted；
//   4. 检测 halted，打印周期数与成功状态，返回退出码。
// ============================================================================

#include <verilated.h>
#include "Vtile_ooo_top.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>

// 与 rtl/core/tile_ooo_top.sv 中的 IMEM_DEPTH 保持一致。
static constexpr int kImemDepth = 256;
// HALT 的临时编码（见 rtl/core/fetch_decode.sv）。
static constexpr uint32_t kHaltInst = 0x0000007Fu;

static void cycle(Vtile_ooo_top *top) {
    top->clk = 1;
    top->eval();
    top->clk = 0;
    top->eval();
}

// 通过加载端口写一个指令字（一个时钟沿）。
static void load_word(Vtile_ooo_top *top, int addr, uint32_t word) {
    top->load_en = 1;
    top->load_addr = static_cast<uint32_t>(addr);
    top->load_data = word;
    cycle(top);
    top->load_en = 0;
}

// 解析 Verilog $readmemh 风格的 .hex 文件：
//   - 支持 "//" 注释与空行；
//   - 支持 "@hexaddr" 切换写入地址。
// 返回写入的指令数；失败返回 -1。
static int load_hex(Vtile_ooo_top *top, const std::string &path) {
    std::ifstream in(path);
    if (!in)
        return -1;

    int addr = 0;
    int count = 0;
    std::string line;
    while (std::getline(in, line)) {
        auto comment = line.find("//");
        if (comment != std::string::npos)
            line = line.substr(0, comment);

        std::istringstream iss(line);
        std::string tok;
        while (iss >> tok) {
            if (tok[0] == '@') {
                addr = static_cast<int>(std::strtoul(tok.c_str() + 1, nullptr, 16));
                continue;
            }
            if (addr < 0 || addr >= kImemDepth) {
                std::fprintf(stderr, "error: 程序地址 0x%x 超出指令存储器范围\n", addr);
                return -1;
            }
            load_word(top, addr++,
                      static_cast<uint32_t>(std::strtoul(tok.c_str(), nullptr, 16)));
            ++count;
        }
    }
    return count;
}

// 经 dbg_addr / dbg_data 调试读口逐个 dump 32 个寄存器，供 pytest 对拍解析。
static void dump_regfile(Vtile_ooo_top *top) {
    std::printf("REGFILE_BEGIN\n");
    for (int i = 0; i < 32; ++i) {
        top->dbg_addr = static_cast<uint32_t>(i);
        top->eval();
        std::printf("REG[%d]=0x%08x\n", i, static_cast<unsigned>(top->dbg_data));
    }
    std::printf("REGFILE_END\n");
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    auto *top = new Vtile_ooo_top;

    // 加载阶段保持复位，口令端口默认拉低。
    top->clk = 0;
    top->rst_n = 0;
    top->load_en = 0;

    // 先跑一次 eval()，让 RTL 的 initial 块（imem 上电清零）先执行完，
    // 避免它与后续加载写口在同一首个时钟沿竞争、把已写入的程序清掉。
    top->eval();

    // 1. 确定程序路径：命令行参数优先，其次为编译期默认 PROGRAM_HEX。
    const char *path = nullptr;
    if (argc >= 2)
        path = argv[1];
#ifdef PROGRAM_HEX
    if (!path)
        path = PROGRAM_HEX;
#endif

    // 2. 加载程序；失败则回退到内置单条 HALT。
    int words = -1;
    if (path)
        words = load_hex(top, path);
    if (words < 0) {
        if (path)
            std::fprintf(stderr, "warning: 无法打开程序文件 \"%s\"，回退到内置单条 HALT。\n", path);
        load_word(top, 0, kHaltInst);
        words = 1;
    }
    top->load_en = 0;
    std::printf("已加载 %d 条指令。\n", words);

    // 3. 复位（继续保持若干周期）。
    for (int i = 0; i < 3; ++i)
        cycle(top);
    top->rst_n = 1;

    // 4. 运行至 halted 或超时。
    constexpr int kMaxCycles = 10000;
    int cycles = 0;
    bool ok = false;
    std::printf("复位释放，开始执行...\n");
    for (int c = 1; c <= kMaxCycles; ++c) {
        cycle(top);
        std::printf("[cycle %4d] pc=0x%08x inst=0x%08x halted=%u\n",
                    c, static_cast<unsigned>(top->pc),
                    static_cast<unsigned>(top->inst),
                    static_cast<unsigned>(top->halted));
        if (top->halted) {
            ok = true;
            cycles = c;
            break;
        }
    }

    if (ok) {
        std::printf("SUCCESS: 第 %d 个周期执行 HALT，pc=0x%08x\n",
                    cycles, static_cast<unsigned>(top->pc));
        dump_regfile(top);
    } else {
        std::printf("FAIL: %d 个周期内未观察到 HALT。\n", kMaxCycles);
    }

    top->final();
    delete top;
    return ok ? 0 : 1;
}