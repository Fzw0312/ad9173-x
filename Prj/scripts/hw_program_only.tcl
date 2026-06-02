set origin_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $origin_dir ..]]
set build_root [file normalize [file join $prj_dir .. build vivado ad9173_dac_udp]]
set build_dir  [file normalize [file join $build_root ku5p_vivado]]

if {[info exists ::env(KU5P_BUILD_ROOT)] && $::env(KU5P_BUILD_ROOT) ne ""} {
    set build_root [file normalize $::env(KU5P_BUILD_ROOT)]
    set build_dir  [file normalize [file join $build_root ku5p_vivado]]
}

set bit_file [file join $build_dir ku5p_bringup_top.bit]
set ltx_file [file join $build_dir ku5p_bringup_top.ltx]

if {[info exists ::env(KU5P_HW_BIT)] && $::env(KU5P_HW_BIT) ne ""} {
    set bit_file [file normalize $::env(KU5P_HW_BIT)]
}
if {[info exists ::env(KU5P_HW_LTX)] && $::env(KU5P_HW_LTX) ne ""} {
    set ltx_file [file normalize $::env(KU5P_HW_LTX)]
}

puts "INFO: bit_file=$bit_file"
puts "INFO: ltx_file=$ltx_file"

open_hw_manager
connect_hw_server -allow_non_jtag

set targets [get_hw_targets *]
if {[llength $targets] == 0} {
    error "No hardware target found."
}

current_hw_target [lindex $targets 0]
open_hw_target

set devices [get_hw_devices]
if {[llength $devices] == 0} {
    error "No hardware device found."
}

current_hw_device [lindex $devices 0]
set_property PROGRAM.FILE $bit_file [current_hw_device]
if {[file exists $ltx_file]} {
    set_property PROBES.FILE $ltx_file [current_hw_device]
} else {
    puts "INFO: no LTX file found; programming bitstream without debug probes."
}
program_hw_devices [current_hw_device]
refresh_hw_device [current_hw_device]

close_hw_manager
exit
