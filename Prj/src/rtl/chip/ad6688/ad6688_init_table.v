module ad6688_init_table (
    input  wire [7:0] addr,
    output reg  [31:0] cmd
);

    localparam [7:0] OP_WRITE   = 8'h01;
    localparam [7:0] OP_WAIT_MS = 8'h02;
    localparam [7:0] OP_END     = 8'hff;

    always @(*) begin
        case (addr)
            8'd0:  cmd = {OP_WRITE, 16'h000a, 8'h01};
            8'd1:  cmd = {OP_WRITE, 16'h0000, 8'h81};
            8'd2:  cmd = {OP_WAIT_MS, 16'h0000, 8'd10};
            8'd3:  cmd = {OP_WRITE, 16'h0001, 8'h02};
            8'd4:  cmd = {OP_WAIT_MS, 16'h0000, 8'd10};
            8'd5:  cmd = {OP_WRITE, 16'h0571, 8'h15};
            8'd6:  cmd = {OP_WRITE, 16'h0002, 8'h00};
            8'd7:  cmd = {OP_WRITE, 16'h0008, 8'h03};
            8'd8:  cmd = {OP_WRITE, 16'h003f, 8'h80};
            8'd9:  cmd = {OP_WRITE, 16'h0040, 8'h80};
            8'd10: cmd = {OP_WRITE, 16'h0108, 8'h00};
            8'd11: cmd = {OP_WRITE, 16'h1908, 8'h00};
            8'd12: cmd = {OP_WRITE, 16'h18e3, 8'h00};
            8'd13: cmd = {OP_WRITE, 16'h18a6, 8'h00};
            8'd14: cmd = {OP_WRITE, 16'h1910, 8'h08};
            8'd15: cmd = {OP_WRITE, 16'h1a4c, 8'h09};
            8'd16: cmd = {OP_WRITE, 16'h1a4d, 8'h09};
            8'd17: cmd = {OP_WRITE, 16'h0109, 8'h00};
            8'd18: cmd = {OP_WRITE, 16'h010a, 8'h00};
            8'd19: cmd = {OP_WAIT_MS, 16'h0000, 8'd5};
            8'd20: cmd = {OP_WRITE, 16'h0120, 8'h04};
            8'd21: cmd = {OP_WRITE, 16'h0200, 8'h02};
            8'd22: cmd = {OP_WRITE, 16'h0201, 8'h08};
            8'd23: cmd = {OP_WRITE, 16'h0300, 8'h00};
            8'd24: cmd = {OP_WRITE, 16'h0310, 8'h07};
            8'd25: cmd = {OP_WRITE, 16'h0311, 8'h70};
            8'd26: cmd = {OP_WRITE, 16'h0330, 8'h07};
            8'd27: cmd = {OP_WRITE, 16'h0331, 8'h75};
            // Keep the existing DDC/JESD mode, but set both DDC NCO FTWs to
            // zero so a low-frequency loopback appears at its analog input
            // frequency instead of being translated by the previous 3.5 GHz
            // reference configuration.
            8'd28: cmd = {OP_WRITE, 16'h0316, 8'h00};
            8'd29: cmd = {OP_WRITE, 16'h0317, 8'h00};
            8'd30: cmd = {OP_WRITE, 16'h0318, 8'h00};
            8'd31: cmd = {OP_WRITE, 16'h0319, 8'h00};
            8'd32: cmd = {OP_WRITE, 16'h031a, 8'h00};
            8'd33: cmd = {OP_WRITE, 16'h031b, 8'h00};
            8'd34: cmd = {OP_WRITE, 16'h0336, 8'h00};
            8'd35: cmd = {OP_WRITE, 16'h0337, 8'h00};
            8'd36: cmd = {OP_WRITE, 16'h0338, 8'h00};
            8'd37: cmd = {OP_WRITE, 16'h0339, 8'h00};
            8'd38: cmd = {OP_WRITE, 16'h033a, 8'h00};
            8'd39: cmd = {OP_WRITE, 16'h033b, 8'h00};
            8'd40: cmd = {OP_WRITE, 16'h056e, 8'h00};
            8'd41: cmd = {OP_WRITE, 16'h058e, 8'h03};
            8'd42: cmd = {OP_WAIT_MS, 16'h0000, 8'd10};
            8'd43: cmd = {OP_WRITE, 16'h0592, 8'h80};
            8'd44: cmd = {OP_WRITE, 16'h058b, 8'h07};
            8'd45: cmd = {OP_WRITE, 16'h058c, 8'h00};
            8'd46: cmd = {OP_WRITE, 16'h058d, 8'h1f};
            8'd47: cmd = {OP_WRITE, 16'h0583, 8'h00};
            8'd48: cmd = {OP_WRITE, 16'h0584, 8'h01};
            8'd49: cmd = {OP_WRITE, 16'h0585, 8'h02};
            8'd50: cmd = {OP_WRITE, 16'h0586, 8'h03};
            8'd51: cmd = {OP_WRITE, 16'h0587, 8'h04};
            8'd52: cmd = {OP_WRITE, 16'h0588, 8'h05};
            8'd53: cmd = {OP_WRITE, 16'h0589, 8'h06};
            8'd54: cmd = {OP_WRITE, 16'h058a, 8'h07};
            8'd55: cmd = {OP_WRITE, 16'h05b2, 8'h65};
            8'd56: cmd = {OP_WRITE, 16'h05b3, 8'h74};
            8'd57: cmd = {OP_WRITE, 16'h05b5, 8'h23};
            8'd58: cmd = {OP_WRITE, 16'h05b6, 8'h10};
            8'd59: cmd = {OP_WRITE, 16'h05c0, 8'h11};
            8'd60: cmd = {OP_WRITE, 16'h05c1, 8'h11};
            8'd61: cmd = {OP_WRITE, 16'h05c2, 8'h11};
            8'd62: cmd = {OP_WRITE, 16'h05c3, 8'h11};
            8'd63: cmd = {OP_WRITE, 16'h1228, 8'h4f};
            8'd64: cmd = {OP_WRITE, 16'h1228, 8'h0f};
            8'd65: cmd = {OP_WRITE, 16'h1222, 8'h00};
            8'd66: cmd = {OP_WRITE, 16'h1222, 8'h04};
            8'd67: cmd = {OP_WRITE, 16'h1222, 8'h00};
            8'd68: cmd = {OP_WRITE, 16'h1262, 8'h80};
            8'd69: cmd = {OP_WRITE, 16'h1262, 8'h00};
            8'd70: cmd = {OP_WRITE, 16'h0571, 8'h16};
            8'd71: cmd = {OP_END, 16'h0000, 8'h00};
            default: cmd = {OP_END, 16'h0000, 8'h00};
        endcase
    end

endmodule
