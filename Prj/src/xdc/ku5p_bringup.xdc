# Independent fabric clock on carrier
set_property PACKAGE_PIN T24 [get_ports sys_clk_p]
set_property PACKAGE_PIN U24 [get_ports sys_clk_n]
set_property IOSTANDARD LVDS [get_ports {sys_clk_p sys_clk_n}]
set_property DIFF_TERM_ADV TERM_100 [get_ports sys_clk_p]
create_clock -name sys_clk -period 5.000 [get_ports sys_clk_p]

# JESD GT refclk from HMC7044 BR40_P/N over FMC_GBTCLK1_M2C
set_property PACKAGE_PIN K7 [get_ports jesd_refclk_p]
set_property PACKAGE_PIN K6 [get_ports jesd_refclk_n]
create_clock -name jesd_refclk -period 4.069 [get_ports jesd_refclk_p]
create_generated_clock -name jesd_refclk_mon \
    -source [get_ports jesd_refclk_p] \
    -divide_by 1 \
    [get_pins u_jesd_clock/u_coreclk_bufg/O]
create_clock -name jesd_txoutclk0 -period 4.069 [get_pins u_jesd_txoutclk_bufg0/O]
create_clock -name jesd_txoutclk1 -period 4.069 [get_pins u_jesd_txoutclk_bufg1/O]

# HMC7044 -> FPGA SYSREF
set_property PACKAGE_PIN G24 [get_ports sysref2_p]
set_property PACKAGE_PIN G25 [get_ports sysref2_n]
set_property IOSTANDARD LVDS [get_ports {sysref2_p sysref2_n}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {sysref2_p sysref2_n}]

# AD9173 SYNC inputs to FPGA
# SYNC1 is physically crossed on the latest AD9173 mezzanine:
# DAC_SYNC1_P -> FMC_LA32_N and DAC_SYNC1_N -> FMC_LA32_P.
# Constraints stay on the FPGA package P/N pins; RTL inverts dac_sync1
# after the IBUFDS to recover the active-low JESD SYNC1 polarity.
set_property PACKAGE_PIN C18 [get_ports dac_sync0_p]
set_property PACKAGE_PIN C19 [get_ports dac_sync0_n]
set_property PACKAGE_PIN B15 [get_ports dac_sync1_p]
set_property PACKAGE_PIN A15 [get_ports dac_sync1_n]
set_property IOSTANDARD LVDS [get_ports {dac_sync0_p dac_sync0_n dac_sync1_p dac_sync1_n}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {dac_sync0_p dac_sync0_n dac_sync1_p dac_sync1_n}]

# HMC7044 SPI
set_property PACKAGE_PIN H21 [get_ports clock_cs]
set_property PACKAGE_PIN H22 [get_ports clock_sclk]
set_property PACKAGE_PIN J19 [get_ports clock_sdio]
set_property IOSTANDARD LVCMOS18 [get_ports {clock_cs clock_sclk clock_sdio}]

# AD9173 SPI + control
set_property PACKAGE_PIN D18 [get_ports dac_cs]
set_property PACKAGE_PIN E16 [get_ports dac_sclk]
set_property PACKAGE_PIN A23 [get_ports dac_sdio]
set_property PACKAGE_PIN E17 [get_ports dac_sdo]
# Board rework: AD9173 SPI SDIO is wired on the former RESETB path.
# RESETB is not FPGA-driven in this bring-up; keep the RTL resetb signal
# internal for sequencing/ILA only.
# AD9173 netlist: TXEN_0/1 -> FMC D24/D23 = LA23_N/P -> FPGA B22/C22.
set_property PACKAGE_PIN B22 [get_ports txen_0]
set_property PACKAGE_PIN C22 [get_ports txen_1]
set_property IOSTANDARD LVCMOS18 [get_ports {dac_cs dac_sclk dac_sdio dac_sdo txen_0 txen_1}]

# AD9173 JESD TX
# link0 / lanes0-3 -> quad226 -> DAC_SERDIN0..3
set_property PACKAGE_PIN N5 [get_ports {dac_tx_p[0]}]
set_property PACKAGE_PIN N4 [get_ports {dac_tx_n[0]}]
set_property PACKAGE_PIN L5 [get_ports {dac_tx_p[1]}]
set_property PACKAGE_PIN L4 [get_ports {dac_tx_n[1]}]
set_property PACKAGE_PIN J5 [get_ports {dac_tx_p[2]}]
set_property PACKAGE_PIN J4 [get_ports {dac_tx_n[2]}]
set_property PACKAGE_PIN G5 [get_ports {dac_tx_p[3]}]
set_property PACKAGE_PIN G4 [get_ports {dac_tx_n[3]}]

# link1 / lanes4-7 -> quad227. These package pins follow the board routing
# order SERDIN5, SERDIN7, SERDIN6, SERDIN4; AD9173 register 0x308..0x30B
# remaps that physical order back to logical lanes 4..7.
set_property PACKAGE_PIN F7 [get_ports {dac_tx_p[4]}]
set_property PACKAGE_PIN F6 [get_ports {dac_tx_n[4]}]
set_property PACKAGE_PIN E5 [get_ports {dac_tx_p[5]}]
set_property PACKAGE_PIN E4 [get_ports {dac_tx_n[5]}]
set_property PACKAGE_PIN D7 [get_ports {dac_tx_p[6]}]
set_property PACKAGE_PIN D6 [get_ports {dac_tx_n[6]}]
set_property PACKAGE_PIN B7 [get_ports {dac_tx_p[7]}]
set_property PACKAGE_PIN B6 [get_ports {dac_tx_n[7]}]

# PHY1 1G RGMII path for UDP DAC configuration and waveform download.
# RK-XCKU5P-F V1.2 pin table maps these nets to Bank 66; schematic pages
# show the PHY I/O rail as PHY1_IODVDD with 1.8 V supplies, so constrain as
# LVCMOS18 for the first PL-only UDP bring-up.
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
