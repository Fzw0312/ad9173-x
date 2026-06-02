`timescale 1ns/1ps

module tb_udp_rgmii_loopback_path;

    localparam integer CAPTURE_BEATS = 16;
    localparam integer DATA_PAYLOAD_SAMPLES = 16;
    localparam integer TOTAL_SAMPLES = CAPTURE_BEATS * 4;

    reg clk = 1'b0;
    reg tx_clk_45 = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;

    wire [13:0] ram_rd_byte_addr;
    reg  [7:0]  ram_rd_byte = 8'd0;
    wire        busy;
    wire        done;
    wire [31:0] packet_count;
    wire [7:0]  tx_data;
    wire        tx_valid;
    wire        rgmii_tx_clk;
    wire [3:0]  rgmii_txd;
    wire        rgmii_tx_ctl;

    integer fd;
    integer sample_idx;
    reg [7:0] rgmii_recon_byte;

    always #4 clk = ~clk;

    initial begin
        #1 tx_clk_45 = 1'b1;
        forever #4 tx_clk_45 = ~tx_clk_45;
    end

    k5ad_udp_packetizer #(
        .CAPTURE_BEATS(CAPTURE_BEATS),
        .DATA_PAYLOAD_SAMPLES(DATA_PAYLOAD_SAMPLES),
        .SRC_MAC(48'h02_00_00_00_5a_01),
        .SRC_IP(32'hC0A8_010A),
        .SRC_PORT(16'd6006),
        .DST_PORT(16'd6006)
    ) u_packetizer (
        .clk             (clk),
        .rst             (rst),
        .start           (start),
        .capture_id      (32'd1),
        .ram_rd_byte     (ram_rd_byte),
        .ram_rd_byte_addr(ram_rd_byte_addr),
        .busy            (busy),
        .done            (done),
        .packet_count    (packet_count),
        .tx_data         (tx_data),
        .tx_valid        (tx_valid)
    );

    rgmii_tx u_rgmii_tx (
        .tx_clk      (clk),
        .tx_clk_90   (tx_clk_45),
        .rst         (rst),
        .txd         (tx_data),
        .tx_en       (tx_valid),
        .rgmii_tx_clk(rgmii_tx_clk),
        .rgmii_txd   (rgmii_txd),
        .rgmii_tx_ctl(rgmii_tx_ctl)
    );

    always @* begin
        sample_idx = ram_rd_byte_addr >> 1;
        if (ram_rd_byte_addr[0] == 1'b0) begin
            ram_rd_byte = sample_code_byte(sample_idx, 1'b0);
        end else begin
            ram_rd_byte = sample_code_byte(sample_idx, 1'b1);
        end
    end

    always @(posedge clk) begin
        #1;
        if (rgmii_tx_ctl) begin
            rgmii_recon_byte[3:0] = rgmii_txd;
        end
    end

    always @(negedge clk) begin
        #1;
        if (rgmii_tx_ctl) begin
            rgmii_recon_byte[7:4] = rgmii_txd;
            $fwrite(fd, "%02x\n", rgmii_recon_byte);
        end
    end

    initial begin
        fd = $fopen("tb_udp_rgmii_loopback_path_bytes.txt", "w");
        if (fd == 0) begin
            $display("ERROR: failed to open RGMII output byte file");
            $finish;
        end

        repeat (6) @(posedge clk);
        rst <= 1'b0;
        rgmii_recon_byte <= 8'd0;
        repeat (4) @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait (done);
        repeat (20) @(posedge clk);
        if (packet_count != 4) begin
            $display("ERROR: expected 4 packets, got %0d", packet_count);
            $finish;
        end
        $fclose(fd);
        $display("UDP_RGMII_LOOPBACK_PATH_OK packets=%0d samples=%0d",
                 packet_count, TOTAL_SAMPLES);
        $finish;
    end

    function [15:0] sample_code;
        input integer idx;
        begin
            sample_code = (idx * 257 + 16'h1234) & 16'hffff;
        end
    endfunction

    function [7:0] sample_code_byte;
        input integer idx;
        input         high_byte;
        reg [15:0] code;
        begin
            code = sample_code(idx);
            sample_code_byte = high_byte ? code[15:8] : code[7:0];
        end
    endfunction

endmodule
