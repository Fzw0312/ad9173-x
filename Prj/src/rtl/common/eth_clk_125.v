`timescale 1ns/1ps

module eth_clk_125 (
    input  wire clk_200,
    input  wire rst,
    output wire clk_125,
    output wire clk_125_90,
    output wire locked
);

    wire clkfb;
    wire clkfb_buf;
    wire clk125_i;
    wire clk125_90_i;

    MMCME4_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(5.000),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(5.000),
        .CLKFBOUT_PHASE(0.000),
        .CLKOUT0_DIVIDE_F(8.000),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT0_PHASE(0.000),
        .CLKOUT1_DIVIDE(8),
        .CLKOUT1_DUTY_CYCLE(0.500),
        .CLKOUT1_PHASE(45.000),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1(clk_200),
        .RST(rst),
        .PWRDWN(1'b0),
        .CLKFBIN(clkfb_buf),
        .CLKFBOUT(clkfb),
        .LOCKED(locked),
        .CLKOUT0(clk125_i),
        .CLKOUT0B(),
        .CLKOUT1(clk125_90_i),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6()
    );

    BUFG u_clkfb_buf (
        .I(clkfb),
        .O(clkfb_buf)
    );

    BUFG u_clk125_buf (
        .I(clk125_i),
        .O(clk_125)
    );

    BUFG u_clk125_90_buf (
        .I(clk125_90_i),
        .O(clk_125_90)
    );

endmodule
