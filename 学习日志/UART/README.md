# UART Echo FPGA Project

这是一个独立的 UART 回环项目，面向野火升腾 Mini 开发板和 Vivado 2022.2。

## 功能

- 时钟：50 MHz
- 串口格式：115200 baud，8 数据位，1 停止位，无校验（115200 8N1）
- 接收模块：包含输入同步、起始位中心采样、数据位采样和有效脉冲
- 发送模块：包含空闲、起始位、8 位数据和停止位
- 接收 FIFO：16 字节，用于缓存连续输入的数据
- 回环功能：电脑发送什么，开发板就返回什么
- LED：显示最近收到的字节的低 4 位
- 仿真：包含单字节 `A` 测试和连续 `QWER` 测试

## 文件说明

| 文件 | 作用 |
|---|---|
| `uart_rx.v` | UART 接收模块 |
| `uart_tx.v` | UART 发送模块 |
| `uart_echo_top.v` | 顶层模块和 16 字节 FIFO |
| `uart_echo_top.xdc` | 开发板引脚和时钟约束 |
| `tb_uart_echo_top.v` | 单字节自检仿真 |
| `tb_uart_echo_burst.v` | 连续 QWER 自检仿真 |
| `create_uart_echo_project.tcl` | 自动创建、综合、实现和生成 bit 文件 |

## 开发板引脚

| 信号 | FPGA 引脚 |
|---|---|
| `clk_50m` | `W19` |
| `rst_n` | `Y19` |
| `uart_rx_pin` | `W17` |
| `uart_tx_pin` | `V17` |
| `led[0]` | `N20` |
| `led[1]` | `M20` |
| `led[2]` | `N22` |
| `led[3]` | `M22` |

## 创建 Vivado 工程

在 Vivado 2022.2 的 Tcl Console 中运行：

```tcl
cd E:/Vivado_works/traffic_light/uart_echo
source create_uart_echo_project.tcl
```

脚本会创建 `uart_echo_project`，并自动执行综合、实现和 bit 文件生成。

生成的 `.bit` 文件属于 Vivado 构建产物，已被 Git 忽略；需要烧录时使用本地生成的文件即可。

## 仿真通过标志

成功运行仿真后，Tcl Console 应看到：

```text
TEST_PASS: single byte A was echoed correctly
TEST_PASS: QWER burst was echoed correctly
```

## 串口助手设置

- 串口号：以设备管理器显示的端口为准，例如 `COM4`
- 波特率：`115200`
- 数据位：`8`
- 停止位：`1`
- 校验位：`无`
- 接收模式：文本模式
- 文本编码：建议 UTF-8 或 ASCII

发送 `QWER`，接收区应返回 `QWER`。开发板上的 LED 会根据最近接收字节的低 4 位变化。

## 后续课程：uart_command_ack

`uart_command_ack/` 是在回环项目基础上继续完成的串口命令控制项目。

- 发送 `0`：关闭所有 LED，并回复 `LED OFF`
- 发送 `1`：点亮 LED0，并回复 `LED GREEN`
- 发送 `2`：点亮 LED1，并回复 `LED YELLOW`
- 发送 `3`：点亮 LED2，并回复 `LED RED`
- 发送其他字符：保持 LED 状态，并回复 `ERROR`

该项目新增命令译码器、应答字符串发送状态机和 4 字节应答 FIFO。
