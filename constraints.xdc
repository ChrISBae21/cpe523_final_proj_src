set_property PACKAGE_PIN W5        [get_ports clk]
set_property IOSTANDARD LVCMOS33   [get_ports clk]

create_clock -name sys_clk_100MHz -period 10.000 [get_ports clk]

set_property PACKAGE_PIN U18       [get_ports rst_n]
set_property IOSTANDARD LVCMOS33   [get_ports rst_n]
set_property PULLUP true           [get_ports rst_n]

set_property PACKAGE_PIN T18       [get_ports start]
set_property IOSTANDARD LVCMOS33   [get_ports start]

set_property PACKAGE_PIN U16       [get_ports done]
set_property IOSTANDARD LVCMOS33   [get_ports done]