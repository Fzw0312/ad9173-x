`timescale 1ns/1ps

module tb_k5wg_udp_dac_config_rgmii_rx;

    reg clk = 1'b0;
    reg tx_clk_90 = 1'b0;
    reg rst = 1'b1;
    reg [7:0] tx_data = 8'd0;
    reg tx_valid = 1'b0;

    wire rgmii_tx_clk;
    wire [3:0] rgmii_txd;
    wire rgmii_tx_ctl;
    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_error;
    wire cfg_valid;
    wire cfg_reset_phase;
    wire [47:0] cfg_phase_inc0;
    wire [47:0] cfg_phase_inc1;
    wire [47:0] cfg_phase_inc2;
    wire [47:0] cfg_phase_inc3;
    wire [15:0] cfg_scale0;
    wire [15:0] cfg_scale1;
    wire [15:0] cfg_scale2;
    wire [15:0] cfg_scale3;
    wire wave_wr_en;
    wire [11:0] wave_wr_addr;
    wire [31:0] wave_wr_data;
    wire [12:0] wave_total_samples;
    wire wave_commit_toggle;
    wire [31:0] packet_count;
    wire [31:0] config_count;
    wire [31:0] data_count;
    wire [31:0] commit_count;
    wire [31:0] drop_count;
    wire [31:0] status_dbg;

    integer i;
    reg seen_cfg;

    always #4 clk = ~clk;

    initial begin
        #1 tx_clk_90 = 1'b1;
        forever #4 tx_clk_90 = ~tx_clk_90;
    end

    rgmii_tx u_tx (
        .tx_clk      (clk),
        .tx_clk_90   (tx_clk_90),
        .rst         (rst),
        .txd         (tx_data),
        .tx_en       (tx_valid),
        .rgmii_tx_clk(rgmii_tx_clk),
        .rgmii_txd   (rgmii_txd),
        .rgmii_tx_ctl(rgmii_tx_ctl)
    );

    rgmii_rx u_rx (
        .rx_clk      (rgmii_tx_clk),
        .rst         (rst),
        .rgmii_rxd   (rgmii_txd),
        .rgmii_rx_ctl(rgmii_tx_ctl),
        .rx_data     (rx_data),
        .rx_valid    (rx_valid),
        .rx_error    (rx_error)
    );

    k5wg_udp_dac_config_rx #(
        .FPGA_IP(32'hC0A8_010A),
        .UDP_PORT(16'd5005)
    ) u_parser (
        .clk            (clk),
        .rst            (rst),
        .rx_data        (rx_data),
        .rx_valid       (rx_valid),
        .rx_error       (rx_error),
        .cfg_valid      (cfg_valid),
        .cfg_reset_phase(cfg_reset_phase),
        .cfg_phase_inc0 (cfg_phase_inc0),
        .cfg_phase_inc1 (cfg_phase_inc1),
        .cfg_phase_inc2 (cfg_phase_inc2),
        .cfg_phase_inc3 (cfg_phase_inc3),
        .cfg_scale0     (cfg_scale0),
        .cfg_scale1     (cfg_scale1),
        .cfg_scale2     (cfg_scale2),
        .cfg_scale3     (cfg_scale3),
        .wave_wr_en     (wave_wr_en),
        .wave_wr_addr   (wave_wr_addr),
        .wave_wr_data   (wave_wr_data),
        .wave_total_samples(wave_total_samples),
        .wave_commit_toggle(wave_commit_toggle),
        .packet_count   (packet_count),
        .config_count   (config_count),
        .data_count     (data_count),
        .commit_count   (commit_count),
        .drop_count     (drop_count),
        .status_dbg     (status_dbg)
    );

    initial begin
        repeat (10) @(posedge clk);
        rst <= 1'b0;
        repeat (6) @(posedge clk);
        send_frame;
        repeat (40) @(posedge clk);

        if (!seen_cfg ||
            cfg_phase_inc0 != 48'h010203040506 ||
            cfg_phase_inc1 != 48'h112233445566 ||
            cfg_phase_inc2 != 48'h5566778899aa ||
            cfg_phase_inc3 != 48'h99aabbccddee ||
            cfg_scale0 != 16'h1111 ||
            cfg_scale1 != 16'h2222 ||
            cfg_scale2 != 16'h3333 ||
            cfg_scale3 != 16'h4444) begin
            $display("ERROR: RGMII decoded config mismatch seen=%b status=%08x cfgs=%0d drops=%0d inc=%08x/%08x/%08x/%08x",
                     seen_cfg, status_dbg, config_count, drop_count,
                     cfg_phase_inc0, cfg_phase_inc1,
                     cfg_phase_inc2, cfg_phase_inc3);
            $finish;
        end

        $display("K5WG_UDP_DAC_CONFIG_RGMII_RX_OK configs=%0d drops=%0d packets=%0d",
                 config_count, drop_count, packet_count);
        $finish;
    end

    always @(posedge clk) begin
        if (rst) begin
            seen_cfg <= 1'b0;
        end else if (cfg_valid) begin
            seen_cfg <= 1'b1;
        end
    end

    initial begin
        repeat (30000) @(posedge clk);
        $display("ERROR: timeout status=%08x packets=%0d configs=%0d drops=%0d",
                 status_dbg, packet_count, config_count, drop_count);
        $finish;
    end

    task send_byte;
        input [7:0] b;
        begin
            @(posedge clk);
            tx_data <= b;
            tx_valid <= 1'b1;
        end
    endtask

    task send_frame;
        begin
            for (i = 0; i < 7; i = i + 1) send_byte(8'h55);
            send_byte(8'hd5);
            send_eth_ip_udp_header;
            send_k5wg_header;
            send_k5dc_payload;
            send_word32_le(32'h12345678);
            @(posedge clk);
            tx_valid <= 1'b0;
            tx_data <= 8'd0;
        end
    endtask

    task send_eth_ip_udp_header;
        begin
            send_byte(8'hff); send_byte(8'hff); send_byte(8'hff);
            send_byte(8'hff); send_byte(8'hff); send_byte(8'hff);
            send_byte(8'h02); send_byte(8'h00); send_byte(8'h00);
            send_byte(8'h00); send_byte(8'h5a); send_byte(8'h02);
            send_byte(8'h08); send_byte(8'h00);
            send_byte(8'h45); send_byte(8'h00);
            send_byte(8'h00); send_byte(8'h60);
            send_byte(8'h12); send_byte(8'h34);
            send_byte(8'h40); send_byte(8'h00);
            send_byte(8'h40); send_byte(8'h11);
            send_byte(8'h00); send_byte(8'h00);
            send_byte(8'hc0); send_byte(8'ha8); send_byte(8'h01); send_byte(8'h64);
            send_byte(8'hff); send_byte(8'hff); send_byte(8'hff); send_byte(8'hff);
            send_byte(8'h13); send_byte(8'h8d);
            send_byte(8'h13); send_byte(8'h8d);
            send_byte(8'h00); send_byte(8'h44);
            send_byte(8'h00); send_byte(8'h00);
        end
    endtask

    task send_k5wg_header;
        begin
            send_byte(8'h4b); send_byte(8'h35); send_byte(8'h57); send_byte(8'h47);
            send_byte(8'h01); send_byte(8'h02);
            send_byte(8'h1c); send_byte(8'h00);
            send_word32_le(32'd2);
            send_word32_le(32'd0);
            send_word32_le(32'd48);
            send_word32_le(32'd0);
            send_word32_le(32'd0);
        end
    endtask

    task send_k5dc_payload;
        begin
            send_byte(8'h4b); send_byte(8'h35); send_byte(8'h44); send_byte(8'h43);
            send_byte(8'h01);
            send_byte(8'h01);
            send_byte(8'h0f); send_byte(8'h00);
            send_byte(8'h00); send_byte(8'h00); send_byte(8'h9b); send_byte(8'h3a);
            send_word48_le(48'h010203040506);
            send_word48_le(48'h112233445566);
            send_word48_le(48'h5566778899aa);
            send_word48_le(48'h99aabbccddee);
            send_word16_le(16'h1111);
            send_word16_le(16'h2222);
            send_word16_le(16'h3333);
            send_word16_le(16'h4444);
            send_word32_le(32'd0);
        end
    endtask

    task send_word48_le;
        input [47:0] value;
        begin
            send_byte(value[7:0]);
            send_byte(value[15:8]);
            send_byte(value[23:16]);
            send_byte(value[31:24]);
            send_byte(value[39:32]);
            send_byte(value[47:40]);
        end
    endtask

    task send_word32_le;
        input [31:0] value;
        begin
            send_byte(value[7:0]);
            send_byte(value[15:8]);
            send_byte(value[23:16]);
            send_byte(value[31:24]);
        end
    endtask

    task send_word16_le;
        input [15:0] value;
        begin
            send_byte(value[7:0]);
            send_byte(value[15:8]);
        end
    endtask

endmodule
