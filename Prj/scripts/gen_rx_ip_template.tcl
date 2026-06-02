set origin_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $origin_dir ..]]
set temp_root  [file normalize [file join $prj_dir .. build vivado ad9173_ad6688 rx_ip_template]]
set ip_dir     [file join $temp_root ip]

file delete -force $temp_root
file mkdir $ip_dir
cd $temp_root

create_project rx_ip_template $temp_root -part xcku5p-ffvb676-2-i -force
set_property target_language Verilog [current_project]

create_ip -name jesd204c -vendor xilinx.com -library ip -version 4.2 -module_name jesd204c_rx_link0 -dir $ip_dir
set_property -dict [list \
    CONFIG.C_NODE_IS_TRANSMIT {0} \
    CONFIG.C_LANES {8} \
    CONFIG.Transceiver {GTYE4} \
    CONFIG.AXICLK_FREQ {200.0} \
    CONFIG.GT_Line_Rate {9.8304} \
    CONFIG.GT_REFCLK_FREQ {245.76} \
    CONFIG.GT_REFCLK_FREQ_REQUEST {245.76} \
    CONFIG.DRPCLK_FREQ {200.0} \
    CONFIG.C_PLL_SELECTION {1} \
    CONFIG.C_ENCODING {0} \
    CONFIG.C_USE_FEC {false} \
] [get_ips jesd204c_rx_link0]

generate_target all [get_ips jesd204c_rx_link0]
close_project
