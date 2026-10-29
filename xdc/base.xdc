set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]

create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk]

set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports rstn]
set_false_path -from [get_ports rstn]

set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports calib_done]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports dbg_use_buff_a]
#set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports empty]
set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports underflow]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports dbg_use_buff_b]

#set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports led4]
#set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports led5]
#set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports led6]
#set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports led7]

## sw_mode, higher_up_tresh, lower_down_tresh are not ports of test_ov7670_wrapper yet.
## Uncomment once they are added to the block design (avoids CRITICAL WARNING 17-55).
set_property -dict { PACKAGE_PIN A8    IOSTANDARD LVCMOS33 } [get_ports { sw_mode[0] }]; #IO_L12N_T1_MRCC_16 Sch=sw[0]
set_property -dict { PACKAGE_PIN C11   IOSTANDARD LVCMOS33 } [get_ports { sw_mode[1] }]; #IO_L13P_T2_MRCC_16 Sch=sw[1]
set_property -dict { PACKAGE_PIN C10   IOSTANDARD LVCMOS33 } [get_ports { sw_mode[2] }]; #IO_L13N_T2_MRCC_16 Sch=sw[2]
set_property -dict { PACKAGE_PIN A10   IOSTANDARD LVCMOS33 } [get_ports { sw_mode[3] }]; #IO_L14P_T2_SRCC_16 Sch=sw[3]

set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports trig_one_frame_cam]
set_property -dict {PACKAGE_PIN C9 IOSTANDARD LVCMOS33} [get_ports trig_one_frame_vga]
#set_property -dict {PACKAGE_PIN B9 IOSTANDARD LVCMOS33} [get_ports {higher_up_tresh}]
#set_property -dict {PACKAGE_PIN B8 IOSTANDARD LVCMOS33} [get_ports {lower_down_tresh}]


## ============================================================
## async_fifo gray-pointer CDC
## clk_pll_i (MIG ui_clk) and clk_out3 (clk_wiz) both come from sys_clk_pin,
## so Vivado treats them as synchronous and times the crossing against the
## worst edge pair (~3 ns). The crossing is a 2-FF gray-code synchronizer,
## so constrain only the datapath delay and keep the bits aligned with bus skew.
## ============================================================
set_max_delay -datapath_only -from [get_cells -hier -filter {NAME =~ *wr_gray_ptr_reg*}] -to [get_cells -hier -filter {NAME =~ *wr_gray_sync1_reg*}] 12.000
set_max_delay -datapath_only -from [get_cells -hier -filter {NAME =~ *rd_gray_ptr_reg*}] -to [get_cells -hier -filter {NAME =~ *rd_gray_sync1_reg*}] 12.000

set_bus_skew -from [get_cells -hier -filter {NAME =~ *wr_gray_ptr_reg*}] -to [get_cells -hier -filter {NAME =~ *wr_gray_sync1_reg*}] 10.000
set_bus_skew -from [get_cells -hier -filter {NAME =~ *rd_gray_ptr_reg*}] -to [get_cells -hier -filter {NAME =~ *rd_gray_sync1_reg*}] 10.000


## ============================================================
## OV7670 wiring on PMOD JA
## JA1 = SCL
## JA2 = VSYNC
## JA3 = HREF
## JA4 = D7
## JA7 = RESET
## JA8 = D1
## JA9 = D3
## JA10 = D5
## ============================================================

set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33} [get_ports cam_scl]
set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS33} [get_ports cam_vsync]
set_property -dict {PACKAGE_PIN A11 IOSTANDARD LVCMOS33} [get_ports cam_href]
set_property -dict {PACKAGE_PIN D12 IOSTANDARD LVCMOS33} [get_ports {cam_d[7]}]
set_property -dict {PACKAGE_PIN D13 IOSTANDARD LVCMOS33} [get_ports cam_rst]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports {cam_d[1]}]
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS33} [get_ports {cam_d[3]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {cam_d[5]}]

## ============================================================
## OV7670 wiring on PMOD JB

## JB1 = PCLK
## JB2 = SDA
## JB3 = XCLK
## JB4 = D6
## JB7 = D4
## JB8 = D2
## JB9 = D0
## JB10 = PWDN
## ============================================================

set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS33} [get_ports cam_pclk]
set_property -dict {PACKAGE_PIN E16 IOSTANDARD LVCMOS33} [get_ports cam_sda]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports cam_xclk]
set_property -dict {PACKAGE_PIN C15 IOSTANDARD LVCMOS33} [get_ports {cam_d[6]}]
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS33} [get_ports {cam_d[4]}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS33} [get_ports {cam_d[2]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {cam_d[0]}]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports cam_pwdn]


set_property PULLTYPE PULLUP [get_ports cam_sda]
set_property PULLTYPE PULLUP [get_ports cam_scl]
create_clock -period 40.000 -name cam_pclk_clk -waveform {0.000 20.000} [get_ports cam_pclk]

set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks sys_clk_pin] -group [get_clocks cam_pclk_clk]

set_input_delay -clock [get_clocks cam_pclk_clk] -max 10.000 [get_ports {cam_href cam_vsync {cam_d[*]}}]
set_input_delay -clock [get_clocks cam_pclk_clk] -min 0.000 [get_ports {cam_href cam_vsync {cam_d[*]}}]

## ============================================================
## Pmod VGA Digilent
##
## Pmod VGA J1 -> Arty A7 JC
## Pmod VGA J2 -> Arty A7 JD


## JC1 = R0
## JC2 = R1
## JC3 = R2
## JC4 = R3
## JC7 = B0
## JC8 = B1
## JC9 = B2
## JC10 = B3

## JD1 = G0
## JD2 = G1
## JD3 = G2
## JD4 = G3
## JD7 = HSYNC
## JD8 = VSYNC
## ============================================================

set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports {vga_r[0]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {vga_r[1]}]
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports {vga_r[2]}]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports {vga_r[3]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {vga_b[0]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {vga_b[1]}]
set_property -dict {PACKAGE_PIN T13 IOSTANDARD LVCMOS33} [get_ports {vga_b[2]}]
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports {vga_b[3]}]

set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports {vga_g[0]}]
set_property -dict {PACKAGE_PIN D3 IOSTANDARD LVCMOS33} [get_ports {vga_g[1]}]
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33} [get_ports {vga_g[2]}]
set_property -dict {PACKAGE_PIN F3 IOSTANDARD LVCMOS33} [get_ports {vga_g[3]}]

set_property -dict {PACKAGE_PIN E2 IOSTANDARD LVCMOS33} [get_ports vga_hs]
set_property -dict {PACKAGE_PIN D2 IOSTANDARD LVCMOS33} [get_ports vga_vs]
