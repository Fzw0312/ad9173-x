set origin_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $origin_dir ..]]
set build_root [file normalize [file join $prj_dir .. build vivado ad9173_dac_only]]
set build_dir  [file normalize [file join $build_root ku5p_vivado]]

if {[info exists ::env(KU5P_BUILD_ROOT)] && $::env(KU5P_BUILD_ROOT) ne ""} {
    set build_root [file normalize $::env(KU5P_BUILD_ROOT)]
    set build_dir  [file normalize [file join $build_root ku5p_vivado]]
}

set ltx_file [file join $build_dir ku5p_dac_only_top.ltx]
if {[info exists ::env(KU5P_HW_LTX)] && $::env(KU5P_HW_LTX) ne ""} {
    set ltx_file [file normalize $::env(KU5P_HW_LTX)]
}

proc usage {} {
    puts "Usage:"
    puts "  vivado -mode batch -source Prj/scripts/hw_runtime_vio_nco_apply.tcl -tclargs status"
    puts "  vivado -mode batch -source Prj/scripts/hw_runtime_vio_nco_apply.tcl -tclargs apply <ch0_amp_hex> <ch0_ftw_hex> <ch1_amp_hex> <ch1_ftw_hex> ?relay_mask_hex? ?path_sel?"
    puts "Example:"
    puts "  vivado -mode batch -source Prj/scripts/hw_runtime_vio_nco_apply.tcl -tclargs apply 50ff 115c635403d6 50ff 01bc70553395 9 1"
}

proc norm_hex {value width_bits} {
    set value [string trim $value]
    regsub -nocase {^0x} $value {} value
    set width_nibbles [expr {($width_bits + 3) / 4}]
    if {$value eq ""} {
        set value "0"
    }
    if {![regexp -nocase {^[0-9a-f]+$} $value]} {
        error "Invalid hex value '$value'"
    }
    regsub -nocase {^0+} $value {} value
    if {$value eq ""} {
        set value "0"
    }
    if {[string length $value] > $width_nibbles} {
        error "Hex value '$value' does not fit in $width_bits bits"
    }
    return "[string repeat 0 [expr {$width_nibbles - [string length $value]}]]$value"
}

proc mapped_probe_name {name} {
    switch -- $name {
        probe_in0  {return mb_status0_1}
        probe_in1  {return mb_status1}
        probe_in2  {return dac_status_dbg}
        probe_in3  {return dac_sanity_dbg}
        probe_in4  {return dac_debug_dbg}
        probe_in5  {return dac_runtime_dbg}
        probe_in6  {return relay_atten_status_word}
        probe_out0 {return runtime_ch0_amp_vio}
        probe_out1 {return runtime_ch0_ftw_vio}
        probe_out2 {return runtime_ch1_amp_vio}
        probe_out3 {return runtime_ch1_ftw_vio}
        probe_out4 {return runtime_relay_atten_mask_vio}
        probe_out5 {return runtime_output_path_sel_vio}
        probe_out6 {return runtime_apply_toggle_vio}
        probe_out7 {return runtime_sweep_stop_ftw_vio}
        probe_out8 {return runtime_sweep_step_ftw_vio}
        probe_out9 {return runtime_sweep_interval_vio}
        probe_out10 {return runtime_sweep_log_shift_vio}
        probe_out11 {return runtime_sweep_control_vio}
        probe_out12 {return runtime_sweep_toggle_vio}
        probe_out13 {return runtime_sweep_segment_ftw_vio}
        default    {return $name}
    }
}

proc probe_by_name {vio name} {
    set logical_name $name
    set name [mapped_probe_name $name]
    set matches [get_hw_probes -quiet $name -of_objects $vio]
    if {[llength $matches] == 0} {
        set matches [get_hw_probes -quiet */$name -of_objects $vio]
    }
    if {[llength $matches] == 0} {
        foreach probe [get_hw_probes -of_objects $vio] {
            if {[get_property NAME $probe] eq $name} {
                lappend matches $probe
            }
        }
    }
    if {[llength $matches] == 0} {
        error "Cannot find VIO probe $logical_name ($name)"
    }
    return [lindex $matches 0]
}

