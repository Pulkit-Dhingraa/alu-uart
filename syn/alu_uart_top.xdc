## alu_uart_top.xdc — Nexys 4 (XC7A100T-1CSG324C)
## Pin names match the Digilent master XDC.

## 100 MHz clock -> 10 ns period. This is the timing target Vivado checks every path against.
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -name sys_clk -period 10.000 -waveform {0 5} [get_ports clk]

## CPU_RESET button (active-low)
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports cpu_resetn]

## USB-UART bridge. Names are from the FPGA's point of view:
##   board signal UART_TXD_IN  (PC -> FPGA) = our input  uart_rxd
##   board signal UART_RXD_OUT (FPGA -> PC) = our output uart_txd
set_property -dict { PACKAGE_PIN C4  IOSTANDARD LVCMOS33 } [get_ports uart_rxd]
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports uart_txd]

## The reset button and the UART line are asynchronous to our clock: they go through
## 2-flop synchronisers inside the design, so there is no clock relationship to time.
set_false_path -from [get_ports {cpu_resetn uart_rxd}]
set_false_path -to   [get_ports uart_txd]

## Bank voltage settings (removes a DRC warning)
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
