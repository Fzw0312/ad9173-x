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

    wire [15:0] dac0_sample0 = scale_sample(dac0_raw0, dac0_scale);
    wire [15:0] dac0_sample1 = scale_sample(dac0_raw1, dac0_scale);
    wire [15:0] dac0_sample2 = scale_sample(dac0_raw2, dac0_scale);
    wire [15:0] dac0_sample3 = scale_sample(dac0_raw3, dac0_scale);
    wire [15:0] dac1_sample0 = scale_sample(dac1_raw0, dac1_scale);
    wire [15:0] dac1_sample1 = scale_sample(dac1_raw1, dac1_scale);
    wire [15:0] dac1_sample2 = scale_sample(dac1_raw2, dac1_scale);
    wire [15:0] dac1_sample3 = scale_sample(dac1_raw3, dac1_scale);
    wire [15:0] dac2_sample0 = scale_sample(dac2_raw0, dac2_scale);
    wire [15:0] dac2_sample1 = scale_sample(dac2_raw1, dac2_scale);
    wire [15:0] dac2_sample2 = scale_sample(dac2_raw2, dac2_scale);
    wire [15:0] dac2_sample3 = scale_sample(dac2_raw3, dac2_scale);
    wire [15:0] dac3_sample0 = scale_sample(dac3_raw0, dac3_scale);
    wire [15:0] dac3_sample1 = scale_sample(dac3_raw1, dac3_scale);
    wire [15:0] dac3_sample2 = scale_sample(dac3_raw2, dac3_scale);
    wire [15:0] dac3_sample3 = scale_sample(dac3_raw3, dac3_scale);

    function [15:0] quarter_sine;
        input [8:0] addr;
        begin
            case (addr)
                9'd0: quarter_sine = 16'h0000;
                9'd1: quarter_sine = 16'h0064;
                9'd2: quarter_sine = 16'h00c9;
                9'd3: quarter_sine = 16'h012d;
                9'd4: quarter_sine = 16'h0192;
                9'd5: quarter_sine = 16'h01f6;
                9'd6: quarter_sine = 16'h025a;
                9'd7: quarter_sine = 16'h02bf;
                9'd8: quarter_sine = 16'h0323;
                9'd9: quarter_sine = 16'h0387;
                9'd10: quarter_sine = 16'h03ec;
                9'd11: quarter_sine = 16'h0450;
                9'd12: quarter_sine = 16'h04b4;
                9'd13: quarter_sine = 16'h0518;
                9'd14: quarter_sine = 16'h057c;
                9'd15: quarter_sine = 16'h05e0;
                9'd16: quarter_sine = 16'h0644;
                9'd17: quarter_sine = 16'h06a8;
                9'd18: quarter_sine = 16'h070c;
                9'd19: quarter_sine = 16'h0770;
                9'd20: quarter_sine = 16'h07d4;
                9'd21: quarter_sine = 16'h0837;
                9'd22: quarter_sine = 16'h089b;
                9'd23: quarter_sine = 16'h08fe;
                9'd24: quarter_sine = 16'h0962;
                9'd25: quarter_sine = 16'h09c5;
                9'd26: quarter_sine = 16'h0a28;
                9'd27: quarter_sine = 16'h0a8b;
                9'd28: quarter_sine = 16'h0aee;
                9'd29: quarter_sine = 16'h0b51;
                9'd30: quarter_sine = 16'h0bb4;
                9'd31: quarter_sine = 16'h0c17;
                9'd32: quarter_sine = 16'h0c79;
                9'd33: quarter_sine = 16'h0cdc;
                9'd34: quarter_sine = 16'h0d3e;
                9'd35: quarter_sine = 16'h0da0;
                9'd36: quarter_sine = 16'h0e02;
                9'd37: quarter_sine = 16'h0e64;
                9'd38: quarter_sine = 16'h0ec6;
                9'd39: quarter_sine = 16'h0f28;
                9'd40: quarter_sine = 16'h0f89;
                9'd41: quarter_sine = 16'h0fea;
                9'd42: quarter_sine = 16'h104c;
                9'd43: quarter_sine = 16'h10ad;
                9'd44: quarter_sine = 16'h110e;
                9'd45: quarter_sine = 16'h116e;
                9'd46: quarter_sine = 16'h11cf;
                9'd47: quarter_sine = 16'h122f;
                9'd48: quarter_sine = 16'h128f;
                9'd49: quarter_sine = 16'h12ef;
                9'd50: quarter_sine = 16'h134f;
                9'd51: quarter_sine = 16'h13af;
                9'd52: quarter_sine = 16'h140e;
                9'd53: quarter_sine = 16'h146e;
                9'd54: quarter_sine = 16'h14cd;
                9'd55: quarter_sine = 16'h152c;
                9'd56: quarter_sine = 16'h158a;
                9'd57: quarter_sine = 16'h15e9;
                9'd58: quarter_sine = 16'h1647;
                9'd59: quarter_sine = 16'h16a5;
                9'd60: quarter_sine = 16'h1703;
                9'd61: quarter_sine = 16'h1760;
                9'd62: quarter_sine = 16'h17be;
                9'd63: quarter_sine = 16'h181b;
                9'd64: quarter_sine = 16'h1878;
                9'd65: quarter_sine = 16'h18d4;
                9'd66: quarter_sine = 16'h1931;
                9'd67: quarter_sine = 16'h198d;
                9'd68: quarter_sine = 16'h19e9;
                9'd69: quarter_sine = 16'h1a45;
                9'd70: quarter_sine = 16'h1aa0;
                9'd71: quarter_sine = 16'h1afb;
                9'd72: quarter_sine = 16'h1b56;
                9'd73: quarter_sine = 16'h1bb1;
                9'd74: quarter_sine = 16'h1c0b;
                9'd75: quarter_sine = 16'h1c65;
                9'd76: quarter_sine = 16'h1cbf;
                9'd77: quarter_sine = 16'h1d19;
                9'd78: quarter_sine = 16'h1d72;
                9'd79: quarter_sine = 16'h1dcb;
                9'd80: quarter_sine = 16'h1e24;
                9'd81: quarter_sine = 16'h1e7c;
                9'd82: quarter_sine = 16'h1ed4;
                9'd83: quarter_sine = 16'h1f2c;
                9'd84: quarter_sine = 16'h1f84;
                9'd85: quarter_sine = 16'h1fdb;
                9'd86: quarter_sine = 16'h2032;
                9'd87: quarter_sine = 16'h2089;
                9'd88: quarter_sine = 16'h20df;
                9'd89: quarter_sine = 16'h2135;
                9'd90: quarter_sine = 16'h218a;
                9'd91: quarter_sine = 16'h21e0;
                9'd92: quarter_sine = 16'h2235;
                9'd93: quarter_sine = 16'h228a;
                9'd94: quarter_sine = 16'h22de;
                9'd95: quarter_sine = 16'h2332;
                9'd96: quarter_sine = 16'h2386;
                9'd97: quarter_sine = 16'h23d9;
                9'd98: quarter_sine = 16'h242c;
                9'd99: quarter_sine = 16'h247f;
                9'd100: quarter_sine = 16'h24d1;
                9'd101: quarter_sine = 16'h2523;
                9'd102: quarter_sine = 16'h2574;
                9'd103: quarter_sine = 16'h25c6;
                9'd104: quarter_sine = 16'h2616;
                9'd105: quarter_sine = 16'h2667;
                9'd106: quarter_sine = 16'h26b7;
                9'd107: quarter_sine = 16'h2707;
                9'd108: quarter_sine = 16'h2756;
                9'd109: quarter_sine = 16'h27a5;
                9'd110: quarter_sine = 16'h27f4;
                9'd111: quarter_sine = 16'h2842;
                9'd112: quarter_sine = 16'h2890;
                9'd113: quarter_sine = 16'h28dd;
                9'd114: quarter_sine = 16'h292a;
                9'd115: quarter_sine = 16'h2977;
                9'd116: quarter_sine = 16'h29c3;
                9'd117: quarter_sine = 16'h2a0f;
                9'd118: quarter_sine = 16'h2a5a;
                9'd119: quarter_sine = 16'h2aa5;
                9'd120: quarter_sine = 16'h2af0;
                9'd121: quarter_sine = 16'h2b3a;
                9'd122: quarter_sine = 16'h2b84;
                9'd123: quarter_sine = 16'h2bcd;
                9'd124: quarter_sine = 16'h2c16;
                9'd125: quarter_sine = 16'h2c5f;
                9'd126: quarter_sine = 16'h2ca7;
                9'd127: quarter_sine = 16'h2cef;
                9'd128: quarter_sine = 16'h2d36;
                9'd129: quarter_sine = 16'h2d7d;
                9'd130: quarter_sine = 16'h2dc3;
                9'd131: quarter_sine = 16'h2e09;
                9'd132: quarter_sine = 16'h2e4e;
                9'd133: quarter_sine = 16'h2e94;
                9'd134: quarter_sine = 16'h2ed8;
                9'd135: quarter_sine = 16'h2f1c;
                9'd136: quarter_sine = 16'h2f60;
                9'd137: quarter_sine = 16'h2fa3;
                9'd138: quarter_sine = 16'h2fe6;
                9'd139: quarter_sine = 16'h3028;
                9'd140: quarter_sine = 16'h306a;
                9'd141: quarter_sine = 16'h30ab;
                9'd142: quarter_sine = 16'h30ec;
                9'd143: quarter_sine = 16'h312d;
                9'd144: quarter_sine = 16'h316d;
                9'd145: quarter_sine = 16'h31ac;
                9'd146: quarter_sine = 16'h31eb;
                9'd147: quarter_sine = 16'h322a;
                9'd148: quarter_sine = 16'h3268;
                9'd149: quarter_sine = 16'h32a5;
                9'd150: quarter_sine = 16'h32e2;
                9'd151: quarter_sine = 16'h331f;
                9'd152: quarter_sine = 16'h335b;
                9'd153: quarter_sine = 16'h3396;
                9'd154: quarter_sine = 16'h33d2;
                9'd155: quarter_sine = 16'h340c;
                9'd156: quarter_sine = 16'h3446;
                9'd157: quarter_sine = 16'h3480;
                9'd158: quarter_sine = 16'h34b9;
                9'd159: quarter_sine = 16'h34f1;
                9'd160: quarter_sine = 16'h3529;
                9'd161: quarter_sine = 16'h3561;
                9'd162: quarter_sine = 16'h3598;
                9'd163: quarter_sine = 16'h35cf;
                9'd164: quarter_sine = 16'h3605;
                9'd165: quarter_sine = 16'h363a;
                9'd166: quarter_sine = 16'h366f;
                9'd167: quarter_sine = 16'h36a3;
                9'd168: quarter_sine = 16'h36d7;
                9'd169: quarter_sine = 16'h370b;
                9'd170: quarter_sine = 16'h373e;
                9'd171: quarter_sine = 16'h3770;
                9'd172: quarter_sine = 16'h37a2;
                9'd173: quarter_sine = 16'h37d3;
                9'd174: quarter_sine = 16'h3804;
                9'd175: quarter_sine = 16'h3834;
                9'd176: quarter_sine = 16'h3863;
                9'd177: quarter_sine = 16'h3892;
                9'd178: quarter_sine = 16'h38c1;
                9'd179: quarter_sine = 16'h38ef;
                9'd180: quarter_sine = 16'h391c;
                9'd181: quarter_sine = 16'h3949;
                9'd182: quarter_sine = 16'h3976;
                9'd183: quarter_sine = 16'h39a1;
                9'd184: quarter_sine = 16'h39cc;
                9'd185: quarter_sine = 16'h39f7;
                9'd186: quarter_sine = 16'h3a21;
                9'd187: quarter_sine = 16'h3a4b;
                9'd188: quarter_sine = 16'h3a74;
                9'd189: quarter_sine = 16'h3a9c;
                9'd190: quarter_sine = 16'h3ac4;
                9'd191: quarter_sine = 16'h3aeb;
                9'd192: quarter_sine = 16'h3b12;
                9'd193: quarter_sine = 16'h3b38;
                9'd194: quarter_sine = 16'h3b5e;
                9'd195: quarter_sine = 16'h3b83;
                9'd196: quarter_sine = 16'h3ba7;
                9'd197: quarter_sine = 16'h3bcb;
                9'd198: quarter_sine = 16'h3bee;
                9'd199: quarter_sine = 16'h3c11;
                9'd200: quarter_sine = 16'h3c33;
                9'd201: quarter_sine = 16'h3c55;
                9'd202: quarter_sine = 16'h3c76;
                9'd203: quarter_sine = 16'h3c96;
                9'd204: quarter_sine = 16'h3cb6;
                9'd205: quarter_sine = 16'h3cd5;
                9'd206: quarter_sine = 16'h3cf4;
                9'd207: quarter_sine = 16'h3d12;
                9'd208: quarter_sine = 16'h3d2f;
                9'd209: quarter_sine = 16'h3d4c;
                9'd210: quarter_sine = 16'h3d68;
                9'd211: quarter_sine = 16'h3d84;
                9'd212: quarter_sine = 16'h3d9f;
                9'd213: quarter_sine = 16'h3dba;
                9'd214: quarter_sine = 16'h3dd3;
                9'd215: quarter_sine = 16'h3ded;
                9'd216: quarter_sine = 16'h3e05;
                9'd217: quarter_sine = 16'h3e1e;
                9'd218: quarter_sine = 16'h3e35;
                9'd219: quarter_sine = 16'h3e4c;
                9'd220: quarter_sine = 16'h3e62;
                9'd221: quarter_sine = 16'h3e78;
                9'd222: quarter_sine = 16'h3e8d;
                9'd223: quarter_sine = 16'h3ea2;
                9'd224: quarter_sine = 16'h3eb5;
                9'd225: quarter_sine = 16'h3ec9;
                9'd226: quarter_sine = 16'h3edb;
                9'd227: quarter_sine = 16'h3eee;
                9'd228: quarter_sine = 16'h3eff;
                9'd229: quarter_sine = 16'h3f10;
                9'd230: quarter_sine = 16'h3f20;
                9'd231: quarter_sine = 16'h3f30;
                9'd232: quarter_sine = 16'h3f3f;
                9'd233: quarter_sine = 16'h3f4d;
                9'd234: quarter_sine = 16'h3f5b;
                9'd235: quarter_sine = 16'h3f68;
                9'd236: quarter_sine = 16'h3f75;
                9'd237: quarter_sine = 16'h3f81;
                9'd238: quarter_sine = 16'h3f8c;
                9'd239: quarter_sine = 16'h3f97;
                9'd240: quarter_sine = 16'h3fa1;
                9'd241: quarter_sine = 16'h3fab;
                9'd242: quarter_sine = 16'h3fb4;
                9'd243: quarter_sine = 16'h3fbc;
                9'd244: quarter_sine = 16'h3fc4;
                9'd245: quarter_sine = 16'h3fcb;
                9'd246: quarter_sine = 16'h3fd1;
                9'd247: quarter_sine = 16'h3fd7;
                9'd248: quarter_sine = 16'h3fdc;
                9'd249: quarter_sine = 16'h3fe1;
                9'd250: quarter_sine = 16'h3fe5;
                9'd251: quarter_sine = 16'h3fe8;
                9'd252: quarter_sine = 16'h3feb;
                9'd253: quarter_sine = 16'h3fed;
                9'd254: quarter_sine = 16'h3fef;
                9'd255: quarter_sine = 16'h3ff0;
                9'd256: quarter_sine = 16'h3ff0;
                default: quarter_sine = 16'h0000;
            endcase
        end
    endfunction

    function [15:0] sine_sample;
        input [47:0] phase;
        reg   [7:0]  lut_addr;
        reg   [8:0]  mirror_addr;
        reg   [15:0] magnitude;
        begin
            lut_addr = phase[45:38];
            mirror_addr = 9'd256 - {1'b0, lut_addr};
            case (phase[47:46])
                2'b00: begin
                    magnitude   = quarter_sine({1'b0, lut_addr});
                    sine_sample = magnitude;
                end
                2'b01: begin
                    magnitude   = quarter_sine(mirror_addr);
                    sine_sample = magnitude;
                end
                2'b10: begin
                    magnitude   = quarter_sine({1'b0, lut_addr});
                    sine_sample = (magnitude == 16'd0) ? 16'd0 : (~magnitude + 16'd1);
                end
                default: begin
                    magnitude   = quarter_sine(mirror_addr);
                    sine_sample = (magnitude == 16'd0) ? 16'd0 : (~magnitude + 16'd1);
                end
            endcase
        end
    endfunction

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
                        // LF 通路时关闭 RF/DAC0、DAC1 侧 payload，避免 RF 侧串出。
                        data_out[255:192] <= 64'd0;
                        data_out[191:128] <= 64'd0;
                    end else begin
                        data_out[255:192] <= {
                            wave_ch0_sample3, wave_ch0_sample2,
                            wave_ch0_sample1, wave_ch0_sample0
                        };
                        data_out[191:128] <= {
                            wave_ch1_sample3, wave_ch1_sample2,
                            wave_ch1_sample1, wave_ch1_sample0
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
                dac0_raw0 <= sine_sample(dac0_phase0_r);
                dac0_raw1 <= sine_sample(dac0_phase1_r);
                dac0_raw2 <= sine_sample(dac0_phase2_r);
                dac0_raw3 <= sine_sample(dac0_phase3_r);
                dac1_raw0 <= sine_sample(dac1_phase0_r);
                dac1_raw1 <= sine_sample(dac1_phase1_r);
                dac1_raw2 <= sine_sample(dac1_phase2_r);
                dac1_raw3 <= sine_sample(dac1_phase3_r);
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
                        // LF 通路使用内部 DAC2 的 JESD 样点槽承载低频波形。
                        data_out[127:64] <= {
                            wave_ch0_sample3, wave_ch0_sample2,
                            wave_ch0_sample1, wave_ch0_sample0
                        };
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
                dac2_raw0 <= sine_sample(dac2_phase0_r);
                dac2_raw1 <= sine_sample(dac2_phase1_r);
                dac2_raw2 <= sine_sample(dac2_phase2_r);
                dac2_raw3 <= sine_sample(dac2_phase3_r);
                dac3_raw0 <= sine_sample(dac3_phase0_r);
                dac3_raw1 <= sine_sample(dac3_phase1_r);
                dac3_raw2 <= sine_sample(dac3_phase2_r);
                dac3_raw3 <= sine_sample(dac3_phase3_r);
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
