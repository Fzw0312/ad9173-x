set origin_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $origin_dir ..]]
set build_root [file normalize [file join $prj_dir .. build vivado ad9173_ad6688]]
set build_dir  [file normalize [file join $build_root ku5p_vivado]]

if {[info exists ::env(KU5P_BUILD_ROOT)] && $::env(KU5P_BUILD_ROOT) ne ""} {
    set build_root [file normalize $::env(KU5P_BUILD_ROOT)]
    set build_dir  [file normalize [file join $build_root ku5p_vivado]]
}

set bit_file      [file join $build_dir ku5p_bringup_top.bit]
set ltx_file      [file join $build_dir ku5p_bringup_top.ltx]
set csv_file      [file join $build_root hw_ila_trigger_capture.csv]
set trigger_probe adc_done
set trigger_value "eq1'b1"
set trigger_pos   1024

if {[info exists ::env(KU5P_HW_BIT)] && $::env(KU5P_HW_BIT) ne ""} {
    set bit_file [file normalize $::env(KU5P_HW_BIT)]
}
if {[info exists ::env(KU5P_HW_LTX)] && $::env(KU5P_HW_LTX) ne ""} {
    set ltx_file [file normalize $::env(KU5P_HW_LTX)]
}
if {[info exists ::env(KU5P_HW_CSV)] && $::env(KU5P_HW_CSV) ne ""} {
    set csv_file [file normalize $::env(KU5P_HW_CSV)]
}
if {[info exists ::env(KU5P_HW_TRIGGER_PROBE)] && $::env(KU5P_HW_TRIGGER_PROBE) ne ""} {
    set trigger_probe $::env(KU5P_HW_TRIGGER_PROBE)
}
if {[info exists ::env(KU5P_HW_TRIGGER_VALUE)] && $::env(KU5P_HW_TRIGGER_VALUE) ne ""} {
    set trigger_value $::env(KU5P_HW_TRIGGER_VALUE)
}
if {[info exists ::env(KU5P_HW_TRIGGER_POSITION)] && $::env(KU5P_HW_TRIGGER_POSITION) ne ""} {
    set trigger_pos $::env(KU5P_HW_TRIGGER_POSITION)
}

puts "INFO: bit_file=$bit_file"
puts "INFO: ltx_file=$ltx_file"
puts "INFO: csv_file=$csv_file"
puts "INFO: trigger_probe=$trigger_probe"
puts "INFO: trigger_value=$trigger_value"
puts "INFO: trigger_pos=$trigger_pos"

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
set_property PROBES.FILE  $ltx_file [current_hw_device]
program_hw_devices [current_hw_device]
refresh_hw_device [current_hw_device]

set ilas [get_hw_ilas]
if {[llength $ilas] == 0} {
    error "No ILA cores found after programming."
}

set ila [lindex $ilas 0]
puts "INFO: ila=$ila"

set probes [get_hw_probes -of_objects $ila]
puts "INFO: probe_count=[llength $probes]"
foreach probe $probes {
    puts "INFO: probe=$probe"
}

set trig [get_hw_probes $trigger_probe -of_objects $ila]
if {[llength $trig] == 0} {
    error "Trigger probe '$trigger_probe' not found."
}

set_property TRIGGER_COMPARE_VALUE $trigger_value [lindex $trig 0]
catch {set_property CONTROL.TRIGGER_POSITION $trigger_pos $ila}
catch {commit_hw_ila $ila}

run_hw_ila $ila
wait_on_hw_ila $ila
set data [upload_hw_ila_data $ila]
display_hw_ila_data $data
write_hw_ila_data -force -csv_file $csv_file $data

puts "INFO: ila_data=$data"
puts "INFO: csv_written=$csv_file"

close_hw_manager
exit
