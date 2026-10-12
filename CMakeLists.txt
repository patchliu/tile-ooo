cmake_minimum_required(VERSION 3.16)

project(tile_ooo LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# 阶段 1：仿真骨架（跑通 HALT）。只包含 RTL 前端 + Verilator harness + 单条程序。
# 后续阶段再逐步加入 rtl/memory、rtl/tensor、tests、tools 等子目录。
add_subdirectory(sim/verilator)