set origin_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $origin_dir ..]]
set build_root [file normalize [file join $prj_dir .. build vivado ad9173_dac_only]]
set build_dir  [file normalize [file join $build_root ku5p_vivado]]
set build_jobs 4

if {[info exists ::env(KU5P_BUILD_ROOT)] && $::env(KU5P_BUILD_ROOT) ne ""} {
    set build_root [file normalize $::env(KU5P_BUILD_ROOT)]
    set build_dir  [file normalize [file join $build_root ku5p_vivado]]
}
if {[info exists ::env(KU5P_VIVADO_JOBS)] && $::env(KU5P_VIVADO_JOBS) ne ""} {
    set build_jobs $::env(KU5P_VIVADO_JOBS)
}

set synth_dcp [file join $build_dir post_synth.dcp]
set route_dcp [file join $build_dir post_route.dcp]
set ltx_file  [file join $build_dir ku5p_dac_only_top.ltx]
set bit_file  [file join $build_dir ku5p_dac_only_top.bit]

if {[info exists ::env(KU5P_SYNTH_DCP)] && $::env(KU5P_SYNTH_DCP) ne ""} {
    set synth_dcp [file normalize $::env(KU5P_SYNTH_DCP)]
}
if {[info exists ::env(KU5P_ROUTE_DCP)] && $::env(KU5P_ROUTE_DCP) ne ""} {
    set route_dcp [file normalize $::env(KU5P_ROUTE_DCP)]
}
if {[info exists ::env(KU5P_HW_LTX)] && $::env(KU5P_HW_LTX) ne ""} {
    set ltx_file [file normalize $::env(KU5P_HW_LTX)]
}
if {[info exists ::env(KU5P_HW_BIT)] && $::env(KU5P_HW_BIT) ne ""} {
    set bit_file [file normalize $::env(KU5P_HW_BIT)]
}

puts "INFO: synth_dcp=$synth_dcp"
puts "INFO: route_dcp=$route_dcp"
puts "INFO: ltx_file=$ltx_file"
puts "INFO: bit_file=$bit_file"

if {![file exists $synth_dcp]} {
    error "Synthesis checkpoint not found: $synth_dcp"
}

file mkdir $build_dir
cd $build_dir
set_param general.maxThreads $build_jobs

open_checkpoint $synth_dcp
opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force $route_dcp
report_timing_summary -file [file join $build_dir post_route_timing.rpt]
report_utilization     -file [file join $build_dir post_route_util.rpt]
catch {report_clock_interaction -file [file join $build_dir post_route_clock_interaction.rpt]}
catch {check_timing -verbose -file [file join $build_dir post_route_check_timing.rpt]}
catch {report_drc -file [file join $build_dir post_route_drc.rpt]}
catch {report_bus_skew -file [file join $build_dir post_route_bus_skew.rpt]}
catch {write_debug_probes -force $ltx_file}
write_bitstream -force $bit_file

close_design
exit
