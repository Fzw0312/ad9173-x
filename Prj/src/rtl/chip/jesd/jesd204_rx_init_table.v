module jesd204_rx_init_table (
    input  wire [7:0]  addr,
    output reg  [63:0] cmd
);

    localparam [7:0] OP_WRITE   = 8'h01;
    localparam [7:0] OP_WAIT_MS = 8'h02;
    localparam [7:0] OP_END     = 8'hff;

    always @(*) begin
        case (addr)
            8'd0:  cmd = {OP_WRITE,   12'h040, 32'h000000ff, 12'd0};
            8'd1:  cmd = {OP_WRITE,   12'h03c, 32'h03021f00, 12'd0};
            8'd2:  cmd = {OP_WRITE,   12'h020, 32'h00000001, 12'd0};
            8'd3:  cmd = {OP_WAIT_MS, 40'd0,   16'd1};
            8'd4:  cmd = {OP_WRITE,   12'h020, 32'h00000000, 12'd0};
            8'd5:  cmd = {OP_WAIT_MS, 40'd0,   16'd1};
            default: cmd = {OP_END, 56'd0};
        endcase
    end

endmodule
