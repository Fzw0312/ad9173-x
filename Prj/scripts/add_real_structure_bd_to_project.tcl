# Add a real-structure Block Design to the existing Vivado project.
#
# This BD is meant for engineering inspection. It uses actual Xilinx IP cells
# for JESD204C/PHY/MicroBlaze/VIO and actual RTL module-reference cells for
# the custom logic that Vivado allows in BD. The existing RTL top remains the
# implementation top for bitstream generation.
#
# DDS note:
# The real design does not instantiate a top-level DDS Compiler cell. DDS lives
# inside pattern_gen_256 -> dds48_phase_to_sine_quad -> dds_phase_to_sine XCI.
# Vivado BD module references do not expand those nested RTL/IP internals, so
# the implementation-consistent top-level BD shows DDS as part of pattern_gen_256.
#
# Usage:
#   vivado -mode batch -source Prj/scripts/add_real_structure_bd_to_project.tcl

set origin_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $origin_dir ..]]
set xpr_path   [file normalize [file join $prj_dir .. build vivado ad9173_dac_only ku5p_vivado ku5p_dac_only.xpr]]
set bd_name    ku5p_real_structure_bd

if {[info exists ::env(KU5P_PRJ_DIR)] && $::env(KU5P_PRJ_DIR) ne ""} {
    set prj_dir [file normalize $::env(KU5P_PRJ_DIR)]
    set xpr_path [file normalize [file join $prj_dir .. build vivado ad9173_dac_only ku5p_vivado ku5p_dac_only.xpr]]
}
if {[info exists ::env(KU5P_XPR)] && $::env(KU5P_XPR) ne ""} {
    set xpr_path [file normalize $::env(KU5P_XPR)]
}
if {[info exists ::env(KU5P_REAL_BD_NAME)] && $::env(KU5P_REAL_BD_NAME) ne ""} {
    set bd_name $::env(KU5P_REAL_BD_NAME)
}

if {![file exists $xpr_path]} {
    error "Vivado project not found: $xpr_path"
}

open_project $xpr_path
update_compile_order -fileset sources_1

proc remove_bd_if_present {name} {
    set bd_files [get_files -quiet "*${name}.bd"]
    if {[llength $bd_files] > 0} {
        remove_files -quiet $bd_files
    }
    set bd_dir [file join [get_property DIRECTORY [current_project]] \
        "[get_property NAME [current_project]].srcs" sources_1 bd $name]
    if {[file exists $bd_dir]} {
        file delete -force $bd_dir
    }
}

foreach old_bd {ad9173_system_overview ku5p_bringup_real_bd probe_module_refs} {
    remove_bd_if_present $old_bd
}
remove_bd_if_present $bd_name

create_bd_design $bd_name
current_bd_design $bd_name

proc module_cell {ref name} {
    puts "INFO: adding RTL module reference $name ($ref)"
    return [create_bd_cell -type module -reference $ref $name]
}

proc ip_cell {vlnv name props} {
    puts "INFO: adding IP cell $name ($vlnv)"
    set c [create_bd_cell -type ip -vlnv $vlnv $name]
    if {[llength $props] > 0} {
        set_property -dict $props $c
    }
    return $c
}

proc pin_exists {pin_path} {
    expr {[llength [get_bd_pins -quiet $pin_path]] > 0}
}

proc intf_exists {pin_path} {
    expr {[llength [get_bd_intf_pins -quiet $pin_path]] > 0}
}

proc try_connect {src dst net_name} {
    if {[pin_exists $src] && [pin_exists $dst]} {
        set net [get_bd_nets -quiet $net_name]
        if {[llength $net] == 0} {
            create_bd_net $net_name
        }
        catch {connect_bd_net -net $net_name [get_bd_pins $src] [get_bd_pins $dst]}
    } else {
        puts "WARN: skip missing pin connection $src -> $dst"
    }
}

