# UART 协议

串口设置：115200 baud、8 数据位、1 停止位、无校验、无流控。所有多字节数值按小端序发送。

## 请求帧

```text
55 AA 01 CMD LEN_L LEN_H SEQ PAYLOAD CRC0 CRC1 CRC2 CRC3
```

CRC32 从 `01` 开始计算，覆盖 `VERSION、CMD、LEN_L、LEN_H、SEQ、PAYLOAD`，多项式为反射形式 `0xEDB88320`，初值 `FFFFFFFF`，结果异或 `FFFFFFFF`，然后低字节先发送。

## 命令

| CMD | 名称 | 负载 |
|---:|---|---|
| `01` | GET_STATUS | 无 |
| `02` | READ_PARAM | 无 |
| `03` | WRITE_PARAM | 11 字节参数 |
| `04` | SAVE_FLASH | 无 |
| `05` | LOAD_FLASH | 无 |
| `06` | LOAD_DEFAULT | 无 |

11 字节参数顺序：

```text
mode, green_time_L, green_time_H,
yellow_time_L, yellow_time_H,
red_time_L, red_time_H,
device_id_0, device_id_1, device_id_2, device_id_3
```

## 响应帧

```text
55 AA (CMD + 80) STATUS LEN_L LEN_H SEQ PAYLOAD CRC0 CRC1 CRC2 CRC3
```

状态码：`00` 成功，`01` 帧或 CRC 错误，`02` 非法命令，`03` 参数范围错误，`04` Flash 忙或超时，`05` Flash 回读校验失败，`06` 没有有效 Flash 记录。
