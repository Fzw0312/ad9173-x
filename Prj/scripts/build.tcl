set origin_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $origin_dir ..]]
set build_root [file normalize [file join $prj_dir .. build vivado ad9173_ad6688]]
set build_dir  [file normalize [file join $build_root ku5p_vivado]]
set stage_dir  [file normalize [file join $build_root stage]]
set ip_dir     [file normalize [file join $build_dir ip]]
set build_jobs 4
set build_stage bit

if {[info exists ::env(KU5P_PRJ_DIR)] && $::env(KU5P_PRJ_DIR) ne ""} {
    set prj_dir [file normalize $::env(KU5P_PRJ_DIR)]
    set build_root [file normalize [file join $prj_dir .. build vivado ad9173_ad6688]]
    set build_dir  [file normalize [file join $build_root ku5p_vivado]]
    set stage_dir  [file normalize [file join $build_root stage]]
    set ip_dir     [file normalize [file join $build_dir ip]]
}

if {[info exists ::env(KU5P_BUILD_ROOT)] && $::env(KU5P_BUILD_ROOT) ne ""} {
    set build_root [file normalize $::env(KU5P_BUILD_ROOT)]
    set build_dir  [file normalize [file join $build_root ku5p_vivado]]
    set stage_dir  [file normalize [file join $build_root stage]]
    set ip_dir     [file normalize [file join $build_dir ip]]
}

file mkdir $build_root

if {[info exists ::env(KU5P_VIVADO_JOBS)] && $::env(KU5P_VIVADO_JOBS) ne ""} {
    set build_jobs $::env(KU5P_VIVADO_JOBS)
}
if {[info exists ::env(KU5P_BUILD_STAGE)] && $::env(KU5P_BUILD_STAGE) ne ""} {
    set build_stage $::env(KU5P_BUILD_STAGE)
}
if {$build_stage ni {synth route bit}} {
    error "KU5P_BUILD_STAGE must be synth, route, or bit"
}

proc reset_dir {dir_path} {
    if {[file exists $dir_path]} {
        file delete -force $dir_path
    }
    file mkdir $dir_path
}

reset_dir $build_dir
reset_dir $stage_dir
file mkdir $ip_dir

# Vivado's debug-core implementation flow creates temporary projects under the
# current working directory. Keep that cwd away from the repository path
# because the source tree contains '&', which makes those generated project
# names illegal during dbg_hub/xsdbm synthesis.
cd $build_dir

proc stage_file {src dst} {
    file mkdir [file dirname $dst]
    file copy -force $src $dst
    return $dst
}

proc bus_nets {base width} {
    set nets [list]
    for {set idx 0} {$idx < $width} {incr idx} {
        lappend nets "${base}\[$idx\]"
    }
    return $nets
}

proc ensure_debug_probe {core probe_idx} {
    while {[llength [get_debug_ports ${core}/probe${probe_idx} -quiet]] == 0} {
        create_debug_port $core probe
    }
}

proc configure_debug_probe {core probe_idx width} {
    ensure_debug_probe $core $probe_idx
    set_property PORT_WIDTH $width [get_debug_ports ${core}/probe${probe_idx}]
}