proc ensure_ext_port {name dir type width freq_hz polarity} {
    set p [get_bd_ports -quiet $name]
    if {[llength $p] == 0} {
        set args [list create_bd_port -dir $dir]
        if {$type ne ""} {
            lappend args -type $type
        }
        if {$type eq "clk" && $freq_hz ne ""} {
            lappend args -freq_hz $freq_hz
        }
        if {$width ne "" && $width > 1} {
            lappend args -from [expr {$width - 1}] -to 0
        }
        lappend args $name
        set p [eval $args]
    }
    if {$freq_hz ne ""} {
        catch {set_property CONFIG.FREQ_HZ $freq_hz $p}
    }
    if {$polarity ne ""} {
        catch {set_property CONFIG.POLARITY $polarity $p}
    }
    return $p
}

proc connect_port_to_pin {port_name pin_path net_name} {
    if {[pin_exists $pin_path] && [llength [get_bd_ports -quiet $port_name]] > 0} {
        set net [get_bd_nets -quiet $net_name]
        if {[llength $net] == 0} {
            create_bd_net $net_name
        }
        catch {connect_bd_net -net $net_name [get_bd_ports $port_name] [get_bd_pins $pin_path]}
    } else {
        puts "WARN: skip missing port/pin connection $port_name -> $pin_path"
    }
}

proc connect_port_to_pins {port_name pin_paths net_name} {
    foreach pin_path $pin_paths {
        connect_port_to_pin $port_name $pin_path $net_name
    }
}

proc expose_pin {pin_path port_name dir type width freq_hz polarity} {
    if {[pin_exists $pin_path]} {
        ensure_ext_port $port_name $dir $type $width $freq_hz $polarity
        connect_port_to_pin $port_name $pin_path net_ext_$port_name
    } else {
        puts "WARN: skip exposing missing pin $pin_path"
    }
}

proc try_connect_intf {src dst} {
    if {[intf_exists $src] && [intf_exists $dst]} {
        catch {connect_bd_intf_net [get_bd_intf_pins $src] [get_bd_intf_pins $dst]}
    } else {
        puts "WARN: skip missing interface connection $src -> $dst"
    }
}

proc make_ext_pin {cell_pin name} {
    if {[pin_exists $cell_pin]} {
        catch {make_bd_pins_external -name $name [get_bd_pins $cell_pin]}
    }
}

# Custom RTL cells that map directly to files under Prj/src/rtl.
module_cell eth_clk_125              eth_clk_125_0
module_cell rgmii_rx                 rgmii_rx_0
module_cell rgmii_tx                 rgmii_tx_0
module_cell k5wg_udp_dac_config_rx   udp_cfg_rx_0
module_cell mb_io_dac_regs           mb_io_dac_regs_0
module_cell hmc7044_init             hmc7044_init_0
module_cell ad9173_init              ad9173_init_0
module_cell jesd204_tx_init_link0    jesd204_tx_init_link0_0
module_cell jesd204_tx_init_link1    jesd204_tx_init_link1_0
module_cell jesd_phy_tx_axi_init     jesd_phy_tx_axi_init0_0
module_cell jesd_phy_tx_axi_init     jesd_phy_tx_axi_init1_0
module_cell pattern_gen_256          pattern_gen_256_0
module_cell tx_mapper                tx_mapper_0

# Xilinx IP cells with the same core choices/configuration as build_dac_udp.tcl.
ip_cell xilinx.com:ip:microblaze_mcs:3.0 mb_mcs_ctrl_bd [list \
    CONFIG.MEMSIZE {16384} \
    CONFIG.USE_IO_BUS {1} \
    CONFIG.DEBUG_ENABLED {1} \
    CONFIG.USE_BSCAN {0}]

