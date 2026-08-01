## Wildfire Ascend Mini / XC7A35T-FGG484-2
## Board pins verified against the existing traffic-light and SPI projects.

set_property PACKAGE_PIN W19 [get_ports clk_50m]
set_property IOSTANDARD LVCMOS33 [get_ports clk_50m]
create_clock -period 20.000 -name clk_50m [get_ports clk_50m]

set_property PACKAGE_PIN Y19 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

set_property PACKAGE_PIN W17 [get_ports uart_rx_pin]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_pin]
set_property PACKAGE_PIN V17 [get_ports uart_tx_pin]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_pin]

set_property PACKAGE_PIN T19 [get_ports flash_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports flash_cs_n]
set_property PACKAGE_PIN P22 [get_ports flash_io0]
set_property IOSTANDARD LVCMOS33 [get_ports flash_io0]
set_property PACKAGE_PIN R22 [get_ports flash_io1]
set_property IOSTANDARD LVCMOS33 [get_ports flash_io1]
set_property PACKAGE_PIN P21 [get_ports flash_io2]
set_property IOSTANDARD LVCMOS33 [get_ports flash_io2]
set_property PACKAGE_PIN R21 [get_ports flash_io3]
set_property IOSTANDARD LVCMOS33 [get_ports flash_io3]

set_property PACKAGE_PIN N20 [get_ports {led[0]}]
set_property PACKAGE_PIN M20 [get_ports {led[1]}]
set_property PACKAGE_PIN N22 [get_ports {led[2]}]
set_property PACKAGE_PIN M22 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