set rtl_files [list \
    [stage_file [file join $prj_dir src rtl common spi_write_master.v]            [file join $stage_dir src rtl common spi_write_master.v]] \
    [stage_file [file join $prj_dir src rtl common spi_init_engine.v]             [file join $stage_dir src rtl common spi_init_engine.v]] \
    [stage_file [file join $prj_dir src rtl common spi_read_master_4wire.v]       [file join $stage_dir src rtl common spi_read_master_4wire.v]] \
    [stage_file [file join $prj_dir src rtl common spi_read_master_3wire.v]       [file join $stage_dir src rtl common spi_read_master_3wire.v]] \
    [stage_file [file join $prj_dir src rtl common adi_spi_master.v]              [file join $stage_dir src rtl common adi_spi_master.v]] \
    [stage_file [file join $prj_dir src rtl common axi_lite_write_master.v]       [file join $stage_dir src rtl common axi_lite_write_master.v]] \
    [stage_file [file join $prj_dir src rtl common axi_lite_rdwr_master.v]        [file join $stage_dir src rtl common axi_lite_rdwr_master.v]] \
    [stage_file [file join $prj_dir src rtl common axi_lite_init_engine.v]        [file join $stage_dir src rtl common axi_lite_init_engine.v]] \
    [stage_file [file join $prj_dir src rtl common jesd_tx_axi_probe.v]           [file join $stage_dir src rtl common jesd_tx_axi_probe.v]] \
    [stage_file [file join $prj_dir src rtl common jesd_rx_axi_probe.v]           [file join $stage_dir src rtl common jesd_rx_axi_probe.v]] \
    [stage_file [file join $prj_dir src rtl common jesd_phy_axi_probe.v]          [file join $stage_dir src rtl common jesd_phy_axi_probe.v]] \
    [stage_file [file join $prj_dir src rtl common jesd_clock.v]                  [file join $stage_dir src rtl common jesd_clock.v]] \
    [stage_file [file join $prj_dir src rtl common pattern_gen_256.v]             [file join $stage_dir src rtl common pattern_gen_256.v]] \
    [stage_file [file join $prj_dir src rtl common tx_mapper.v]                   [file join $stage_dir src rtl common tx_mapper.v]] \
    [stage_file [file join $prj_dir src rtl common ad6688_lane_reorder.v]         [file join $stage_dir src rtl common ad6688_lane_reorder.v]] \
    [stage_file [file join $prj_dir src rtl common adc0_sample_packer.v]          [file join $stage_dir src rtl common adc0_sample_packer.v]] \
    [stage_file [file join $prj_dir src rtl common adc_window_to_axis.v]           [file join $stage_dir src rtl common adc_window_to_axis.v]] \
    [stage_file [file join $prj_dir src rtl common adc_capture_bram64.v]          [file join $stage_dir src rtl common adc_capture_bram64.v]] \
    [stage_file [file join $prj_dir src rtl common adc_capture_ddr64_model.v]     [file join $stage_dir src rtl common adc_capture_ddr64_model.v]] \
    [stage_file [file join $prj_dir src rtl common adc_udp_capture_ctrl.v]        [file join $stage_dir src rtl common adc_udp_capture_ctrl.v]] \
    [stage_file [file join $prj_dir src rtl common eth_crc32_byte.v]              [file join $stage_dir src rtl common eth_crc32_byte.v]] \
    [stage_file [file join $prj_dir src rtl common ipv4_checksum.v]               [file join $stage_dir src rtl common ipv4_checksum.v]] \
    [stage_file [file join $prj_dir src rtl common k5ad_udp_packetizer.v]         [file join $stage_dir src rtl common k5ad_udp_packetizer.v]] \
    [stage_file [file join $prj_dir src rtl common k5ad_udp_packetizer_ddr.v]     [file join $stage_dir src rtl common k5ad_udp_packetizer_ddr.v]] \
    [stage_file [file join $prj_dir src rtl common k5wg_udp_dac_config_rx.v]      [file join $stage_dir src rtl common k5wg_udp_dac_config_rx.v]] \
    [stage_file [file join $prj_dir src rtl common eth_clk_125.v]                 [file join $stage_dir src rtl common eth_clk_125.v]] \
    [stage_file [file join $prj_dir src rtl common rgmii_tx.v]                    [file join $stage_dir src rtl common rgmii_tx.v]] \
    [stage_file [file join $prj_dir src rtl common rgmii_rx.v]                    [file join $stage_dir src rtl common rgmii_rx.v]] \
    [stage_file [file join $prj_dir src rtl chip hmc7044 hmc7044_init_table.v]    [file join $stage_dir src rtl chip hmc7044 hmc7044_init_table.v]] \
    [stage_file [file join $prj_dir src rtl chip hmc7044 hmc7044_init.v]          [file join $stage_dir src rtl chip hmc7044 hmc7044_init.v]] \
    [stage_file [file join $prj_dir src rtl chip ad9173 ad9173_init_table.v]      [file join $stage_dir src rtl chip ad9173 ad9173_init_table.v]] \
    [stage_file [file join $prj_dir src rtl chip ad9173 ad9173_init.v]            [file join $stage_dir src rtl chip ad9173 ad9173_init.v]] \
    [stage_file [file join $prj_dir src rtl chip ad9173 ad9173_link_diag.v]       [file join $stage_dir src rtl chip ad9173 ad9173_link_diag.v]] \
    [stage_file [file join $prj_dir src rtl chip ad6688 ad6688_init_table.v]      [file join $stage_dir src rtl chip ad6688 ad6688_init_table.v]] \
    [stage_file [file join $prj_dir src rtl chip ad6688 ad6688_init.v]            [file join $stage_dir src rtl chip ad6688 ad6688_init.v]] \
    [stage_file [file join $prj_dir src rtl chip jesd jesd204_tx_init_table_link0.v] [file join $stage_dir src rtl chip jesd jesd204_tx_init_table_link0.v]] \
    [stage_file [file join $prj_dir src rtl chip jesd jesd204_tx_init_table_link1.v] [file join $stage_dir src rtl chip jesd jesd204_tx_init_table_link1.v]] \
    [stage_file [file join $prj_dir src rtl chip jesd jesd204_tx_init_link0.v]    [file join $stage_dir src rtl chip jesd jesd204_tx_init_link0.v]] \
    [stage_file [file join $prj_dir src rtl chip jesd jesd204_tx_init_link1.v]    [file join $stage_dir src rtl chip jesd jesd204_tx_init_link1.v]] \
    [stage_file [file join $prj_dir src rtl chip jesd jesd204_rx_init_table.v]    [file join $stage_dir src rtl chip jesd jesd204_rx_init_table.v]] \
    [stage_file [file join $prj_dir src rtl chip jesd jesd204_rx_init.v]          [file join $stage_dir src rtl chip jesd jesd204_rx_init.v]] \
    [stage_file [file join $prj_dir src rtl top ku5p_bringup_top.v]               [file join $stage_dir src rtl top ku5p_bringup_top.v]] \
]

