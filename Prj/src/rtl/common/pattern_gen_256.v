`timescale 1ns/1ps

module pattern_gen_256 #(
    parameter integer WAVE_ADDR_WIDTH = 12
) (
    input  wire         clk,
    input  wire [1:0]   rst,
    input  wire [1:0]   advance,
    input  wire         cfg_valid,
    input  wire         cfg_reset_phase,
    input  wire         cfg_ram_mode,
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
    input  wire         output_path_sel,
    output reg  [255:0] data_out
);

    // FPGA 侧 JESD 样点发生器。
    //
    // 两种输出来源：
    // 1. DDS 单音样点：用 48-bit 相位累加器和 quarter_sine 表生成正弦。
    // 2. RAM 任意波形：从 UDP 写入的 waveform RAM 中读出 CH0/CH1 样点。
    //
    // data_out 是 4 个 DAC converter、每个 converter 每拍 4 个连续样点：
    //   data_out[255:192] -> DAC0 的 4 个 16-bit 样点
    //   data_out[191:128] -> DAC1 的 4 个 16-bit 样点
    //   data_out[127:64]  -> DAC2 的 4 个 16-bit 样点
    //   data_out[63:0]    -> DAC3 的 4 个 16-bit 样点
    //
    // 当前工程送入 JESD 的是 16-bit two's-complement 样点槽。若外部只想
    // 使用 14-bit 有效码，应在生成样点时左对齐到 [15:2]，低 2 bit 清零。
    //
    // AD9173 NCO FTW 保持 0 时，这些 JESD payload 样点直接决定模拟输出
    // 频率。JESD core clock 为 245.76 MHz，每拍 4 个样点，所以每路 DAC
    // payload sample rate 为 983.04 MSPS。
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
    reg [47:0] dac0_phase0_r;
    reg [47:0] dac0_phase1_r;
    reg [47:0] dac0_phase2_r;
    reg [47:0] dac0_phase3_r;
    reg [47:0] dac1_phase0_r;
    reg [47:0] dac1_phase1_r;
    reg [47:0] dac1_phase2_r;
    reg [47:0] dac1_phase3_r;
    reg [47:0] dac2_phase0_r;
    reg [47:0] dac2_phase1_r;
    reg [47:0] dac2_phase2_r;
    reg [47:0] dac2_phase3_r;
    reg [47:0] dac3_phase0_r;
    reg [47:0] dac3_phase1_r;
    reg [47:0] dac3_phase2_r;
    reg [47:0] dac3_phase3_r;
    reg [15:0] dac0_raw0;
    reg [15:0] dac0_raw1;
    reg [15:0] dac0_raw2;
    reg [15:0] dac0_raw3;
    reg [15:0] dac1_raw0;
    reg [15:0] dac1_raw1;
    reg [15:0] dac1_raw2;
    reg [15:0] dac1_raw3;
    reg [15:0] dac2_raw0;
    reg [15:0] dac2_raw1;
    reg [15:0] dac2_raw2;
    reg [15:0] dac2_raw3;
    reg [15:0] dac3_raw0;
    reg [15:0] dac3_raw1;
    reg [15:0] dac3_raw2;
    reg [15:0] dac3_raw3;
    reg [15:0] dac0_dds0;
    reg [15:0] dac0_dds1;
    reg [15:0] dac0_dds2;
    reg [15:0] dac0_dds3;
    reg [15:0] dac1_dds0;
    reg [15:0] dac1_dds1;
    reg [15:0] dac1_dds2;
    reg [15:0] dac1_dds3;
    reg [15:0] dac2_dds0;
    reg [15:0] dac2_dds1;
    reg [15:0] dac2_dds2;
    reg [15:0] dac2_dds3;
    reg [15:0] dac3_dds0;
    reg [15:0] dac3_dds1;
    reg [15:0] dac3_dds2;
    reg [15:0] dac3_dds3;
    reg [WAVE_BEAT_ADDR_WIDTH-1:0] wave_read_beat;
    reg [WAVE_BEAT_ADDR_WIDTH:0] wave_beat_limit;
    reg [1:0] wave_rd_valid_pipe;
    reg wave_active;
    (* ASYNC_REG = "TRUE" *) reg [2:0] wave_commit_meta;
    wire [127:0] wave_mem_dout;
    wire wave_mem_rd_en = wave_active && (|advance);
    wire [0:0] wave_mem_wea = (!wave_rst && wave_wr_en) ? 1'b1 : 1'b0;
    wire dds0_valid;
    wire dds1_valid;
    wire dds2_valid;
    wire dds3_valid;
    wire [15:0] dds0_sample0;
    wire [15:0] dds0_sample1;
    wire [15:0] dds0_sample2;
    wire [15:0] dds0_sample3;
    wire [15:0] dds1_sample0;
    wire [15:0] dds1_sample1;
    wire [15:0] dds1_sample2;
    wire [15:0] dds1_sample3;
    wire [15:0] dds2_sample0;
    wire [15:0] dds2_sample1;
    wire [15:0] dds2_sample2;
    wire [15:0] dds2_sample3;
    wire [15:0] dds3_sample0;
    wire [15:0] dds3_sample1;
    wire [15:0] dds3_sample2;
    wire [15:0] dds3_sample3;

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
    // waveform RAM 每个地址写入一个 CH0/CH1 16-bit 样点对。
    // JESD 每拍需要 4 个样点，所以 RAM 读口一次取出 4 个样点对。
    wire [15:0] wave_ch0_sample0 = wave_mem_dout[15:0];
    wire [15:0] wave_ch1_sample0 = wave_mem_dout[31:16];
    wire [15:0] wave_ch0_sample1 = wave_mem_dout[47:32];
    wire [15:0] wave_ch1_sample1 = wave_mem_dout[63:48];
    wire [15:0] wave_ch0_sample2 = wave_mem_dout[79:64];
    wire [15:0] wave_ch1_sample2 = wave_mem_dout[95:80];
    wire [15:0] wave_ch0_sample3 = wave_mem_dout[111:96];
    wire [15:0] wave_ch1_sample3 = wave_mem_dout[127:112];

    wire [15:0] dac0_sample0 = scale_sample(dac0_dds0, dac0_scale);
    wire [15:0] dac0_sample1 = scale_sample(dac0_dds1, dac0_scale);
    wire [15:0] dac0_sample2 = scale_sample(dac0_dds2, dac0_scale);
    wire [15:0] dac0_sample3 = scale_sample(dac0_dds3, dac0_scale);
    wire [15:0] dac1_sample0 = scale_sample(dac1_dds0, dac1_scale);
    wire [15:0] dac1_sample1 = scale_sample(dac1_dds1, dac1_scale);
    wire [15:0] dac1_sample2 = scale_sample(dac1_dds2, dac1_scale);
    wire [15:0] dac1_sample3 = scale_sample(dac1_dds3, dac1_scale);
    wire [15:0] dac2_sample0 = scale_sample(dac2_dds0, dac2_scale);
    wire [15:0] dac2_sample1 = scale_sample(dac2_dds1, dac2_scale);
    wire [15:0] dac2_sample2 = scale_sample(dac2_dds2, dac2_scale);
    wire [15:0] dac2_sample3 = scale_sample(dac2_dds3, dac2_scale);
    wire [15:0] dac3_sample0 = scale_sample(dac3_dds0, dac3_scale);
    wire [15:0] dac3_sample1 = scale_sample(dac3_dds1, dac3_scale);
    wire [15:0] dac3_sample2 = scale_sample(dac3_dds2, dac3_scale);
    wire [15:0] dac3_sample3 = scale_sample(dac3_dds3, dac3_scale);

    // 幅度缩放：输入和输出都是 signed 16-bit 样点。
    // scale 使用 unsigned Q1.15 风格，0 表示静音，接近 0x7fff 表示满幅。
    function [15:0] scale_sample;
        input [15:0] sample;
        input [15:0] scale;
        reg signed [15:0] signed_sample;
        reg signed [32:0] product;
        begin
            if (scale == 16'd0) begin
                scale_sample = 16'd0;
            end else begin
                signed_sample = sample;
                product = (signed_sample * $signed({1'b0, scale})) + 33'sd16384;
                scale_sample = product[30:15];
            end
        end
    endfunction

    function [15:0] invert_sample;
        input [15:0] sample;
        reg signed [15:0] signed_sample;
        begin
            signed_sample = sample;
            if (sample == 16'h8000) begin
                invert_sample = 16'h7fff;
            end else begin
                invert_sample = -signed_sample;
            end
        end
    endfunction

    always @* begin
        dac0_dds0 = invert_sample(dac0_raw0);
        dac0_dds1 = invert_sample(dac0_raw1);
        dac0_dds2 = invert_sample(dac0_raw2);
        dac0_dds3 = invert_sample(dac0_raw3);
        dac1_dds0 = invert_sample(dac1_raw0);
        dac1_dds1 = invert_sample(dac1_raw1);
        dac1_dds2 = invert_sample(dac1_raw2);
        dac1_dds3 = invert_sample(dac1_raw3);
        dac2_dds0 = invert_sample(dac2_raw0);
        dac2_dds1 = invert_sample(dac2_raw1);
        dac2_dds2 = invert_sample(dac2_raw2);
        dac2_dds3 = invert_sample(dac2_raw3);
        dac3_dds0 = invert_sample(dac3_raw0);
        dac3_dds1 = invert_sample(dac3_raw1);
        dac3_dds2 = invert_sample(dac3_raw2);
        dac3_dds3 = invert_sample(dac3_raw3);
        if (dac0_phase_inc == 48'd0) begin
            dac0_dds0 = 16'h8001;
            dac0_dds1 = 16'h8001;
            dac0_dds2 = 16'h8001;
            dac0_dds3 = 16'h8001;
        end
        if (dac1_phase_inc == 48'd0) begin
            dac1_dds0 = 16'h8001;
            dac1_dds1 = 16'h8001;
            dac1_dds2 = 16'h8001;
            dac1_dds3 = 16'h8001;
        end
        if (dac2_phase_inc == 48'd0) begin
            dac2_dds0 = 16'h8001;
            dac2_dds1 = 16'h8001;
            dac2_dds2 = 16'h8001;
            dac2_dds3 = 16'h8001;
        end
        if (dac3_phase_inc == 48'd0) begin
            dac3_dds0 = 16'h8001;
            dac3_dds1 = 16'h8001;
            dac3_dds2 = 16'h8001;
            dac3_dds3 = 16'h8001;
        end
    end

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

    dds48_phase_to_sine_quad u_dds0 (
        .clk        (clk),
        .rst        (rst[0]),
        .enable     (advance[0]),
        .phase_reset(cfg_valid && cfg_reset_phase),
        .phase0     (dac0_phase0),
        .phase1     (dac0_phase1),
        .phase2     (dac0_phase2),
        .phase3     (dac0_phase3),
        .sample0    (dds0_sample0),
        .sample1    (dds0_sample1),
        .sample2    (dds0_sample2),
        .sample3    (dds0_sample3),
        .valid      (dds0_valid)
    );

    dds48_phase_to_sine_quad u_dds1 (
        .clk        (clk),
        .rst        (rst[0]),
        .enable     (advance[0]),
        .phase_reset(cfg_valid && cfg_reset_phase),
        .phase0     (dac1_phase0),
        .phase1     (dac1_phase1),
        .phase2     (dac1_phase2),
        .phase3     (dac1_phase3),
        .sample0    (dds1_sample0),
        .sample1    (dds1_sample1),
        .sample2    (dds1_sample2),
        .sample3    (dds1_sample3),
        .valid      (dds1_valid)
    );

    dds48_phase_to_sine_quad u_dds2 (
        .clk        (clk),
        .rst        (rst[1]),
        .enable     (advance[1]),
        .phase_reset(cfg_valid && cfg_reset_phase),
        .phase0     (dac2_phase0),
        .phase1     (dac2_phase1),
        .phase2     (dac2_phase2),
        .phase3     (dac2_phase3),
        .sample0    (dds2_sample0),
        .sample1    (dds2_sample1),
        .sample2    (dds2_sample2),
        .sample3    (dds2_sample3),
        .valid      (dds2_valid)
    );

    dds48_phase_to_sine_quad u_dds3 (
        .clk        (clk),
        .rst        (rst[1]),
        .enable     (advance[1]),
        .phase_reset(cfg_valid && cfg_reset_phase),
        .phase0     (dac3_phase0),
        .phase1     (dac3_phase1),
        .phase2     (dac3_phase2),
        .phase3     (dac3_phase3),
        .sample0    (dds3_sample0),
        .sample1    (dds3_sample1),
        .sample2    (dds3_sample2),
        .sample3    (dds3_sample3),
        .valid      (dds3_valid)
    );

    always @(posedge clk) begin
        wave_commit_meta <= {wave_commit_meta[1:0], wave_commit_toggle};
        if (rst[0]) begin
            dac0_phase <= 48'd0;
            dac1_phase <= 48'd0;
            dac0_phase_inc <= cfg_phase_inc0;
            dac1_phase_inc <= cfg_phase_inc1;
            dac0_scale <= cfg_scale0;
            dac1_scale <= cfg_scale1;
            dac0_phase0_r <= 48'd0;
            dac0_phase1_r <= 48'd0;
            dac0_phase2_r <= 48'd0;
            dac0_phase3_r <= 48'd0;
            dac1_phase0_r <= 48'd0;
            dac1_phase1_r <= 48'd0;
            dac1_phase2_r <= 48'd0;
            dac1_phase3_r <= 48'd0;
            dac0_raw0 <= 16'd0;
            dac0_raw1 <= 16'd0;
            dac0_raw2 <= 16'd0;
            dac0_raw3 <= 16'd0;
            dac1_raw0 <= 16'd0;
            dac1_raw1 <= 16'd0;
            dac1_raw2 <= 16'd0;
            dac1_raw3 <= 16'd0;
            data_out[255:128] <= 128'd0;
            wave_active <= 1'b0;
            wave_read_beat <= {WAVE_BEAT_ADDR_WIDTH{1'b0}};
            wave_beat_limit <= {{WAVE_BEAT_ADDR_WIDTH{1'b0}}, 1'b1};
            wave_rd_valid_pipe <= 2'b00;
            wave_commit_meta <= 3'b000;
        end else begin
            wave_rd_valid_pipe <= {wave_rd_valid_pipe[0], wave_mem_rd_en};
            if (cfg_valid) begin
                // HostApp/UDP/VIO 下发新的 DDS FTW 和幅度。
                // cfg_ram_mode=1 表示这次配置只更新 RAM 播放参数，不打断
                // 当前 RAM 任意波形输出。
                dac0_phase_inc <= cfg_phase_inc0;
                dac1_phase_inc <= cfg_phase_inc1;
                dac0_scale <= cfg_scale0;
                dac1_scale <= cfg_scale1;
                if (!cfg_ram_mode) begin
                    wave_active <= 1'b0;
                    wave_rd_valid_pipe <= 2'b00;
                end
            end
            if (wave_commit_seen) begin
                // UDP DATA/COMMIT 完成后，切到 RAM 任意波形播放。
                wave_active <= 1'b1;
                wave_read_beat <= {WAVE_BEAT_ADDR_WIDTH{1'b0}};
                wave_beat_limit <= wave_total_beats;
                wave_rd_valid_pipe <= 2'b00;
            end else if (cfg_valid && cfg_reset_phase) begin
                dac0_phase <= 48'd0;
                dac1_phase <= 48'd0;
            end else if (wave_active && (|advance)) begin
                wave_read_beat <= wave_next_beat;
                if (wave_word_valid) begin
                    if (output_path_sel) begin
                        // LF RAM uses DAC1; keep DAC0 quiet.
                        data_out[255:192] <= 64'd0;
                        data_out[191:128] <= {
                            invert_sample(wave_ch0_sample3), invert_sample(wave_ch0_sample2),
                            invert_sample(wave_ch0_sample1), invert_sample(wave_ch0_sample0)
                        };
                    end else begin
                        data_out[255:192] <= {
                            invert_sample(wave_ch0_sample3), invert_sample(wave_ch0_sample2),
                            invert_sample(wave_ch0_sample1), invert_sample(wave_ch0_sample0)
                        };
                        data_out[191:128] <= {
                            invert_sample(wave_ch1_sample3), invert_sample(wave_ch1_sample2),
                            invert_sample(wave_ch1_sample1), invert_sample(wave_ch1_sample0)
                        };
                    end
                end
            end else if (advance[0]) begin
                dac0_phase0_r <= dac0_phase0;
                dac0_phase1_r <= dac0_phase1;
                dac0_phase2_r <= dac0_phase2;
                dac0_phase3_r <= dac0_phase3;
                dac1_phase0_r <= dac1_phase0;
                dac1_phase1_r <= dac1_phase1;
                dac1_phase2_r <= dac1_phase2;
                dac1_phase3_r <= dac1_phase3;
                dac0_raw0 <= dds0_sample0;
                dac0_raw1 <= dds0_sample1;
                dac0_raw2 <= dds0_sample2;
                dac0_raw3 <= dds0_sample3;
                dac1_raw0 <= dds1_sample0;
                dac1_raw1 <= dds1_sample1;
                dac1_raw2 <= dds1_sample2;
                dac1_raw3 <= dds1_sample3;
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
            dac2_phase <= 48'd0;
            dac3_phase <= 48'd0;
            dac2_phase_inc <= cfg_phase_inc2;
            dac3_phase_inc <= cfg_phase_inc3;
            dac2_scale <= cfg_scale2;
            dac3_scale <= cfg_scale3;
            dac2_phase0_r <= 48'd0;
            dac2_phase1_r <= 48'd0;
            dac2_phase2_r <= 48'd0;
            dac2_phase3_r <= 48'd0;
            dac3_phase0_r <= 48'd0;
            dac3_phase1_r <= 48'd0;
            dac3_phase2_r <= 48'd0;
            dac3_phase3_r <= 48'd0;
            dac2_raw0 <= 16'd0;
            dac2_raw1 <= 16'd0;
            dac2_raw2 <= 16'd0;
            dac2_raw3 <= 16'd0;
            dac3_raw0 <= 16'd0;
            dac3_raw1 <= 16'd0;
            dac3_raw2 <= 16'd0;
            dac3_raw3 <= 16'd0;
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
                    if (output_path_sel) begin
                        data_out[127:64] <= 64'd0;
                    end else begin
                        // RF 通路时关闭 LF 侧 payload，保证同时只有一路输出。
                        data_out[127:64] <= 64'd0;
                    end
                    data_out[63:0] <= 64'd0;
                end
            end else if (cfg_valid && cfg_reset_phase) begin
                dac2_phase <= 48'd0;
                dac3_phase <= 48'd0;
            end else if (advance[1]) begin
                dac2_phase0_r <= dac2_phase0;
                dac2_phase1_r <= dac2_phase1;
                dac2_phase2_r <= dac2_phase2;
                dac2_phase3_r <= dac2_phase3;
                dac3_phase0_r <= dac3_phase0;
                dac3_phase1_r <= dac3_phase1;
                dac3_phase2_r <= dac3_phase2;
                dac3_phase3_r <= dac3_phase3;
                dac2_raw0 <= dds2_sample0;
                dac2_raw1 <= dds2_sample1;
                dac2_raw2 <= dds2_sample2;
                dac2_raw3 <= dds2_sample3;
                dac3_raw0 <= dds3_sample0;
                dac3_raw1 <= dds3_sample1;
                dac3_raw2 <= dds3_sample2;
                dac3_raw3 <= dds3_sample3;
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
