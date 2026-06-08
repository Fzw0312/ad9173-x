// FPGA JESD/GT 参考时钟缓冲模块。
//
// HMC7044 ch10(BR40_P/N) 输出 245.76 MHz 到 FPGA GBTCLK 引脚。
// 这里使用 IBUFDS_GTE4 接入 GT refclk，同时通过 BUFG_GT 给 JESD core
// 作为 tx_core_clk/user clock。该时钟与 build_dac_udp.tcl 中的
// GT_REFCLK_FREQ=245.76 MHz 保持一致。
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

    // BR40 已由 HMC7044 配置为 245.76 MHz。这里保持 ODIV2 不分频，
    // 让 JESD core/user clock 也工作在 245.76 MHz。
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
