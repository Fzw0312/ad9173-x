`timescale 1ns/1ps

module mb_io_dac_regs #(
    parameter [47:0] DEFAULT_DAC0_FTW = 48'h053555555555,
    parameter [47:0] DEFAULT_DAC1_FTW = 48'h07d000000000,
    parameter [47:0] DEFAULT_DAC2_FTW = 48'h053555555555,
    parameter [47:0] DEFAULT_DAC3_FTW = 48'h07d000000000
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        io_addr_strobe,
    input  wire [31:0] io_address,
    input  wire [3:0]  io_byte_enable,
    output reg  [31:0] io_read_data,
    input  wire        io_read_strobe,
    output reg         io_ready,
    input  wire [31:0] io_write_data,
    input  wire        io_write_strobe,

    input  wire [31:0] status0,
    input  wire [31:0] status1,

    output reg         cfg_valid,
    output reg         cfg_reset_phase,
    output reg  [47:0] cfg_phase_inc0,
    output reg  [47:0] cfg_phase_inc1,
    output reg  [47:0] cfg_phase_inc2,
    output reg  [47:0] cfg_phase_inc3,
    output reg  [15:0] cfg_scale0,
    output reg  [15:0] cfg_scale1,
    output reg  [15:0] cfg_scale2,
    output reg  [15:0] cfg_scale3,

    output reg  [3:0]  rf_switch_sel,
    output reg  [15:0] rf_atten0,
    output reg  [15:0] rf_atten1,
    output reg  [15:0] rf_atten2,
    output reg  [15:0] rf_atten3,
    output reg  [31:0] rf_control_flags,
    output reg  [7:0]  dac0_profile,
    output reg  [7:0]  dac1_profile
);

    localparam [7:0] REG_IDENT       = 8'h00;
    localparam [7:0] REG_VERSION     = 8'h01;
    localparam [7:0] REG_STATUS0     = 8'h02;
    localparam [7:0] REG_STATUS1     = 8'h03;
    localparam [7:0] REG_CONTROL     = 8'h04;
    localparam [7:0] REG_COMMAND     = 8'h05;
    localparam [7:0] REG_SCALE01     = 8'h06;
    localparam [7:0] REG_SCALE23     = 8'h07;
    localparam [7:0] REG_FTW0_LO     = 8'h08;
    localparam [7:0] REG_FTW0_HI     = 8'h09;
    localparam [7:0] REG_FTW1_LO     = 8'h0a;
    localparam [7:0] REG_FTW1_HI     = 8'h0b;
    localparam [7:0] REG_FTW2_LO     = 8'h0c;
    localparam [7:0] REG_FTW2_HI     = 8'h0d;
    localparam [7:0] REG_FTW3_LO     = 8'h0e;
    localparam [7:0] REG_FTW3_HI     = 8'h0f;
    localparam [7:0] REG_RF_SWITCH   = 8'h10;
    localparam [7:0] REG_ATTEN01     = 8'h11;
    localparam [7:0] REG_ATTEN23     = 8'h12;
    localparam [7:0] REG_RF_FLAGS    = 8'h13;
    localparam [7:0] REG_DAC_PROFILE = 8'h14;
    localparam [7:0] REG_UPDATE_CNT  = 8'h15;

    reg [31:0] control_reg;
    reg [31:0] update_count;
    reg [31:0] merged_word;

    function [31:0] merge32;
        input [31:0] current_value;
        input [31:0] write_value;
        input [3:0]  byte_enable;
        begin
            merge32 = current_value;
            if (byte_enable[0]) begin
                merge32[7:0] = write_value[7:0];
            end
            if (byte_enable[1]) begin
                merge32[15:8] = write_value[15:8];
            end
            if (byte_enable[2]) begin
                merge32[23:16] = write_value[23:16];
            end
            if (byte_enable[3]) begin
                merge32[31:24] = write_value[31:24];
            end
        end
    endfunction

    function [15:0] merge16;
        input [15:0] current_value;
        input [31:0] write_value;
        input [3:0]  byte_enable;
        begin
            merge16 = current_value;
            if (byte_enable[0]) begin
                merge16[7:0] = write_value[7:0];
            end
            if (byte_enable[1]) begin
                merge16[15:8] = write_value[15:8];
            end
        end
    endfunction

    function [31:0] read_mux;
        input [7:0] addr;
        begin
            case (addr)
                REG_IDENT:       read_mux = 32'h44414358; // "DACX"
                REG_VERSION:     read_mux = 32'h0001_0000;
                REG_STATUS0:     read_mux = status0;
                REG_STATUS1:     read_mux = status1;
                REG_CONTROL:     read_mux = control_reg;
                REG_COMMAND:     read_mux = 32'd0;
                REG_SCALE01:     read_mux = {cfg_scale1, cfg_scale0};
                REG_SCALE23:     read_mux = {cfg_scale3, cfg_scale2};
                REG_FTW0_LO:     read_mux = cfg_phase_inc0[31:0];
                REG_FTW0_HI:     read_mux = {16'd0, cfg_phase_inc0[47:32]};
                REG_FTW1_LO:     read_mux = cfg_phase_inc1[31:0];
                REG_FTW1_HI:     read_mux = {16'd0, cfg_phase_inc1[47:32]};
                REG_FTW2_LO:     read_mux = cfg_phase_inc2[31:0];
                REG_FTW2_HI:     read_mux = {16'd0, cfg_phase_inc2[47:32]};
                REG_FTW3_LO:     read_mux = cfg_phase_inc3[31:0];
                REG_FTW3_HI:     read_mux = {16'd0, cfg_phase_inc3[47:32]};
                REG_RF_SWITCH:   read_mux = {28'd0, rf_switch_sel};
                REG_ATTEN01:     read_mux = {rf_atten1, rf_atten0};
                REG_ATTEN23:     read_mux = {rf_atten3, rf_atten2};
                REG_RF_FLAGS:    read_mux = rf_control_flags;
                REG_DAC_PROFILE: read_mux = {16'd0, dac1_profile, dac0_profile};
                REG_UPDATE_CNT:  read_mux = update_count;
                default:         read_mux = 32'd0;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            io_read_data <= 32'd0;
            io_ready <= 1'b0;
            cfg_valid <= 1'b0;
            cfg_reset_phase <= 1'b0;
            cfg_phase_inc0 <= DEFAULT_DAC0_FTW;
            cfg_phase_inc1 <= DEFAULT_DAC1_FTW;
            cfg_phase_inc2 <= DEFAULT_DAC2_FTW;
            cfg_phase_inc3 <= DEFAULT_DAC3_FTW;
            cfg_scale0 <= 16'h7fff;
            cfg_scale1 <= 16'h7fff;
            cfg_scale2 <= 16'h7fff;
            cfg_scale3 <= 16'h7fff;
            rf_switch_sel <= 4'd0;
            rf_atten0 <= 16'd0;
            rf_atten1 <= 16'd0;
            rf_atten2 <= 16'd0;
            rf_atten3 <= 16'd0;
            rf_control_flags <= 32'd0;
            dac0_profile <= 8'h01;
            dac1_profile <= 8'h02;
            control_reg <= 32'd0;
            update_count <= 32'd0;
            merged_word <= 32'd0;
        end else begin
            io_ready <= 1'b0;
            cfg_valid <= 1'b0;

            if (io_addr_strobe || io_read_strobe || io_write_strobe) begin
                io_ready <= 1'b1;
                io_read_data <= read_mux(io_address[9:2]);
            end

            if (io_write_strobe) begin
                case (io_address[9:2])
                    REG_CONTROL: begin
                        control_reg <= merge32(control_reg, io_write_data,
                                               io_byte_enable);
                    end

                    REG_COMMAND: begin
                        if (io_write_data[0] && control_reg[0]) begin
                            cfg_valid <= 1'b1;
                            cfg_reset_phase <= control_reg[1] |
                                               io_write_data[1];
                            update_count <= update_count + 1'b1;
                        end
                        if (io_write_data[8]) begin
                            update_count <= 32'd0;
                        end
                    end

                    REG_SCALE01: begin
                        merged_word = merge32({cfg_scale1, cfg_scale0},
                                              io_write_data,
                                              io_byte_enable);
                        cfg_scale0 <= merged_word[15:0];
                        cfg_scale1 <= merged_word[31:16];
                    end

                    REG_SCALE23: begin
                        merged_word = merge32({cfg_scale3, cfg_scale2},
                                              io_write_data,
                                              io_byte_enable);
                        cfg_scale2 <= merged_word[15:0];
                        cfg_scale3 <= merged_word[31:16];
                    end

                    REG_FTW0_LO: begin
                        cfg_phase_inc0[31:0] <=
                            merge32(cfg_phase_inc0[31:0], io_write_data,
                                    io_byte_enable);
                    end
                    REG_FTW0_HI: begin
                        cfg_phase_inc0[47:32] <=
                            merge16(cfg_phase_inc0[47:32], io_write_data,
                                    io_byte_enable);
                    end
                    REG_FTW1_LO: begin
                        cfg_phase_inc1[31:0] <=
                            merge32(cfg_phase_inc1[31:0], io_write_data,
                                    io_byte_enable);
                    end
                    REG_FTW1_HI: begin
                        cfg_phase_inc1[47:32] <=
                            merge16(cfg_phase_inc1[47:32], io_write_data,
                                    io_byte_enable);
                    end
                    REG_FTW2_LO: begin
                        cfg_phase_inc2[31:0] <=
                            merge32(cfg_phase_inc2[31:0], io_write_data,
                                    io_byte_enable);
                    end
                    REG_FTW2_HI: begin
                        cfg_phase_inc2[47:32] <=
                            merge16(cfg_phase_inc2[47:32], io_write_data,
                                    io_byte_enable);
                    end
                    REG_FTW3_LO: begin
                        cfg_phase_inc3[31:0] <=
                            merge32(cfg_phase_inc3[31:0], io_write_data,
                                    io_byte_enable);
                    end
                    REG_FTW3_HI: begin
                        cfg_phase_inc3[47:32] <=
                            merge16(cfg_phase_inc3[47:32], io_write_data,
                                    io_byte_enable);
                    end

                    REG_RF_SWITCH: begin
                        merged_word = merge32({28'd0, rf_switch_sel},
                                              io_write_data,
                                              io_byte_enable);
                        rf_switch_sel <= merged_word[3:0];
                    end

                    REG_ATTEN01: begin
                        merged_word = merge32({rf_atten1, rf_atten0},
                                              io_write_data,
                                              io_byte_enable);
                        rf_atten0 <= merged_word[15:0];
                        rf_atten1 <= merged_word[31:16];
                    end

                    REG_ATTEN23: begin
                        merged_word = merge32({rf_atten3, rf_atten2},
                                              io_write_data,
                                              io_byte_enable);
                        rf_atten2 <= merged_word[15:0];
                        rf_atten3 <= merged_word[31:16];
                    end

                    REG_RF_FLAGS: begin
                        rf_control_flags <= merge32(rf_control_flags,
                                                    io_write_data,
                                                    io_byte_enable);
                    end

                    REG_DAC_PROFILE: begin
                        merged_word = merge32({16'd0, dac1_profile,
                                               dac0_profile},
                                              io_write_data,
                                              io_byte_enable);
                        dac0_profile <= merged_word[7:0];
                        dac1_profile <= merged_word[15:8];
                    end

                    default: begin
                    end
                endcase
            end
        end
    end

endmodule