set xdc_file [stage_file [file join $prj_dir src xdc ku5p_bringup.xdc] [file join $stage_dir src xdc ku5p_bringup.xdc]]

create_project ku5p_bringup $build_dir -part xcku5p-ffvb676-2-i -force
set_property target_language Verilog [current_project]
set_property top ku5p_bringup_top [current_fileset]
set_param general.maxThreads $build_jobs

create_ip -name jesd204c -vendor xilinx.com -library ip -version 4.2 -module_name jesd204c_tx_link0 -dir $ip_dir
set_property -dict [list \
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
    CONFIG.C_USE_FEC {false} \
] [get_ips jesd204c_tx_link0]

create_ip -name jesd204c -vendor xilinx.com -library ip -version 4.2 -module_name jesd204c_tx_link1 -dir $ip_dir
set_property -dict [list \
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
    CONFIG.C_USE_FEC {false} \
] [get_ips jesd204c_tx_link1]

create_ip -name jesd204c -vendor xilinx.com -library ip -version 4.2 -module_name jesd204c_rx_link0 -dir $ip_dir
set_property -dict [list \
    CONFIG.C_NODE_IS_TRANSMIT {0} \
    CONFIG.C_LANES {8} \
    CONFIG.Transceiver {GTYE4} \
    CONFIG.AXICLK_FREQ {200.0} \
    CONFIG.GT_Line_Rate {9.8304} \
    CONFIG.GT_REFCLK_FREQ {245.76} \
    CONFIG.GT_REFCLK_FREQ_REQUEST {245.76} \
    CONFIG.DRPCLK_FREQ {200.0} \
    CONFIG.C_PLL_SELECTION {1} \
    CONFIG.C_ENCODING {0} \
    CONFIG.C_USE_FEC {false} \
] [get_ips jesd204c_rx_link0]

create_ip -name jesd204_phy -vendor xilinx.com -library ip -version 4.0 -module_name jesd204_phy_tx_quad226 -dir $ip_dir
set_property -dict [list \
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
    CONFIG.Rx_use_64b {0} \
] [get_ips jesd204_phy_tx_quad226]

