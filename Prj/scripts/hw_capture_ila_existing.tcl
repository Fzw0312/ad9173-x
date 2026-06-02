set origin_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $origin_dir ..]]
set build_root [file normalize [file join $prj_dir .. build vivado ad9173_ad6688]]
set build_dir  [file normalize [file join $build_root ku5p_vivado]]

if {[info exists ::env(KU5P_BUILD_ROOT)] && $::env(KU5P_BUILD_ROOT) ne ""} {
    set build_root [file normalize $::env(KU5P_BUILD_ROOT)]
    set build_dir  [file normalize [file join $build_root ku5p_vivado]]
}

set ltx_file [file join $build_dir ku5p_bringup_top.ltx]
set csv_file [file join $build_root hw_ila_capture_existing.csv]

if {[info exists ::env(KU5P_HW_LTX)] && $::env(KU5P_HW_LTX) ne ""} {
    set ltx_file [file normalize $::env(KU5P_HW_LTX)]
}
if {[info exists ::env(KU5P_HW_CSV)] && $::env(KU5P_HW_CSV) ne ""} {
    set csv_file [file normalize $::env(KU5P_HW_CSV)]
}

puts "INFO: ltx_file=$ltx_file"
puts "INFO: csv_file=$csv_file"

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
set_property PROBES.FILE $ltx_file [current_hw_device]
refresh_hw_device [current_hw_device]

set ilas [get_hw_ilas]
if {[llength $ilas] == 0} {
    error "No ILA cores found on existing programmed device."
}
set ila [lindex $ilas 0]
puts "INFO: ila=$ila"
run_hw_ila $ila
wait_on_hw_ila $ila
set data [upload_hw_ila_data $ila]
display_hw_ila_data $data
write_hw_ila_data -force -csv_file $csv_file $data
puts "INFO: csv_written=$csv_file"
close_hw_manager
exit
