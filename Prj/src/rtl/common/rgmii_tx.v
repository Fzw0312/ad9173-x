`timescale 1ns/1ps

module rgmii_tx (
    input  wire       tx_clk,
    input  wire       tx_clk_90,
    input  wire       rst,
    input  wire [7:0] txd,
    input  wire       tx_en,
    output wire       rgmii_tx_clk,
    output wire [3:0] rgmii_txd,
    output wire       rgmii_tx_ctl
);

    ODDRE1 #(
        .SIM_DEVICE("ULTRASCALE_PLUS"),
        .SRVAL(1'b0)
    ) u_clk_oddr (
        .Q (rgmii_tx_clk),
        .C (tx_clk_90),
        .D1(1'b1),
        .D2(1'b0),
        .SR(rst)
    );

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : g_txd
            ODDRE1 #(
                .SIM_DEVICE("ULTRASCALE_PLUS"),
                .SRVAL(1'b0)
            ) u_txd_oddr (
                .Q (rgmii_txd[i]),
                .C (tx_clk),
                .D1(txd[i]),
                .D2(txd[i + 4]),
                .SR(rst)
            );
        end
    endgenerate

    ODDRE1 #(
        .SIM_DEVICE("ULTRASCALE_PLUS"),
        .SRVAL(1'b0)
    ) u_ctl_oddr (
        .Q (rgmii_tx_ctl),
        .C (tx_clk),
        .D1(tx_en),
        .D2(tx_en),
        .SR(rst)
    );

endmodule
