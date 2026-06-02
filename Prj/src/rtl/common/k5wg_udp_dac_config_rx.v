`timescale 1ns/1ps

// Lightweight UDP parser for HostApp DAC DDS control.
//
// This is not a general Ethernet MAC.  It consumes the byte stream recovered
// from RGMII RX and recognizes one hardware-friendly K5WG CONFIG payload:
//
//   Ethernet/IPv4/UDP(dst port 5005)/K5WG header/K5DC binary payload
//
// K5WG JSON frames are deliberately ignored.  The binary payload is:
//   0x00  char[4]  "K5DC"
//   0x04  u8       version = 1
//   0x05  u8       flags, bit0 requests DDS phase reset
//   0x06  u16      channel mask, currently informational
//   0x08  u32      sample_rate_hz, rounded, informational
//   0x0c  u48[4]   DAC0..DAC3 phase increments
//   0x24  u16[4]   DAC0..DAC3 unsigned Q1.15 amplitude scales
//   0x2c  u32      reserved
//
// K5WG DATA frames carry int16 little-endian CH0/CH1 sample pairs. This parser
// writes up to 2**WAVE_ADDR_WIDTH sample pairs and toggles wave_commit_toggle
// when the host sends a COMMIT frame.
module k5wg_udp_dac_config_rx #(
    parameter [31:0] FPGA_IP = 32'hC0A8_010A,
    parameter [15:0] UDP_PORT = 16'd5005,
    parameter integer WAVE_ADDR_WIDTH = 12
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    input  wire        rx_error,

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
    output reg         wave_wr_en,
    output reg  [WAVE_ADDR_WIDTH-1:0] wave_wr_addr,
    output reg  [31:0] wave_wr_data,
    output reg  [WAVE_ADDR_WIDTH:0] wave_total_samples,
    output reg         wave_commit_toggle,
    output reg  [31:0] packet_count,
    output reg  [31:0] config_count,
    output reg  [31:0] data_count,
    output reg  [31:0] commit_count,
    output reg  [31:0] drop_count,
    output wire [31:0] status_dbg
);

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_FRAME = 2'd1;

    localparam integer UDP_PAYLOAD_OFFSET = 42;
    localparam integer K5WG_HEADER_LEN    = 28;
    localparam integer K5DC_OFFSET        = UDP_PAYLOAD_OFFSET + K5WG_HEADER_LEN;
    localparam integer K5DC_LAST_OFFSET   = K5DC_OFFSET + 48 - 1;
    localparam integer DATA_HEADER_LEN     = 20;
    localparam integer DATA_SAMPLE_OFFSET  = K5DC_OFFSET + DATA_HEADER_LEN;
    localparam integer MAX_WAVE_SAMPLES    = (1 << WAVE_ADDR_WIDTH);

    reg [1:0]  state;
    reg [15:0] frame_index;
    reg [3:0]  preamble_count;
    reg        frame_active;

    reg eth_type_ok;
    reg ipv4_proto_ok;
    reg dst_ip_ok;
    reg udp_port_ok;
    reg k5wg_ok;
    reg k5dc_ok;
    reg k5dc_version_ok;
    reg [7:0] frame_type;
    reg [31:0] payload_len;
    reg [7:0] payload_flags;
    reg [15:0] channel_mask;
    reg [31:0] sample_rate_hz;
    reg [47:0] temp_phase_inc0;
    reg [47:0] temp_phase_inc1;
    reg [47:0] temp_phase_inc2;
    reg [47:0] temp_phase_inc3;
    reg [15:0] temp_scale0;
    reg [15:0] temp_scale1;
    reg [15:0] temp_scale2;
    reg [15:0] temp_scale3;
    reg [15:0] data_flags;
    reg [15:0] data_sample_format;
    reg [31:0] data_sample_offset;
    reg [31:0] data_sample_count;
    reg [31:0] data_total_samples;
    reg [31:0] temp_wave_word;
    reg        data_frame_had_write;

    assign status_dbg = {
        4'hc,
        state,
        frame_active,
        rx_valid,
        rx_error,
        wave_commit_toggle,
        wave_wr_en,
        eth_type_ok,
        ipv4_proto_ok,
        dst_ip_ok,
        udp_port_ok,
        k5wg_ok,
        k5dc_ok,
        k5dc_version_ok,
        cfg_valid,
        frame_type[3:0],
        config_count[3:0],
        data_count[3:0]
    };

    function [WAVE_ADDR_WIDTH:0] clip_wave_samples;
        input [31:0] value;
        begin
            if (value == 32'd0) begin
                clip_wave_samples = {{WAVE_ADDR_WIDTH{1'b0}}, 1'b1};
            end else if (value > MAX_WAVE_SAMPLES) begin
                clip_wave_samples = {1'b1, {WAVE_ADDR_WIDTH{1'b0}}};
            end else begin
                clip_wave_samples = value[WAVE_ADDR_WIDTH:0];
            end
        end
    endfunction

    task reset_frame_checks;
        begin
            eth_type_ok       <= 1'b1;
            ipv4_proto_ok     <= 1'b1;
            dst_ip_ok         <= 1'b1;
            udp_port_ok       <= 1'b1;
            k5wg_ok           <= 1'b1;
            k5dc_ok           <= 1'b1;
            k5dc_version_ok   <= 1'b1;
            frame_type        <= 8'd0;
            payload_len       <= 32'd0;
            payload_flags     <= 8'd0;
            channel_mask      <= 16'd0;
            sample_rate_hz    <= 32'd0;
            temp_phase_inc0   <= 48'd0;
            temp_phase_inc1   <= 48'd0;
            temp_phase_inc2   <= 48'd0;
            temp_phase_inc3   <= 48'd0;
            temp_scale0       <= 16'd0;
            temp_scale1       <= 16'd0;
            temp_scale2       <= 16'd0;
            temp_scale3       <= 16'd0;
            data_flags        <= 16'd0;
            data_sample_format <= 16'd0;
            data_sample_offset <= 32'd0;
            data_sample_count <= 32'd0;
            data_total_samples <= 32'd0;
            temp_wave_word    <= 32'd0;
            data_frame_had_write <= 1'b0;
        end
    endtask

    task process_frame_byte;
        input [15:0] idx;
        input [7:0]  b;
        integer byte_index;
        integer sample_index;
        integer byte_lane;
        reg [31:0] sample_addr;
        reg [31:0] wave_word_next;
        begin
            case (idx)
                16'd12: eth_type_ok <= eth_type_ok && (b == 8'h08);
                16'd13: eth_type_ok <= eth_type_ok && (b == 8'h00);
                16'd14: ipv4_proto_ok <= ipv4_proto_ok && (b[7:4] == 4'h4) &&
                                          (b[3:0] == 4'd5);
                16'd23: ipv4_proto_ok <= ipv4_proto_ok && (b == 8'h11);
                16'd30: dst_ip_ok <= dst_ip_ok &&
                                      ((b == FPGA_IP[31:24]) || (b == 8'hff));
                16'd31: dst_ip_ok <= dst_ip_ok &&
                                      ((b == FPGA_IP[23:16]) || (b == 8'hff));
                16'd32: dst_ip_ok <= dst_ip_ok &&
                                      ((b == FPGA_IP[15:8]) || (b == 8'hff));
                16'd33: dst_ip_ok <= dst_ip_ok &&
                                      ((b == FPGA_IP[7:0]) || (b == 8'hff));
                16'd36: udp_port_ok <= udp_port_ok && (b == UDP_PORT[15:8]);
                16'd37: udp_port_ok <= udp_port_ok && (b == UDP_PORT[7:0]);
                16'd42: k5wg_ok <= k5wg_ok && (b == 8'h4b);
                16'd43: k5wg_ok <= k5wg_ok && (b == 8'h35);
                16'd44: k5wg_ok <= k5wg_ok && (b == 8'h57);
                16'd45: k5wg_ok <= k5wg_ok && (b == 8'h47);
                16'd46: k5wg_ok <= k5wg_ok && (b == 8'h01);
                16'd47: frame_type <= b;
                16'd48: k5wg_ok <= k5wg_ok && (b == K5WG_HEADER_LEN[7:0]);
                16'd49: k5wg_ok <= k5wg_ok && (b == 8'h00);
                16'd58: payload_len[7:0] <= b;
                16'd59: payload_len[15:8] <= b;
                16'd60: payload_len[23:16] <= b;
                16'd61: payload_len[31:24] <= b;
                K5DC_OFFSET + 0: k5dc_ok <= k5dc_ok && (b == 8'h4b);
                K5DC_OFFSET + 1: k5dc_ok <= k5dc_ok && (b == 8'h35);
                K5DC_OFFSET + 2: k5dc_ok <= k5dc_ok && (b == 8'h44);
                K5DC_OFFSET + 3: k5dc_ok <= k5dc_ok && (b == 8'h43);
                K5DC_OFFSET + 4: k5dc_version_ok <= k5dc_version_ok &&
                                                   (b == 8'h01);
                K5DC_OFFSET + 5: payload_flags <= b;
                K5DC_OFFSET + 6: channel_mask[7:0] <= b;
                K5DC_OFFSET + 7: channel_mask[15:8] <= b;
                K5DC_OFFSET + 8: sample_rate_hz[7:0] <= b;
                K5DC_OFFSET + 9: sample_rate_hz[15:8] <= b;
                K5DC_OFFSET + 10: sample_rate_hz[23:16] <= b;
                K5DC_OFFSET + 11: sample_rate_hz[31:24] <= b;
                K5DC_OFFSET + 12: temp_phase_inc0[7:0] <= b;
                K5DC_OFFSET + 13: temp_phase_inc0[15:8] <= b;
                K5DC_OFFSET + 14: temp_phase_inc0[23:16] <= b;
                K5DC_OFFSET + 15: temp_phase_inc0[31:24] <= b;
                K5DC_OFFSET + 16: temp_phase_inc0[39:32] <= b;
                K5DC_OFFSET + 17: temp_phase_inc0[47:40] <= b;
                K5DC_OFFSET + 18: temp_phase_inc1[7:0] <= b;
                K5DC_OFFSET + 19: temp_phase_inc1[15:8] <= b;
                K5DC_OFFSET + 20: temp_phase_inc1[23:16] <= b;
                K5DC_OFFSET + 21: temp_phase_inc1[31:24] <= b;
                K5DC_OFFSET + 22: temp_phase_inc1[39:32] <= b;
                K5DC_OFFSET + 23: temp_phase_inc1[47:40] <= b;
                K5DC_OFFSET + 24: temp_phase_inc2[7:0] <= b;
                K5DC_OFFSET + 25: temp_phase_inc2[15:8] <= b;
                K5DC_OFFSET + 26: temp_phase_inc2[23:16] <= b;
                K5DC_OFFSET + 27: temp_phase_inc2[31:24] <= b;
                K5DC_OFFSET + 28: temp_phase_inc2[39:32] <= b;
                K5DC_OFFSET + 29: temp_phase_inc2[47:40] <= b;
                K5DC_OFFSET + 30: temp_phase_inc3[7:0] <= b;
                K5DC_OFFSET + 31: temp_phase_inc3[15:8] <= b;
                K5DC_OFFSET + 32: temp_phase_inc3[23:16] <= b;
                K5DC_OFFSET + 33: temp_phase_inc3[31:24] <= b;
                K5DC_OFFSET + 34: temp_phase_inc3[39:32] <= b;
                K5DC_OFFSET + 35: temp_phase_inc3[47:40] <= b;
                K5DC_OFFSET + 36: temp_scale0[7:0] <= b;
                K5DC_OFFSET + 37: temp_scale0[15:8] <= b;
                K5DC_OFFSET + 38: temp_scale1[7:0] <= b;
                K5DC_OFFSET + 39: temp_scale1[15:8] <= b;
                K5DC_OFFSET + 40: temp_scale2[7:0] <= b;
                K5DC_OFFSET + 41: temp_scale2[15:8] <= b;
                K5DC_OFFSET + 42: temp_scale3[7:0] <= b;
                K5DC_OFFSET + 43: temp_scale3[15:8] <= b;
                default: begin
                end
            endcase

            if ((idx == K5DC_LAST_OFFSET) && (frame_type == 8'h02)) begin
                if (eth_type_ok && ipv4_proto_ok && dst_ip_ok &&
                    udp_port_ok && k5wg_ok && k5dc_ok &&
                    k5dc_version_ok) begin
                    cfg_valid      <= 1'b1;
                    cfg_reset_phase <= payload_flags[0];
                    cfg_phase_inc0 <= temp_phase_inc0;
                    cfg_phase_inc1 <= temp_phase_inc1;
                    cfg_phase_inc2 <= temp_phase_inc2;
                    cfg_phase_inc3 <= temp_phase_inc3;
                    cfg_scale0     <= temp_scale0;
                    cfg_scale1     <= temp_scale1;
                    cfg_scale2     <= temp_scale2;
                    cfg_scale3     <= temp_scale3;
                    config_count   <= config_count + 1'b1;
                end else begin
                    drop_count <= drop_count + 1'b1;
                end
            end

            if (frame_type == 8'h03) begin
                case (idx)
                    K5DC_OFFSET + 0: data_flags[7:0] <= b;
                    K5DC_OFFSET + 1: data_flags[15:8] <= b;
                    K5DC_OFFSET + 2: data_sample_format[7:0] <= b;
                    K5DC_OFFSET + 3: data_sample_format[15:8] <= b;
                    K5DC_OFFSET + 4: data_sample_offset[7:0] <= b;
                    K5DC_OFFSET + 5: data_sample_offset[15:8] <= b;
                    K5DC_OFFSET + 6: data_sample_offset[23:16] <= b;
                    K5DC_OFFSET + 7: data_sample_offset[31:24] <= b;
                    K5DC_OFFSET + 8: data_sample_count[7:0] <= b;
                    K5DC_OFFSET + 9: data_sample_count[15:8] <= b;
                    K5DC_OFFSET + 10: data_sample_count[23:16] <= b;
                    K5DC_OFFSET + 11: data_sample_count[31:24] <= b;
                    K5DC_OFFSET + 12: data_total_samples[7:0] <= b;
                    K5DC_OFFSET + 13: data_total_samples[15:8] <= b;
                    K5DC_OFFSET + 14: data_total_samples[23:16] <= b;
                    K5DC_OFFSET + 15: begin
                        data_total_samples[31:24] <= b;
                        wave_total_samples <=
                            clip_wave_samples({b, data_total_samples[23:0]});
                    end
                    default: begin
                    end
                endcase

                if (idx >= DATA_SAMPLE_OFFSET) begin
                    byte_index = idx - DATA_SAMPLE_OFFSET;
                    sample_index = byte_index >> 2;
                    byte_lane = byte_index & 3;
                    sample_addr = data_sample_offset + sample_index;
                    if (eth_type_ok && ipv4_proto_ok && dst_ip_ok &&
                        udp_port_ok && k5wg_ok &&
                        (data_sample_format == 16'd1) &&
                        (sample_index < data_sample_count) &&
                        (sample_addr < MAX_WAVE_SAMPLES)) begin
                        case (byte_lane)
                            0: begin
                                temp_wave_word[7:0] <= b;
                            end
                            1: begin
                                temp_wave_word[15:8] <= b;
                            end
                            2: begin
                                temp_wave_word[23:16] <= b;
                            end
                            default: begin
                                wave_word_next = {b, temp_wave_word[23:0]};
                                temp_wave_word[31:24] <= b;
                                wave_wr_en <= 1'b1;
                                wave_wr_addr <= sample_addr[WAVE_ADDR_WIDTH-1:0];
                                wave_wr_data <= wave_word_next;
                                data_frame_had_write <= 1'b1;
                            end
                        endcase
                    end
                end
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state           <= ST_IDLE;
            frame_index     <= 16'd0;
            preamble_count  <= 4'd0;
            frame_active    <= 1'b0;
            cfg_valid       <= 1'b0;
            cfg_reset_phase <= 1'b0;
            cfg_phase_inc0  <= 48'h053555555555;
            cfg_phase_inc1  <= 48'h07d000000000;
            cfg_phase_inc2  <= 48'h053555555555;
            cfg_phase_inc3  <= 48'h07d000000000;
            cfg_scale0      <= 16'h7fff;
            cfg_scale1      <= 16'h7fff;
            cfg_scale2      <= 16'h7fff;
            cfg_scale3      <= 16'h7fff;
            wave_wr_en      <= 1'b0;
            wave_wr_addr    <= {WAVE_ADDR_WIDTH{1'b0}};
            wave_wr_data    <= 32'd0;
            wave_total_samples <= {1'b1, {WAVE_ADDR_WIDTH{1'b0}}};
            wave_commit_toggle <= 1'b0;
            packet_count    <= 32'd0;
            config_count    <= 32'd0;
            data_count      <= 32'd0;
            commit_count    <= 32'd0;
            drop_count      <= 32'd0;
            reset_frame_checks;
        end else begin
            cfg_valid <= 1'b0;
            wave_wr_en <= 1'b0;

            case (state)
                ST_IDLE: begin
                    frame_active <= 1'b0;
                    frame_index  <= 16'd0;
                    if (rx_valid) begin
                        if (rx_data == 8'h55) begin
                            if (preamble_count != 4'd15) begin
                                preamble_count <= preamble_count + 1'b1;
                            end
                        end else if ((rx_data == 8'hd5) &&
                                     (preamble_count != 4'd0)) begin
                            reset_frame_checks;
                            frame_active   <= 1'b1;
                            frame_index    <= 16'd0;
                            preamble_count <= 4'd0;
                            state          <= ST_FRAME;
                        end else begin
                            reset_frame_checks;
                            frame_active   <= 1'b1;
                            frame_index    <= 16'd1;
                            preamble_count <= 4'd0;
                            state          <= ST_FRAME;
                            process_frame_byte(16'd0, rx_data);
                        end
                    end else begin
                        preamble_count <= 4'd0;
                    end
                end

                ST_FRAME: begin
                    if (rx_error) begin
                        frame_active   <= 1'b0;
                        preamble_count <= 4'd0;
                        drop_count     <= drop_count + 1'b1;
                        state          <= ST_IDLE;
                    end else if (rx_valid) begin
                        process_frame_byte(frame_index, rx_data);
                        frame_index <= frame_index + 1'b1;
                    end else begin
                        frame_active   <= 1'b0;
                        preamble_count <= 4'd0;
                        packet_count   <= packet_count + 1'b1;
                        if (frame_type == 8'h03) begin
                            if (data_frame_had_write) begin
                                data_count <= data_count + 1'b1;
                            end else if (eth_type_ok && ipv4_proto_ok &&
                                         dst_ip_ok && udp_port_ok && k5wg_ok) begin
                                drop_count <= drop_count + 1'b1;
                            end
                        end else if ((frame_type == 8'h04) &&
                                     eth_type_ok && ipv4_proto_ok &&
                                     dst_ip_ok && udp_port_ok && k5wg_ok) begin
                            wave_commit_toggle <= ~wave_commit_toggle;
                            commit_count <= commit_count + 1'b1;
                        end
                        state          <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
