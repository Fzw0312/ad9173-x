`timescale 1ns/1ps

module tb_pattern_gen_256_cfg;

    localparam integer WAVE_ADDR_WIDTH = 15;

    reg clk = 1'b0;
    reg [1:0] rst = 2'b11;
    reg [1:0] advance = 2'b00;
    reg cfg_valid = 1'b0;
    reg cfg_reset_phase = 1'b0;
    reg cfg_ram_mode = 1'b0;
    reg [47:0] cfg_phase_inc0 = 48'h100000000000;
    reg [47:0] cfg_phase_inc1 = 48'h200000000000;
    reg [47:0] cfg_phase_inc2 = 48'h300000000000;
    reg [47:0] cfg_phase_inc3 = 48'h400000000000;
    reg [15:0] cfg_scale0 = 16'h4000;
    reg [15:0] cfg_scale1 = 16'h2000;
    reg [15:0] cfg_scale2 = 16'h1000;
    reg [15:0] cfg_scale3 = 16'h0800;
    reg wave_wr_en = 1'b0;
    reg [WAVE_ADDR_WIDTH-1:0] wave_wr_addr = {WAVE_ADDR_WIDTH{1'b0}};
    reg [31:0] wave_wr_data = 32'd0;
    reg [WAVE_ADDR_WIDTH:0] wave_total_samples = 4;
    reg wave_commit_toggle = 1'b0;
    reg output_path_sel = 1'b0;
    wire [255:0] data_out;

    always #2 clk = ~clk;

    pattern_gen_256 #(
        .WAVE_ADDR_WIDTH(WAVE_ADDR_WIDTH)
    ) u_dut (
        .clk            (clk),
        .rst            (rst),
        .advance        (advance),
        .cfg_valid      (cfg_valid),
        .cfg_reset_phase(cfg_reset_phase),
        .cfg_ram_mode   (cfg_ram_mode),
        .cfg_phase_inc0 (cfg_phase_inc0),
        .cfg_phase_inc1 (cfg_phase_inc1),
        .cfg_phase_inc2 (cfg_phase_inc2),
        .cfg_phase_inc3 (cfg_phase_inc3),
        .cfg_scale0     (cfg_scale0),
        .cfg_scale1     (cfg_scale1),
        .cfg_scale2     (cfg_scale2),
        .cfg_scale3     (cfg_scale3),
        .wave_clk       (clk),
        .wave_rst       (rst[0]),
        .wave_wr_en     (wave_wr_en),
        .wave_wr_addr   (wave_wr_addr),
        .wave_wr_data   (wave_wr_data),
        .wave_total_samples(wave_total_samples),
        .wave_commit_toggle(wave_commit_toggle),
        .output_path_sel(output_path_sel),
        .data_out       (data_out)
    );

    initial begin
        repeat (4) @(posedge clk);
        rst <= 2'b00;
        cfg_valid <= 1'b1;
        cfg_reset_phase <= 1'b1;
        @(posedge clk);
        cfg_valid <= 1'b0;
        cfg_reset_phase <= 1'b0;
        advance <= 2'b11;
        repeat (4) @(posedge clk);
        advance <= 2'b00;

        if (data_out[255:240] === 16'hxxxx ||
            u_dut.dac0_phase_inc != 48'h100000000000 ||
            u_dut.dac1_phase_inc != 48'h200000000000 ||
            u_dut.dac2_phase_inc != 48'h300000000000 ||
            u_dut.dac3_phase_inc != 48'h400000000000 ||
            u_dut.dac0_scale != 16'h4000 ||
            u_dut.dac1_scale != 16'h2000 ||
            u_dut.dac2_scale != 16'h1000 ||
            u_dut.dac3_scale != 16'h0800) begin
            $display("ERROR: pattern config not applied");
            $finish;
        end

        write_wave_sample(0, 16'h1000, 16'h2000);
        write_wave_sample(1, 16'h1001, 16'h2001);
        write_wave_sample(2, 16'h1002, 16'h2002);
        write_wave_sample(3, 16'h1003, 16'h2003);
        wave_commit_toggle <= ~wave_commit_toggle;
        repeat (4) @(posedge clk);
        advance <= 2'b11;
        repeat (4) @(posedge clk);
        advance <= 2'b00;
        if (data_out[255:192] != {16'h1003, 16'h1002, 16'h1001, 16'h1000} ||
            data_out[191:128] != {16'h2003, 16'h2002, 16'h2001, 16'h2000} ||
            data_out[127:64]  != 64'd0 ||
            data_out[63:0]    != 64'd0) begin
            $display("ERROR: waveform playback mismatch data=%064x", data_out);
            $finish;
        end

        output_path_sel <= 1'b1;
        wave_commit_toggle <= ~wave_commit_toggle;
        repeat (4) @(posedge clk);
        advance <= 2'b11;
        repeat (4) @(posedge clk);
        advance <= 2'b00;
        if (data_out[255:192] != 64'd0 ||
            data_out[191:128] != 64'd0 ||
            data_out[127:64]  != {16'h1003, 16'h1002, 16'h1001, 16'h1000} ||
            data_out[63:0]    != 64'd0) begin
            $display("ERROR: LF waveform routing mismatch data=%064x", data_out);
            $finish;
        end

        cfg_ram_mode <= 1'b1;
        cfg_valid <= 1'b1;
        @(posedge clk);
        cfg_valid <= 1'b0;
        cfg_ram_mode <= 1'b0;
        advance <= 2'b11;
        repeat (4) @(posedge clk);
        advance <= 2'b00;
        if (!u_dut.wave_active ||
            data_out[255:192] != 64'd0 ||
            data_out[191:128] != 64'd0 ||
            data_out[127:64]  != {16'h1003, 16'h1002, 16'h1001, 16'h1000} ||
            data_out[63:0]    != 64'd0) begin
            $display("ERROR: RAM config interrupted waveform playback active=%b data=%064x",
                     u_dut.wave_active, data_out);
            $finish;
        end

        cfg_valid <= 1'b1;
        @(posedge clk);
        cfg_valid <= 1'b0;
        repeat (2) @(posedge clk);
        if (u_dut.wave_active) begin
            $display("ERROR: non-RAM config did not stop waveform playback");
            $finish;
        end

        $display("PATTERN_GEN_256_CFG_OK data0=%04x data1=%04x",
                 data_out[207:192], data_out[79:64]);
        $finish;
    end

    task write_wave_sample;
        input [WAVE_ADDR_WIDTH-1:0] addr;
        input [15:0] ch0;
        input [15:0] ch1;
        begin
            @(posedge clk);
            wave_wr_addr <= addr;
            wave_wr_data <= {ch1, ch0};
            wave_wr_en <= 1'b1;
            @(posedge clk);
            wave_wr_en <= 1'b0;
        end
    endtask

    initial begin
        repeat (1000) @(posedge clk);
        $display("ERROR: timeout");
        $finish;
    end

endmodule
