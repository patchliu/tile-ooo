# 仿真可执行目标（阶段 1：跑通 HALT）。
#
# 依赖：Verilator（>= 5.0）、CMake、Ninja、C++ 编译器。
# 构建与运行：
#   cmake -S . -B build -G Ninja        # 在仓库根目录执行
#   cmake --build build
#   ./build/sim/verilator/tile_ooo_sim
#
# 也可用命令行参数指定其他 .hex 程序文件：
#   ./build/sim/verilator/tile_ooo_sim path/to/program.hex

find_package(verilator REQUIRED)

get_filename_component(RTL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/core" ABSOLUTE)

add_executable(tile_ooo_sim main.cpp)

verilate(tile_ooo_sim
    SOURCES
        "${RTL_DIR}/isa_pkg.sv"
        "${RTL_DIR}/regfile.sv"
        "${RTL_DIR}/fetch_decode.sv"
        "${RTL_DIR}/scalar_pipeline.sv"
        "${RTL_DIR}/tile_ooo_top.sv"
    TOP_MODULE tile_ooo_top
    PREFIX Vtile_ooo_top
    VERILATOR_ARGS -Wall
)

# 默认程序：阶段 2 为 ADDI 冒烟（programs/smoke/addi.hex）。
get_filename_component(PROGRAM_HEX_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../programs/smoke/addi.hex" ABSOLUTE)
target_compile_definitions(tile_ooo_sim PRIVATE PROGRAM_HEX="${PROGRAM_HEX_PATH}")