set origin_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $origin_dir ..]]
set build_root [file normalize [file join $prj_dir .. build vivado ad9173_dac_only]]
set build_dir  [file normalize [file join $build_root ku5p_vivado]]
set stage_dir  [file normalize [file join $build_root stage]]
set ip_dir     [file normalize [file join $build_dir ip]]
set build_jobs 4
set build_stage bit
set enable_ila 0

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
if {[info exists ::env(KU5P_ENABLE_ILA)] && $::env(KU5P_ENABLE_ILA) ne ""} {
    set enable_ila $::env(KU5P_ENABLE_ILA)
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

proc archive_existing_bit_outputs {build_root build_dir tag} {
    set outputs [list \
        [file join $build_dir ku5p_dac_only_top.bit] \
        [file join $build_dir ku5p_dac_only_top.ltx]]
    set have_existing 0
    foreach output $outputs {
        if {[file exists $output]} {
            set have_existing 1
        }
    }
    if {!$have_existing} {
        return
    }

    set stamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    set archive_dir [file join $build_root bit_archive "${stamp}_${tag}"]
    file mkdir $archive_dir
    foreach output $outputs {
        if {[file exists $output]} {
            file copy -force $output [file join $archive_dir [file tail $output]]
        }
    }
    puts "INFO: archived existing bit outputs to $archive_dir"
}

archive_existing_bit_outputs $build_root $build_dir "prebuild"
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
    [stage_file [file join $prj_dir src rtl common pe43711_serial_ctrl.v]         [file join $stage_dir src rtl common pe43711_serial_ctrl.v]] \
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

# JESD204C TX link0: 连接 AD9173 的 SERDIN0..3，承载 DAC0/DAC1 payload。
# HMC7044 给 FPGA 的 GT refclk 是 245.76 MHz；GT 线速配置为 9.8304 Gbps。
# RTL 中 JESD core clock 也是 245.76 MHz，每拍每个 DAC converter 送 4 个
# 16-bit 样点槽，因此每路 DAC payload sample rate 为 983.04 MSPS。
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

# JESD204C TX link1: 连接 AD9173 的另一组 SERDIN，承载 DAC2/DAC3 payload。
# 参数必须与 link0、AD9173 deframer 和 HMC7044 输出时钟保持一致。
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

# GT PHY quad226：对应板上 DAC_SERDIN0..3。
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

# GT PHY quad227：对应板上 DAC_SERDIN4..7。物理 lane 顺序在
# ad9173_init_table.v 的 crossbar 寄存器中重新映射。
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
set mb_debug_enabled 1
if {$enable_ila != 0} {
    set mb_debug_enabled 0
}
set_property -dict [list \
    CONFIG.FREQ {200.0} \
    CONFIG.MEMSIZE {16384} \
    CONFIG.USE_IO_BUS {1} \
    CONFIG.DEBUG_ENABLED $mb_debug_enabled \
    CONFIG.USE_BSCAN {0} \
] [get_ips mb_mcs_ctrl]

create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name runtime_vio -dir $ip_dir
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {7} \
    CONFIG.C_NUM_PROBE_OUT {15} \
    CONFIG.C_EN_PROBE_IN_ACTIVITY {1} \
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
    CONFIG.C_PROBE_OUT4_WIDTH {7} \
    CONFIG.C_PROBE_OUT5_WIDTH {1} \
    CONFIG.C_PROBE_OUT6_WIDTH {1} \
    CONFIG.C_PROBE_OUT7_WIDTH {48} \
    CONFIG.C_PROBE_OUT8_WIDTH {48} \
    CONFIG.C_PROBE_OUT9_WIDTH {32} \
    CONFIG.C_PROBE_OUT10_WIDTH {16} \
    CONFIG.C_PROBE_OUT11_WIDTH {8} \
    CONFIG.C_PROBE_OUT12_WIDTH {1} \
    CONFIG.C_PROBE_OUT13_WIDTH {48} \
    CONFIG.C_PROBE_OUT14_WIDTH {48} \
    CONFIG.C_PROBE_OUT0_INIT_VAL {0x50ff} \
    CONFIG.C_PROBE_OUT1_INIT_VAL {0x115c635403d6} \
    CONFIG.C_PROBE_OUT2_INIT_VAL {0x50ff} \
    CONFIG.C_PROBE_OUT3_INIT_VAL {0x01bc70553395} \
    CONFIG.C_PROBE_OUT4_INIT_VAL {0x40} \
    CONFIG.C_PROBE_OUT5_INIT_VAL {0x0} \
    CONFIG.C_PROBE_OUT6_INIT_VAL {0x0} \
    CONFIG.C_PROBE_OUT7_INIT_VAL {0x115c635403d6} \
    CONFIG.C_PROBE_OUT8_INIT_VAL {0x000000100000} \
    CONFIG.C_PROBE_OUT9_INIT_VAL {0x00030d40} \
    CONFIG.C_PROBE_OUT10_INIT_VAL {0x199a} \
    CONFIG.C_PROBE_OUT11_INIT_VAL {0x00} \
    CONFIG.C_PROBE_OUT12_INIT_VAL {0x0} \
    CONFIG.C_PROBE_OUT13_INIT_VAL {0x001bc7053395} \
    CONFIG.C_PROBE_OUT14_INIT_VAL {0x000000000000} \
] [get_ips runtime_vio]

