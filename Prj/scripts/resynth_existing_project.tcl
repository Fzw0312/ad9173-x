set origin_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $origin_dir ..]]
set build_root [file normalize [file join $prj_dir .. build vivado ad9173_dac_only]]
set build_dir  [file normalize [file join $build_root ku5p_vivado]]
set stage_dir  [file normalize [file join $build_root stage]]
set build_jobs 4

if {[info exists ::env(KU5P_PRJ_DIR)] && $::env(KU5P_PRJ_DIR) ne ""} {
    set prj_dir [file normalize $::env(KU5P_PRJ_DIR)]
}
if {[info exists ::env(KU5P_BUILD_ROOT)] && $::env(KU5P_BUILD_ROOT) ne ""} {
    set build_root [file normalize $::env(KU5P_BUILD_ROOT)]
    set build_dir  [file normalize [file join $build_root ku5p_vivado]]
    set stage_dir  [file normalize [file join $build_root stage]]
}
if {[info exists ::env(KU5P_VIVADO_JOBS)] && $::env(KU5P_VIVADO_JOBS) ne ""} {
    set build_jobs $::env(KU5P_VIVADO_JOBS)
}

proc stage_file {src dst} {
    file mkdir [file dirname $dst]
    file copy -force $src $dst
    return $dst
}

set xpr_file [file join $build_dir ku5p_dac_only.xpr]
if {![file exists $xpr_file]} {
    error "Existing Vivado project not found: $xpr_file"
}

set refresh_files [list \
    [stage_file [file join $prj_dir src rtl common jesd_phy_tx_axi_init.v] [file join $stage_dir src rtl common jesd_phy_tx_axi_init.v]] \
    [stage_file [file join $prj_dir src rtl common pattern_gen_256.v]      [file join $stage_dir src rtl common pattern_gen_256.v]] \
    [stage_file [file join $prj_dir src rtl common rgmii_rx.v]             [file join $stage_dir src rtl common rgmii_rx.v]] \
    [stage_file [file join $prj_dir src rtl common k5wg_udp_dac_config_rx.v] [file join $stage_dir src rtl common k5wg_udp_dac_config_rx.v]] \
    [stage_file [file join $prj_dir src rtl top ku5p_bringup_top.v]        [file join $stage_dir src rtl top ku5p_bringup_top.v]] \
]

set xdc_file [stage_file [file join $prj_dir src xdc ku5p_bringup.xdc] \
                         [file join $stage_dir src xdc ku5p_bringup.xdc]]

cd $build_dir
set_param general.maxThreads $build_jobs
open_project $xpr_file
set_property XPM_LIBRARIES {XPM_CDC XPM_MEMORY} [current_project]
foreach refresh_file $refresh_files {
    if {[llength [get_files -quiet $refresh_file]] == 0} {
        add_files -norecurse $refresh_file
    }
}
if {[llength [get_files -quiet $xdc_file]] == 0} {
    add_files -fileset constrs_1 -norecurse $xdc_file
}
update_compile_order -fileset sources_1

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

close_project
exit
