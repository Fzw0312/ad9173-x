module ad9173_link_diag #(
    parameter integer CLK_DIV = 32,
    parameter integer MS_TICKS = 100000,
    parameter integer REPEAT_MS = 100,
    parameter integer ENABLE_LINK0_POLARITY_SWEEP = 0,
    parameter integer ENABLE_LINK0_XBAR_SWEEP = 0,
    parameter [7:0] LINK0_XBAR_SWEEP_POLARITY = 8'h00
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        sdio_i,
    output reg         running,
    output reg         done_seen,
    output reg  [31:0] link0_status_dbg,
    output reg  [31:0] link1_status_dbg,
    output reg  [31:0] link0_error_dbg,
    output reg  [31:0] link1_error_dbg,
    output reg  [31:0] link0_ilas0_dbg,
    output reg  [31:0] link1_ilas0_dbg,
    output reg  [31:0] link0_ilas1_dbg,
    output reg  [31:0] link1_ilas1_dbg,
    output reg  [31:0] link0_lid_dbg,
    output reg  [31:0] link1_lid_dbg,
    output reg  [31:0] link0_checksum_dbg,
    output reg  [31:0] link1_checksum_dbg,
    output reg  [31:0] link0_compsum_dbg,
    output reg  [31:0] link1_compsum_dbg,
    output reg  [31:0] datapath_cfg_dbg,
    output reg  [31:0] nco_ftw_low_dbg,
    output reg  [31:0] nco_ftw_high_dbg,
    output reg  [31:0] lane_cfg_dbg,
    output reg  [31:0] serdes_cfg_dbg,
    output reg  [31:0] polarity_cfg_dbg,
    output wire [31:0] sweep_ctrl_dbg,
    output wire [31:0] sweep_result_dbg,
    output wire [31:0] live_dbg,
    output wire        sclk,
    output wire        cs_n,
    output wire        sdio_o,
    output wire        sdio_oe
);

    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_PAGE_START = 4'd1;
    localparam [3:0] ST_PAGE_WAIT  = 4'd2;
    localparam [3:0] ST_GAP        = 4'd3;
    localparam [3:0] ST_READ_START = 4'd4;
    localparam [3:0] ST_READ_WAIT  = 4'd5;
    localparam [3:0] ST_REPEAT     = 4'd6;
    localparam [3:0] ST_SWEEP_LOAD = 4'd7;
    localparam [3:0] ST_SWEEP_WAIT = 4'd8;
    localparam [3:0] ST_SWEEP_GAP  = 4'd9;

    reg [3:0]  state;
    reg [1:0]  scan_phase;
    reg [4:0]  read_idx;
    reg [3:0]  sweep_step;
    reg [4:0]  sweep_value;
    reg [7:0]  sweep_apply_count;
    reg [23:0] sweep_status_ok_mask;
    reg [23:0] sweep_checksum_ok_mask;
    reg [23:0] sweep_lid_ok_mask;
    reg [23:0] sweep_full_ok_mask;
    reg [31:0] wait_count;
    reg        write_start;
    reg        read_start;
    reg [23:0] write_word;
    reg [15:0] read_addr;

    wire       write_busy;
    wire       write_done;
    wire       read_busy;
    wire       read_done;
    wire [7:0] read_data;
    wire       write_sclk;
    wire       write_cs_n;
    wire       write_sdio;
    wire       read_sclk;
    wire       read_cs_n;
    wire       read_sdio_o;
    wire       read_sdio_oe;
    wire [4:0] last_read_idx;
    wire       xbar_sweep_en;
    wire       polarity_sweep_en;
    wire [15:0] link0_xbar_regs;

    assign last_read_idx = (scan_phase == 2'd2) ? 5'd23 : 5'd26;
    assign xbar_sweep_en = (ENABLE_LINK0_XBAR_SWEEP != 0);
    assign polarity_sweep_en = (ENABLE_LINK0_POLARITY_SWEEP != 0);

    assign sclk    = read_busy ? read_sclk    : write_sclk;
    assign cs_n    = read_busy ? read_cs_n    : write_cs_n;
    assign sdio_o  = read_busy ? read_sdio_o  : write_sdio;
    assign sdio_oe = read_busy ? read_sdio_oe : 1'b1;

    assign live_dbg = {
        7'd0,
        done_seen,
        running,
        write_busy,
        write_done,
        read_busy,
        read_done,
        scan_phase,
        read_idx,
        state,
        read_data
    };

    assign sweep_ctrl_dbg = xbar_sweep_en ?
        {sweep_status_ok_mask, sweep_value[4:0], state[2:0]} :
        {sweep_lid_ok_mask[15:0], sweep_apply_count, sweep_value[3:0], sweep_step, state};

    assign sweep_result_dbg = xbar_sweep_en ?
        {8'hcb, sweep_full_ok_mask} :
        {sweep_status_ok_mask[15:0], sweep_checksum_ok_mask[15:0]};

    function [15:0] link0_xbar_perm;
        input [4:0] perm_idx;
        begin
            case (perm_idx)
                5'd0:  link0_xbar_perm = 16'h1a08; // L0..3 <- SERDIN0,1,2,3
                5'd1:  link0_xbar_perm = 16'h1308; // L0..3 <- SERDIN0,1,3,2
                5'd2:  link0_xbar_perm = 16'h1910; // L0..3 <- SERDIN0,2,1,3
                5'd3:  link0_xbar_perm = 16'h0b10; // L0..3 <- SERDIN0,2,3,1
                5'd4:  link0_xbar_perm = 16'h1118; // L0..3 <- SERDIN0,3,1,2
                5'd5:  link0_xbar_perm = 16'h0a18; // L0..3 <- SERDIN0,3,2,1
                5'd6:  link0_xbar_perm = 16'h1a01; // L0..3 <- SERDIN1,0,2,3
                5'd7:  link0_xbar_perm = 16'h1301; // L0..3 <- SERDIN1,0,3,2
                5'd8:  link0_xbar_perm = 16'h1811; // L0..3 <- SERDIN1,2,0,3
                5'd9:  link0_xbar_perm = 16'h0311; // L0..3 <- SERDIN1,2,3,0
                5'd10: link0_xbar_perm = 16'h1019; // L0..3 <- SERDIN1,3,0,2
                5'd11: link0_xbar_perm = 16'h0219; // L0..3 <- SERDIN1,3,2,0
                5'd12: link0_xbar_perm = 16'h1902; // L0..3 <- SERDIN2,0,1,3
                5'd13: link0_xbar_perm = 16'h0b02; // L0..3 <- SERDIN2,0,3,1
                5'd14: link0_xbar_perm = 16'h180a; // L0..3 <- SERDIN2,1,0,3
                5'd15: link0_xbar_perm = 16'h030a; // L0..3 <- SERDIN2,1,3,0
                5'd16: link0_xbar_perm = 16'h081a; // L0..3 <- SERDIN2,3,0,1
                5'd17: link0_xbar_perm = 16'h011a; // L0..3 <- SERDIN2,3,1,0
                5'd18: link0_xbar_perm = 16'h1103; // L0..3 <- SERDIN3,0,1,2
                5'd19: link0_xbar_perm = 16'h0a03; // L0..3 <- SERDIN3,0,2,1
                5'd20: link0_xbar_perm = 16'h100b; // L0..3 <- SERDIN3,1,0,2
                5'd21: link0_xbar_perm = 16'h020b; // L0..3 <- SERDIN3,1,2,0
                5'd22: link0_xbar_perm = 16'h0813; // L0..3 <- SERDIN3,2,0,1
                default: link0_xbar_perm = 16'h0113; // L0..3 <- SERDIN3,2,1,0
            endcase
        end
    endfunction

    assign link0_xbar_regs = link0_xbar_perm(sweep_value);

    spi_write_master #(
        .CLK_DIV(CLK_DIV),
        .UPDATE_MOSI_ON_LOW(1)
    ) u_write (
        .clk    (clk),
        .rst    (rst),
        .start  (write_start),
        .tx_word(write_word),
        .busy   (write_busy),
        .done   (write_done),
        .sclk   (write_sclk),
        .cs_n   (write_cs_n),
        .mosi   (write_sdio)
    );

    spi_read_master_3wire #(
        .CLK_DIV(CLK_DIV)
    ) u_read (
        .clk    (clk),
        .rst    (rst),
        .start  (read_start),
        .addr   (read_addr),
        .sdio_i (sdio_i),
        .busy   (read_busy),
        .done   (read_done),
        .rx_data(read_data),
        .sclk   (read_sclk),
        .cs_n   (read_cs_n),
        .sdio_o (read_sdio_o),
        .sdio_oe(read_sdio_oe)
    );

    always @(*) begin
        if (scan_phase == 2'd2) begin
            case (read_idx)
                5'd0:  read_addr = 16'h0110;
                5'd1:  read_addr = 16'h0111;
                5'd2:  read_addr = 16'h0112;
                5'd3:  read_addr = 16'h0113;
                5'd4:  read_addr = 16'h0114;
                5'd5:  read_addr = 16'h0115;
                5'd6:  read_addr = 16'h0116;
                5'd7:  read_addr = 16'h0117;
                5'd8:  read_addr = 16'h0118;
                5'd9:  read_addr = 16'h0119;
                5'd10: read_addr = 16'h011c;
                5'd11: read_addr = 16'h011d;
                5'd12: read_addr = 16'h0308;
                5'd13: read_addr = 16'h0309;
                5'd14: read_addr = 16'h030a;
                5'd15: read_addr = 16'h030b;
                5'd16: read_addr = 16'h0304;
                5'd17: read_addr = 16'h0305;
                5'd18: read_addr = 16'h0306;
                5'd19: read_addr = 16'h0307;
                5'd20: read_addr = 16'h0334;
                5'd21: read_addr = 16'h0085;
                5'd22: read_addr = 16'h01de;
                default: read_addr = 16'h0596;
            endcase
        end else begin
            case (read_idx)
                5'd0: read_addr = 16'h046c;
                5'd1: read_addr = 16'h046d;
                5'd2: read_addr = 16'h046e;
                5'd3: read_addr = 16'h046f;
                5'd4: read_addr = 16'h0470;
                5'd5: read_addr = 16'h0471;
                5'd6: read_addr = 16'h0472;
                5'd7: read_addr = 16'h0473;
                5'd8: read_addr = 16'h0402;
                5'd9: read_addr = 16'h0412;
                5'd10: read_addr = 16'h041a;
                5'd11: read_addr = 16'h0422;
                5'd12: read_addr = 16'h0403;
                5'd13: read_addr = 16'h0404;
                5'd14: read_addr = 16'h0405;
                5'd15: read_addr = 16'h0406;
                5'd16: read_addr = 16'h0408;
                5'd17: read_addr = 16'h0409;
                5'd18: read_addr = 16'h040a;
                5'd19: read_addr = 16'h040d;
                5'd20: read_addr = 16'h040e;
                5'd21: read_addr = 16'h0415;
                5'd22: read_addr = 16'h0416;
                5'd23: read_addr = 16'h041d;
                5'd24: read_addr = 16'h041e;
                5'd25: read_addr = 16'h0425;
                default: read_addr = 16'h0426;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state            <= ST_IDLE;
            running          <= 1'b0;
            done_seen        <= 1'b0;
            link0_status_dbg <= 32'd0;
            link1_status_dbg <= 32'd0;
            link0_error_dbg  <= 32'd0;
            link1_error_dbg  <= 32'd0;
            link0_ilas0_dbg  <= 32'd0;
            link1_ilas0_dbg  <= 32'd0;
            link0_ilas1_dbg  <= 32'd0;
            link1_ilas1_dbg  <= 32'd0;
            link0_lid_dbg    <= 32'd0;
            link1_lid_dbg    <= 32'd0;
            link0_checksum_dbg <= 32'd0;
            link1_checksum_dbg <= 32'd0;
            link0_compsum_dbg  <= 32'd0;
            link1_compsum_dbg  <= 32'd0;
            datapath_cfg_dbg <= 32'd0;
            nco_ftw_low_dbg  <= 32'd0;
            nco_ftw_high_dbg <= 32'd0;
            lane_cfg_dbg     <= 32'd0;
            serdes_cfg_dbg   <= 32'd0;
            polarity_cfg_dbg <= 32'd0;
            scan_phase       <= 2'd0;
            read_idx         <= 5'd0;
            sweep_step       <= 4'd0;
            sweep_value      <= xbar_sweep_en ? 5'd0 : 5'd15;
            sweep_apply_count <= 8'd0;
            sweep_status_ok_mask <= 24'd0;
            sweep_checksum_ok_mask <= 24'd0;
            sweep_lid_ok_mask <= 24'd0;
            sweep_full_ok_mask <= 24'd0;
            wait_count       <= 32'd0;
            write_start      <= 1'b0;
            read_start       <= 1'b0;
            write_word       <= 24'd0;
        end else begin
            write_start <= 1'b0;
            read_start  <= 1'b0;

            case (state)
                ST_IDLE: begin
                    running <= 1'b0;
                    if (enable) begin
                        running     <= 1'b1;
                        scan_phase  <= 2'd0;
                        read_idx    <= 5'd0;
                        write_word  <= {16'h0300, 8'h0b};
                        state       <= ST_PAGE_START;
                    end
                end

                ST_PAGE_START: begin
                    running <= 1'b1;
                    if (!write_busy && !read_busy) begin
                        write_start <= 1'b1;
                        state       <= ST_PAGE_WAIT;
                    end
                end

                ST_PAGE_WAIT: begin
                    running <= 1'b1;
                    if (write_done) begin
                        wait_count <= MS_TICKS;
                        state      <= ST_GAP;
                    end
                end

                ST_GAP: begin
                    running <= 1'b1;
                    if (wait_count == 32'd0) begin
                        state <= ST_READ_START;
                    end else begin
                        wait_count <= wait_count - 1'b1;
                    end
                end

                ST_READ_START: begin
                    running <= 1'b1;
                    if (!read_busy && !write_busy) begin
                        read_start <= 1'b1;
                        state      <= ST_READ_WAIT;
                    end
                end

                ST_READ_WAIT: begin
                    running <= 1'b1;
                    if (read_done) begin
                        if (scan_phase == 2'd0) begin
                            case (read_idx)
                                5'd0:  link0_error_dbg[7:0]     <= read_data;
                                5'd1:  link0_error_dbg[15:8]    <= read_data;
                                5'd2:  link0_error_dbg[23:16]   <= read_data;
                                5'd3:  link0_error_dbg[31:24]   <= read_data;
                                5'd4:  link0_status_dbg[7:0]    <= read_data;
                                5'd5:  link0_status_dbg[15:8]   <= read_data;
                                5'd6:  link0_status_dbg[23:16]  <= read_data;
                                5'd7:  link0_status_dbg[31:24]  <= read_data;
                                5'd8:  link0_lid_dbg[7:0]       <= read_data;
                                5'd9:  link0_lid_dbg[15:8]      <= read_data;
                                5'd10: link0_lid_dbg[23:16]     <= read_data;
                                5'd11: link0_lid_dbg[31:24]     <= read_data;
                                5'd12: link0_ilas0_dbg[7:0]     <= read_data;
                                5'd13: link0_ilas0_dbg[15:8]    <= read_data;
                                5'd14: link0_ilas0_dbg[23:16]   <= read_data;
                                5'd15: link0_ilas0_dbg[31:24]   <= read_data;
                                5'd16: link0_ilas1_dbg[7:0]     <= read_data;
                                5'd17: link0_ilas1_dbg[15:8]    <= read_data;
                                5'd18: link0_ilas1_dbg[23:16]   <= read_data;
                                5'd19: begin
                                    link0_ilas1_dbg[31:24]   <= read_data;
                                    link0_checksum_dbg[7:0]  <= read_data;
                                end
                                5'd20: link0_compsum_dbg[7:0]   <= read_data;
                                5'd21: link0_checksum_dbg[15:8] <= read_data;
                                5'd22: link0_compsum_dbg[15:8]  <= read_data;
                                5'd23: link0_checksum_dbg[23:16] <= read_data;
                                5'd24: link0_compsum_dbg[23:16]  <= read_data;
                                5'd25: link0_checksum_dbg[31:24] <= read_data;
                                default: link0_compsum_dbg[31:24] <= read_data;
                            endcase
                        end else if (scan_phase == 2'd1) begin
                            case (read_idx)
                                5'd0:  link1_error_dbg[7:0]     <= read_data;
                                5'd1:  link1_error_dbg[15:8]    <= read_data;
                                5'd2:  link1_error_dbg[23:16]   <= read_data;
                                5'd3:  link1_error_dbg[31:24]   <= read_data;
                                5'd4:  link1_status_dbg[7:0]    <= read_data;
                                5'd5:  link1_status_dbg[15:8]   <= read_data;
                                5'd6:  link1_status_dbg[23:16]  <= read_data;
                                5'd7:  link1_status_dbg[31:24]  <= read_data;
                                5'd8:  link1_lid_dbg[7:0]       <= read_data;
                                5'd9:  link1_lid_dbg[15:8]      <= read_data;
                                5'd10: link1_lid_dbg[23:16]     <= read_data;
                                5'd11: link1_lid_dbg[31:24]     <= read_data;
                                5'd12: link1_ilas0_dbg[7:0]     <= read_data;
                                5'd13: link1_ilas0_dbg[15:8]    <= read_data;
                                5'd14: link1_ilas0_dbg[23:16]   <= read_data;
                                5'd15: link1_ilas0_dbg[31:24]   <= read_data;
                                5'd16: link1_ilas1_dbg[7:0]     <= read_data;
                                5'd17: link1_ilas1_dbg[15:8]    <= read_data;
                                5'd18: link1_ilas1_dbg[23:16]   <= read_data;
                                5'd19: begin
                                    link1_ilas1_dbg[31:24]   <= read_data;
                                    link1_checksum_dbg[7:0]  <= read_data;
                                end
                                5'd20: link1_compsum_dbg[7:0]   <= read_data;
                                5'd21: link1_checksum_dbg[15:8] <= read_data;
                                5'd22: link1_compsum_dbg[15:8]  <= read_data;
                                5'd23: link1_checksum_dbg[23:16] <= read_data;
                                5'd24: link1_compsum_dbg[23:16]  <= read_data;
                                5'd25: link1_checksum_dbg[31:24] <= read_data;
                                default: link1_compsum_dbg[31:24] <= read_data;
                            endcase
                        end else begin
                            case (read_idx)
                                5'd0:  datapath_cfg_dbg[7:0]    <= read_data;
                                5'd1:  datapath_cfg_dbg[15:8]   <= read_data;
                                5'd2:  datapath_cfg_dbg[23:16]  <= read_data;
                                5'd3:  datapath_cfg_dbg[31:24]  <= read_data;
                                5'd4:  nco_ftw_low_dbg[7:0]     <= read_data;
                                5'd5:  nco_ftw_low_dbg[15:8]    <= read_data;
                                5'd6:  nco_ftw_low_dbg[23:16]   <= read_data;
                                5'd7:  nco_ftw_low_dbg[31:24]   <= read_data;
                                5'd8:  nco_ftw_high_dbg[7:0]    <= read_data;
                                5'd9:  nco_ftw_high_dbg[15:8]   <= read_data;
                                5'd10: nco_ftw_high_dbg[23:16]  <= read_data;
                                5'd11: nco_ftw_high_dbg[31:24]  <= read_data;
                                5'd12: lane_cfg_dbg[7:0]        <= read_data;
                                5'd13: lane_cfg_dbg[15:8]       <= read_data;
                                5'd14: lane_cfg_dbg[23:16]      <= read_data;
                                5'd15: lane_cfg_dbg[31:24]      <= read_data;
                                5'd16: serdes_cfg_dbg[7:0]      <= read_data;
                                5'd17: serdes_cfg_dbg[15:8]     <= read_data;
                                5'd18: serdes_cfg_dbg[23:16]    <= read_data;
                                5'd19: serdes_cfg_dbg[31:24]    <= read_data;
                                5'd20: polarity_cfg_dbg[7:0]    <= read_data;
                                5'd21: polarity_cfg_dbg[15:8]   <= read_data;
                                5'd22: polarity_cfg_dbg[23:16]  <= read_data;
                                default: polarity_cfg_dbg[31:24] <= read_data;
                            endcase
                        end

                        if (read_idx == last_read_idx) begin
                            if (scan_phase == 2'd0) begin
                                scan_phase <= 2'd1;
                                read_idx   <= 5'd0;
                                write_word <= {16'h0300, 8'h0f};
                                state      <= ST_PAGE_START;
                            end else if (scan_phase == 2'd1) begin
                                scan_phase <= 2'd2;
                                read_idx   <= 5'd0;
                                write_word <= {16'h0300, 8'h0f};
                                state      <= ST_PAGE_START;
                            end else begin
                                if (xbar_sweep_en) begin
                                    sweep_status_ok_mask[sweep_value] <= (link0_status_dbg == 32'h0f0f0f0f);
                                    sweep_checksum_ok_mask[sweep_value] <= (link0_checksum_dbg == link0_compsum_dbg);
                                    sweep_lid_ok_mask[sweep_value] <= (link0_lid_dbg == 32'h03020100);
                                    sweep_full_ok_mask[sweep_value] <= (link0_status_dbg == 32'h0f0f0f0f) &&
                                                                       (link0_checksum_dbg == link0_compsum_dbg) &&
                                                                       (link0_lid_dbg == 32'h03020100);
                                    sweep_step <= 4'd0;
                                    if (sweep_value == 5'd23) begin
                                        sweep_value <= 5'd0;
                                    end else begin
                                        sweep_value <= sweep_value + 1'b1;
                                    end
                                    state <= ST_SWEEP_LOAD;
                                end else if (polarity_sweep_en) begin
                                    sweep_status_ok_mask[sweep_value] <= (link0_status_dbg == 32'h0f0f0f0f);
                                    sweep_checksum_ok_mask[sweep_value] <= (link0_checksum_dbg == link0_compsum_dbg);
                                    sweep_lid_ok_mask[sweep_value] <= (link0_lid_dbg == 32'h03020100);
                                    sweep_step  <= 4'd0;
                                    sweep_value <= {1'b0, sweep_value[3:0] + 1'b1};
                                    state       <= ST_SWEEP_LOAD;
                                end else begin
                                    done_seen  <= 1'b1;
                                    wait_count <= REPEAT_MS * MS_TICKS;
                                    state      <= ST_REPEAT;
                                end
                            end
                        end else begin
                            read_idx <= read_idx + 1'b1;
                            state    <= ST_READ_START;
                        end
                    end
                end

                ST_SWEEP_LOAD: begin
                    running <= 1'b1;
                    if (!write_busy && !read_busy) begin
                        if (xbar_sweep_en) begin
                            case (sweep_step)
                                4'd0: write_word <= {16'h0308, link0_xbar_regs[7:0]};
                                4'd1: write_word <= {16'h0309, link0_xbar_regs[15:8]};
                                4'd2: write_word <= {16'h0334, LINK0_XBAR_SWEEP_POLARITY};
                                4'd3: write_word <= {16'h0300, 8'h0b};
                                4'd4: write_word <= {16'h0475, 8'h09};
                                4'd5: write_word <= {16'h0453, 8'h03};
                                4'd6: write_word <= {16'h0458, 8'h2f};
                                default: write_word <= {16'h0475, 8'h01};
                            endcase
                        end else begin
                            case (sweep_step)
                                4'd0: write_word <= {16'h0334, 4'h0, sweep_value[3:0]};
                                4'd1: write_word <= {16'h0300, 8'h0b};
                                4'd2: write_word <= {16'h0475, 8'h09};
                                4'd3: write_word <= {16'h0453, 8'h03};
                                4'd4: write_word <= {16'h0458, 8'h2f};
                                default: write_word <= {16'h0475, 8'h01};
                            endcase
                        end
                        write_start <= 1'b1;
                        state       <= ST_SWEEP_WAIT;
                    end
                end

                ST_SWEEP_WAIT: begin
                    running <= 1'b1;
                    if (write_done) begin
                        if ((!xbar_sweep_en && (sweep_step == 4'd5)) ||
                            ( xbar_sweep_en && (sweep_step == 4'd7))) begin
                            sweep_apply_count <= sweep_apply_count + 1'b1;
                            wait_count <= MS_TICKS + MS_TICKS;
                            state      <= ST_SWEEP_GAP;
                        end else begin
                            sweep_step <= sweep_step + 1'b1;
                            state      <= ST_SWEEP_LOAD;
                        end
                    end
                end

                ST_SWEEP_GAP: begin
                    running <= 1'b1;
                    if (wait_count == 32'd0) begin
                        done_seen  <= 1'b1;
                        wait_count <= REPEAT_MS * MS_TICKS;
                        state      <= ST_REPEAT;
                    end else begin
                        wait_count <= wait_count - 1'b1;
                    end
                end

                ST_REPEAT: begin
                    running <= 1'b0;
                    if (!enable) begin
                        state <= ST_IDLE;
                    end else if (wait_count == 32'd0) begin
                        running    <= 1'b1;
                        scan_phase <= 2'd0;
                        read_idx   <= 5'd0;
                        write_word <= {16'h0300, 8'h0b};
                        state      <= ST_PAGE_START;
                    end else begin
                        wait_count <= wait_count - 1'b1;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
