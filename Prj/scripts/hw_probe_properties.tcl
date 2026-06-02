set origin_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $origin_dir ..]]
set build_root [file normalize [file join $prj_dir .. build vivado ad9173_ad6688]]
set build_dir  [file normalize [file join $build_root ku5p_vivado]]

if {[info exists ::env(KU5P_BUILD_ROOT)] && $::env(KU5P_BUILD_ROOT) ne ""} {
    set build_root [file normalize $::env(KU5P_BUILD_ROOT)]
    set build_dir  [file normalize [file join $build_root ku5p_vivado]]
}

set ltx_file [file join $build_dir ku5p_bringup_top.ltx]
if {[info exists ::env(KU5P_HW_LTX)] && $::env(KU5P_HW_LTX) ne ""} {
    set ltx_file [file normalize $::env(KU5P_HW_LTX)]
}

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
catch {set_property PROBES.FILE $ltx_file [current_hw_device]}
catch {refresh_hw_device [current_hw_device]} refresh_result
puts "INFO: refresh_result=$refresh_result"

puts "INFO: hw_device=[current_hw_device]"
foreach prop [lsort [list_property [current_hw_device]]] {
    set value [get_property $prop [current_hw_device]]
    if {[string match -nocase "*probe*" $prop] ||
        [string match -nocase "*uuid*" $prop] ||
        [string match -nocase "*program*" $prop] ||
        [string match -nocase "*core*" $prop]} {
        puts "DEVICE_PROP $prop=$value"
    }
}

set ilas [get_hw_ilas]
puts "INFO: ila_count=[llength $ilas]"
foreach ila $ilas {
    puts "INFO: ila=$ila"
    foreach prop [lsort [list_property $ila]] {
        set value [get_property $prop $ila]
        puts "ILA_PROP $ila $prop=$value"
    }
}

close_hw_manager
exit
