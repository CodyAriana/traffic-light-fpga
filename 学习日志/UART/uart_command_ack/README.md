# UART command controller with acknowledgements

This is a new lesson copied from `uart_command`. It keeps the UART receiver
and transmitter, but replaces the one-byte echo with readable ASCII replies.

Serial settings: 115200 baud, 8 data bits, 1 stop bit, no parity.

| Input | LED result | Reply |
| --- | --- | --- |
| `0` | all LEDs off | `LED OFF` |
| `1` | LED0 on | `LED GREEN` |
| `2` | LED1 on | `LED YELLOW` |
| `3` | LED2 on | `LED RED` |
| other | keep current LED | `ERROR` |

Every reply ends with CR/LF so that a serial terminal starts a new line.

## File roles

- `uart_rx.v`: UART receiver
- `uart_tx.v`: UART transmitter
- `uart_cmd_decoder_ack.v`: command and response-code decoder
- `uart_response_tx.v`: fixed-string response state machine
- `uart_command_ack_top.v`: top-level wiring and four-entry response FIFO
- `tb_uart_command_ack_top.v`: automated LED and response simulation
- `uart_command_ack_top.xdc`: Ascend Mini pin constraints
- `create_uart_command_ack_project.tcl`: Vivado project and bitstream build
