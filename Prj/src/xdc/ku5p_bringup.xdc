# 载板独立 fabric 时钟，作为系统控制、SPI、状态机和以太网辅助逻辑时钟。
set_property PACKAGE_PIN T24 [get_ports sys_clk_p]
set_property PACKAGE_PIN U24 [get_ports sys_clk_n]
set_property IOSTANDARD LVDS [get_ports {sys_clk_p sys_clk_n}]
set_property DIFF_TERM_ADV TERM_100 [get_ports sys_clk_p]
create_clock -name sys_clk -period 5.000 [get_ports sys_clk_p]

# JESD GT 参考时钟：来自 HMC7044 ch10/BR40_P/N，经 FMC_GBTCLK1_M2C
# 进入 FPGA。频率为 245.76 MHz，对应 JESD204C 9.8304 Gbps 线速。
set_property PACKAGE_PIN K7 [get_ports jesd_refclk_p]
set_property PACKAGE_PIN K6 [get_ports jesd_refclk_n]
create_clock -name jesd_refclk -period 4.069 [get_ports jesd_refclk_p]
create_generated_clock -name jesd_refclk_mon \
    -source [get_ports jesd_refclk_p] \
    -divide_by 1 \
    [get_pins u_jesd_clock/u_coreclk_bufg/O]
create_clock -name jesd_txoutclk0 -period 4.069 [get_pins u_jesd_txoutclk_bufg0/O]
create_clock -name jesd_txoutclk1 -period 4.069 [get_pins u_jesd_txoutclk_bufg1/O]

# HMC7044 -> FPGA SYSREF。该 SYSREF 与送入 AD9173 的 SYSREF 同源，
# 用于 JESD subclass 1 的确定性延迟同步。
set_property PACKAGE_PIN G24 [get_ports sysref2_p]
set_property PACKAGE_PIN G25 [get_ports sysref2_n]
set_property IOSTANDARD LVDS [get_ports {sysref2_p sysref2_n}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {sysref2_p sysref2_n}]

# AD9173 SYNC 输入到 FPGA。SYNC 是 AD9173 deframer 给 FPGA JESD TX 的
# 链路同步反馈信号。
# 最新 AD9173 子板上 SYNC1 差分对物理交叉：
# DAC_SYNC1_P -> FMC_LA32_N，DAC_SYNC1_N -> FMC_LA32_P。
# 约束仍按 FPGA package P/N 管脚写，RTL 在 IBUFDS 后反相 dac_sync1，
# 恢复 active-low JESD SYNC1 极性。
set_property PACKAGE_PIN C18 [get_ports dac_sync0_p]
set_property PACKAGE_PIN C19 [get_ports dac_sync0_n]
set_property PACKAGE_PIN B15 [get_ports dac_sync1_p]
set_property PACKAGE_PIN A15 [get_ports dac_sync1_n]
set_property IOSTANDARD LVDS [get_ports {dac_sync0_p dac_sync0_n dac_sync1_p dac_sync1_n}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {dac_sync0_p dac_sync0_n dac_sync1_p dac_sync1_n}]

# HMC7044 SPI：上电首先通过该 SPI 配置 DAC_CLKIN、SYSREF、JESD refclk。
set_property PACKAGE_PIN H21 [get_ports clock_cs]
set_property PACKAGE_PIN H22 [get_ports clock_sclk]
set_property PACKAGE_PIN J19 [get_ports clock_sdio]
set_property IOSTANDARD LVCMOS18 [get_ports {clock_cs clock_sclk clock_sdio}]

# AD9173 SPI + control：用于初始化 DAC PLL、JESD deframer、NCO、幅度等。
set_property PACKAGE_PIN D18 [get_ports dac_cs]
set_property PACKAGE_PIN E16 [get_ports dac_sclk]
set_property PACKAGE_PIN A23 [get_ports dac_sdio]
set_property PACKAGE_PIN E17 [get_ports dac_sdo]
# 板级改线：AD9173 SPI SDIO 接在原 RESETB 路径上。
# 本工程不再由 FPGA 直接驱动 RESETB，RTL 内部 resetb 只用于时序/ILA 观察。
# AD9173 netlist: TXEN_0/1 -> FMC D24/D23 = LA23_N/P -> FPGA B22/C22。
# TXEN 可用于打开/关闭对应 DAC 输出通道。
set_property PACKAGE_PIN B22 [get_ports txen_0]
set_property PACKAGE_PIN C22 [get_ports txen_1]
set_property IOSTANDARD LVCMOS18 [get_ports {dac_cs dac_sclk dac_sdio dac_sdo txen_0 txen_1}]

