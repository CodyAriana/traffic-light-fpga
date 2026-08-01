# 验证记录

使用 Vivado 2022.2 XSim 对以下模块进行了编译、仿真和断言检查：

- `crc32`
- `parameter_regs`
- `command_parser`
- `uart_rx`
- `uart_tx`
- `uart_rx_fifo`
- `spi_flash_xfer`
- `flash_record_manager`
- `system_controller`
- `fpga_param_storage_top`

重点覆盖：参数合法性、帧格式和 CRC 错误、UART 收发、Flash A/B 选择、CRC/COMMIT 无效记录、Flash 忙和超时、回读失败、掉电中断保存、系统命令到顶层 UART 响应的完整链路。

最终顶层集成测试已验证：发送 `LOAD_DEFAULT` 请求后，响应头、响应命令、状态码、长度和序号均正确，说明 UART RX → FIFO → 解析器 → 系统控制器 → UART TX 链路已连通。