ip_cell xilinx.com:ip:vio:3.0 runtime_vio_bd [list \
    CONFIG.C_NUM_PROBE_IN {7} \
    CONFIG.C_NUM_PROBE_OUT {15} \
    CONFIG.C_PROBE_IN0_WIDTH {32} \
    CONFIG.C_PROBE_IN1_WIDTH {32} \
    CONFIG.C_PROBE_IN2_WIDTH {32} \
    CONFIG.C_PROBE_IN3_WIDTH {32} \
    CONFIG.C_PROBE_IN4_WIDTH {32} \
    CONFIG.C_PROBE_IN5_WIDTH {32} \
    CONFIG.C_PROBE_IN6_WIDTH {32} \
    CONFIG.C_PROBE_OUT0_WIDTH {16} \
    CONFIG.C_PROBE_OUT1_WIDTH {48} \
    CONFIG.C_PROBE_OUT2_WIDTH {16} \
    CONFIG.C_PROBE_OUT3_WIDTH {48} \
    CONFIG.C_PROBE_OUT4_WIDTH {4} \
    CONFIG.C_PROBE_OUT5_WIDTH {1} \
    CONFIG.C_PROBE_OUT6_WIDTH {1} \
    CONFIG.C_PROBE_OUT7_WIDTH {48} \
    CONFIG.C_PROBE_OUT8_WIDTH {48} \
    CONFIG.C_PROBE_OUT9_WIDTH {32} \
    CONFIG.C_PROBE_OUT10_WIDTH {16} \
    CONFIG.C_PROBE_OUT11_WIDTH {8} \
    CONFIG.C_PROBE_OUT12_WIDTH {1} \
    CONFIG.C_PROBE_OUT13_WIDTH {48} \
    CONFIG.C_PROBE_OUT14_WIDTH {48}]

set jesd_props [list \
    CONFIG.C_NODE_IS_TRANSMIT {1} \
    CONFIG.C_LANES {4} \
    CONFIG.Transceiver {GTYE4} \
    CONFIG.AXICLK_FREQ {200.0} \
    CONFIG.GT_Line_Rate {9.8304} \
    CONFIG.GT_REFCLK_FREQ {245.76} \
    CONFIG.GT_REFCLK_FREQ_REQUEST {245.76} \
    CONFIG.DRPCLK_FREQ {200.0} \
    CONFIG.C_PLL_SELECTION {1} \
    CONFIG.C_ENCODING {0} \
    CONFIG.C_USE_FEC {false}]
ip_cell xilinx.com:ip:jesd204c:4.2 jesd204c_tx_link0_bd $jesd_props
ip_cell xilinx.com:ip:jesd204c:4.2 jesd204c_tx_link1_bd $jesd_props

set phy_props0 [list \
    CONFIG.AXICLK_FREQ {200.0} \
    CONFIG.Axi_Lite {true} \
    CONFIG.C_LANES {4} \
    CONFIG.GT_Location {X0Y0} \
    CONFIG.Transceiver {GTYE4} \
    CONFIG.SupportLevel {1} \
    CONFIG.GT_Line_Rate {9.8304} \
    CONFIG.GT_REFCLK_FREQ {245.76} \
    CONFIG.C_PLL_SELECTION {1} \
    CONFIG.RX_GT_REFCLK_FREQ {245.76} \
    CONFIG.RX_GT_Line_Rate {9.8304} \
    CONFIG.RX_PLL_SELECTION {1} \
    CONFIG.DRPCLK_FREQ {200.0} \
    CONFIG.TransceiverControl {true} \
    CONFIG.Tx_JesdVersion {1} \
    CONFIG.Rx_JesdVersion {1} \
    CONFIG.Tx_use_64b {0} \
    CONFIG.Rx_use_64b {0}]
set phy_props1 [string map {X0Y0 X0Y4} $phy_props0]
ip_cell xilinx.com:ip:jesd204_phy:4.0 jesd204_phy_tx_quad226_bd $phy_props0
ip_cell xilinx.com:ip:jesd204_phy:4.0 jesd204_phy_tx_quad227_bd $phy_props1

# Main implemented datapath.
try_connect rgmii_rx_0/rx_data udp_cfg_rx_0/rx_data net_rx_data
try_connect rgmii_rx_0/rx_valid udp_cfg_rx_0/rx_valid net_rx_valid
try_connect rgmii_rx_0/rx_error udp_cfg_rx_0/rx_error net_rx_error

foreach n {cfg_valid cfg_reset_phase cfg_ram_mode cfg_phase_inc0 cfg_phase_inc1 cfg_phase_inc2 cfg_phase_inc3 cfg_scale0 cfg_scale1 cfg_scale2 cfg_scale3} {
    try_connect udp_cfg_rx_0/$n pattern_gen_256_0/$n net_udp_to_pattern_$n
}
try_connect udp_cfg_rx_0/wave_wr_en pattern_gen_256_0/wave_wr_en net_wave_wr_en
try_connect udp_cfg_rx_0/wave_wr_addr pattern_gen_256_0/wave_wr_addr net_wave_wr_addr
try_connect udp_cfg_rx_0/wave_wr_data pattern_gen_256_0/wave_wr_data net_wave_wr_data
try_connect udp_cfg_rx_0/wave_total_samples pattern_gen_256_0/wave_total_samples net_wave_total_samples
try_connect udp_cfg_rx_0/wave_commit_toggle pattern_gen_256_0/wave_commit_toggle net_wave_commit