create_ip -name jesd204_phy -vendor xilinx.com -library ip -version 4.0 -module_name jesd204_phy_tx_quad227 -dir $ip_dir
set_property -dict [list \
    CONFIG.AXICLK_FREQ {200.0} \
    CONFIG.Axi_Lite {true} \
    CONFIG.C_LANES {4} \
    CONFIG.GT_Location {X0Y4} \
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
    CONFIG.Rx_use_64b {0} \
] [get_ips jesd204_phy_tx_quad227]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ku5p_bringup_ila -dir $ip_dir
set_property -dict [list \
    CONFIG.C_MONITOR_TYPE {Native} \
    CONFIG.C_DATA_DEPTH {2048} \
    CONFIG.C_TRIGIN_EN {false} \
    CONFIG.C_TRIGOUT_EN {false} \
    CONFIG.C_INPUT_PIPE_STAGES {2} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_EN_STRG_QUAL {false} \
    CONFIG.ALL_PROBE_SAME_MU {false} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {16} \
    CONFIG.C_NUM_OF_PROBES {111} \
    CONFIG.C_PROBE0_WIDTH {4} \
    CONFIG.C_PROBE1_WIDTH {32} \
    CONFIG.C_PROBE2_WIDTH {16} \
    CONFIG.C_PROBE3_WIDTH {16} \
    CONFIG.C_PROBE4_WIDTH {10} \
    CONFIG.C_PROBE5_WIDTH {32} \
    CONFIG.C_PROBE6_WIDTH {32} \
    CONFIG.C_PROBE7_WIDTH {16} \
    CONFIG.C_PROBE8_WIDTH {2} \
    CONFIG.C_PROBE9_WIDTH {2} \
    CONFIG.C_PROBE10_WIDTH {2} \
    CONFIG.C_PROBE11_WIDTH {2} \
    CONFIG.C_PROBE12_WIDTH {8} \
    CONFIG.C_PROBE13_WIDTH {8} \
    CONFIG.C_PROBE14_WIDTH {8} \
    CONFIG.C_PROBE15_WIDTH {14} \
    CONFIG.C_PROBE16_WIDTH {24} \
    CONFIG.C_PROBE17_WIDTH {10} \
    CONFIG.C_PROBE18_WIDTH {16} \
    CONFIG.C_PROBE19_WIDTH {32} \
    CONFIG.C_PROBE20_WIDTH {32} \
    CONFIG.C_PROBE21_WIDTH {32} \
    CONFIG.C_PROBE22_WIDTH {32} \
    CONFIG.C_PROBE23_WIDTH {32} \
    CONFIG.C_PROBE24_WIDTH {32} \
    CONFIG.C_PROBE25_WIDTH {32} \
    CONFIG.C_PROBE26_WIDTH {32} \
    CONFIG.C_PROBE27_WIDTH {32} \
    CONFIG.C_PROBE28_WIDTH {32} \
    CONFIG.C_PROBE29_WIDTH {32} \
    CONFIG.C_PROBE30_WIDTH {16} \
    CONFIG.C_PROBE31_WIDTH {32} \
    CONFIG.C_PROBE32_WIDTH {8} \
    CONFIG.C_PROBE33_WIDTH {8} \
    CONFIG.C_PROBE34_WIDTH {32} \
    CONFIG.C_PROBE35_WIDTH {32} \
    CONFIG.C_PROBE36_WIDTH {32} \
    CONFIG.C_PROBE37_WIDTH {32} \
    CONFIG.C_PROBE38_WIDTH {32} \
    CONFIG.C_PROBE39_WIDTH {32} \
    CONFIG.C_PROBE40_WIDTH {32} \
    CONFIG.C_PROBE41_WIDTH {32} \
    CONFIG.C_PROBE42_WIDTH {32} \
    CONFIG.C_PROBE43_WIDTH {32} \
    CONFIG.C_PROBE44_WIDTH {32} \
    CONFIG.C_PROBE45_WIDTH {32} \
    CONFIG.C_PROBE46_WIDTH {32} \
    CONFIG.C_PROBE47_WIDTH {32} \
    CONFIG.C_PROBE48_WIDTH {32} \
    CONFIG.C_PROBE49_WIDTH {32} \
    CONFIG.C_PROBE50_WIDTH {32} \
    CONFIG.C_PROBE51_WIDTH {32} \
    CONFIG.C_PROBE52_WIDTH {32} \
    CONFIG.C_PROBE53_WIDTH {32} \
    CONFIG.C_PROBE54_WIDTH {32} \
    CONFIG.C_PROBE55_WIDTH {32} \
    CONFIG.C_PROBE56_WIDTH {32} \
    CONFIG.C_PROBE57_WIDTH {32} \
    CONFIG.C_PROBE58_WIDTH {32} \
    CONFIG.C_PROBE59_WIDTH {32} \
    CONFIG.C_PROBE60_WIDTH {32} \
    CONFIG.C_PROBE61_WIDTH {32} \
    CONFIG.C_PROBE62_WIDTH {32} \
    CONFIG.C_PROBE63_WIDTH {32} \
    CONFIG.C_PROBE64_WIDTH {32} \
    CONFIG.C_PROBE65_WIDTH {32} \
    CONFIG.C_PROBE66_WIDTH {32} \
    CONFIG.C_PROBE67_WIDTH {32} \
    CONFIG.C_PROBE68_WIDTH {32} \
    CONFIG.C_PROBE69_WIDTH {32} \
    CONFIG.C_PROBE70_WIDTH {32} \
    CONFIG.C_PROBE71_WIDTH {32} \
    CONFIG.C_PROBE72_WIDTH {32} \
    CONFIG.C_PROBE73_WIDTH {32} \
    CONFIG.C_PROBE74_WIDTH {32} \
    CONFIG.C_PROBE75_WIDTH {32} \
    CONFIG.C_PROBE76_WIDTH {32} \
    CONFIG.C_PROBE77_WIDTH {32} \
    CONFIG.C_PROBE78_WIDTH {32} \
    CONFIG.C_PROBE79_WIDTH {32} \
    CONFIG.C_PROBE80_WIDTH {32} \
    CONFIG.C_PROBE81_WIDTH {32} \
    CONFIG.C_PROBE82_WIDTH {32} \
    CONFIG.C_PROBE83_WIDTH {32} \
    CONFIG.C_PROBE84_WIDTH {32} \
    CONFIG.C_PROBE85_WIDTH {32} \
    CONFIG.C_PROBE86_WIDTH {32} \
    CONFIG.C_PROBE87_WIDTH {32} \
    CONFIG.C_PROBE88_WIDTH {32} \
    CONFIG.C_PROBE89_WIDTH {32} \
    CONFIG.C_PROBE90_WIDTH {32} \
    CONFIG.C_PROBE91_WIDTH {32} \
    CONFIG.C_PROBE92_WIDTH {32} \
    CONFIG.C_PROBE93_WIDTH {32} \
    CONFIG.C_PROBE94_WIDTH {32} \
    CONFIG.C_PROBE95_WIDTH {32} \
    CONFIG.C_PROBE96_WIDTH {32} \
    CONFIG.C_PROBE97_WIDTH {32} \
    CONFIG.C_PROBE98_WIDTH {32} \
    CONFIG.C_PROBE99_WIDTH {32} \
    CONFIG.C_PROBE100_WIDTH {32} \
    CONFIG.C_PROBE101_WIDTH {32} \
    CONFIG.C_PROBE102_WIDTH {32} \
    CONFIG.C_PROBE103_WIDTH {32} \
    CONFIG.C_PROBE104_WIDTH {32} \
    CONFIG.C_PROBE105_WIDTH {32} \
    CONFIG.C_PROBE106_WIDTH {32} \
    CONFIG.C_PROBE107_WIDTH {32} \
    CONFIG.C_PROBE108_WIDTH {32} \
    CONFIG.C_PROBE109_WIDTH {32} \
    CONFIG.C_PROBE110_WIDTH {32} \
	] [get_ips ku5p_bringup_ila]