# RF 输出控制。
# PE43711 PS 在 RTL 中保持高电平，匹配已验证过的 NCO-only 参考工程。
# B9/output_path_sel 为外部 RF/LF 通路选择控制：0=RF，1=LF。
set_property PACKAGE_PIN C11 [get_ports pe43711_data]
set_property PACKAGE_PIN E11 [get_ports pe43711_clk]
set_property PACKAGE_PIN D11 [get_ports pe43711_le]
set_property PACKAGE_PIN D9 [get_ports pe43711_ps]
set_property PACKAGE_PIN B9 [get_ports output_path_sel]
set_property IOSTANDARD LVCMOS18 [get_ports {pe43711_data pe43711_clk pe43711_le pe43711_ps output_path_sel}]
set_property DRIVE 8 [get_ports {pe43711_data pe43711_clk pe43711_le pe43711_ps output_path_sel}]
set_property SLEW SLOW [get_ports {pe43711_data pe43711_clk pe43711_le pe43711_ps output_path_sel}]

# AD9173 JESD TX。
# link0 / lanes0-3 -> quad226 -> DAC_SERDIN0..3，承载 DAC0/DAC1 payload。
set_property PACKAGE_PIN N5 [get_ports {dac_tx_p[0]}]
set_property PACKAGE_PIN N4 [get_ports {dac_tx_n[0]}]
set_property PACKAGE_PIN L5 [get_ports {dac_tx_p[1]}]
set_property PACKAGE_PIN L4 [get_ports {dac_tx_n[1]}]
set_property PACKAGE_PIN J5 [get_ports {dac_tx_p[2]}]
set_property PACKAGE_PIN J4 [get_ports {dac_tx_n[2]}]
set_property PACKAGE_PIN G5 [get_ports {dac_tx_p[3]}]
set_property PACKAGE_PIN G4 [get_ports {dac_tx_n[3]}]

# link1 / lanes4-7 -> quad227，承载 DAC2/DAC3 payload。
# 这些 FPGA package pins 按板级布线顺序连接到 SERDIN5、SERDIN7、
# SERDIN6、SERDIN4；AD9173 寄存器 0x308..0x30B 会把该物理顺序
# 重新映射回 logical lanes 4..7。
set_property PACKAGE_PIN F7 [get_ports {dac_tx_p[4]}]
set_property PACKAGE_PIN F6 [get_ports {dac_tx_n[4]}]
set_property PACKAGE_PIN E5 [get_ports {dac_tx_p[5]}]
set_property PACKAGE_PIN E4 [get_ports {dac_tx_n[5]}]
set_property PACKAGE_PIN D7 [get_ports {dac_tx_p[6]}]
set_property PACKAGE_PIN D6 [get_ports {dac_tx_n[6]}]
set_property PACKAGE_PIN B7 [get_ports {dac_tx_p[7]}]
set_property PACKAGE_PIN B6 [get_ports {dac_tx_n[7]}]

