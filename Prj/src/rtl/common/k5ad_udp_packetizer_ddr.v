`timescale 1ns/1ps

// K5AD UDP packetizer for a latency-bearing capture store.
//
// Each DATA chunk is first fetched through ram_rd_req/ram_rd_valid into a local
// chunk buffer while the payload CRC is computed.  The Ethernet frame is then
// emitted continuously at one byte per clk, so DDR/MIG read latency cannot
// create gaps inside an RGMII frame.
module k5ad_udp_packetizer_ddr #(
    parameter integer CAPTURE_BEATS = 2048,
    parameter integer DATA_PAYLOAD_SAMPLES = 512,
    parameter [47:0]  SRC_MAC = 48'h02_00_00_00_5a_01,
    parameter [31:0]  SRC_IP  = 32'hC0A8_010A,
    parameter [15:0]  SRC_PORT = 16'd6006,
    parameter [15:0]  DST_PORT = 16'd6006
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [31:0] capture_id,

    output reg         ram_rd_req,
    input  wire        ram_rd_ready,
    input  wire        ram_rd_valid,
    input  wire [7:0]  ram_rd_byte,
    output reg  [13:0] ram_rd_byte_addr,

    output reg         busy,
    output reg         done,
    output reg  [31:0] packet_count,
    output reg  [7:0]  tx_data,
    output reg         tx_valid,
    output reg  [31:0] prefetch_count
);

    localparam integer TOTAL_SAMPLES = CAPTURE_BEATS * 4;
    localparam integer DATA_CHUNK_COUNT =
        (TOTAL_SAMPLES + DATA_PAYLOAD_SAMPLES - 1) / DATA_PAYLOAD_SAMPLES;
    localparam integer CHUNK_DATA_BYTES = DATA_PAYLOAD_SAMPLES * 2;

    localparam [3:0] ST_IDLE      = 4'd0;
    localparam [3:0] ST_PAY_HDR   = 4'd1;
    localparam [3:0] ST_READ_REQ  = 4'd2;
    localparam [3:0] ST_READ_WAIT = 4'd3;
    localparam [3:0] ST_PREAMBLE  = 4'd4;
    localparam [3:0] ST_FRAME     = 4'd5;
    localparam [3:0] ST_FCS       = 4'd6;
    localparam [3:0] ST_IFG       = 4'd7;

    localparam integer UDP_HEADER_OFFSET = 42;
    localparam integer K5AD_HEADER_LEN   = 28;
    localparam integer K5AD_DATA_HDR_LEN = 24;
    localparam integer UDP_PAYLOAD_BASE  = UDP_HEADER_OFFSET + K5AD_HEADER_LEN;
    localparam integer DATA_SAMPLE_BASE  = UDP_PAYLOAD_BASE + K5AD_DATA_HDR_LEN;

    reg [3:0]  state;
    reg [15:0] byte_index;
    reg [15:0] preamble_index;
    reg [7:0]  ifg_count;
    reg [1:0]  fcs_index;
    reg [15:0] frame_len;
    reg [15:0] ip_len;
    reg [15:0] udp_len;
    reg [15:0] payload_len;
    reg [15:0] chunk_sample_count;
    reg [31:0] chunk_sample_offset;
    reg [15:0] chunk_data_bytes;
    reg [15:0] chunk_index;
    reg [15:0] prefetch_index;
    reg [31:0] seq_num;
    reg [31:0] active_capture_id;
    reg [31:0] eth_crc_state;
    reg [31:0] eth_crc_final;
    reg [31:0] payload_crc_state;
    reg [31:0] payload_crc_final;
    reg [15:0] payload_hdr_index;
    reg [7:0]  frame_byte;
    reg [7:0]  payload_crc_byte;
    reg        start_q;

    reg [7:0] chunk_mem [0:CHUNK_DATA_BYTES-1];

    wire start_rise = start && !start_q;
    wire [15:0] ip_checksum;
    wire [31:0] eth_crc_next;
    wire [31:0] payload_crc_next;
    wire [31:0] total_samples32 = TOTAL_SAMPLES[31:0];

    ipv4_checksum u_ip_checksum (
        .total_length  (ip_len),
        .identification(seq_num[15:0]),
        .src_ip        (SRC_IP),
        .dst_ip        (32'hFFFF_FFFF),
        .checksum      (ip_checksum)
    );

    eth_crc32_byte u_eth_crc (
        .crc_in (eth_crc_state),
        .data_in(frame_byte),
        .crc_out(eth_crc_next)
    );

    eth_crc32_byte u_payload_crc (
        .crc_in (payload_crc_state),
        .data_in(payload_crc_byte),
        .crc_out(payload_crc_next)
    );

    always @* begin
        payload_len = K5AD_DATA_HDR_LEN + chunk_data_bytes;
        udp_len     = 16'd8 + K5AD_HEADER_LEN + payload_len;
        ip_len      = 16'd20 + udp_len;
        frame_len   = 16'd14 + ip_len;
    end

    always @* begin
        payload_crc_byte = 8'd0;
        if (state == ST_PAY_HDR) begin
            payload_crc_byte = adc_data_payload_header_byte(
                payload_hdr_index,
                active_capture_id,
                chunk_sample_offset,
                {16'd0, chunk_sample_count},
                total_samples32
            );
        end else if (state == ST_READ_WAIT) begin
            payload_crc_byte = ram_rd_byte;
        end
    end

    always @* begin
        frame_byte = 8'd0;
        if (byte_index < 16'd6) begin
            frame_byte = 8'hff;
        end else if (byte_index < 16'd12) begin
            case (byte_index - 16'd6)
                16'd0: frame_byte = SRC_MAC[47:40];
                16'd1: frame_byte = SRC_MAC[39:32];
                16'd2: frame_byte = SRC_MAC[31:24];
                16'd3: frame_byte = SRC_MAC[23:16];
                16'd4: frame_byte = SRC_MAC[15:8];
                default: frame_byte = SRC_MAC[7:0];
            endcase
        end else if (byte_index == 16'd12) begin
            frame_byte = 8'h08;
        end else if (byte_index == 16'd13) begin
            frame_byte = 8'h00;
        end else if (byte_index < 16'd34) begin
            case (byte_index - 16'd14)
                16'd0:  frame_byte = 8'h45;
                16'd1:  frame_byte = 8'h00;
                16'd2:  frame_byte = ip_len[15:8];
                16'd3:  frame_byte = ip_len[7:0];
                16'd4:  frame_byte = seq_num[15:8];
                16'd5:  frame_byte = seq_num[7:0];
                16'd6:  frame_byte = 8'h40;
                16'd7:  frame_byte = 8'h00;
                16'd8:  frame_byte = 8'h40;
                16'd9:  frame_byte = 8'h11;
                16'd10: frame_byte = ip_checksum[15:8];
                16'd11: frame_byte = ip_checksum[7:0];
                16'd12: frame_byte = SRC_IP[31:24];
                16'd13: frame_byte = SRC_IP[23:16];
                16'd14: frame_byte = SRC_IP[15:8];
                16'd15: frame_byte = SRC_IP[7:0];
                16'd16: frame_byte = 8'hff;
                16'd17: frame_byte = 8'hff;
                16'd18: frame_byte = 8'hff;
                default: frame_byte = 8'hff;
            endcase
        end else if (byte_index < UDP_HEADER_OFFSET) begin
            case (byte_index - 16'd34)
                16'd0: frame_byte = SRC_PORT[15:8];
                16'd1: frame_byte = SRC_PORT[7:0];
                16'd2: frame_byte = DST_PORT[15:8];
                16'd3: frame_byte = DST_PORT[7:0];
                16'd4: frame_byte = udp_len[15:8];
                16'd5: frame_byte = udp_len[7:0];
                16'd6: frame_byte = 8'h00;
                default: frame_byte = 8'h00;
            endcase
        end else if (byte_index < UDP_PAYLOAD_BASE) begin
            frame_byte = k5ad_header_byte(
                byte_index - UDP_HEADER_OFFSET,
                seq_num,
                payload_len,
                payload_crc_final
            );
        end else if (byte_index < DATA_SAMPLE_BASE) begin
            frame_byte = adc_data_payload_header_byte(
                byte_index - UDP_PAYLOAD_BASE,
                active_capture_id,
                chunk_sample_offset,
                {16'd0, chunk_sample_count},
                total_samples32
            );
        end else begin
            frame_byte = chunk_mem[byte_index - DATA_SAMPLE_BASE];
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state               <= ST_IDLE;
            byte_index          <= 16'd0;
            preamble_index      <= 16'd0;
            ifg_count           <= 8'd0;
            fcs_index           <= 2'd0;
            chunk_index         <= 16'd0;
            chunk_sample_offset <= 32'd0;
            chunk_sample_count  <= 16'd0;
            chunk_data_bytes    <= 16'd0;
            prefetch_index      <= 16'd0;
            seq_num            <= 32'd1;
            active_capture_id   <= 32'd0;
            eth_crc_state       <= 32'hFFFF_FFFF;
            eth_crc_final       <= 32'd0;
            payload_crc_state   <= 32'hFFFF_FFFF;
            payload_crc_final   <= 32'd0;
            payload_hdr_index   <= 16'd0;
            ram_rd_req          <= 1'b0;
            ram_rd_byte_addr    <= 14'd0;
            busy                <= 1'b0;
            done                <= 1'b0;
            packet_count        <= 32'd0;
            tx_data             <= 8'd0;
            tx_valid            <= 1'b0;
            start_q             <= 1'b0;
            prefetch_count      <= 32'd0;
        end else begin
            start_q    <= start;
            done       <= 1'b0;
            tx_valid   <= 1'b0;
            ram_rd_req <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start_rise) begin
                        busy                <= 1'b1;
                        chunk_index         <= 16'd0;
                        chunk_sample_offset <= 32'd0;
                        chunk_sample_count  <= data_chunk_samples(16'd0);
                        chunk_data_bytes    <= data_chunk_samples(16'd0) << 1;
                        active_capture_id   <= capture_id;
                        payload_crc_state   <= 32'hFFFF_FFFF;
                        payload_hdr_index   <= 16'd0;
                        state               <= ST_PAY_HDR;
                    end
                end

                ST_PAY_HDR: begin
                    busy              <= 1'b1;
                    payload_crc_state <= payload_crc_next;
                    if (payload_hdr_index == K5AD_DATA_HDR_LEN - 1) begin
                        prefetch_index   <= 16'd0;
                        ram_rd_byte_addr <= chunk_sample_offset[13:0] << 1;
                        if (chunk_data_bytes == 16'd0) begin
                            payload_crc_final <= ~payload_crc_next;
                            preamble_index    <= 16'd0;
                            byte_index        <= 16'd0;
                            eth_crc_state     <= 32'hFFFF_FFFF;
                            state             <= ST_PREAMBLE;
                        end else begin
                            state <= ST_READ_REQ;
                        end
                    end else begin
                        payload_hdr_index <= payload_hdr_index + 1'b1;
                    end
                end

                ST_READ_REQ: begin
                    busy <= 1'b1;
                    if (ram_rd_req && ram_rd_ready) begin
                        ram_rd_req <= 1'b0;
                        state      <= ST_READ_WAIT;
                    end else begin
                        ram_rd_req <= 1'b1;
                    end
                end

                ST_READ_WAIT: begin
                    busy <= 1'b1;
                    if (ram_rd_valid) begin
                        chunk_mem[prefetch_index] <= ram_rd_byte;
                        payload_crc_state         <= payload_crc_next;
                        prefetch_count            <= prefetch_count + 1'b1;
                        if (prefetch_index == chunk_data_bytes - 1'b1) begin
                            payload_crc_final <= ~payload_crc_next;
                            preamble_index    <= 16'd0;
                            byte_index        <= 16'd0;
                            eth_crc_state     <= 32'hFFFF_FFFF;
                            state             <= ST_PREAMBLE;
                        end else begin
                            prefetch_index   <= prefetch_index + 1'b1;
                            ram_rd_byte_addr <= ram_rd_byte_addr + 1'b1;
                            state            <= ST_READ_REQ;
                        end
                    end
                end

                ST_PREAMBLE: begin
                    tx_valid <= 1'b1;
                    tx_data  <= (preamble_index == 16'd7) ? 8'hd5 : 8'h55;
                    if (preamble_index == 16'd7) begin
                        preamble_index <= 16'd0;
                        byte_index     <= 16'd0;
                        eth_crc_state  <= 32'hFFFF_FFFF;
                        state          <= ST_FRAME;
                    end else begin
                        preamble_index <= preamble_index + 1'b1;
                    end
                end

                ST_FRAME: begin
                    tx_valid      <= 1'b1;
                    tx_data       <= frame_byte;
                    eth_crc_state <= eth_crc_next;
                    if (byte_index == frame_len - 1'b1) begin
                        eth_crc_final <= ~eth_crc_next;
                        fcs_index     <= 2'd0;
                        state         <= ST_FCS;
                    end else begin
                        byte_index <= byte_index + 1'b1;
                    end
                end

                ST_FCS: begin
                    tx_valid <= 1'b1;
                    case (fcs_index)
                        2'd0: tx_data <= eth_crc_final[7:0];
                        2'd1: tx_data <= eth_crc_final[15:8];
                        2'd2: tx_data <= eth_crc_final[23:16];
                        default: tx_data <= eth_crc_final[31:24];
                    endcase
                    if (fcs_index == 2'd3) begin
                        packet_count <= packet_count + 1'b1;
                        ifg_count    <= 8'd0;
                        state        <= ST_IFG;
                    end else begin
                        fcs_index <= fcs_index + 1'b1;
                    end
                end

                ST_IFG: begin
                    if (ifg_count < 8'd12) begin
                        ifg_count <= ifg_count + 1'b1;
                    end else if (chunk_index + 1'b1 < DATA_CHUNK_COUNT) begin
                        chunk_index         <= chunk_index + 1'b1;
                        chunk_sample_offset <= chunk_sample_offset + chunk_sample_count;
                        chunk_sample_count  <= data_chunk_samples(chunk_index + 1'b1);
                        chunk_data_bytes    <= data_chunk_samples(chunk_index + 1'b1) << 1;
                        seq_num            <= seq_num + 1'b1;
                        payload_crc_state   <= 32'hFFFF_FFFF;
                        payload_hdr_index   <= 16'd0;
                        state               <= ST_PAY_HDR;
                    end else begin
                        seq_num <= seq_num + 1'b1;
                        busy     <= 1'b0;
                        done     <= 1'b1;
                        state    <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    function [15:0] data_chunk_samples;
        input [15:0] chunk;
        reg [31:0] start_sample;
        reg [31:0] remaining;
        begin
            start_sample = chunk * DATA_PAYLOAD_SAMPLES;
            if (start_sample >= TOTAL_SAMPLES) begin
                data_chunk_samples = 16'd0;
            end else begin
                remaining = TOTAL_SAMPLES - start_sample;
                if (remaining > DATA_PAYLOAD_SAMPLES) begin
                    data_chunk_samples = DATA_PAYLOAD_SAMPLES[15:0];
                end else begin
                    data_chunk_samples = remaining[15:0];
                end
            end
        end
    endfunction

    function [7:0] k5ad_header_byte;
        input [15:0] idx;
        input [31:0] seq_num_i;
        input [15:0] payload_len_i;
        input [31:0] payload_crc_i;
        begin
            k5ad_header_byte = 8'd0;
            case (idx)
                16'd0:  k5ad_header_byte = 8'h4b;
                16'd1:  k5ad_header_byte = 8'h35;
                16'd2:  k5ad_header_byte = 8'h41;
                16'd3:  k5ad_header_byte = 8'h44;
                16'd4:  k5ad_header_byte = 8'h01;
                16'd5:  k5ad_header_byte = 8'h03;
                16'd6:  k5ad_header_byte = 8'd28;
                16'd7:  k5ad_header_byte = 8'd0;
                16'd8:  k5ad_header_byte = seq_num_i[7:0];
                16'd9:  k5ad_header_byte = seq_num_i[15:8];
                16'd10: k5ad_header_byte = seq_num_i[23:16];
                16'd11: k5ad_header_byte = seq_num_i[31:24];
                16'd16: k5ad_header_byte = payload_len_i[7:0];
                16'd17: k5ad_header_byte = payload_len_i[15:8];
                16'd20: k5ad_header_byte = payload_crc_i[7:0];
                16'd21: k5ad_header_byte = payload_crc_i[15:8];
                16'd22: k5ad_header_byte = payload_crc_i[23:16];
                16'd23: k5ad_header_byte = payload_crc_i[31:24];
                default: k5ad_header_byte = 8'd0;
            endcase
        end
    endfunction

    function [7:0] adc_data_payload_header_byte;
        input [15:0] idx;
        input [31:0] capture_id_i;
        input [31:0] sample_offset_i;
        input [31:0] sample_count_i;
        input [31:0] total_samples_i;
        begin
            adc_data_payload_header_byte = 8'd0;
            case (idx)
                16'd0:  adc_data_payload_header_byte = capture_id_i[7:0];
                16'd1:  adc_data_payload_header_byte = capture_id_i[15:8];
                16'd2:  adc_data_payload_header_byte = capture_id_i[23:16];
                16'd3:  adc_data_payload_header_byte = capture_id_i[31:24];
                16'd4:  adc_data_payload_header_byte = 8'h01;
                16'd5:  adc_data_payload_header_byte = 8'h00;
                16'd6:  adc_data_payload_header_byte = 8'h01;
                16'd7:  adc_data_payload_header_byte = 8'h00;
                16'd8:  adc_data_payload_header_byte = sample_offset_i[7:0];
                16'd9:  adc_data_payload_header_byte = sample_offset_i[15:8];
                16'd10: adc_data_payload_header_byte = sample_offset_i[23:16];
                16'd11: adc_data_payload_header_byte = sample_offset_i[31:24];
                16'd12: adc_data_payload_header_byte = sample_count_i[7:0];
                16'd13: adc_data_payload_header_byte = sample_count_i[15:8];
                16'd14: adc_data_payload_header_byte = sample_count_i[23:16];
                16'd15: adc_data_payload_header_byte = sample_count_i[31:24];
                16'd16: adc_data_payload_header_byte = total_samples_i[7:0];
                16'd17: adc_data_payload_header_byte = total_samples_i[15:8];
                16'd18: adc_data_payload_header_byte = total_samples_i[23:16];
                16'd19: adc_data_payload_header_byte = total_samples_i[31:24];
                default: adc_data_payload_header_byte = 8'd0;
            endcase
        end
    endfunction

endmodule
