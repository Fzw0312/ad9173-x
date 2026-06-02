set origin_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $origin_dir ..]]
set build_root [file normalize [file join $prj_dir .. build vivado ad9173_dac_only]]
set build_dir  [file normalize [file join $build_root ku5p_vivado]]
set stage_dir  [file normalize [file join $build_root stage]]
set ip_dir     [file normalize [file join $build_dir ip]]
set build_jobs 4
set build_stage bit

if {[info exists ::env(KU5P_PRJ_DIR)] && $::env(KU5P_PRJ_DIR) ne ""} {
    set prj_dir [file normalize $::env(KU5P_PRJ_DIR)]
    set build_root [file normalize [file join $prj_dir .. build vivado ad9173_dac_only]]
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

cd $build_dir

proc stage_file {src dst} {
    file mkdir [file dirname $dst]
    file copy -force $src $dst
    return $dst
}

set rtl_files [list \
    [stage_file [file join $prj_dir src rtl common spi_write_master.v]            [file join $stage_dir src rtl common spi_write_master.v]] \
    [stage_file [file join $prj_dir src rtl common spi_init_engine.v]             [file join $stage_dir src rtl common spi_init_engine.v]] \
    [stage_file [file join $prj_dir src rtl common spi_read_master_4wire.v]       [file join $stage_dir src rtl common spi_read_master_4wire.v]] \
    [stage_file [file join $prj_dir src rtl common spi_read_master_3wire.v]       [file join $stage_dir src rtl common spi_read_master_3wire.v]] \
    [stage_file [file join $prj_dir src rtl common axi_lite_write_master.v]       [file join $stage_dir src rtl common axi_lite_write_master.v]] \
    [stage_file [file join $prj_dir src rtl common axi_lite_init_engine.v]        [file join $stage_dir src rtl common axi_lite_init_engine.v]] \
    [stage_file [file join $prj_dir src rtl common jesd_phy_tx_axi_init.v]        [file join $stage_dir src rtl common jesd_phy_tx_axi_init.v]] \
    [stage_file [file join $prj_dir src rtl common jesd_clock.v]                  [file join $stage_dir src rtl common jesd_clock.v]] \
    [stage_file [file join $prj_dir src rtl common mb_io_dac_regs.v]             [file join $stage_dir src rtl common mb_io_dac_regs.v]] \
    [stage_file [file join $prj_dir src rtl common mb_control_island.v]           [file join $stage_dir src rtl common mb_control_island.v]] \
    [stage_file [file join $prj_dir src rtl common pattern_gen_256.v]             [file join $stage_dir src rtl common pattern_gen_256.v]] \
    [stage_file [file join $prj_dir src rtl common tx_mapper.v]                   [file join $stage_dir src rtl common tx_mapper.v]] \
    [stage_file [file join $prj_dir src rtl common k5wg_udp_dac_config_rx.v]      [file join $stage_dir src rtl common k5wg_udp_dac_config_rx.v]] \
    [stage_file [file join $prj_dir src rtl common eth_clk_125.v]                 [file join $stage_dir src rtl common eth_clk_125.v]] \
    [stage_file [file join $prj_dir src rtl common rgmii_tx.v]                    [file join $stage_dir src rtl common rgmii_tx.v]] \
    [stage_file [file join $prj_dir src rtl common rgmii_rx.v]                    [file join $stage_dir src rtl common rgmii_rx.v]] \
    [stage_file [file join $prj_dir src rtl chip hmc7044 hmc7044_init_table.v]    [file join $stage_dir src rtl chip hmc7044 hmc7044_init_table.v]] \
    [stage_file [file join $prj_dir src rtl chip hmc7044 hmc7044_init.v]          [file join $stage_dir src rtl chip hmc7044 hmc7044_init.v]] \
    [stage_file [file join $prj_dir src rtl chip ad9173 ad9173_init_table.v]      [file join $stage_dir src rtl chip ad9173 ad9173_init_table.v]] \
    [stage_file [file join $prj_dir src rtl chip ad9173 ad9173_init.v]            [file join $stage_dir src rtl chip ad9173 ad9173_init.v]] \
    [stage_file [file join $prj_dir src rtl chip jesd jesd204_tx_init_table_link0.v] [file join $stage_dir src rtl chip jesd jesd204_tx_init_table_link0.v]] \
    [stage_file [file join $prj_dir src rtl chip jesd jesd204_tx_init_table_link1.v] [file join $stage_dir src rtl chip jesd jesd204_tx_init_table_link1.v]] \
    [stage_file [file join $prj_dir src rtl chip jesd jesd204_tx_init_link0.v]    [file join $stage_dir src rtl chip jesd jesd204_tx_init_link0.v]] \
    [stage_file [file join $prj_dir src rtl chip jesd jesd204_tx_init_link1.v]    [file join $stage_dir src rtl chip jesd jesd204_tx_init_link1.v]] \
    [stage_file [file join $prj_dir src rtl top ku5p_bringup_top.v]               [file join $stage_dir src rtl top ku5p_bringup_top.v]] \
]

set xdc_file [stage_file [file join $prj_dir src xdc ku5p_bringup.xdc] [file join $stage_dir src xdc ku5p_bringup.xdc]]

create_project ku5p_dac_only $build_dir -part xcku5p-ffvb676-2-i -force
set_property target_language Verilog [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_MEMORY} [current_project]
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

create_ip -name microblaze_mcs -vendor xilinx.com -library ip -version 3.0 -module_name mb_mcs_ctrl -dir $ip_dir
set_property -dict [list \
    CONFIG.FREQ {200.0} \
    CONFIG.MEMSIZE {16384} \
    CONFIG.USE_IO_BUS {1} \
    CONFIG.DEBUG_ENABLED {1} \
    CONFIG.USE_BSCAN {0} \
] [get_ips mb_mcs_ctrl]

generate_target all [get_ips]
export_ip_user_files -of_objects [get_ips] -no_script -sync -force -quiet

add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse $xdc_file
update_compile_order -fileset sources_1

set ip_objects [list \
    [get_ips jesd204c_tx_link0] \
    [get_ips jesd204c_tx_link1] \
    [get_ips jesd204_phy_tx_quad226] \
    [get_ips jesd204_phy_tx_quad227] \
    [get_ips mb_mcs_ctrl] \
]
foreach ip_obj $ip_objects {
    set ip_file [get_property IP_FILE $ip_obj]
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

if {$build_stage eq "route"} {
    puts "INFO: KU5P_BUILD_STAGE=route; stopping after route."
    close_project
    exit
}

write_bitstream -force [file join $build_dir ku5p_dac_only_top.bit]
close_project
exit