# PHY1 1G RGMII：用于 HostApp UDP DAC 配置和 RAM 波形下载。
# RK-XCKU5P-F V1.2 pin 表把这些网络映射到 Bank 66；原理图显示 PHY I/O
# 电源为 1.8 V，因此约束为 LVCMOS18。
set_property PACKAGE_PIN M25 [get_ports phy1_txck]
set_property PACKAGE_PIN M26 [get_ports phy1_txctl]
set_property PACKAGE_PIN L23 [get_ports {phy1_txd[0]}]
set_property PACKAGE_PIN L22 [get_ports {phy1_txd[1]}]
set_property PACKAGE_PIN L20 [get_ports {phy1_txd[2]}]
set_property PACKAGE_PIN K20 [get_ports {phy1_txd[3]}]
set_property PACKAGE_PIN K22 [get_ports phy1_rxck]
set_property PACKAGE_PIN K23 [get_ports phy1_rxctl]
set_property PACKAGE_PIN L24 [get_ports {phy1_rxd[0]}]
set_property PACKAGE_PIN L25 [get_ports {phy1_rxd[1]}]
set_property PACKAGE_PIN K25 [get_ports {phy1_rxd[2]}]
set_property PACKAGE_PIN K26 [get_ports {phy1_rxd[3]}]
set_property PACKAGE_PIN L19 [get_ports phy1_mdc]
set_property PACKAGE_PIN M19 [get_ports phy1_mdio]
set_property IOSTANDARD LVCMOS18 [get_ports {phy1_txck phy1_txctl phy1_txd[*] phy1_rxck phy1_rxctl phy1_rxd[*] phy1_mdc phy1_mdio}]
set_property SLEW FAST [get_ports {phy1_txck phy1_txctl phy1_txd[*]}]
set_property DRIVE 8 [get_ports {phy1_txck phy1_txctl phy1_txd[*] phy1_mdc}]
create_clock -name phy1_rxck -period 8.000 [get_ports phy1_rxck]
create_generated_clock -name eth_tx_clk \
    -source [get_pins u_eth_clk_125/u_mmcm/CLKIN1] \
    -multiply_by 5 -divide_by 8 \
    [get_pins u_eth_clk_125/u_clk125_buf/O]
create_generated_clock -name phy1_txck_out \
    -source [get_pins u_phy1_rgmii_tx/u_clk_oddr/CLK] \
    -divide_by 1 \
    [get_ports phy1_txck]

# RGMII v2.0 TX uses a centered clock. Data/TXCTL are launched from the
# non-shifted 125 MHz clock, while TXCK is forwarded later through an ODDR.
# Model the capture clock from the actual TXCK ODDR clock pin so Vivado
# accounts for the real forwarded-clock insertion path.
# The routed TXCK edge is about 1.3 ns later than TXD/TXCTL at the pins in
# this implementation.  Model that board-level RGMII-ID relationship so the
# source-synchronous output hold check matches the actual forwarded clock.
set_output_delay -clock [get_clocks phy1_txck_out] -max 1.000 [get_ports {phy1_txctl phy1_txd[*]}]
set_output_delay -clock [get_clocks phy1_txck_out] -min 1.500 [get_ports {phy1_txctl phy1_txd[*]}]
set_output_delay -clock [get_clocks phy1_txck_out] -clock_fall -max 1.000 -add_delay [get_ports {phy1_txctl phy1_txd[*]}]
set_output_delay -clock [get_clocks phy1_txck_out] -clock_fall -min 1.500 -add_delay [get_ports {phy1_txctl phy1_txd[*]}]
set_input_delay -clock [get_clocks phy1_rxck] -max 2.000 [get_ports {phy1_rxctl phy1_rxd[*]}]
# The RTL8211F RGMII-ID receive path is expected to present RXD/RXCTL with
# positive hold relative to RXC. Model a small external minimum delay instead
# of the impossible simultaneous-switching case; the FPGA also inserts a fixed
# IDELAYE3 at the receive pins to center the sampling point.
set_input_delay -clock [get_clocks phy1_rxck] -min 0.500 [get_ports {phy1_rxctl phy1_rxd[*]}]
set_input_delay -clock [get_clocks phy1_rxck] -clock_fall -max 2.000 -add_delay [get_ports {phy1_rxctl phy1_rxd[*]}]
set_input_delay -clock [get_clocks phy1_rxck] -clock_fall -min 0.500 -add_delay [get_ports {phy1_rxctl phy1_rxd[*]}]
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks {jesd_refclk jesd_refclk_mon jesd_txoutclk0 jesd_txoutclk1}] \
    -group [get_clocks {eth_tx_clk phy1_txck_out}] \
    -group [get_clocks phy1_rxck]