try_connect pattern_gen_256_0/data_out tx_mapper_0/data_in net_dac_samples_256
try_connect tx_mapper_0/data_out0 jesd204c_tx_link0_bd/tx_tdata net_jesd_tdata0
try_connect tx_mapper_0/data_out1 jesd204c_tx_link1_bd/tx_tdata net_jesd_tdata1

try_connect jesd204c_tx_link0_bd/tx_reset_gt jesd204_phy_tx_quad226_bd/tx_reset_gt net_link0_tx_reset_gt
try_connect jesd204c_tx_link1_bd/tx_reset_gt jesd204_phy_tx_quad227_bd/tx_reset_gt net_link1_tx_reset_gt
try_connect jesd204c_tx_link0_bd/tx_reset_done jesd204_phy_tx_quad226_bd/tx_reset_done net_link0_tx_reset_done
try_connect jesd204c_tx_link1_bd/tx_reset_done jesd204_phy_tx_quad227_bd/tx_reset_done net_link1_tx_reset_done

foreach i {0 1 2 3} {
    try_connect jesd204c_tx_link0_bd/gt${i}_txdata jesd204_phy_tx_quad226_bd/gt${i}_txdata net_l0_gt${i}_txdata
    try_connect jesd204c_tx_link0_bd/gt${i}_txcharisk jesd204_phy_tx_quad226_bd/gt${i}_txcharisk net_l0_gt${i}_txcharisk
    try_connect jesd204c_tx_link0_bd/gt${i}_txheader jesd204_phy_tx_quad226_bd/gt${i}_txheader net_l0_gt${i}_txheader
    try_connect jesd204c_tx_link1_bd/gt${i}_txdata jesd204_phy_tx_quad227_bd/gt${i}_txdata net_l1_gt${i}_txdata
    try_connect jesd204c_tx_link1_bd/gt${i}_txcharisk jesd204_phy_tx_quad227_bd/gt${i}_txcharisk net_l1_gt${i}_txcharisk
    try_connect jesd204c_tx_link1_bd/gt${i}_txheader jesd204_phy_tx_quad227_bd/gt${i}_txheader net_l1_gt${i}_txheader
}

# Slow-control island implemented as MicroBlaze MCS IP + mb_io_dac_regs RTL.
try_connect mb_mcs_ctrl_bd/IO_addr_strobe mb_io_dac_regs_0/io_addr_strobe net_mb_io_addr_strobe
try_connect mb_mcs_ctrl_bd/IO_address mb_io_dac_regs_0/io_address net_mb_io_address
try_connect mb_mcs_ctrl_bd/IO_byte_enable mb_io_dac_regs_0/io_byte_enable net_mb_io_byte_enable
try_connect mb_io_dac_regs_0/io_read_data mb_mcs_ctrl_bd/IO_read_data net_mb_io_read_data
try_connect mb_mcs_ctrl_bd/IO_read_strobe mb_io_dac_regs_0/io_read_strobe net_mb_io_read_strobe
try_connect mb_io_dac_regs_0/io_ready mb_mcs_ctrl_bd/IO_ready net_mb_io_ready
try_connect mb_mcs_ctrl_bd/IO_write_data mb_io_dac_regs_0/io_write_data net_mb_io_write_data
try_connect mb_mcs_ctrl_bd/IO_write_strobe mb_io_dac_regs_0/io_write_strobe net_mb_io_write_strobe

