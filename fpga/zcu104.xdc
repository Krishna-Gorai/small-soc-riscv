# Small_SoC on the ZCU104 (xczu7ev-ffvc1156-2-e).
# Pin locations and I/O standards from the Vivado board file
# XilinxBoardStore/boards/Xilinx/zcu104/1.1/part0_pins.xml.

# ---- 300 MHz differential system clock (DDR4 bank, 1.2 V) ----
set_property -dict {PACKAGE_PIN AH18 IOSTANDARD DIFF_SSTL12} [get_ports clk300_p]
set_property -dict {PACKAGE_PIN AH17 IOSTANDARD DIFF_SSTL12} [get_ports clk300_n]
create_clock -period 3.333 -name clk300 [get_ports clk300_p]
# The 100 MHz SoC clock is derived automatically from the BUFGCE_DIV.

# ---- CPU_RESET push button (active high) ----
set_property -dict {PACKAGE_PIN M11 IOSTANDARD LVCMOS33} [get_ports cpu_reset]

# ---- DIP switches ----
set_property -dict {PACKAGE_PIN E4 IOSTANDARD LVCMOS33} [get_ports {dip[0]}]
set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports {dip[1]}]
set_property -dict {PACKAGE_PIN F5 IOSTANDARD LVCMOS33} [get_ports {dip[2]}]
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33} [get_ports {dip[3]}]

# ---- push buttons ----
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS33} [get_ports {pb[0]}]
set_property -dict {PACKAGE_PIN C4 IOSTANDARD LVCMOS33} [get_ports {pb[1]}]
set_property -dict {PACKAGE_PIN B3 IOSTANDARD LVCMOS33} [get_ports {pb[2]}]
set_property -dict {PACKAGE_PIN C3 IOSTANDARD LVCMOS33} [get_ports {pb[3]}]

# ---- LEDs ----
set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN D6 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN B5 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

# ---- UART, PL channel of the CP2108 USB-UART bridge (1.8 V bank) ----
set_property -dict {PACKAGE_PIN C19 IOSTANDARD LVCMOS18} [get_ports uart_tx]
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS18} [get_ports uart_rx]

# ---- asynchronous board I/O: no timing requirement ----
set_false_path -from [get_ports {cpu_reset dip[*] pb[*] uart_rx}]
set_false_path -to   [get_ports {led[*] uart_tx}]

# ---- JTAG debug port: BSCANE2 TCK is an independent clock ----
# The hardware manager's default TCK is 15 MHz; constrain at 30 MHz for margin.
create_clock -period 33.333 -name jtag_tck [get_pins u_bscan/TCK]
set_clock_groups -asynchronous -group [get_clocks jtag_tck] \
                               -group [get_clocks -include_generated_clocks clk300]
