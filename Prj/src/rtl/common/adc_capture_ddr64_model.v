`timescale 1ns/1ps

// Latency-aware ADC capture storage model.
//
// This module is the current PL-side stand-in for the future MIG-backed DDR
// capture window.  The write side stores 64-bit ADC beats, and the read side
// models a DDR/MIG-style byte read request with delayed valid data.
//
// It is intentionally small enough for the present bring-up window, but its
// read handshake is the interface the UDP path must tolerate before replacing
// this model with a real MIG/AXI reader.
module adc_capture_ddr64_model #(
    parameter integer ADDR_WIDTH = 11,
    parameter integer READ_LATENCY = 6,
    parameter integer READY_STALL_PERIOD = 0,
    parameter integer READY_STALL_CYCLES = 0
) (
    input  wire                    wr_clk,
    input  wire                    wr_en,
    input  wire [ADDR_WIDTH-1:0]   wr_addr,
    input  wire [63:0]             wr_data,

    input  wire                    rd_clk,
    input  wire                    rd_rst,
    input  wire                    rd_req,
    output wire                    rd_ready,
    input  wire [ADDR_WIDTH+2:0]   rd_byte_addr,
    output reg                     rd_valid,
    output reg  [7:0]              rd_byte
);

    localparam integer DEPTH = (1 << ADDR_WIDTH);
    localparam integer LATENCY = (READ_LATENCY < 1) ? 1 : READ_LATENCY;

    (* ram_style = "block" *) reg [63:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH+2:0] addr_pipe [0:LATENCY-1];
    reg [LATENCY-1:0] valid_pipe;
    reg [15:0] ready_count;

    integer i;

    assign rd_ready = (READY_STALL_PERIOD <= 0) ? 1'b1 :
        (ready_count >= READY_STALL_CYCLES);

    always @(posedge wr_clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
    end

    always @(posedge rd_clk) begin
        if (rd_rst) begin
            valid_pipe <= {LATENCY{1'b0}};
            ready_count <= 16'd0;
            rd_valid   <= 1'b0;
            rd_byte    <= 8'd0;
            for (i = 0; i < LATENCY; i = i + 1) begin
                addr_pipe[i] <= {(ADDR_WIDTH+3){1'b0}};
            end
        end else begin
            if (READY_STALL_PERIOD > 0) begin
                if (ready_count == READY_STALL_PERIOD - 1) begin
                    ready_count <= 16'd0;
                end else begin
                    ready_count <= ready_count + 1'b1;
                end
            end

            valid_pipe[0] <= rd_req && rd_ready;
            addr_pipe[0]  <= rd_byte_addr;
            for (i = 1; i < LATENCY; i = i + 1) begin
                valid_pipe[i] <= valid_pipe[i-1];
                addr_pipe[i]  <= addr_pipe[i-1];
            end

            rd_valid <= valid_pipe[LATENCY-1];
            if (valid_pipe[LATENCY-1]) begin
                rd_byte <= select_byte(addr_pipe[LATENCY-1]);
            end
        end
    end

    function [7:0] select_byte;
        input [ADDR_WIDTH+2:0] byte_addr;
        reg [63:0] rd_word;
        begin
            rd_word = mem[byte_addr[ADDR_WIDTH+2:3]];
            case (byte_addr[2:0])
                3'd0: select_byte = rd_word[7:0];
                3'd1: select_byte = rd_word[15:8];
                3'd2: select_byte = rd_word[23:16];
                3'd3: select_byte = rd_word[31:24];
                3'd4: select_byte = rd_word[39:32];
                3'd5: select_byte = rd_word[47:40];
                3'd6: select_byte = rd_word[55:48];
                default: select_byte = rd_word[63:56];
            endcase
        end
    endfunction

endmodule
