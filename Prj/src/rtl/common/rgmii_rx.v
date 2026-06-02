`timescale 1ns/1ps

// Minimal RGMII RX byte recoverer.
//
// The PHY provides RXD[3:0] and RXCTL DDR-synchronous to rx_clk.  RGMII
// encodes RX_DV on the rising RXCTL edge and RX_DV xor RX_ER on the falling
// edge.  This block returns one byte per rx_clk in the rx_clk clock domain.
module rgmii_rx #(
    parameter integer INPUT_DELAY_COUNT = 511
) (
    input  wire       rx_clk,
    input  wire       rst,
    input  wire [3:0] rgmii_rxd,
    input  wire       rgmii_rx_ctl,
    output wire [7:0] rx_data,
    output wire       rx_valid,
    output wire       rx_error
);

    wire [3:0] rxd_delay;
    wire [3:0] rxd_rise;
    wire [3:0] rxd_fall;
    wire       ctl_delay;
    wire       ctl_rise;
    wire       ctl_fall;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : g_rxd
            IDELAYE3 #(
                .CASCADE("NONE"),
                .DELAY_FORMAT("COUNT"),
                .DELAY_SRC("IDATAIN"),
                .DELAY_TYPE("FIXED"),
                .DELAY_VALUE(INPUT_DELAY_COUNT),
                .REFCLK_FREQUENCY(300.0),
                .SIM_DEVICE("ULTRASCALE_PLUS"),
                .UPDATE_MODE("ASYNC")
            ) u_idelay_rxd (
                .CASC_OUT(),
                .CNTVALUEOUT(),
                .DATAOUT(rxd_delay[i]),
                .CASC_IN(1'b0),
                .CASC_RETURN(1'b0),
                .CE(1'b0),
                .CLK(rx_clk),
                .CNTVALUEIN(9'd0),
                .DATAIN(1'b0),
                .EN_VTC(1'b1),
                .IDATAIN(rgmii_rxd[i]),
                .INC(1'b0),
                .LOAD(1'b0),
                .RST(rst)
            );

            IDDRE1 #(
                .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
                .IS_CB_INVERTED(1'b1),
                .IS_C_INVERTED(1'b0)
            ) u_iddre1_rxd (
                .Q1(rxd_rise[i]),
                .Q2(rxd_fall[i]),
                .C (rx_clk),
                .CB(rx_clk),
                .D (rxd_delay[i]),
                .R (1'b0)
            );
        end
    endgenerate

    IDELAYE3 #(
        .CASCADE("NONE"),
        .DELAY_FORMAT("COUNT"),
        .DELAY_SRC("IDATAIN"),
        .DELAY_TYPE("FIXED"),
        .DELAY_VALUE(INPUT_DELAY_COUNT),
        .REFCLK_FREQUENCY(300.0),
        .SIM_DEVICE("ULTRASCALE_PLUS"),
        .UPDATE_MODE("ASYNC")
    ) u_idelay_ctl (
        .CASC_OUT(),
        .CNTVALUEOUT(),
        .DATAOUT(ctl_delay),
        .CASC_IN(1'b0),
        .CASC_RETURN(1'b0),
        .CE(1'b0),
        .CLK(rx_clk),
        .CNTVALUEIN(9'd0),
        .DATAIN(1'b0),
        .EN_VTC(1'b1),
        .IDATAIN(rgmii_rx_ctl),
        .INC(1'b0),
        .LOAD(1'b0),
        .RST(rst)
    );

    IDDRE1 #(
        .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
        .IS_CB_INVERTED(1'b1),
        .IS_C_INVERTED(1'b0)
    ) u_iddre1_ctl (
        .Q1(ctl_rise),
        .Q2(ctl_fall),
        .C (rx_clk),
        .CB(rx_clk),
        .D (ctl_delay),
        .R (1'b0)
    );

    assign rx_data  = {rxd_fall, rxd_rise};
    assign rx_valid = ctl_rise;
    assign rx_error = ctl_rise ^ ctl_fall;

endmodule
