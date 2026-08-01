# FPGA 参数存储系统

面向 Artix-7 XC7A35T-FGG484-2 开发板的可掉电保存参数系统。电脑通过 USB-UART 修改运行参数，系统可以把参数写入板载 SPI NOR Flash，并在下次上电时自动恢复。

## 功能

- UART 115200 baud，8N1
- UART 命令帧和响应帧带 CRC32
- 参数写入前进行范围检查
- 双备份 Flash 记录区，保存到另一个扇区后再提交 COMMIT 标记
- 上电扫描两个记录区，选择 CRC、版本、COMMIT 都正确且序号最新的记录
- Flash WIP 轮询具备超时保护
- 完整 RTL 单元仿真、系统级仿真和顶层 UART 集成仿真

## 目录

| 目录 | 内容 |
|---|---|
| `rtl/` | 可综合 Verilog 模块 |
| `sim/` | XSim 测试文件 |
| `constr/` | 开发板引脚和时钟约束 |
| `scripts/` | 创建 Vivado 工程的 Tcl 脚本 |
| `docs/` | 协议、Flash 记录格式和验证记录 |

## 创建 Vivado 工程

在 Vivado 2022.2 Tcl Console 中执行：

```tcl
cd E:/Vivado_works/fpga_param_storage
source scripts/create_fpga_param_storage_project.tcl
```

工程会创建在 `vivado_project/`，综合顶层为 `fpga_param_storage_top`。生成 bitstream 后使用 **Program Device** 下载 FPGA，不要把 bitstream 当作 Flash 参数记录去烧写。

## 板级接口

- UART RX：W17
- UART TX：V17
- SPI Flash CS：T19
- SPI Flash IO0/IO1/IO2/IO3：P22/R22/P21/R21
- LED0/LED1/LED2/LED3：N20/M20/N22/M22

Flash 时钟由 `STARTUPE2` 连接到 FPGA 的专用 CCLK 路径，因此顶层没有普通 `flash_sck` 端口。

LED 状态：`led[0]` 表示系统忙，`led[1]` 表示 UART 正在发送，`led[2]` 表示当前参数有效，`led[3]` 表示最近一次错误状态非零。

## 参数默认值

`mode=0`、绿灯 5 秒、黄灯 2 秒、红灯 5 秒、`device_id=1001`。参数修改只改变 RAM 中的当前值，只有执行 `SAVE_FLASH` 才会写入非易失 Flash。

## 重要说明

仿真和 Vivado 工程已经完成验证；最终 bitstream 下载到实际开发板后，还需要用串口助手按 `docs/protocol.md` 发送命令做一次板级验证。
