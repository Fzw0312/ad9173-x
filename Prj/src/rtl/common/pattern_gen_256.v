`timescale 1ns/1ps

module pattern_gen_256 #(
    parameter integer WAVE_ADDR_WIDTH = 12
) (
    input  wire         clk,
    input  wire [1:0]   rst,
    input  wire [1:0]   advance,
    input  wire         cfg_valid,
    input  wire         cfg_reset_phase,
    input  wire [47:0]  cfg_phase_inc0,
    input  wire [47:0]  cfg_phase_inc1,
    input  wire [47:0]  cfg_phase_inc2,
    input  wire [47:0]  cfg_phase_inc3,
    input  wire [15:0]  cfg_scale0,
    input  wire [15:0]  cfg_scale1,
    input  wire [15:0]  cfg_scale2,
    input  wire [15:0]  cfg_scale3,
    input  wire         wave_clk,
    input  wire         wave_rst,
    input  wire         wave_wr_en,
    input  wire [WAVE_ADDR_WIDTH-1:0] wave_wr_addr,
    input  wire [31:0]  wave_wr_data,
    input  wire [WAVE_ADDR_WIDTH:0] wave_total_samples,
    input  wire         wave_commit_toggle,
    output reg  [255:0] data_out
);

    // Payload-only tone generation: AD9173 NCO FTW is kept at zero, so these
    // DDS words directly set the analog output tones through JESD samples.
    // The JESD core clock is 245.76 MHz and each beat carries four
    // consecutive samples per converter, so each DAC stream is 983.04 MSPS.
    localparam [47:0] DAC0_PHASE_INC = 48'h053555555555; // 20 MHz
    localparam [47:0] DAC1_PHASE_INC = 48'h07d000000000; // 30 MHz
    localparam [47:0] DAC2_PHASE_INC = 48'h053555555555; // 20 MHz mirror
    localparam [47:0] DAC3_PHASE_INC = 48'h07d000000000; // 30 MHz mirror
    localparam integer WAVE_BEAT_ADDR_WIDTH = WAVE_ADDR_WIDTH - 2;
    localparam integer WAVE_MEMORY_BITS = (1 << WAVE_ADDR_WIDTH) * 32;

    reg [47:0] dac0_phase;
    reg [47:0] dac1_phase;
    reg [47:0] dac2_phase;
    reg [47:0] dac3_phase;
    reg [47:0] dac0_phase_inc;
    reg [47:0] dac1_phase_inc;
    reg [47:0] dac2_phase_inc;
    reg [47:0] dac3_phase_inc;
    reg [15:0] dac0_scale;
    reg [15:0] dac1_scale;
    reg [15:0] dac2_scale;
    reg [15:0] dac3_scale;
    reg [WAVE_BEAT_ADDR_WIDTH-1:0] wave_read_beat;
    reg [WAVE_BEAT_ADDR_WIDTH:0] wave_beat_limit;
    reg [1:0] wave_rd_valid_pipe;
    reg wave_active;
    (* ASYNC_REG = "TRUE" *) reg [2:0] wave_commit_meta;
    wire [127:0] wave_mem_dout;
    wire wave_mem_rd_en = wave_active && (|advance);
    wire [0:0] wave_mem_wea = (!wave_rst && wave_wr_en) ? 1'b1 : 1'b0;

    wire [47:0] dac0_phase0 = dac0_phase;
    wire [47:0] dac0_phase1 = dac0_phase + dac0_phase_inc;
    wire [47:0] dac0_phase2 = dac0_phase + (dac0_phase_inc << 1);
    wire [47:0] dac0_phase3 = dac0_phase + (dac0_phase_inc << 1) + dac0_phase_inc;
    wire [47:0] dac1_phase0 = dac1_phase;
    wire [47:0] dac1_phase1 = dac1_phase + dac1_phase_inc;
    wire [47:0] dac1_phase2 = dac1_phase + (dac1_phase_inc << 1);
    wire [47:0] dac1_phase3 = dac1_phase + (dac1_phase_inc << 1) + dac1_phase_inc;
    wire [47:0] dac2_phase0 = dac2_phase;
    wire [47:0] dac2_phase1 = dac2_phase + dac2_phase_inc;
    wire [47:0] dac2_phase2 = dac2_phase + (dac2_phase_inc << 1);
    wire [47:0] dac2_phase3 = dac2_phase + (dac2_phase_inc << 1) + dac2_phase_inc;
    wire [47:0] dac3_phase0 = dac3_phase;
    wire [47:0] dac3_phase1 = dac3_phase + dac3_phase_inc;
    wire [47:0] dac3_phase2 = dac3_phase + (dac3_phase_inc << 1);
    wire [47:0] dac3_phase3 = dac3_phase + (dac3_phase_inc << 1) + dac3_phase_inc;

    wire wave_commit_seen = wave_commit_meta[2] ^ wave_commit_meta[1];
    wire [WAVE_BEAT_ADDR_WIDTH:0] wave_total_beats_raw =
        (wave_total_samples[WAVE_ADDR_WIDTH:2] +
         ((wave_total_samples[1:0] != 2'b00) ? 1'b1 : 1'b0));
    wire [WAVE_BEAT_ADDR_WIDTH:0] wave_total_beats =
        (wave_total_beats_raw == {WAVE_BEAT_ADDR_WIDTH+1{1'b0}}) ?
        {{WAVE_BEAT_ADDR_WIDTH{1'b0}}, 1'b1} : wave_total_beats_raw;
    wire [WAVE_BEAT_ADDR_WIDTH:0] wave_next_beat_ext =
        {1'b0, wave_read_beat} + {{WAVE_BEAT_ADDR_WIDTH{1'b0}}, 1'b1};
    wire wave_next_wrap = (wave_next_beat_ext >= wave_beat_limit);
    wire [WAVE_BEAT_ADDR_WIDTH-1:0] wave_next_beat =
        wave_next_wrap ? {WAVE_BEAT_ADDR_WIDTH{1'b0}} :
        wave_next_beat_ext[WAVE_BEAT_ADDR_WIDTH-1:0];
    wire wave_word_valid = wave_rd_valid_pipe[1];
    wire [15:0] wave_ch0_sample0 = wave_mem_dout[15:0];
    wire [15:0] wave_ch1_sample0 = wave_mem_dout[31:16];
    wire [15:0] wave_ch0_sample1 = wave_mem_dout[47:32];
    wire [15:0] wave_ch1_sample1 = wave_mem_dout[63:48];
    wire [15:0] wave_ch0_sample2 = wave_mem_dout[79:64];
    wire [15:0] wave_ch1_sample2 = wave_mem_dout[95:80];
    wire [15:0] wave_ch0_sample3 = wave_mem_dout[111:96];
    wire [15:0] wave_ch1_sample3 = wave_mem_dout[127:112];

    wire [15:0] dac0_sample0 = scale_sample(sine_sample(dac0_phase0), dac0_scale);
    wire [15:0] dac0_sample1 = scale_sample(sine_sample(dac0_phase1), dac0_scale);
    wire [15:0] dac0_sample2 = scale_sample(sine_sample(dac0_phase2), dac0_scale);
    wire [15:0] dac0_sample3 = scale_sample(sine_sample(dac0_phase3), dac0_scale);
    wire [15:0] dac1_sample0 = scale_sample(sine_sample(dac1_phase0), dac1_scale);
    wire [15:0] dac1_sample1 = scale_sample(sine_sample(dac1_phase1), dac1_scale);
    wire [15:0] dac1_sample2 = scale_sample(sine_sample(dac1_phase2), dac1_scale);
    wire [15:0] dac1_sample3 = scale_sample(sine_sample(dac1_phase3), dac1_scale);
    wire [15:0] dac2_sample0 = scale_sample(sine_sample(dac2_phase0), dac2_scale);
    wire [15:0] dac2_sample1 = scale_sample(sine_sample(dac2_phase1), dac2_scale);
    wire [15:0] dac2_sample2 = scale_sample(sine_sample(dac2_phase2), dac2_scale);
    wire [15:0] dac2_sample3 = scale_sample(sine_sample(dac2_phase3), dac2_scale);
    wire [15:0] dac3_sample0 = scale_sample(sine_sample(dac3_phase0), dac3_scale);
    wire [15:0] dac3_sample1 = scale_sample(sine_sample(dac3_phase1), dac3_scale);
    wire [15:0] dac3_sample2 = scale_sample(sine_sample(dac3_phase2), dac3_scale);
    wire [15:0] dac3_sample3 = scale_sample(sine_sample(dac3_phase3), dac3_scale);

    function [15:0] quarter_sine;
        input [5:0] addr;
        begin
            case (addr)
                6'd0:  quarter_sine = 16'h0000;
                6'd1:  quarter_sine = 16'h0192;
                6'd2:  quarter_sine = 16'h0324;
                6'd3:  quarter_sine = 16'h04b5;
                6'd4:  quarter_sine = 16'h0646;
                6'd5:  quarter_sine = 16'h07d6;
                6'd6:  quarter_sine = 16'h0964;
                6'd7:  quarter_sine = 16'h0af1;
                6'd8:  quarter_sine = 16'h0c7c;
                6'd9:  quarter_sine = 16'h0e05;
                6'd10: quarter_sine = 16'h0f8c;
                6'd11: quarter_sine = 16'h1111;
                6'd12: quarter_sine = 16'h1294;
                6'd13: quarter_sine = 16'h1413;
                6'd14: quarter_sine = 16'h1590;
                6'd15: quarter_sine = 16'h1709;
                6'd16: quarter_sine = 16'h187e;
                6'd17: quarter_sine = 16'h19f0;
                6'd18: quarter_sine = 16'h1b5d;
                6'd19: quarter_sine = 16'h1cc6;
                6'd20: quarter_sine = 16'h1e2b;
                6'd21: quarter_sine = 16'h1f8c;
                6'd22: quarter_sine = 16'h20e7;
                6'd23: quarter_sine = 16'h223d;
                6'd24: quarter_sine = 16'h238e;
                6'd25: quarter_sine = 16'h24da;
                6'd26: quarter_sine = 16'h2620;
                6'd27: quarter_sine = 16'h2760;
                6'd28: quarter_sine = 16'h289a;
                6'd29: quarter_sine = 16'h29ce;
                6'd30: quarter_sine = 16'h2afb;
                6'd31: quarter_sine = 16'h2c21;
                6'd32: quarter_sine = 16'h2d41;
                6'd33: quarter_sine = 16'h2e5a;
                6'd34: quarter_sine = 16'h2f6c;
                6'd35: quarter_sine = 16'h3076;
                6'd36: quarter_sine = 16'h3179;
                6'd37: quarter_sine = 16'h3274;
                6'd38: quarter_sine = 16'h3368;
                6'd39: quarter_sine = 16'h3453;
                6'd40: quarter_sine = 16'h3537;
                6'd41: quarter_sine = 16'h3612;
                6'd42: quarter_sine = 16'h36e5;
                6'd43: quarter_sine = 16'h37b0;
                6'd44: quarter_sine = 16'h3871;
                6'd45: quarter_sine = 16'h392b;
                6'd46: quarter_sine = 16'h39da;
                6'd47: quarter_sine = 16'h3a82;
                6'd48: quarter_sine = 16'h3b20;
                6'd49: quarter_sine = 16'h3bb6;
                6'd50: quarter_sine = 16'h3c42;
                6'd51: quarter_sine = 16'h3cc5;
                6'd52: quarter_sine = 16'h3d3e;
                6'd53: quarter_sine = 16'h3dae;
                6'd54: quarter_sine = 16'h3e14;
                6'd55: quarter_sine = 16'h3e70;
                6'd56: quarter_sine = 16'h3ec3;
                6'd57: quarter_sine = 16'h3f0c;
                6'd58: quarter_sine = 16'h3f4b;
                6'd59: quarter_sine = 16'h3f80;
                6'd60: quarter_sine = 16'h3fab;
                6'd61: quarter_sine = 16'h3fcc;
                6'd62: quarter_sine = 16'h3fe3;
                6'd63: quarter_sine = 16'h3ff0;
                default: quarter_sine = 16'h0000;
            endcase
        end
    endfunction

    function [15:0] sine_sample;
        input [47:0] phase;
        reg   [5:0]  lut_addr;
        reg   [15:0] magnitude;
        begin
            lut_addr = phase[45:40];
            case (phase[47:46])
                2'b00: begin
                    magnitude   = quarter_sine(lut_addr);
                    sine_sample = magnitude;
                end
                2'b01: begin
                    magnitude   = quarter_sine(~lut_addr);
                    sine_sample = magnitude;
                end
                2'b10: begin
                    magnitude   = quarter_sine(lut_addr);
                    sine_sample = (magnitude == 16'd0) ? 16'd0 : (~magnitude + 16'd1);
                end
                default: begin
                    magnitude   = quarter_sine(~lut_addr);
                    sine_sample = (magnitude == 16'd0) ? 16'd0 : (~magnitude + 16'd1);
                end
            endcase
        end
    endfunction

    function [15:0] signed_shift_sample;
        input [15:0] sample;
        input [3:0]  shift;
        reg signed [15:0] signed_sample;
        begin
            signed_sample = sample;
            case (shift)
                4'd0: signed_shift_sample = signed_sample;
                4'd1: signed_shift_sample = signed_sample >>> 1;
                4'd2: signed_shift_sample = signed_sample >>> 2;
                4'd3: signed_shift_sample = signed_sample >>> 3;
                4'd4: signed_shift_sample = signed_sample >>> 4;
                4'd5: signed_shift_sample = signed_sample >>> 5;
                4'd6: signed_shift_sample = signed_sample >>> 6;
                4'd7: signed_shift_sample = signed_sample >>> 7;
                default: signed_shift_sample = 16'd0;
            endcase
        end
    endfunction

    function [15:0] scale_sample;
        input [15:0] sample;
        input [15:0] scale;
        begin
            // Coarse power-of-two amplitude scaling keeps HostApp channel
            // enable/amplitude control without placing 16 unpipelined DSPs on
            // the 245.76 MHz JESD sample path.
            if (scale == 16'd0) begin
                scale_sample = 16'd0;
            end else if (scale >= 16'h6000) begin
                scale_sample = sample;
            end else if (scale >= 16'h3000) begin
                scale_sample = signed_shift_sample(sample, 4'd1);
            end else if (scale >= 16'h1800) begin
                scale_sample = signed_shift_sample(sample, 4'd2);
            end else if (scale >= 16'h0c00) begin
                scale_sample = signed_shift_sample(sample, 4'd3);
            end else if (scale >= 16'h0600) begin
                scale_sample = signed_shift_sample(sample, 4'd4);
            end else if (scale >= 16'h0300) begin
                scale_sample = signed_shift_sample(sample, 4'd5);
            end else if (scale >= 16'h0180) begin
                scale_sample = signed_shift_sample(sample, 4'd6);
            end else if (scale >= 16'h00c0) begin
                scale_sample = signed_shift_sample(sample, 4'd7);
            end else begin
                scale_sample = 16'd0;
            end
        end
    endfunction

    xpm_memory_sdpram #(
        .MEMORY_SIZE       (WAVE_MEMORY_BITS),
        .MEMORY_PRIMITIVE  ("block"),
        .CLOCKING_MODE     ("independent_clock"),
        .ECC_MODE          ("no_ecc"),
        .MEMORY_INIT_FILE  ("none"),
        .MEMORY_INIT_PARAM ("0"),
        .USE_MEM_INIT      (0),
        .WAKEUP_TIME       ("disable_sleep"),
        .AUTO_SLEEP_TIME   (0),
        .MESSAGE_CONTROL   (0),
        .MEMORY_OPTIMIZATION("true"),
        .CASCADE_HEIGHT    (0),
        .WRITE_DATA_WIDTH_A(32),
        .BYTE_WRITE_WIDTH_A(32),
        .ADDR_WIDTH_A      (WAVE_ADDR_WIDTH),
        .READ_DATA_WIDTH_B (128),
        .ADDR_WIDTH_B      (WAVE_BEAT_ADDR_WIDTH),
        .READ_RESET_VALUE_B("0"),
        .READ_LATENCY_B    (2),
        .WRITE_MODE_B      ("no_change")
    ) u_wave_bram (
        .sleep          (1'b0),
        .clka           (wave_clk),
        .ena            (1'b1),
        .wea            (wave_mem_wea),
        .addra          (wave_wr_addr),
        .dina           (wave_wr_data),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .clkb           (clk),
        .rstb           (rst[0]),
        .enb            (wave_mem_rd_en),
        .regceb         (1'b1),
        .addrb          (wave_read_beat),
        .doutb          (wave_mem_dout),
        .sbiterrb       (),
        .dbiterrb       ()
    );

    always @(posedge clk) begin
        wave_commit_meta <= {wave_commit_meta[1:0], wave_commit_toggle};
        if (rst[0]) begin
            dac0_phase <= 32'd0;
            dac1_phase <= 32'd0;
            dac0_phase_inc <= cfg_phase_inc0;
            dac1_phase_inc <= cfg_phase_inc1;
            dac0_scale <= cfg_scale0;
            dac1_scale <= cfg_scale1;
            data_out[255:128] <= 128'd0;
            wave_active <= 1'b0;
            wave_read_beat <= {WAVE_BEAT_ADDR_WIDTH{1'b0}};
            wave_beat_limit <= {{WAVE_BEAT_ADDR_WIDTH{1'b0}}, 1'b1};
            wave_rd_valid_pipe <= 2'b00;
            wave_commit_meta <= 3'b000;
        end else begin
            wave_rd_valid_pipe <= {wave_rd_valid_pipe[0], wave_mem_rd_en};
            if (cfg_valid) begin
                dac0_phase_inc <= cfg_phase_inc0;
                dac1_phase_inc <= cfg_phase_inc1;
                dac0_scale <= cfg_scale0;
                dac1_scale <= cfg_scale1;
                wave_active <= 1'b0;
                wave_rd_valid_pipe <= 2'b00;
            end
            if (wave_commit_seen) begin
                wave_active <= 1'b1;
                wave_read_beat <= {WAVE_BEAT_ADDR_WIDTH{1'b0}};
                wave_beat_limit <= wave_total_beats;
                wave_rd_valid_pipe <= 2'b00;
            end else if (cfg_valid && cfg_reset_phase) begin
                dac0_phase <= 32'd0;
                dac1_phase <= 32'd0;
            end else if (wave_active && (|advance)) begin
                wave_read_beat <= wave_next_beat;
                if (wave_word_valid) begin
                    data_out[255:192] <= {
                        wave_ch0_sample3, wave_ch0_sample2,
                        wave_ch0_sample1, wave_ch0_sample0
                    };
                    data_out[191:128] <= {
                        wave_ch1_sample3, wave_ch1_sample2,
                        wave_ch1_sample1, wave_ch1_sample0
                    };
                end
            end else if (advance[0]) begin
                dac0_phase <= dac0_phase + (dac0_phase_inc << 2);
                dac1_phase <= dac1_phase + (dac1_phase_inc << 2);
                data_out[255:192] <= {
                    dac0_sample3, dac0_sample2, dac0_sample1, dac0_sample0
                };
                data_out[191:128] <= {
                    dac1_sample3, dac1_sample2, dac1_sample1, dac1_sample0
                };
            end
        end
        if (rst[1]) begin
            dac2_phase <= 32'd0;
            dac3_phase <= 32'd0;
            dac2_phase_inc <= cfg_phase_inc2;
            dac3_phase_inc <= cfg_phase_inc3;
            dac2_scale <= cfg_scale2;
            dac3_scale <= cfg_scale3;
            data_out[127:0] <= 128'd0;
        end else begin
            if (cfg_valid) begin
                dac2_phase_inc <= cfg_phase_inc2;
                dac3_phase_inc <= cfg_phase_inc3;
                dac2_scale <= cfg_scale2;
                dac3_scale <= cfg_scale3;
            end
            if (wave_active && (|advance)) begin
                if (wave_word_valid) begin
                    data_out[127:64] <= {
                        wave_ch0_sample3, wave_ch0_sample2,
                        wave_ch0_sample1, wave_ch0_sample0
                    };
                    data_out[63:0] <= {
                        wave_ch1_sample3, wave_ch1_sample2,
                        wave_ch1_sample1, wave_ch1_sample0
                    };
                end
            end else if (cfg_valid && cfg_reset_phase) begin
                dac2_phase <= 32'd0;
                dac3_phase <= 32'd0;
            end else if (advance[1]) begin
                dac2_phase <= dac2_phase + (dac2_phase_inc << 2);
                dac3_phase <= dac3_phase + (dac3_phase_inc << 2);
                data_out[127:64] <= {
                    dac2_sample3, dac2_sample2, dac2_sample1, dac2_sample0
                };
                data_out[63:0] <= {
                    dac3_sample3, dac3_sample2, dac3_sample1, dac3_sample0
                };
            end
        end
    end

endmodule
