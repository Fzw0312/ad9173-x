`timescale 1ns/1ps

module tb_k5wg_udp_dac_config_rx;

    localparam integer WAVE_ADDR_WIDTH = 15;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [7:0] rx_data = 8'd0;
    reg rx_valid = 1'b0;
    reg rx_error = 1'b0;

    wire cfg_valid;
    wire cfg_reset_phase;
    wire cfg_nco_only;
    wire cfg_ram_mode;
    wire [47:0] cfg_phase_inc0;
    wire [47:0] cfg_phase_inc1;
    wire [47:0] cfg_phase_inc2;
    wire [47:0] cfg_phase_inc3;
    wire [15:0] cfg_scale0;
    wire [15:0] cfg_scale1;
    wire [15:0] cfg_scale2;
    wire [15:0] cfg_scale3;
    wire [47:0] cfg_main_nco_ftw;
    wire [3:0] cfg_rf_atten_mask;
    wire cfg_output_path_sel;
    wire wave_wr_en;
    wire [WAVE_ADDR_WIDTH-1:0] wave_wr_addr;
    wire [31:0] wave_wr_data;
    wire [WAVE_ADDR_WIDTH:0] wave_total_samples;
    wire wave_commit_toggle;
    wire [31:0] packet_count;
    wire [31:0] config_count;
    wire [31:0] data_count;
    wire [31:0] commit_count;
    wire [31:0] drop_count;
    wire [31:0] status_dbg;

    integer i;
    reg seen_cfg;
    reg seen_commit;
    reg [31:0] wave_write_count;
    reg [WAVE_ADDR_WIDTH-1:0] last_wave_addr;
    reg [31:0] last_wave_data;
    reg last_commit_toggle = 1'b0;

    always #4 clk = ~clk;

    k5wg_udp_dac_config_rx #(
        .FPGA_IP(32'hC0A8_010A),
        .UDP_PORT(16'd5005),
        .WAVE_ADDR_WIDTH(WAVE_ADDR_WIDTH)
    ) u_dut (
        .clk            (clk),
        .rst            (rst),
        .rx_data        (rx_data),
        .rx_valid       (rx_valid),
        .rx_error       (rx_error),
        .cfg_valid      (cfg_valid),
        .cfg_reset_phase(cfg_reset_phase),
        .cfg_nco_only   (cfg_nco_only),
        .cfg_ram_mode   (cfg_ram_mode),
        .cfg_phase_inc0 (cfg_phase_inc0),
        .cfg_phase_inc1 (cfg_phase_inc1),
        .cfg_phase_inc2 (cfg_phase_inc2),
        .cfg_phase_inc3 (cfg_phase_inc3),
        .cfg_scale0     (cfg_scale0),
        .cfg_scale1     (cfg_scale1),
        .cfg_scale2     (cfg_scale2),
        .cfg_scale3     (cfg_scale3),
        .cfg_main_nco_ftw(cfg_main_nco_ftw),
        .cfg_rf_atten_mask(cfg_rf_atten_mask),
        .cfg_output_path_sel(cfg_output_path_sel),
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
        repeat (8) @(posedge clk);
        rst <= 1'b0;
        repeat (4) @(posedge clk);

        send_valid_config(1'b1);
        repeat (4) @(posedge clk);
        if (!seen_cfg) begin
            $display("ERROR: cfg_valid was not observed");
            $finish;
        end
        if (!cfg_reset_phase ||
            !cfg_ram_mode ||
            cfg_phase_inc0 != 48'h010203040506 ||
            cfg_phase_inc1 != 48'h112233445566 ||
            cfg_phase_inc2 != 48'h5566778899aa ||
            cfg_phase_inc3 != 48'h99aabbccddee ||
            cfg_scale0 != 16'h1111 ||
            cfg_scale1 != 16'h2222 ||
            cfg_scale2 != 16'h3333 ||
            cfg_scale3 != 16'h4444 ||
            cfg_main_nco_ftw != 48'he31155555555 ||
            cfg_rf_atten_mask != 4'h5 ||
            cfg_output_path_sel != 1'b1 ||
            config_count != 32'd1) begin
            $display("ERROR: decoded config mismatch cfg=%b reset=%b ram=%b inc=%08x/%08x/%08x/%08x scale=%04x/%04x/%04x/%04x rf=%02x path=%b count=%0d status=%08x",
                     cfg_valid, cfg_reset_phase, cfg_ram_mode,
                     cfg_phase_inc0, cfg_phase_inc1,
                     cfg_phase_inc2, cfg_phase_inc3,
                     cfg_scale0, cfg_scale1, cfg_scale2, cfg_scale3,
                     cfg_rf_atten_mask, cfg_output_path_sel,
                     config_count, status_dbg);
            $finish;
        end

        send_data_frame;
        repeat (4) @(posedge clk);
        if (data_count != 32'd1 ||
            wave_write_count != 32'd2 ||
            wave_total_samples != 2 ||
            last_wave_addr != 1 ||
            last_wave_data != 32'h44443333) begin
            $display("ERROR: data frame mismatch data_count=%0d writes=%0d total=%0d last=%0d/%08x status=%08x",
                     data_count, wave_write_count, wave_total_samples,
                     last_wave_addr, last_wave_data, status_dbg);
            $finish;
        end

        last_commit_toggle = wave_commit_toggle;
        send_commit_frame;
        repeat (4) @(posedge clk);
        if (commit_count != 32'd1 ||
            wave_commit_toggle == last_commit_toggle ||
            !seen_commit) begin
            $display("ERROR: commit frame mismatch commit_count=%0d toggle=%b seen=%b status=%08x",
                     commit_count, wave_commit_toggle, seen_commit, status_dbg);
            $finish;
        end

        send_high_addr_data_frame;
        repeat (4) @(posedge clk);
        if (data_count != 32'd2 ||
            wave_write_count != 32'd3 ||
            wave_total_samples != 16'd32768 ||
            last_wave_addr != 15'd32767 ||
            last_wave_data != 32'h66665555) begin
            $display("ERROR: high address data mismatch data_count=%0d writes=%0d total=%0d last=%0d/%08x status=%08x",
                     data_count, wave_write_count, wave_total_samples,
                     last_wave_addr, last_wave_data, status_dbg);
            $finish;
        end

        send_bad_port_config;
        repeat (4) @(posedge clk);
        if (config_count != 32'd1 || drop_count == 32'd0) begin
            $display("ERROR: bad port frame was not dropped count=%0d drop=%0d",
                     config_count, drop_count);
            $finish;
        end

        $display("K5WG_UDP_DAC_CONFIG_RX_OK configs=%0d data=%0d commits=%0d drops=%0d packets=%0d",
                 config_count, data_count, commit_count, drop_count,
                 packet_count);
        $finish;
    end

    always @(posedge clk) begin
        if (rst) begin
            seen_cfg <= 1'b0;
            seen_commit <= 1'b0;
            wave_write_count <= 32'd0;
            last_wave_addr <= {WAVE_ADDR_WIDTH{1'b0}};
            last_wave_data <= 32'd0;
            last_commit_toggle <= 1'b0;
        end else if (cfg_valid) begin
            seen_cfg <= 1'b1;
        end else begin
            if (wave_wr_en) begin
                wave_write_count <= wave_write_count + 1'b1;
                last_wave_addr <= wave_wr_addr;
                last_wave_data <= wave_wr_data;
            end
            if (wave_commit_toggle != last_commit_toggle) begin
                seen_commit <= 1'b1;
            end
        end
    end

    initial begin
        repeat (20000) @(posedge clk);
        $display("ERROR: timeout status=%08x packets=%0d configs=%0d drops=%0d",
                 status_dbg, packet_count, config_count, drop_count);
        $finish;
    end

    task send_byte;
        input [7:0] b;
        begin
            @(posedge clk);
            rx_data  <= b;
            rx_valid <= 1'b1;
        end
    endtask

    task end_frame;
        begin
            @(posedge clk);
            rx_valid <= 1'b0;
            rx_data  <= 8'd0;
            repeat (3) @(posedge clk);
        end
    endtask

    task send_valid_config;
        input reset_phase;
        begin
            for (i = 0; i < 7; i = i + 1) send_byte(8'h55);
            send_byte(8'hd5);
            send_eth_ip_udp_header(16'd5005);
            send_k5wg_header(8'h02, 32'd52);
            send_k5dc_payload(reset_phase);
            end_frame;
        end
    endtask

    task send_bad_port_config;
        begin
            for (i = 0; i < 7; i = i + 1) send_byte(8'h55);
            send_byte(8'hd5);
            send_eth_ip_udp_header(16'd5006);
            send_k5wg_header(8'h02, 32'd52);
            send_k5dc_payload(1'b0);
            end_frame;
        end
    endtask

    task send_data_frame;
        begin
            for (i = 0; i < 7; i = i + 1) send_byte(8'h55);
            send_byte(8'hd5);
            send_eth_ip_udp_header(16'd5005);
            send_k5wg_header(8'h03, 32'd28);
            send_word16_le(16'h0003);
            send_word16_le(16'h0001);
            send_word32_le(32'd0);
            send_word32_le(32'd2);
            send_word32_le(32'd2);
            send_word32_le(32'd0);
            send_word16_le(16'h1111);
            send_word16_le(16'h2222);
            send_word16_le(16'h3333);
            send_word16_le(16'h4444);
            end_frame;
        end
    endtask

    task send_commit_frame;
        begin
            for (i = 0; i < 7; i = i + 1) send_byte(8'h55);
            send_byte(8'hd5);
            send_eth_ip_udp_header(16'd5005);
            send_k5wg_header(8'h04, 32'd0);
            end_frame;
        end
    endtask

    task send_eth_ip_udp_header;
        input [15:0] dst_port;
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
            send_byte(8'hc0); send_byte(8'ha8); send_byte(8'h01); send_byte(8'h0a);
            send_byte(8'h13); send_byte(8'h8d);
            send_byte(dst_port[15:8]);
            send_byte(dst_port[7:0]);
            send_byte(8'h00); send_byte(8'h44);
            send_byte(8'h00); send_byte(8'h00);
        end
    endtask

    task send_k5wg_header;
        input [7:0] frame_type;
        input [31:0] payload_len;
        begin
            send_byte(8'h4b); send_byte(8'h35); send_byte(8'h57); send_byte(8'h47);
            send_byte(8'h01); send_byte(frame_type);
            send_byte(8'h1c); send_byte(8'h00);
            send_byte(8'h01); send_byte(8'h00); send_byte(8'h00); send_byte(8'h00);
            send_byte(8'h00); send_byte(8'h00); send_byte(8'h00); send_byte(8'h00);
            send_word32_le(payload_len);
            send_byte(8'h00); send_byte(8'h00); send_byte(8'h00); send_byte(8'h00);
            send_byte(8'h00); send_byte(8'h00); send_byte(8'h00); send_byte(8'h00);
        end
    endtask

    task send_k5dc_payload;
        input reset_phase;
        begin
            send_byte(8'h4b); send_byte(8'h35); send_byte(8'h44); send_byte(8'h43);
            send_byte(8'h01);
            send_byte((reset_phase ? 8'h01 : 8'h00) | 8'h04);
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
            send_word32_le(32'h55555555);
            send_byte(8'h55);
            send_byte(8'h01);
            send_word16_le(16'he311);
        end
    endtask

    task send_high_addr_data_frame;
        begin
            for (i = 0; i < 7; i = i + 1) send_byte(8'h55);
            send_byte(8'hd5);
            send_eth_ip_udp_header(16'd5005);
            send_k5wg_header(8'h03, 32'd20);
            send_word16_le(16'h0003);
            send_word16_le(16'h0001);
            send_word32_le(32'd32767);
            send_word32_le(32'd1);
            send_word32_le(32'd32768);
            send_word32_le(32'd0);
            send_word16_le(16'h5555);
            send_word16_le(16'h6666);
            end_frame;
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
