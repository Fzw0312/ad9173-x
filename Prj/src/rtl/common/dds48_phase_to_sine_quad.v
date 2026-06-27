`timescale 1ns/1ps

module dds48_phase_to_sine_quad (
    input  wire         clk,
    input  wire         rst,
    input  wire         enable,
    input  wire         phase_reset,
    input  wire [47:0]  phase0,
    input  wire [47:0]  phase1,
    input  wire [47:0]  phase2,
    input  wire [47:0]  phase3,
    output reg  [15:0]  sample0,
    output reg  [15:0]  sample1,
    output reg  [15:0]  sample2,
    output reg  [15:0]  sample3,
    output reg          valid
);

    localparam [2:0] WARMUP_CYCLES = 3'd6;

    wire [15:0] phase_word0 = phase0[47:32];
    wire [15:0] phase_word1 = phase1[47:32];
    wire [15:0] phase_word2 = phase2[47:32];
    wire [15:0] phase_word3 = phase3[47:32];

    wire dds_valid0;
    wire dds_valid1;
    wire dds_valid2;
    wire dds_valid3;
    wire [15:0] dds_sample0;
    wire [15:0] dds_sample1;
    wire [15:0] dds_sample2;
    wire [15:0] dds_sample3;

    reg [2:0] warmup_cnt;

    dds_phase_to_sine u_dds0 (
        .aclk                 (clk),
        .s_axis_phase_tvalid   (enable && !rst),
        .s_axis_phase_tdata    (phase_word0),
        .m_axis_data_tvalid    (dds_valid0),
        .m_axis_data_tdata     (dds_sample0)
    );

    dds_phase_to_sine u_dds1 (
        .aclk                 (clk),
        .s_axis_phase_tvalid   (enable && !rst),
        .s_axis_phase_tdata    (phase_word1),
        .m_axis_data_tvalid    (dds_valid1),
        .m_axis_data_tdata     (dds_sample1)
    );

    dds_phase_to_sine u_dds2 (
        .aclk                 (clk),
        .s_axis_phase_tvalid   (enable && !rst),
        .s_axis_phase_tdata    (phase_word2),
        .m_axis_data_tvalid    (dds_valid2),
        .m_axis_data_tdata     (dds_sample2)
    );

    dds_phase_to_sine u_dds3 (
        .aclk                 (clk),
        .s_axis_phase_tvalid   (enable && !rst),
        .s_axis_phase_tdata    (phase_word3),
        .m_axis_data_tvalid    (dds_valid3),
        .m_axis_data_tdata     (dds_sample3)
    );

    always @(posedge clk) begin
        if (rst || phase_reset) begin
            warmup_cnt <= WARMUP_CYCLES;
            sample0 <= 16'd0;
            sample1 <= 16'd0;
            sample2 <= 16'd0;
            sample3 <= 16'd0;
            valid   <= 1'b0;
        end else begin
            if (!enable) begin
                warmup_cnt <= WARMUP_CYCLES;
                valid <= 1'b0;
            end else if (warmup_cnt != 3'd0) begin
                warmup_cnt <= warmup_cnt - 3'd1;
                valid <= 1'b0;
            end else begin
                valid <= dds_valid0 & dds_valid1 & dds_valid2 & dds_valid3;
                if (dds_valid0) sample0 <= dds_sample0;
                if (dds_valid1) sample1 <= dds_sample1;
                if (dds_valid2) sample2 <= dds_sample2;
                if (dds_valid3) sample3 <= dds_sample3;
            end
        end
    end

endmodule