proc set_out {vio name value width_bits} {
    set probe [probe_by_name $vio $name]
    set hex_value [norm_hex $value $width_bits]
    set_property OUTPUT_VALUE $hex_value $probe
    commit_hw_vio $probe
    puts "SET $name=$hex_value"
}

proc get_out {vio name} {
    set probe [probe_by_name $vio $name]
    set value [get_property OUTPUT_VALUE $probe]
    puts "OUT $name=$value"
    return $value
}

proc get_in {vio name} {
    set probe [probe_by_name $vio $name]
    set value [get_property INPUT_VALUE $probe]
    puts "IN  $name=$value"
    return $value
}

proc print_status {vio} {
    refresh_hw_vio $vio
    puts "---- VIO outputs ----"
    get_out $vio probe_out0
    get_out $vio probe_out1
    get_out $vio probe_out2
    get_out $vio probe_out3
    get_out $vio probe_out4
    get_out $vio probe_out5
    get_out $vio probe_out6
    get_out $vio probe_out7
    get_out $vio probe_out8
    get_out $vio probe_out9
    get_out $vio probe_out10
    get_out $vio probe_out11
    get_out $vio probe_out12
    get_out $vio probe_out13
    puts "---- VIO inputs ----"
    get_in $vio probe_in0
    get_in $vio probe_in1
    get_in $vio probe_in2
    get_in $vio probe_in3
    get_in $vio probe_in4
    get_in $vio probe_in5
    get_in $vio probe_in6
}

set mode "status"
if {[llength $argv] > 0} {
    set mode [lindex $argv 0]
}

if {$mode ne "status" && $mode ne "apply"} {
    usage
    error "Unknown mode: $mode"
}
if {$mode eq "apply" && [llength $argv] < 5} {
    usage
    error "apply mode needs at least 4 values"
}

puts "INFO: ltx_file=$ltx_file"

open_hw_manager
catch {disconnect_hw_server}
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
if {[file exists $ltx_file]} {
    set_property PROBES.FILE $ltx_file [current_hw_device]
    set_property FULL_PROBES.FILE $ltx_file [current_hw_device]
}
refresh_hw_device [current_hw_device]

set vios [get_hw_vios]
if {[llength $vios] == 0} {
    error "No VIO core found. Check that the bitstream and LTX match."
}
set vio [lindex $vios 0]
puts "INFO: vio=$vio"

if {$mode eq "status"} {
    print_status $vio
} else {
    set ch0_amp [lindex $argv 1]
    set ch0_ftw [lindex $argv 2]
    set ch1_amp [lindex $argv 3]
    set ch1_ftw [lindex $argv 4]
    set relay_mask "0"
    set path_sel "1"
    if {[llength $argv] >= 6} {
        set relay_mask [lindex $argv 5]
    }
    if {[llength $argv] >= 7} {
        set path_sel [lindex $argv 6]
    }

    refresh_hw_vio $vio
    set old_apply [get_property OUTPUT_VALUE [probe_by_name $vio probe_out6]]
    set_out $vio probe_out0 $ch0_amp 16
    set_out $vio probe_out1 $ch0_ftw 48
    set_out $vio probe_out2 $ch1_amp 16
    set_out $vio probe_out3 $ch1_ftw 48
    set_out $vio probe_out4 $relay_mask 4
    set_out $vio probe_out5 $path_sel 1

    if {[string match -nocase "*1" $old_apply]} {
        set new_apply 0
    } else {
        set new_apply 1
    }
    set_out $vio probe_out6 $new_apply 1
    after 500
    print_status $vio
}

close_hw_manager
exit
