set origin_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $origin_dir ..]]
set build_root [file normalize [file join $prj_dir .. build vivado ad9173_dac_only]]
set build_dir  [file normalize [file join $build_root ku5p_vivado]]

if {[info exists ::env(KU5P_BUILD_ROOT)] && $::env(KU5P_BUILD_ROOT) ne ""} {
    set build_root [file normalize $::env(KU5P_BUILD_ROOT)]
    set build_dir  [file normalize [file join $build_root ku5p_vivado]]
}

set dcp_file [file join $build_dir post_route.dcp]
set ltx_file [file join $build_dir ku5p_dac_only_top.ltx]
set bit_file [file join $build_dir ku5p_dac_only_top.bit]
set run_reports 1

set_param general.maxThreads 1

if {[info exists ::env(KU5P_ROUTE_DCP)] && $::env(KU5P_ROUTE_DCP) ne ""} {
    set dcp_file [file normalize $::env(KU5P_ROUTE_DCP)]
}
if {[info exists ::env(KU5P_HW_LTX)] && $::env(KU5P_HW_LTX) ne ""} {
    set ltx_file [file normalize $::env(KU5P_HW_LTX)]
}
if {[info exists ::env(KU5P_HW_BIT)] && $::env(KU5P_HW_BIT) ne ""} {
    set bit_file [file normalize $::env(KU5P_HW_BIT)]
}
if {[info exists ::env(KU5P_WRITE_BIT_REPORTS)] && $::env(KU5P_WRITE_BIT_REPORTS) ne ""} {
    set run_reports $::env(KU5P_WRITE_BIT_REPORTS)
}

puts "INFO: dcp_file=$dcp_file"
puts "INFO: ltx_file=$ltx_file"
puts "INFO: bit_file=$bit_file"

if {![file exists $dcp_file]} {
    error "Route checkpoint not found: $dcp_file"
}

proc archive_existing_bit_outputs {build_root bit_file ltx_file tag} {
    set outputs [list $bit_file $ltx_file]
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

open_checkpoint $dcp_file
if {$run_reports} {
    report_timing_summary -file [file join $build_dir post_route_reopen_timing.rpt]
    catch {check_timing -verbose -file [file join $build_dir post_route_reopen_check_timing.rpt]}
    catch {report_drc -file [file join $build_dir post_route_reopen_drc.rpt]}
}
archive_existing_bit_outputs $build_root $bit_file $ltx_file "pre_write_bit"
catch {write_debug_probes -force $ltx_file}
write_bitstream -force $bit_file
close_design
exit
