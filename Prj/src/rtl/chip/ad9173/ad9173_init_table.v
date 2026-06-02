module ad9173_init_table (
    input  wire [7:0] addr,
    output reg  [31:0] cmd
);

    localparam [7:0] OP_WRITE   = 8'h01;
    localparam [7:0] OP_WAIT_MS = 8'h02;
    localparam [7:0] OP_END     = 8'hff;

    always @(*) begin
        case (addr)
            8'd0:  cmd = {OP_WRITE, 16'h0000, 8'h81};
            8'd1:  cmd = {OP_WRITE, 16'h0000, 8'h24};
            8'd2:  cmd = {OP_WRITE, 16'h0090, 8'h03};
            8'd3:  cmd = {OP_WRITE, 16'h0203, 8'h03};
            8'd4:  cmd = {OP_WRITE, 16'h0091, 8'h00};
            8'd5:  cmd = {OP_WRITE, 16'h0206, 8'h01};
            8'd6:  cmd = {OP_WRITE, 16'h0705, 8'h01};
            8'd7:  cmd = {OP_WAIT_MS, 16'h0000, 8'd10};
            8'd8:  cmd = {OP_WRITE, 16'h0090, 8'h00};
            8'd9:  cmd = {OP_WRITE, 16'h0095, 8'h00};
            8'd10: cmd = {OP_WRITE, 16'h0790, 8'h00};
            8'd11: cmd = {OP_WRITE, 16'h0791, 8'h00};
            8'd12: cmd = {OP_WRITE, 16'h0796, 8'he5};
            8'd13: cmd = {OP_WRITE, 16'h07a0, 8'hbc};
            8'd14: cmd = {OP_WRITE, 16'h0794, 8'h08};
            8'd15: cmd = {OP_WRITE, 16'h0797, 8'h10};
            8'd16: cmd = {OP_WRITE, 16'h0797, 8'h20};
            8'd17: cmd = {OP_WRITE, 16'h0798, 8'h10};
            8'd18: cmd = {OP_WRITE, 16'h07a2, 8'h7f};
            8'd19: cmd = {OP_WAIT_MS, 16'h0000, 8'd200};
            8'd20: cmd = {OP_WRITE, 16'h0799, 8'hc3};
            8'd21: cmd = {OP_WRITE, 16'h0793, 8'h18};
            8'd22: cmd = {OP_WRITE, 16'h0094, 8'h00};
            8'd23: cmd = {OP_WRITE, 16'h0792, 8'h02};
            8'd24: cmd = {OP_WRITE, 16'h0792, 8'h00};
            8'd25: cmd = {OP_WAIT_MS, 16'h0000, 8'd200};
            8'd26: cmd = {OP_WRITE, 16'h00c0, 8'h00};
            8'd27: cmd = {OP_WRITE, 16'h00db, 8'h00};
            8'd28: cmd = {OP_WRITE, 16'h00db, 8'h01};
            8'd29: cmd = {OP_WRITE, 16'h00db, 8'h00};
            8'd30: cmd = {OP_WRITE, 16'h00c1, 8'h68};
            8'd31: cmd = {OP_WRITE, 16'h00c1, 8'h69};
            8'd32: cmd = {OP_WRITE, 16'h00c7, 8'h01};
            8'd33: cmd = {OP_WRITE, 16'h0050, 8'h2a};
            8'd34: cmd = {OP_WRITE, 16'h0061, 8'h68};
            8'd35: cmd = {OP_WRITE, 16'h0051, 8'h82};
            8'd36: cmd = {OP_WRITE, 16'h0051, 8'h83};
            8'd37: cmd = {OP_WRITE, 16'h0081, 8'h03};
            8'd38: cmd = {OP_WRITE, 16'h0100, 8'h00};
            8'd39: cmd = {OP_WRITE, 16'h0110, 8'h28};
            8'd40: cmd = {OP_WRITE, 16'h0111, 8'hc1};
            8'd41: cmd = {OP_WRITE, 16'h0084, 8'h40};
            8'd42: cmd = {OP_WRITE, 16'h0312, 8'h00};
            8'd43: cmd = {OP_WRITE, 16'h0300, 8'h0b};
            8'd44: cmd = {OP_WRITE, 16'h0475, 8'h09};
            8'd45: cmd = {OP_WRITE, 16'h0453, 8'h03};
            8'd46: cmd = {OP_WRITE, 16'h0458, 8'h2f};
            8'd47: cmd = {OP_WRITE, 16'h0475, 8'h01};
            8'd48: cmd = {OP_WRITE, 16'h0300, 8'h0f};
            8'd49: cmd = {OP_WRITE, 16'h0475, 8'h09};
            8'd50: cmd = {OP_WRITE, 16'h0453, 8'h03};
            8'd51: cmd = {OP_WRITE, 16'h0458, 8'h2f};
            8'd52: cmd = {OP_WRITE, 16'h0475, 8'h01};
            8'd53: cmd = {OP_WRITE, 16'h0008, 8'hff};
            // Main datapath interpolation is 12x, so keep the main NCO
            // enabled per the AD9173 datasheet, but use FTW=0 for no
            // frequency translation. The JESD payload sets DAC0/DAC1 tones.
            8'd54: cmd = {OP_WRITE, 16'h0112, 8'h08};
            8'd55: cmd = {OP_WRITE, 16'h0113, 8'h00};
            8'd56: cmd = {OP_WRITE, 16'h0114, 8'h00};
            8'd57: cmd = {OP_WRITE, 16'h0115, 8'h00};
            8'd58: cmd = {OP_WRITE, 16'h0116, 8'h00};
            8'd59: cmd = {OP_WRITE, 16'h0117, 8'h00};
            8'd60: cmd = {OP_WRITE, 16'h0118, 8'h00};
            8'd61: cmd = {OP_WRITE, 16'h0119, 8'h00};
            8'd62: cmd = {OP_WRITE, 16'h011c, 8'h00};
            8'd63: cmd = {OP_WRITE, 16'h011d, 8'h00};
            8'd64: cmd = {OP_WRITE, 16'h0113, 8'h01};
            8'd65: cmd = {OP_WRITE, 16'h014b, 8'h00};
            8'd66: cmd = {OP_WRITE, 16'h0240, 8'haa};
            8'd67: cmd = {OP_WRITE, 16'h0241, 8'haa};
            8'd68: cmd = {OP_WRITE, 16'h0242, 8'h55};
            8'd69: cmd = {OP_WRITE, 16'h0243, 8'h55};
            8'd70: cmd = {OP_WRITE, 16'h0244, 8'h1f};
            8'd71: cmd = {OP_WRITE, 16'h0245, 8'h1f};
            8'd72: cmd = {OP_WRITE, 16'h0246, 8'h1f};
            8'd73: cmd = {OP_WRITE, 16'h0247, 8'h1f};
            8'd74: cmd = {OP_WRITE, 16'h0248, 8'h1f};
            8'd75: cmd = {OP_WRITE, 16'h0249, 8'h1f};
            8'd76: cmd = {OP_WRITE, 16'h024a, 8'h1f};
            8'd77: cmd = {OP_WRITE, 16'h024b, 8'h1f};
            8'd78: cmd = {OP_WRITE, 16'h0201, 8'h00};
            8'd79: cmd = {OP_WRITE, 16'h0203, 8'h00};
            8'd80: cmd = {OP_WRITE, 16'h0253, 8'h01};
            8'd81: cmd = {OP_WRITE, 16'h0254, 8'h01};
            8'd82: cmd = {OP_WRITE, 16'h0210, 8'h16};
            8'd83: cmd = {OP_WRITE, 16'h0216, 8'h05};
            8'd84: cmd = {OP_WRITE, 16'h0212, 8'hff};
            8'd85: cmd = {OP_WRITE, 16'h0212, 8'h00};
            8'd86: cmd = {OP_WRITE, 16'h0210, 8'h87};
            8'd87: cmd = {OP_WRITE, 16'h0216, 8'h11};
            8'd88: cmd = {OP_WRITE, 16'h0213, 8'h01};
            8'd89: cmd = {OP_WRITE, 16'h0213, 8'h00};
            8'd90: cmd = {OP_WRITE, 16'h0200, 8'h00};
            8'd91: cmd = {OP_WAIT_MS, 16'h0000, 8'd150};
            8'd92: cmd = {OP_WRITE, 16'h0210, 8'h86};
            8'd93: cmd = {OP_WRITE, 16'h0216, 8'h40};
            8'd94: cmd = {OP_WRITE, 16'h0213, 8'h01};
            8'd95: cmd = {OP_WRITE, 16'h0213, 8'h00};
            8'd96: cmd = {OP_WRITE, 16'h0210, 8'h86};
            8'd97: cmd = {OP_WRITE, 16'h0216, 8'h00};
            8'd98: cmd = {OP_WRITE, 16'h0213, 8'h01};
            8'd99: cmd = {OP_WRITE, 16'h0213, 8'h00};
            8'd100: cmd = {OP_WRITE, 16'h0210, 8'h87};
            8'd101: cmd = {OP_WRITE, 16'h0216, 8'h01};
            8'd102: cmd = {OP_WRITE, 16'h0213, 8'h01};
            8'd103: cmd = {OP_WRITE, 16'h0213, 8'h00};
            8'd104: cmd = {OP_WRITE, 16'h0280, 8'h05};
            8'd105: cmd = {OP_WRITE, 16'h0280, 8'h01};
            8'd106: cmd = {OP_WRITE, 16'h005a, 8'hff};
            // KU5P board mapping:
            //   Link0 logical lanes 0..3 use SERDIN0..3.
            //   Link1 logical lanes 4..7 use quad227 physical order
            //   SERDIN5, SERDIN7, SERDIN6, SERDIN4.
            8'd107: cmd = {OP_WRITE, 16'h0308, 8'h08};
            8'd108: cmd = {OP_WRITE, 16'h0309, 8'h1a};
            8'd109: cmd = {OP_WRITE, 16'h030a, 8'h3d};
            8'd110: cmd = {OP_WRITE, 16'h030b, 8'h26};
            8'd111: cmd = {OP_WRITE, 16'h0306, 8'h0c};
            8'd112: cmd = {OP_WRITE, 16'h0307, 8'h0c};
            8'd113: cmd = {OP_WRITE, 16'h0304, 8'h00};
            8'd114: cmd = {OP_WRITE, 16'h0305, 8'h01};
            8'd115: cmd = {OP_WRITE, 16'h003b, 8'hf1};
            8'd116: cmd = {OP_WRITE, 16'h003a, 8'h02};
            8'd117: cmd = {OP_WRITE, 16'h0300, 8'h0b};
            8'd118: cmd = {OP_WRITE, 16'h0085, 8'h13};
            8'd119: cmd = {OP_WRITE, 16'h01de, 8'h03};
            8'd120: cmd = {OP_WRITE, 16'h0008, 8'hc0};
            8'd121: cmd = {OP_WRITE, 16'h0596, 8'h0c};
            // Link0/Link1 lanes are clean with normal logical polarity.
            // Crossbar sweep kept the identity Link0 order and showed
            // polarity 0x00 as the full-pass candidate.
            8'd122: cmd = {OP_WRITE, 16'h0334, 8'h00};
            // Re-release both QBD deframers after the final lane crossbar
            // and polarity writes so ILAS is captured with the KU5P mapping.
            8'd123: cmd = {OP_WRITE, 16'h0300, 8'h0b};
            8'd124: cmd = {OP_WRITE, 16'h0475, 8'h09};
            8'd125: cmd = {OP_WRITE, 16'h0453, 8'h03};
            8'd126: cmd = {OP_WRITE, 16'h0458, 8'h2f};
            8'd127: cmd = {OP_WRITE, 16'h0475, 8'h01};
            8'd128: cmd = {OP_WAIT_MS, 16'h0000, 8'd1};
            8'd129: cmd = {OP_WRITE, 16'h0300, 8'h0f};
            8'd130: cmd = {OP_WRITE, 16'h0475, 8'h09};
            8'd131: cmd = {OP_WRITE, 16'h0453, 8'h03};
            8'd132: cmd = {OP_WRITE, 16'h0458, 8'h2f};
            8'd133: cmd = {OP_WRITE, 16'h0475, 8'h01};
            8'd134: cmd = {OP_WAIT_MS, 16'h0000, 8'd5};
            8'd135: cmd = {OP_WRITE, 16'h0300, 8'h0b};
            8'd136: cmd = {OP_END, 16'h0000, 8'h00};
            default: cmd = {OP_END, 16'h0000, 8'h00};
        endcase
    end

endmodule
