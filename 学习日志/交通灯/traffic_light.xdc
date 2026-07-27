## ============================================================
## 野火升腾 Mini：交通灯状态机引脚约束
## FPGA：XC7A35T-FGG484-2
## ============================================================

## 50 MHz 系统时钟：一个周期为 20 ns
set_property PACKAGE_PIN W19 [get_ports clk_50m]
set_property IOSTANDARD LVCMOS33 [get_ports clk_50m]
create_clock -period 20.000 -name clk_50m [get_ports clk_50m]

## 低电平有效复位
set_property PACKAGE_PIN Y19 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

## KEY1~KEY4：按下时为低电平，当前实验预留给后续手动控制
set_property PACKAGE_PIN R16 [get_ports {key_n[0]}]
set_property PACKAGE_PIN P15 [get_ports {key_n[1]}]
set_property PACKAGE_PIN T20 [get_ports {key_n[2]}]
set_property PACKAGE_PIN Y18 [get_ports {key_n[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key_n[*]}]

## LED1=绿灯，LED2=黄灯，LED3=红灯，LED4不使用
set_property PACKAGE_PIN N20 [get_ports {led[0]}]
set_property PACKAGE_PIN M20 [get_ports {led[1]}]
set_property PACKAGE_PIN N22 [get_ports {led[2]}]
set_property PACKAGE_PIN M22 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## FPGA 配置参数
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