generate_target all [get_ips]
export_ip_user_files -of_objects [get_ips] -no_script -sync -force -quiet

add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse $xdc_file

update_compile_order -fileset sources_1
set ip_objects [list \
    [get_ips jesd204c_tx_link0] \
    [get_ips jesd204c_tx_link1] \
    [get_ips jesd204c_rx_link0] \
    [get_ips jesd204_phy_tx_quad226] \
    [get_ips jesd204_phy_tx_quad227] \
    [get_ips ku5p_bringup_ila] \
]
foreach ip_obj $ip_objects {
    set ip_file [get_property IP_FILE $ip_obj]
    # Fold generated IP into synth_1 instead of relying on child OOC runs.
    # This avoids wait_on_runs deadlocks observed in automated batch builds.
    set_property generate_synth_checkpoint false [get_files -quiet $ip_file]
}

reset_run synth_1
launch_runs synth_1 -jobs $build_jobs
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "INFO: synth_status=$synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "synth_1 failed: $synth_status"
}

open_run synth_1

write_checkpoint -force [file join $build_dir post_synth.dcp]
report_timing_summary -file [file join $build_dir post_synth_timing.rpt]
report_utilization     -file [file join $build_dir post_synth_util.rpt]
catch {report_clock_interaction -file [file join $build_dir post_synth_clock_interaction.rpt]}
catch {check_timing -verbose -file [file join $build_dir post_synth_check_timing.rpt]}

if {$build_stage eq "synth"} {
    puts "INFO: KU5P_BUILD_STAGE=synth; stopping after post-synth reports."
    close_project
    exit
}

opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force [file join $build_dir post_route.dcp]
report_timing_summary -file [file join $build_dir post_route_timing.rpt]
report_utilization     -file [file join $build_dir post_route_util.rpt]
catch {report_clock_interaction -file [file join $build_dir post_route_clock_interaction.rpt]}
catch {check_timing -verbose -file [file join $build_dir post_route_check_timing.rpt]}
catch {report_drc -file [file join $build_dir post_route_drc.rpt]}
catch {report_bus_skew -file [file join $build_dir post_route_bus_skew.rpt]}
write_debug_probes -force [file join $build_dir ku5p_bringup_top.ltx]

if {$build_stage eq "route"} {
    puts "INFO: KU5P_BUILD_STAGE=route; stopping after route and debug-probe export."
    close_project
    exit
}

write_bitstream -force [file join $build_dir ku5p_bringup_top.bit]