# AXI-Lite programming paths used by the original top-level init engines.
foreach prefix {jesd0 jesd1} cell {jesd204_tx_init_link0_0 jesd204_tx_init_link1_0} ip {jesd204c_tx_link0_bd jesd204c_tx_link1_bd} {
    try_connect ${cell}/s_axi_awaddr  ${ip}/s_axi_awaddr  net_${prefix}_s_axi_awaddr
    try_connect ${cell}/s_axi_awvalid ${ip}/s_axi_awvalid net_${prefix}_s_axi_awvalid
    try_connect ${ip}/s_axi_awready   ${cell}/s_axi_awready net_${prefix}_s_axi_awready
    try_connect ${cell}/s_axi_wdata   ${ip}/s_axi_wdata   net_${prefix}_s_axi_wdata
    try_connect ${cell}/s_axi_wstrb   ${ip}/s_axi_wstrb   net_${prefix}_s_axi_wstrb
    try_connect ${cell}/s_axi_wvalid  ${ip}/s_axi_wvalid  net_${prefix}_s_axi_wvalid
    try_connect ${ip}/s_axi_wready    ${cell}/s_axi_wready net_${prefix}_s_axi_wready
    try_connect ${ip}/s_axi_bresp     ${cell}/s_axi_bresp  net_${prefix}_s_axi_bresp
    try_connect ${ip}/s_axi_bvalid    ${cell}/s_axi_bvalid net_${prefix}_s_axi_bvalid
    try_connect ${cell}/s_axi_bready  ${ip}/s_axi_bready  net_${prefix}_s_axi_bready
}

foreach prefix {phy0 phy1} cell {jesd_phy_tx_axi_init0_0 jesd_phy_tx_axi_init1_0} ip {jesd204_phy_tx_quad226_bd jesd204_phy_tx_quad227_bd} {
    try_connect ${cell}/s_axi_awaddr  ${ip}/s_axi_awaddr  net_${prefix}_s_axi_awaddr
    try_connect ${cell}/s_axi_awvalid ${ip}/s_axi_awvalid net_${prefix}_s_axi_awvalid
    try_connect ${ip}/s_axi_awready   ${cell}/s_axi_awready net_${prefix}_s_axi_awready
    try_connect ${cell}/s_axi_wdata   ${ip}/s_axi_wdata   net_${prefix}_s_axi_wdata
    try_connect ${cell}/s_axi_wvalid  ${ip}/s_axi_wvalid  net_${prefix}_s_axi_wvalid
    try_connect ${ip}/s_axi_wready    ${cell}/s_axi_wready net_${prefix}_s_axi_wready
    try_connect ${ip}/s_axi_bresp     ${cell}/s_axi_bresp  net_${prefix}_s_axi_bresp
    try_connect ${ip}/s_axi_bvalid    ${cell}/s_axi_bvalid net_${prefix}_s_axi_bvalid
    try_connect ${cell}/s_axi_bready  ${ip}/s_axi_bready  net_${prefix}_s_axi_bready
}

# External clocks/resets mirror the clock domains in ku5p_bringup_top.v.
ensure_ext_port sys_clk             I clk 1 200000000 ""
ensure_ext_port phy1_rxck           I clk 1 125000000 ""
ensure_ext_port jesd_core_clk       I clk 1 245760000 ""
ensure_ext_port jesd_refclk         I clk 1 245760000 ""
ensure_ext_port gt_unused_refclk_bd I clk 1 245760000 ""
ensure_ext_port init_rst            I rst 1 "" ACTIVE_HIGH
ensure_ext_port phy1_rx_rst         I rst 1 "" ACTIVE_HIGH
ensure_ext_port jesd_axi_aresetn    I rst 1 "" ACTIVE_LOW
ensure_ext_port jesd_release_n      I rst 1 "" ACTIVE_HIGH
ensure_ext_port rx_sys_reset_const1 I rst 1 "" ACTIVE_HIGH

connect_port_to_pins sys_clk {
    eth_clk_125_0/clk_200
    mb_io_dac_regs_0/clk
    hmc7044_init_0/clk
    ad9173_init_0/clk
    jesd204_tx_init_link0_0/clk
    jesd204_tx_init_link1_0/clk
    jesd_phy_tx_axi_init0_0/clk
    jesd_phy_tx_axi_init1_0/clk
    mb_mcs_ctrl_bd/Clk
    runtime_vio_bd/clk
    jesd204c_tx_link0_bd/s_axi_aclk
    jesd204c_tx_link1_bd/s_axi_aclk
    jesd204_phy_tx_quad226_bd/drpclk
    jesd204_phy_tx_quad226_bd/s_axi_aclk
    jesd204_phy_tx_quad227_bd/drpclk
    jesd204_phy_tx_quad227_bd/s_axi_aclk
} net_sys_clk

