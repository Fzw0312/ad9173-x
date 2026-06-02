`timescale 1ns/1ps

module ipv4_checksum (
    input  wire [15:0] total_length,
    input  wire [15:0] identification,
    input  wire [31:0] src_ip,
    input  wire [31:0] dst_ip,
    output wire [15:0] checksum
);

    reg [19:0] sum0;
    reg [19:0] sum1;
    reg [19:0] sum2;

    always @* begin
        sum0 = 20'd0;
        sum0 = sum0 + 16'h4500;
        sum0 = sum0 + total_length;
        sum0 = sum0 + identification;
        sum0 = sum0 + 16'h4000;
        sum0 = sum0 + 16'h4011;
        sum0 = sum0 + src_ip[31:16];
        sum0 = sum0 + src_ip[15:0];
        sum0 = sum0 + dst_ip[31:16];
        sum0 = sum0 + dst_ip[15:0];
        sum1 = sum0[15:0] + {12'd0, sum0[19:16]};
        sum2 = sum1[15:0] + {12'd0, sum1[19:16]};
    end

    assign checksum = ~sum2[15:0];

endmodule
