`timescale 1ns/1ps

module mb_control_island (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] status0,
    input  wire [31:0] status1,

    output wire        cfg_valid,
    output wire        cfg_reset_phase,
    output wire [47:0] cfg_phase_inc0,
    output wire [47:0] cfg_phase_inc1,
    output wire [47:0] cfg_phase_inc2,
    output wire [47:0] cfg_phase_inc3,
    output wire [15:0] cfg_scale0,
    output wire [15:0] cfg_scale1,
    output wire [15:0] cfg_scale2,
    output wire [15:0] cfg_scale3,

    output wire [3:0]  rf_switch_sel,
    output wire [15:0] rf_atten0,
    output wire [15:0] rf_atten1,
    output wire [15:0] rf_atten2,
    output wire [15:0] rf_atten3,
    output wire [31:0] rf_control_flags,
    output wire [7:0]  dac0_profile,
    output wire [7:0]  dac1_profile
);

    wire        io_addr_strobe;
    wire [31:0] io_address;
    wire [3:0]  io_byte_enable;
    wire [31:0] io_read_data;
    wire        io_read_strobe;
    wire        io_ready;
    wire [31:0] io_write_data;
    wire        io_write_strobe;

    mb_mcs_ctrl u_mb_mcs_ctrl (
        .Clk             (clk),
        .Reset           (rst),
        .IO_addr_strobe  (io_addr_strobe),
        .IO_address      (io_address),
        .IO_byte_enable  (io_byte_enable),
        .IO_read_data    (io_read_data),
        .IO_read_strobe  (io_read_strobe),
        .IO_ready        (io_ready),
        .IO_write_data   (io_write_data),
        .IO_write_strobe (io_write_strobe)
    );

    mb_io_dac_regs u_mb_io_dac_regs (
        .clk             (clk),
        .rst             (rst),
        .io_addr_strobe  (io_addr_strobe),
        .io_address      (io_address),
        .io_byte_enable  (io_byte_enable),
        .io_read_data    (io_read_data),
        .io_read_strobe  (io_read_strobe),
        .io_ready        (io_ready),
        .io_write_data   (io_write_data),
        .io_write_strobe (io_write_strobe),
        .status0         (status0),
        .status1         (status1),
        .cfg_valid       (cfg_valid),
        .cfg_reset_phase (cfg_reset_phase),
        .cfg_phase_inc0  (cfg_phase_inc0),
        .cfg_phase_inc1  (cfg_phase_inc1),
        .cfg_phase_inc2  (cfg_phase_inc2),
        .cfg_phase_inc3  (cfg_phase_inc3),
        .cfg_scale0      (cfg_scale0),
        .cfg_scale1      (cfg_scale1),
        .cfg_scale2      (cfg_scale2),
        .cfg_scale3      (cfg_scale3),
        .rf_switch_sel   (rf_switch_sel),
        .rf_atten0       (rf_atten0),
        .rf_atten1       (rf_atten1),
        .rf_atten2       (rf_atten2),
        .rf_atten3       (rf_atten3),
        .rf_control_flags(rf_control_flags),
        .dac0_profile    (dac0_profile),
        .dac1_profile    (dac1_profile)
    );

endmodule