connect_port_to_pins phy1_rxck {
    rgmii_rx_0/rx_clk
    udp_cfg_rx_0/clk
    pattern_gen_256_0/wave_clk
} net_phy1_rxck

connect_port_to_pins jesd_core_clk {
    pattern_gen_256_0/clk
    jesd204c_tx_link0_bd/tx_core_clk
    jesd204c_tx_link1_bd/tx_core_clk
    jesd204_phy_tx_quad226_bd/tx_core_clk
    jesd204_phy_tx_quad226_bd/rx_core_clk
    jesd204_phy_tx_quad227_bd/tx_core_clk
    jesd204_phy_tx_quad227_bd/rx_core_clk
} net_jesd_core_clk

connect_port_to_pins jesd_refclk {
    jesd204_phy_tx_quad226_bd/qpll0_refclk
    jesd204_phy_tx_quad227_bd/qpll0_refclk
} net_jesd_refclk

# These PHY clock pins are tied to 1'b0 in the RTL top because QPLL0 is used.
# BD validation still requires a clock-typed source, so expose a clearly named
# BD-only placeholder instead of hiding them.
connect_port_to_pins gt_unused_refclk_bd {
    jesd204_phy_tx_quad226_bd/cpll_refclk
    jesd204_phy_tx_quad226_bd/qpll1_refclk
    jesd204_phy_tx_quad227_bd/cpll_refclk
    jesd204_phy_tx_quad227_bd/qpll1_refclk
} net_gt_unused_refclk_bd

connect_port_to_pins init_rst {
    eth_clk_125_0/rst
    hmc7044_init_0/rst
    ad9173_init_0/rst
    jesd204_tx_init_link0_0/rst
    jesd204_tx_init_link1_0/rst
    mb_io_dac_regs_0/rst
} net_init_rst

connect_port_to_pins phy1_rx_rst {
    rgmii_rx_0/rst
    udp_cfg_rx_0/rst
    pattern_gen_256_0/wave_rst
} net_phy1_rx_rst

connect_port_to_pins jesd_axi_aresetn {
    jesd204c_tx_link0_bd/s_axi_aresetn
    jesd204c_tx_link1_bd/s_axi_aresetn
    jesd204_phy_tx_quad226_bd/s_axi_aresetn
    jesd204_phy_tx_quad227_bd/s_axi_aresetn
} net_jesd_axi_aresetn

connect_port_to_pins jesd_release_n {
    jesd204c_tx_link0_bd/tx_core_reset
    jesd204c_tx_link1_bd/tx_core_reset
    jesd204_phy_tx_quad226_bd/tx_sys_reset
    jesd204_phy_tx_quad227_bd/tx_sys_reset
    jesd_phy_tx_axi_init0_0/rst
    jesd_phy_tx_axi_init1_0/rst
} net_jesd_release_n

connect_port_to_pins rx_sys_reset_const1 {
    jesd204_phy_tx_quad226_bd/rx_reset_gt
    jesd204_phy_tx_quad226_bd/rx_sys_reset
    jesd204_phy_tx_quad227_bd/rx_reset_gt
    jesd204_phy_tx_quad227_bd/rx_sys_reset
} net_rx_sys_reset_const1

try_connect eth_clk_125_0/clk_125    rgmii_tx_0/tx_clk    net_eth_clk_125
try_connect eth_clk_125_0/clk_125_90 rgmii_tx_0/tx_clk_90 net_eth_clk_125_90
connect_port_to_pin init_rst rgmii_tx_0/rst net_init_rst

# Board-facing and state-machine-driven signals are externalized because the
# original top-level glue logic remains RTL, not BD.
expose_pin rgmii_rx_0/rgmii_rxd       phy1_rxd       I  "" 4 "" ""
expose_pin rgmii_rx_0/rgmii_rx_ctl    phy1_rxctl     I  "" 1 "" ""
expose_pin rgmii_tx_0/rgmii_tx_clk    phy1_txck      O  clk 1 100000000 ""
expose_pin rgmii_tx_0/rgmii_txd       phy1_txd       O  "" 4 "" ""
expose_pin rgmii_tx_0/rgmii_tx_ctl    phy1_txctl     O  "" 1 "" ""

