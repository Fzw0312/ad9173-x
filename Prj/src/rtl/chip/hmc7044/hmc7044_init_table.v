module hmc7044_init_table (
    input  wire [7:0] addr,
    output reg  [31:0] cmd
);

    localparam [7:0] OP_WRITE   = 8'h01;
    localparam [7:0] OP_WAIT_MS = 8'h02;
    localparam [7:0] OP_END     = 8'hff;

    always @(*) begin
        case (addr)
            8'd0:  cmd = {OP_WRITE, 16'h00c8, 8'h00};
            8'd1:  cmd = {OP_WRITE, 16'h00d2, 8'h00};
            8'd2:  cmd = {OP_WRITE, 16'h00dc, 8'h00};
            8'd3:  cmd = {OP_WRITE, 16'h00e6, 8'h00};
            8'd4:  cmd = {OP_WRITE, 16'h00f0, 8'h00};
            8'd5:  cmd = {OP_WRITE, 16'h00fa, 8'h00};
            8'd6:  cmd = {OP_WRITE, 16'h0104, 8'h00};
            8'd7:  cmd = {OP_WRITE, 16'h010e, 8'h00};
            8'd8:  cmd = {OP_WRITE, 16'h0118, 8'h00};
            8'd9:  cmd = {OP_WRITE, 16'h0122, 8'h00};
            8'd10: cmd = {OP_WRITE, 16'h012c, 8'h00};
            8'd11: cmd = {OP_WRITE, 16'h0136, 8'h00};
            8'd12: cmd = {OP_WRITE, 16'h0140, 8'h00};
            8'd13: cmd = {OP_WRITE, 16'h014a, 8'h00};
            8'd14: cmd = {OP_WRITE, 16'h009f, 8'h4d};
            8'd15: cmd = {OP_WRITE, 16'h00a0, 8'hdf};
            8'd16: cmd = {OP_WRITE, 16'h00a5, 8'h06};
            8'd17: cmd = {OP_WRITE, 16'h00a8, 8'h06};
            8'd18: cmd = {OP_WRITE, 16'h00b0, 8'h04};
            // Board clock sources:
            // - CLKIN0 <- U11 differential 122.88 MHz reference
            // - OSCIN  <- U10 VCXO
            // CLKIN1/FIN is not populated on this board, so PLL1 must not select it.
            8'd19: cmd = {OP_WRITE, 16'h0005, 8'h01};
            // Make the global output-pair enables explicit instead of relying
            // on the reset default. Bit 2 gates the ch4/ch5 pair used by the
            // AD6688 sample clock.
            8'd20: cmd = {OP_WRITE, 16'h0004, 8'h7f};
            8'd21: cmd = {OP_WRITE, 16'h0003, 8'h0f};
            8'd22: cmd = {OP_WRITE, 16'h0033, 8'h01};
            8'd23: cmd = {OP_WRITE, 16'h0034, 8'h00};
            8'd24: cmd = {OP_WRITE, 16'h0035, 8'h18};
            8'd25: cmd = {OP_WRITE, 16'h0036, 8'h00};
            8'd26: cmd = {OP_WRITE, 16'h0032, 8'h01};
            // HMC7044 datasheet recommends PLL1 Lock Detect Timer = 19 or 20
            // for fLCM = 61.44 MHz and ~200 Hz loop bandwidth. The original
            // VCK190 software kept 0x1F, which leaves PLL1 in acquisition for
            // an unnecessarily long time on this board. Use 20 so lock detect
            // can assert in a practical bring-up window.
            8'd27: cmd = {OP_WRITE, 16'h0028, 8'h14};
            // PLL1 now uses CLKIN0, so move the input prescaler programming
            // from Register 0x001D (CLKIN1) to Register 0x001C (CLKIN0).
            8'd28: cmd = {OP_WRITE, 16'h001c, 8'h02};
            8'd29: cmd = {OP_WRITE, 16'h001d, 8'h00};
            8'd30: cmd = {OP_WRITE, 16'h0020, 8'h02};
            8'd31: cmd = {OP_WRITE, 16'h0021, 8'h07};
            8'd32: cmd = {OP_WRITE, 16'h0022, 8'h00};
            8'd33: cmd = {OP_WRITE, 16'h0026, 8'h0e};
            8'd34: cmd = {OP_WRITE, 16'h0027, 8'h00};
            8'd35: cmd = {OP_WRITE, 16'h0014, 8'h00};
            8'd36: cmd = {OP_WRITE, 16'h005c, 8'h00};
            8'd37: cmd = {OP_WRITE, 16'h005d, 8'h04};
            8'd38: cmd = {OP_WRITE, 16'h005a, 8'h00};
            8'd39: cmd = {OP_WRITE, 16'h000a, 8'h15};
            8'd40: cmd = {OP_WRITE, 16'h000b, 8'h00};
            8'd41: cmd = {OP_WRITE, 16'h000c, 8'h00};
            8'd42: cmd = {OP_WRITE, 16'h000d, 8'h00};
            8'd43: cmd = {OP_WRITE, 16'h000e, 8'h15};
            8'd44: cmd = {OP_WRITE, 16'h0046, 8'h00};
            8'd45: cmd = {OP_WRITE, 16'h0047, 8'h00};
            8'd46: cmd = {OP_WRITE, 16'h0048, 8'h00};
            8'd47: cmd = {OP_WRITE, 16'h0049, 8'h00};
            8'd48: cmd = {OP_WRITE, 16'h0050, 8'h1f};
            8'd49: cmd = {OP_WRITE, 16'h0051, 8'h1f};
            8'd50: cmd = {OP_WRITE, 16'h0052, 8'h00};
            8'd51: cmd = {OP_WRITE, 16'h0053, 8'h00};
            8'd52: cmd = {OP_WAIT_MS, 16'h0000, 8'd10};
            // Board-level HMC7044 output routing:
            // ch4  -> TOAD6688_CLK_P/N  : 2949.12 MHz AD6688 sample clock
            // ch6  -> DAC_CLKIN_P/N     : 491.52 MHz DAC clock
            // ch7  -> SYSREF_P/N        : 7.68 MHz DAC SYSREF
            // ch10 -> BR40_P/N          : 245.76 MHz FPGA JESD refclk
            // ch11 -> SYSREF3_P/N       : 7.68 MHz ADC SYSREF
            // ch13 -> SYSREF2_P/N       : 7.68 MHz FPGA SYSREF
            // With the output mux selecting the fundamental VCO clock, the
            // datasheet says to set the unused channel divider to 0.
            8'd53: cmd = {OP_WRITE, 16'h00f1, 8'h00};
            8'd54: cmd = {OP_WRITE, 16'h00f2, 8'h00};
            // AD6688 sample clock is AC-coupled directly from HMC7044 ch4.
            // Use CML with internal 100 ohm output resistance; the board
            // netlist does not show the shunt terminations normally used by
            // LVPECL, and the AD6688 clock input supports AC-coupled CML.
            8'd55: cmd = {OP_WRITE, 16'h00f8, 8'h01};
            8'd56: cmd = {OP_WRITE, 16'h00f3, 8'h00};
            8'd57: cmd = {OP_WRITE, 16'h00f4, 8'h00};
            // Select the fundamental VCO clock path for ch4 to isolate the
            // divider-by-1 path while debugging AD6688 clock detect.
            8'd58: cmd = {OP_WRITE, 16'h00f7, 8'h03};
            8'd59: cmd = {OP_WRITE, 16'h00f0, 8'hc1};
            8'd60: cmd = {OP_WRITE, 16'h0105, 8'h06};
            8'd61: cmd = {OP_WRITE, 16'h0106, 8'h00};
            8'd62: cmd = {OP_WRITE, 16'h010c, 8'h08};
            8'd63: cmd = {OP_WRITE, 16'h0107, 8'h00};
            8'd64: cmd = {OP_WRITE, 16'h0108, 8'h00};
            8'd65: cmd = {OP_WRITE, 16'h010b, 8'h00};
            8'd66: cmd = {OP_WRITE, 16'h0104, 8'hc1};
            8'd67: cmd = {OP_WRITE, 16'h010f, 8'h80};
            8'd68: cmd = {OP_WRITE, 16'h0110, 8'h01};
            8'd69: cmd = {OP_WRITE, 16'h0116, 8'h08};
            8'd70: cmd = {OP_WRITE, 16'h0111, 8'h00};
            8'd71: cmd = {OP_WRITE, 16'h0112, 8'h00};
            8'd72: cmd = {OP_WRITE, 16'h0115, 8'h00};
            8'd73: cmd = {OP_WRITE, 16'h010e, 8'hc1};
            8'd74: cmd = {OP_WRITE, 16'h012d, 8'h0c};
            8'd75: cmd = {OP_WRITE, 16'h012e, 8'h00};
            // BR40_P/N is the FPGA CLK path. CML mode with the channel
            // output-side 100 ohm option gives the best lock behavior seen so
            // far; 50 ohm (0x03) was worse on this board.
            8'd76: cmd = {OP_WRITE, 16'h0134, 8'h01};
            8'd77: cmd = {OP_WRITE, 16'h0135, 8'h00};
            8'd78: cmd = {OP_WRITE, 16'h012f, 8'h00};
            8'd79: cmd = {OP_WRITE, 16'h0130, 8'h00};
            8'd80: cmd = {OP_WRITE, 16'h0133, 8'h00};
            8'd81: cmd = {OP_WRITE, 16'h012c, 8'hc1};
            8'd82: cmd = {OP_WRITE, 16'h0137, 8'h80};
            8'd83: cmd = {OP_WRITE, 16'h0138, 8'h01};
            // SYSREF3 feeds AD6688 for subclass-1 deterministic latency.
            8'd84: cmd = {OP_WRITE, 16'h013e, 8'h10};
            8'd85: cmd = {OP_WRITE, 16'h0139, 8'h00};
            8'd86: cmd = {OP_WRITE, 16'h013a, 8'h00};
            8'd87: cmd = {OP_WRITE, 16'h013d, 8'h00};
            8'd88: cmd = {OP_WRITE, 16'h0136, 8'hc1};
            8'd89: cmd = {OP_WRITE, 16'h014b, 8'h80};
            8'd90: cmd = {OP_WRITE, 16'h014c, 8'h01};
            // SYSREF2 feeds the FPGA fabric LVDS input pair.
            8'd91: cmd = {OP_WRITE, 16'h0152, 8'h10};
            8'd92: cmd = {OP_WRITE, 16'h014d, 8'h00};
            8'd93: cmd = {OP_WRITE, 16'h014e, 8'h00};
            8'd94: cmd = {OP_WRITE, 16'h0151, 8'h00};
            8'd95: cmd = {OP_WRITE, 16'h014a, 8'hc1};
            8'd96: cmd = {OP_WAIT_MS, 16'h0000, 8'd10};
            8'd97: cmd = {OP_WRITE, 16'h0001, 8'h02};
            8'd98: cmd = {OP_WAIT_MS, 16'h0000, 8'd1};
            8'd99: cmd = {OP_WRITE, 16'h0001, 8'h00};
            8'd100: cmd = {OP_WAIT_MS, 16'h0000, 8'd1};
            8'd101: cmd = {OP_END, 16'h0000, 8'h00};
            default: cmd = {OP_END, 16'h0000, 8'h00};
        endcase
    end

endmodule
