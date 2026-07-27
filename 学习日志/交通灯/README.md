# FPGA Traffic Light Controller

基于野火升腾 Mini 开发板的交通灯状态机项目。

## 项目功能

- 50 MHz 时钟驱动交通灯状态机
- 正常模式：绿灯 5 秒、黄灯 2 秒、红灯 5 秒
- KEY1 按下并释放一次：切换到快速模式
- 快速模式：绿灯 1 秒、黄灯 1 秒、红灯 1 秒
- KEY1 采用低电平有效输入
- 包含按键同步、按键消抖和按键边沿检测
- 包含 Vivado 行为仿真测试文件

## 开发环境

- Vivado 2022.2
- FPGA：XC7A35T-FGG484-2
- 开发板：野火升腾 Mini
- 顶层模块：`traffic_light_top`

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `traffic_light.v` | 交通灯 RTL 主程序 |
| `tb_traffic_light.v` | 行为仿真测试文件 |
| `traffic_light.xdc` | 时钟、按键和 LED 引脚约束 |
| `create_vivado_project.tcl` | 创建 Vivado 工程脚本 |
| `run_sim.tcl` | 仿真脚本 |
| `run_bitstream.tcl` | 综合、实现和 Bitstream 脚本 |
| `program_board.tcl` | 下载开发板脚本 |
| `vivado_project/traffic_light.xpr` | Vivado 工程文件 |

## 使用方法

1. 使用 Vivado 2022.2 打开 `vivado_project/traffic_light.xpr`。
2. 运行 `Run Behavioral Simulation`，确认 Tcl Console 出现：

   ```text
   TEST_PASS: traffic_light full cycle verified
   ```

3. 运行综合、实现并生成 Bitstream。
4. 通过 Hardware Manager 下载到开发板。
5. 松开 KEY1 为正常模式，按下并释放 KEY1 可切换快速模式。

Vivado 的缓存、日志、仿真数据库和 Bitstream 等生成文件已通过 `.gitignore` 排除。
