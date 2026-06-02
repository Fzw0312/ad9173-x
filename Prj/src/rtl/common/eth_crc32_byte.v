`timescale 1ns/1ps

module eth_crc32_byte (
    input  wire [31:0] crc_in,
    input  wire [7:0]  data_in,
    output wire [31:0] crc_out
);

    integer i;
    reg [31:0] crc;

    always @* begin
        crc = crc_in;
        for (i = 0; i < 8; i = i + 1) begin
            if ((crc[0] ^ data_in[i]) != 1'b0) begin
                crc = (crc >> 1) ^ 32'hEDB88320;
            end else begin
                crc = (crc >> 1);
            end
        end
    end

    assign crc_out = crc;

endmodule
