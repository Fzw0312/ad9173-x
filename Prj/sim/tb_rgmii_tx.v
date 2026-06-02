`timescale 1ns/1ps

module tb_rgmii_tx;

    reg tx_clk = 1'b0;
    reg tx_clk_90 = 1'b0;
    reg rst = 1'b1;
    reg [7:0] txd = 8'h00;
    reg tx_en = 1'b0;

    wire rgmii_tx_clk;
    wire [3:0] rgmii_txd;
    wire rgmii_tx_ctl;

    always #4 tx_clk = ~tx_clk;

    initial begin
        #6 tx_clk_90 = 1'b1;
        forever #4 tx_clk_90 = ~tx_clk_90;
    end

    rgmii_tx dut (
        .tx_clk      (tx_clk),
        .tx_clk_90   (tx_clk_90),
        .rst         (rst),
        .txd         (txd),
        .tx_en       (tx_en),
        .rgmii_tx_clk(rgmii_tx_clk),
        .rgmii_txd   (rgmii_txd),
        .rgmii_tx_ctl(rgmii_tx_ctl)
    );

    initial begin
        repeat (3) @(posedge tx_clk);
        rst <= 1'b0;
        repeat (20) @(posedge tx_clk);

        drive_and_check(8'ha5, 1'b1);
        drive_and_check(8'h3c, 1'b1);
        drive_and_check(8'hf0, 1'b1);
        drive_and_check(8'h0f, 1'b0);

        repeat (4) @(posedge tx_clk);
        $display("RGMII_TX_OK");
        $finish;
    end

    task drive_and_check;
        input [7:0] value;
        input       enable;
        begin
            @(negedge tx_clk);
            txd <= value;
            tx_en <= enable;
            @(posedge tx_clk_90);
            #1;
            if (rgmii_tx_clk !== 1'b1 ||
                rgmii_txd !== value[3:0] ||
                rgmii_tx_ctl !== enable) begin
                $display("ERROR: rising DDR half value=%02x clk=%b txd=%x ctl=%b",
                         value, rgmii_tx_clk, rgmii_txd, rgmii_tx_ctl);
                $finish;
            end
            @(negedge tx_clk_90);
            #1;
            if (rgmii_tx_clk !== 1'b0 ||
                rgmii_txd !== value[7:4] ||
                rgmii_tx_ctl !== enable) begin
                $display("ERROR: falling DDR half value=%02x clk=%b txd=%x ctl=%b",
                         value, rgmii_tx_clk, rgmii_txd, rgmii_tx_ctl);
                $finish;
            end
        end
    endtask

endmodule
