`timescale 1ns/1ps

// Extract AD6688 real samples from the 256-bit JESD RX beat.
//
// This follows the VCK190 rx_mapper lane interpretation:
// data_in[31:0]    = lane0
// data_in[63:32]   = lane1
// data_in[95:64]   = lane2
// data_in[127:96]  = lane3
// data_in[159:128] = lane4
// data_in[191:160] = lane5
// data_in[223:192] = lane6
// data_in[255:224] = lane7
//
// For ADCA/ADC0, lanes 0..3 form four 32-bit complex samples per rx_core_clk.
// For ADCB/ADC1, lanes 4..7 form four 32-bit complex samples per rx_core_clk.
// COMPONENT_SELECT chooses which half of each 32-bit complex sample is sent
// to the single-channel UDP preview:
//   0: upper 16 bits, matching the original VCK190 "real" component.
//   1: lower 16 bits, the other DDC complex component.
//
// The selected 16-bit component is packed as:
//   sample0 in [15:0], sample1 in [31:16], sample2 in [47:32],
//   sample3 in [63:48].
module adc0_sample_packer #(
    parameter integer ADC_INDEX = 0,
    parameter integer COMPONENT_SELECT = 0
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         link_good,
    input  wire         jesd_valid,
    input  wire [255:0] jesd_data,
    output reg          sample_valid,
    output reg  [63:0]  sample_data,
    output reg  [31:0]  beat_count,
    output reg  [15:0]  first_sample_dbg
);

    wire [31:0] lane0 = (ADC_INDEX == 0) ? jesd_data[31:0]    : jesd_data[159:128];
    wire [31:0] lane1 = (ADC_INDEX == 0) ? jesd_data[63:32]   : jesd_data[191:160];
    wire [31:0] lane2 = (ADC_INDEX == 0) ? jesd_data[95:64]   : jesd_data[223:192];
    wire [31:0] lane3 = (ADC_INDEX == 0) ? jesd_data[127:96]  : jesd_data[255:224];

    wire [31:0] adc0_sample0 = {lane0[7:0],   lane1[7:0],   lane2[7:0],   lane3[7:0]};
    wire [31:0] adc0_sample1 = {lane0[15:8],  lane1[15:8],  lane2[15:8],  lane3[15:8]};
    wire [31:0] adc0_sample2 = {lane0[23:16], lane1[23:16], lane2[23:16], lane3[23:16]};
    wire [31:0] adc0_sample3 = {lane0[31:24], lane1[31:24], lane2[31:24], lane3[31:24]};

    wire [15:0] adc0_sample0_upper = adc0_sample0[31:16];
    wire [15:0] adc0_sample1_upper = adc0_sample1[31:16];
    wire [15:0] adc0_sample2_upper = adc0_sample2[31:16];
    wire [15:0] adc0_sample3_upper = adc0_sample3[31:16];

    wire [15:0] adc0_sample0_lower = adc0_sample0[15:0];
    wire [15:0] adc0_sample1_lower = adc0_sample1[15:0];
    wire [15:0] adc0_sample2_lower = adc0_sample2[15:0];
    wire [15:0] adc0_sample3_lower = adc0_sample3[15:0];

    wire [15:0] adc0_sample0_selected =
        (COMPONENT_SELECT == 0) ? adc0_sample0_upper : adc0_sample0_lower;
    wire [15:0] adc0_sample1_selected =
        (COMPONENT_SELECT == 0) ? adc0_sample1_upper : adc0_sample1_lower;
    wire [15:0] adc0_sample2_selected =
        (COMPONENT_SELECT == 0) ? adc0_sample2_upper : adc0_sample2_lower;
    wire [15:0] adc0_sample3_selected =
        (COMPONENT_SELECT == 0) ? adc0_sample3_upper : adc0_sample3_lower;

    always @(posedge clk) begin
        if (rst) begin
            sample_valid     <= 1'b0;
            sample_data      <= 64'd0;
            beat_count       <= 32'd0;
            first_sample_dbg <= 16'd0;
        end else begin
            sample_valid <= link_good && jesd_valid;
            if (link_good && jesd_valid) begin
                sample_data <= {
                    adc0_sample3_selected,
                    adc0_sample2_selected,
                    adc0_sample1_selected,
                    adc0_sample0_selected
                };
                first_sample_dbg <= adc0_sample0_selected;
                beat_count <= beat_count + 1'b1;
            end
        end
    end

endmodule
