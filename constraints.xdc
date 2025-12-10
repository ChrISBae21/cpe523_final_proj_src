## Basys3 constraints for fft1024_core
## Top:
##   input  clk   - on-board clock
##   input  rst_n - active-low reset (center button)
##   input  start - start pulse (up button)
##   output done  - done flag (LED0)

## --------------------------------------------------------------------
## Clock (Basys3 has a 100 MHz oscillator on pin W5)
## --------------------------------------------------------------------
set_property PACKAGE_PIN W5        [get_ports clk]
set_property IOSTANDARD LVCMOS33   [get_ports clk]

create_clock -name sys_clk_50MHz -period 10.000 [get_ports clk]

## --------------------------------------------------------------------
## Reset (active-low) mapped to center pushbutton (BTNC)
## --------------------------------------------------------------------
set_property PACKAGE_PIN U18       [get_ports rst_n]
set_property IOSTANDARD LVCMOS33   [get_ports rst_n]
set_property PULLUP true           [get_ports rst_n]

## --------------------------------------------------------------------
## Start signal mapped to up pushbutton (BTNU)
## --------------------------------------------------------------------
set_property PACKAGE_PIN T18       [get_ports start]
set_property IOSTANDARD LVCMOS33   [get_ports start]

## --------------------------------------------------------------------
## Done flag mapped to LED0
## --------------------------------------------------------------------
set_property PACKAGE_PIN U16       [get_ports done]
set_property IOSTANDARD LVCMOS33   [get_ports done]