if {$enable_ila != 0} {
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_dac_debug -dir $ip_dir
    set_property -dict [list \
        CONFIG.C_DATA_DEPTH {1024} \
        CONFIG.C_INPUT_PIPE_STAGES {1} \
        CONFIG.C_ADV_TRIGGER {false} \
        CONFIG.C_EN_STRG_QUAL {0} \
        CONFIG.C_NUM_OF_PROBES {15} \
        CONFIG.C_PROBE0_WIDTH {32} \
        CONFIG.C_PROBE1_WIDTH {32} \
        CONFIG.C_PROBE2_WIDTH {32} \
        CONFIG.C_PROBE3_WIDTH {16} \
        CONFIG.C_PROBE4_WIDTH {16} \
        CONFIG.C_PROBE5_WIDTH {16} \
        CONFIG.C_PROBE6_WIDTH {16} \
        CONFIG.C_PROBE7_WIDTH {16} \
        CONFIG.C_PROBE8_WIDTH {16} \
        CONFIG.C_PROBE9_WIDTH {16} \
        CONFIG.C_PROBE10_WIDTH {16} \
        CONFIG.C_PROBE11_WIDTH {64} \
        CONFIG.C_PROBE12_WIDTH {64} \
        CONFIG.C_PROBE13_WIDTH {64} \
        CONFIG.C_PROBE14_WIDTH {64} \
    ] [get_ips ila_dac_debug]
}

generate_target all [get_ips]
export_ip_user_files -of_objects [get_ips] -no_script -sync -force -quiet

add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse $xdc_file
if {$enable_ila != 0} {
    set_property verilog_define {KU5P_ENABLE_ILA} [current_fileset]
}
update_compile_order -fileset sources_1

set ip_objects [list \
    [get_ips jesd204c_tx_link0] \
    [get_ips jesd204c_tx_link1] \
    [get_ips jesd204_phy_tx_quad226] \
    [get_ips jesd204_phy_tx_quad227] \
    [get_ips mb_mcs_ctrl] \
    [get_ips runtime_vio] \
]
if {$enable_ila != 0} {
    lappend ip_objects [get_ips ila_dac_debug]
}
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
if {$enable_ila != 0} {
    write_debug_probes -force [file join $build_dir ku5p_dac_only_top.ltx]
} else {
    write_debug_probes -force [file join $build_dir ku5p_dac_only_top.ltx]
}
close_project
exit
