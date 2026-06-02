module jesd_clock (
    input  wire refclk_pad_n,
    input  wire refclk_pad_p,
    output wire refclk,
    output wire refclk_mon,
    output wire coreclk
);

    wire refclk_i;
    wire refclk_div2_i;
    wire coreclk_i;

    // BR40 is already programmed to 245.76 MHz. Keep ODIV2 in the default
    // no-divide mode so the JESD core/user clock stays at 245.76 MHz.
    IBUFDS_GTE4 #(
        .REFCLK_EN_TX_PATH(1'b0),
        .REFCLK_HROW_CK_SEL(2'b00),
        .REFCLK_ICNTL_RX(2'b00)
    ) u_refclk_ibuf (
        .I    (refclk_pad_p),
        .IB   (refclk_pad_n),
        .CEB  (1'b0),
        .O    (refclk_i),
        .ODIV2(refclk_div2_i)
    );

    BUFG_GT #(
        .SIM_DEVICE("ULTRASCALE_PLUS")
    ) u_coreclk_bufg (
        .I      (refclk_div2_i),
        .CE     (1'b1),
        .CEMASK (1'b1),
        .CLR    (1'b0),
        .CLRMASK(1'b1),
        .DIV    (3'b000),
        .O      (coreclk_i)
    );

    assign refclk     = refclk_i;
    assign refclk_mon = coreclk_i;
    assign coreclk    = coreclk_i;

endmodule
