`timescale 1ns/1ps

// Dual-clock short capture buffer for ADC0 samples.
//
// The write side stores 64-bit beats, each containing four int16 ADC0 samples.
// The read side exposes byte addressing for the UDP packetizer.
module adc_capture_bram64 #(
    parameter integer ADDR_WIDTH = 11
) (
    input  wire                    wr_clk,
    input  wire                    wr_en,
    input  wire [ADDR_WIDTH-1:0]   wr_addr,
    input  wire [63:0]             wr_data,
    input  wire                    rd_clk,
    input  wire [ADDR_WIDTH+2:0]   rd_byte_addr,
    output wire [7:0]              rd_byte
);

    localparam integer DEPTH = (1 << ADDR_WIDTH);

    (* ram_style = "distributed" *) reg [63:0] mem [0:DEPTH-1];
    wire [63:0] rd_word;

    always @(posedge wr_clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
    end

    assign rd_word = mem[rd_byte_addr[ADDR_WIDTH+2:3]];
    assign rd_byte =
        (rd_byte_addr[2:0] == 3'd0) ? rd_word[7:0] :
        (rd_byte_addr[2:0] == 3'd1) ? rd_word[15:8] :
        (rd_byte_addr[2:0] == 3'd2) ? rd_word[23:16] :
        (rd_byte_addr[2:0] == 3'd3) ? rd_word[31:24] :
        (rd_byte_addr[2:0] == 3'd4) ? rd_word[39:32] :
        (rd_byte_addr[2:0] == 3'd5) ? rd_word[47:40] :
        (rd_byte_addr[2:0] == 3'd6) ? rd_word[55:48] :
                                      rd_word[63:56];

endmodule