expose_pin hmc7044_init_0/start       start_hmc      I  "" 1 "" ""
expose_pin hmc7044_init_0/sclk        clock_sclk     O  "" 1 "" ""
expose_pin hmc7044_init_0/cs_n        clock_cs       O  "" 1 "" ""
expose_pin hmc7044_init_0/sdio_i      clock_sdio_i   I  "" 1 "" ""
expose_pin hmc7044_init_0/sdio_o      clock_sdio_o   O  "" 1 "" ""
expose_pin hmc7044_init_0/sdio_oe     clock_sdio_oe  O  "" 1 "" ""

expose_pin ad9173_init_0/start        start_dac      I  "" 1 "" ""
expose_pin ad9173_init_0/sdo          dac_sdo        I  "" 1 "" ""
expose_pin ad9173_init_0/sclk         dac_sclk       O  "" 1 "" ""
expose_pin ad9173_init_0/cs_n         dac_cs         O  "" 1 "" ""
expose_pin ad9173_init_0/sdio_i       dac_sdio_i     I  "" 1 "" ""
expose_pin ad9173_init_0/sdio_o       dac_sdio_o     O  "" 1 "" ""
expose_pin ad9173_init_0/sdio_oe      dac_sdio_oe    O  "" 1 "" ""

expose_pin jesd204c_tx_link0_bd/tx_sysref sysref2_i  I  "" 1 "" ""
connect_port_to_pin sysref2_i jesd204c_tx_link1_bd/tx_sysref net_ext_sysref2_i
expose_pin jesd204c_tx_link0_bd/tx_sync dac_sync0_i  I  "" 1 "" ""
expose_pin jesd204c_tx_link1_bd/tx_sync dac_sync1_i  I  "" 1 "" ""
expose_pin jesd204_phy_tx_quad226_bd/txp_out dac_tx_p_3_0 O "" 4 "" ""
expose_pin jesd204_phy_tx_quad226_bd/txn_out dac_tx_n_3_0 O "" 4 "" ""
expose_pin jesd204_phy_tx_quad227_bd/txp_out dac_tx_p_7_4 O "" 4 "" ""
expose_pin jesd204_phy_tx_quad227_bd/txn_out dac_tx_n_7_4 O "" 4 "" ""
expose_pin jesd204_phy_tx_quad226_bd/rxp_in  rxp_in_tied0_0 I "" 4 "" ""
expose_pin jesd204_phy_tx_quad226_bd/rxn_in  rxn_in_tied0_0 I "" 4 "" ""
expose_pin jesd204_phy_tx_quad227_bd/rxp_in  rxp_in_tied0_1 I "" 4 "" ""
expose_pin jesd204_phy_tx_quad227_bd/rxn_in  rxn_in_tied0_1 I "" 4 "" ""

expose_pin pattern_gen_256_0/advance     tx_tone_advance I "" 1 "" ""
expose_pin pattern_gen_256_0/rst         tx_tone_reset   I rst 1 "" ACTIVE_HIGH
expose_pin pattern_gen_256_0/output_path_sel output_path_sel_legacy I "" 1 "" ""

foreach idx {0 1 2 3 4 5 6} {
    expose_pin runtime_vio_bd/probe_in${idx} runtime_vio_probe_in${idx} I "" "" "" ""
}
foreach idx {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14} {
    expose_pin runtime_vio_bd/probe_out${idx} runtime_vio_probe_out${idx} O "" "" "" ""
}

regenerate_bd_layout
if {[catch {validate_bd_design} validate_msg]} {
    puts "WARN: validate_bd_design reported issues; saving BD for inspection anyway."
    puts $validate_msg
}
save_bd_design

puts "INFO: Added real-structure BD to project: [get_property FILE_NAME [current_bd_design]]"
puts "INFO: Existing implementation top is unchanged: [get_property top [current_fileset]]"
puts "INFO: Open project: $xpr_path"

close_project
