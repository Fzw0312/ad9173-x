// HMC7044 初始化执行模块。
//
// 作用：
// 1. 按 hmc7044_init_table.v 的寄存器表，通过 3-wire SPI 写 HMC7044。
// 2. 写完后轮询 PLL1/PLL2/告警/FSM 状态，确认时钟芯片真正锁定。
// 3. 回读关键输出通道寄存器，确认 DAC_CLKIN、SYSREF、FPGA JESD refclk
//    这些关键时钟输出配置没有写错。
//
// 注意：这里不生成时钟，只配置外部 HMC7044 芯片；FPGA 内部只看到
// HMC7044 输出到引脚上的 jesd_refclk/sysref。
module hmc7044_init #(
    parameter integer CLK_DIV  = 32,
    parameter integer MS_TICKS = 100000
) (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire sdio_i,
    output reg  busy,
    output reg  done,
    output reg  ok,
    output reg  fail,
    output reg  [39:0] status_dbg,
    output reg  [6:0]  verify_group_ok,
    output reg         verify_done,
    output reg         verify_fail_any,
    output reg  [15:0] verify_mismatch_addr,
    output reg  [7:0]  verify_mismatch_data,
    output reg  [7:0]  verify_mismatch_expect,
    output reg  [31:0] ch4_snapshot_dbg,
    output wire [4:0]  debug_state,
    output wire [13:0] debug_retry_count,
    output wire [15:0] debug_read_addr,
    output wire [7:0]  debug_read_data,
    output wire        debug_read_busy,
    output wire        debug_read_done,
    output wire        debug_pll1_locked,
    output wire sclk,
    output wire cs_n,
    output wire sdio_o,
    output wire sdio_oe
);

    localparam [4:0] ST_IDLE        = 5'd0;
    localparam [4:0] ST_RUN_TABLE   = 5'd1;
    localparam [4:0] ST_PLL1_START  = 5'd2;
    localparam [4:0] ST_PLL1_WAIT   = 5'd3;
    localparam [4:0] ST_PLL2_START  = 5'd4;
    localparam [4:0] ST_PLL2_WAIT   = 5'd5;
    localparam [4:0] ST_ALARM_START = 5'd6;
    localparam [4:0] ST_ALARM_WAIT  = 5'd7;
    localparam [4:0] ST_FSM_START   = 5'd8;
    localparam [4:0] ST_FSM_WAIT    = 5'd9;
    localparam [4:0] ST_MISC_START  = 5'd10;
    localparam [4:0] ST_MISC_WAIT   = 5'd11;
    localparam [4:0] ST_VERIFY_START = 5'd12;
    localparam [4:0] ST_VERIFY_WAIT  = 5'd13;
    localparam [4:0] ST_RETRY_WAIT   = 5'd14;
    localparam [4:0] ST_DONE         = 5'd15;
    localparam [4:0] ST_FAIL         = 5'd16;

    // PLL1 在重启和参考源切换后可能需要较长时间才上锁。
    // 这里最多轮询 10 s，避免 PLL1 仍在捕获过程中就误判启动失败。
    localparam [13:0] MAX_RETRY = 14'd10000;

    wire [7:0]  table_addr;
    wire [31:0] table_cmd;
    wire        table_spi_start;
    wire [23:0] table_spi_word;
    wire        table_spi_busy;
    wire        table_spi_done;
    wire        table_done;
    wire        read_busy;
    wire        read_done;
    wire [7:0]  read_data;
    wire        read_sclk;
    wire        read_cs_n;
    wire        read_sdio_o;
    wire        read_sdio_oe;
    wire        write_sclk;
    wire        write_cs_n;
    wire        write_sdio_o;
    reg  [5:0]  verify_index;
    reg  [6:0]  verify_group_fail;
    reg         verify_mismatch_valid;
    reg  [15:0] verify_addr_sel;
    reg  [7:0]  verify_expect_sel;
    reg  [2:0]  verify_group_sel;
    reg         verify_mismatch_now;
    reg  [6:0]  verify_fail_mask_now;

    reg         table_start;
    reg         read_start;
    reg [4:0]   state;
    reg [13:0]  retry_count;
    reg [15:0]  read_addr;
    reg [31:0]  wait_counter;
    reg         pll1_locked;

    assign debug_state       = state;
    assign debug_retry_count = retry_count;
    assign debug_read_addr   = read_addr;
    assign debug_read_data   = read_data;
    assign debug_read_busy   = read_busy;
    assign debug_read_done   = read_done;
    assign debug_pll1_locked = pll1_locked;
    assign sclk    = read_busy ? read_sclk    : write_sclk;
    assign cs_n    = read_busy ? read_cs_n    : write_cs_n;
    assign sdio_o  = read_busy ? read_sdio_o  : write_sdio_o;
    assign sdio_oe = read_busy ? read_sdio_oe : table_spi_busy;

    hmc7044_init_table u_table (
        .addr(table_addr),
        .cmd (table_cmd)
    );

    spi_init_engine #(
        .TABLE_AW(8),
        .MS_TICKS(MS_TICKS)
    ) u_engine (
        .clk       (clk),
        .rst       (rst),
        .start     (table_start),
        .busy      (),
        .done      (table_done),
        .table_addr(table_addr),
        .table_cmd (table_cmd),
        .spi_start (table_spi_start),
        .spi_word  (table_spi_word),
        .spi_busy  (table_spi_busy),
        .spi_done  (table_spi_done)
    );

    spi_write_master #(
        .CLK_DIV(CLK_DIV)
    ) u_spi_write (
        .clk    (clk),
        .rst    (rst),
        .start  (table_spi_start),
        .tx_word(table_spi_word),
        .busy   (table_spi_busy),
        .done   (table_spi_done),
        .sclk   (write_sclk),
        .cs_n   (write_cs_n),
        .mosi   (write_sdio_o)
    );

    spi_read_master_3wire #(
        .CLK_DIV(CLK_DIV)
    ) u_spi_read (
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

    // verify_index 逐项选择需要回读验证的寄存器。
    // verify_group_sel 用于把错误归类到不同输出组，方便 ILA/VIO 查看
    // 是 PLL 配置、DAC_CLKIN、SYSREF 还是 FPGA JESD refclk 相关寄存器出错。
    always @(*) begin
        verify_addr_sel   = 16'h0005;
        verify_expect_sel = 8'h01;
        verify_group_sel  = 3'd0;

        case (verify_index)
            6'd0:  begin verify_addr_sel = 16'h0005; verify_expect_sel = 8'h01; verify_group_sel = 3'd0; end
            6'd1:  begin verify_addr_sel = 16'h0014; verify_expect_sel = 8'h00; verify_group_sel = 3'd0; end
            6'd2:  begin verify_addr_sel = 16'h001c; verify_expect_sel = 8'h02; verify_group_sel = 3'd0; end
            6'd3:  begin verify_addr_sel = 16'h0020; verify_expect_sel = 8'h02; verify_group_sel = 3'd0; end
            6'd4:  begin verify_addr_sel = 16'h0021; verify_expect_sel = 8'h07; verify_group_sel = 3'd0; end
            6'd5:  begin verify_addr_sel = 16'h0022; verify_expect_sel = 8'h00; verify_group_sel = 3'd0; end
            6'd6:  begin verify_addr_sel = 16'h0026; verify_expect_sel = 8'h0e; verify_group_sel = 3'd0; end
            6'd7:  begin verify_addr_sel = 16'h0027; verify_expect_sel = 8'h00; verify_group_sel = 3'd0; end
            6'd8:  begin verify_addr_sel = 16'h0028; verify_expect_sel = 8'h14; verify_group_sel = 3'd0; end

            6'd9:  begin verify_addr_sel = 16'h00f0; verify_expect_sel = 8'hc1; verify_group_sel = 3'd1; end
            6'd10: begin verify_addr_sel = 16'h00f1; verify_expect_sel = 8'h00; verify_group_sel = 3'd1; end
            6'd11: begin verify_addr_sel = 16'h00f2; verify_expect_sel = 8'h00; verify_group_sel = 3'd1; end
            6'd12: begin verify_addr_sel = 16'h00f7; verify_expect_sel = 8'h03; verify_group_sel = 3'd1; end
            6'd13: begin verify_addr_sel = 16'h00f8; verify_expect_sel = 8'h01; verify_group_sel = 3'd1; end

            6'd14: begin verify_addr_sel = 16'h0104; verify_expect_sel = 8'hc1; verify_group_sel = 3'd2; end
            6'd15: begin verify_addr_sel = 16'h0105; verify_expect_sel = 8'h06; verify_group_sel = 3'd2; end
            6'd16: begin verify_addr_sel = 16'h0106; verify_expect_sel = 8'h00; verify_group_sel = 3'd2; end
            6'd17: begin verify_addr_sel = 16'h010c; verify_expect_sel = 8'h08; verify_group_sel = 3'd2; end

            6'd18: begin verify_addr_sel = 16'h010e; verify_expect_sel = 8'hc1; verify_group_sel = 3'd3; end
            6'd19: begin verify_addr_sel = 16'h010f; verify_expect_sel = 8'h80; verify_group_sel = 3'd3; end
            6'd20: begin verify_addr_sel = 16'h0110; verify_expect_sel = 8'h01; verify_group_sel = 3'd3; end
            6'd21: begin verify_addr_sel = 16'h0116; verify_expect_sel = 8'h08; verify_group_sel = 3'd3; end

            6'd22: begin verify_addr_sel = 16'h012c; verify_expect_sel = 8'hc1; verify_group_sel = 3'd4; end
            6'd23: begin verify_addr_sel = 16'h012d; verify_expect_sel = 8'h0c; verify_group_sel = 3'd4; end
            6'd24: begin verify_addr_sel = 16'h012e; verify_expect_sel = 8'h00; verify_group_sel = 3'd4; end
            6'd25: begin verify_addr_sel = 16'h0134; verify_expect_sel = 8'h01; verify_group_sel = 3'd4; end
            6'd26: begin verify_addr_sel = 16'h0135; verify_expect_sel = 8'h00; verify_group_sel = 3'd4; end

            6'd27: begin verify_addr_sel = 16'h0136; verify_expect_sel = 8'hc1; verify_group_sel = 3'd5; end
            6'd28: begin verify_addr_sel = 16'h0137; verify_expect_sel = 8'h80; verify_group_sel = 3'd5; end
            6'd29: begin verify_addr_sel = 16'h0138; verify_expect_sel = 8'h01; verify_group_sel = 3'd5; end
            6'd30: begin verify_addr_sel = 16'h013e; verify_expect_sel = 8'h10; verify_group_sel = 3'd5; end

            6'd31: begin verify_addr_sel = 16'h014a; verify_expect_sel = 8'hc1; verify_group_sel = 3'd6; end
            6'd32: begin verify_addr_sel = 16'h014b; verify_expect_sel = 8'h80; verify_group_sel = 3'd6; end
            6'd33: begin verify_addr_sel = 16'h014c; verify_expect_sel = 8'h01; verify_group_sel = 3'd6; end
            6'd34: begin verify_addr_sel = 16'h0152; verify_expect_sel = 8'h10; verify_group_sel = 3'd6; end
            6'd35: begin verify_addr_sel = 16'h0004; verify_expect_sel = 8'h7f; verify_group_sel = 3'd0; end
            6'd36: begin verify_addr_sel = 16'h00f3; verify_expect_sel = 8'h00; verify_group_sel = 3'd1; end
            6'd37: begin verify_addr_sel = 16'h00f4; verify_expect_sel = 8'h00; verify_group_sel = 3'd1; end
            default: begin verify_addr_sel = 16'h0005; verify_expect_sel = 8'h01; verify_group_sel = 3'd0; end
        endcase
    end

    always @(*) begin
        verify_mismatch_now  = (read_data != verify_expect_sel);
        verify_fail_mask_now = verify_group_fail;
        if (verify_mismatch_now) begin
            verify_fail_mask_now = verify_group_fail | (7'b1 << verify_group_sel);
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            table_start  <= 1'b0;
            read_start   <= 1'b0;
            busy         <= 1'b0;
            done         <= 1'b0;
            ok           <= 1'b0;
            fail         <= 1'b0;
            status_dbg   <= 40'd0;
            verify_group_ok      <= 7'd0;
            verify_done          <= 1'b0;
            verify_fail_any      <= 1'b0;
            verify_mismatch_addr <= 16'd0;
            verify_mismatch_data <= 8'd0;
            verify_mismatch_expect <= 8'd0;
            ch4_snapshot_dbg <= 32'd0;
            state        <= ST_IDLE;
            retry_count  <= 14'd0;
            read_addr    <= 16'h007c;
            wait_counter <= 32'd0;
            pll1_locked  <= 1'b0;
            verify_index <= 6'd0;
            verify_group_fail <= 7'd0;
            verify_mismatch_valid <= 1'b0;
        end else begin
            table_start <= 1'b0;
            read_start  <= 1'b0;
            done        <= 1'b0;

            // 启动流程：
            // ST_RUN_TABLE    : 按表写完整套 HMC7044 配置
            // ST_PLL*_WAIT    : 轮询 PLL/告警/FSM 状态，确认锁定
            // ST_VERIFY_*     : 回读关键寄存器，确认输出通道配置
            // ST_DONE/ST_FAIL : 给顶层状态机返回成功或失败
            case (state)
                ST_IDLE: begin
                    busy         <= 1'b0;
                    ok           <= 1'b0;
                    fail         <= 1'b0;
                    retry_count  <= 14'd0;
                    wait_counter <= 32'd0;
                    if (start) begin
                        status_dbg   <= 40'd0;
                        verify_group_ok      <= 7'd0;
                        verify_done          <= 1'b0;
                        verify_fail_any      <= 1'b0;
                        verify_mismatch_addr <= 16'd0;
                        verify_mismatch_data <= 8'd0;
                        verify_mismatch_expect <= 8'd0;
                        ch4_snapshot_dbg <= 32'd0;
                        read_addr    <= 16'h007c;
                        pll1_locked  <= 1'b0;
                        verify_index <= 6'd0;
                        verify_group_fail <= 7'd0;
                        verify_mismatch_valid <= 1'b0;
                        busy        <= 1'b1;
                        table_start <= 1'b1;
                        state       <= ST_RUN_TABLE;
                    end
                end

                ST_RUN_TABLE: begin
                    if (table_done) begin
                        retry_count <= 14'd0;
                        read_addr   <= 16'h007c;
                        state       <= ST_PLL1_START;
                    end
                end

                ST_PLL1_START: begin
                    if (!read_busy) begin
                        read_start <= 1'b1;
                        state      <= ST_PLL1_WAIT;
                    end
                end

                ST_PLL1_WAIT: begin
                    if (read_done) begin
                        status_dbg[7:0] <= read_data;
                        pll1_locked     <= read_data[5];
                        read_addr       <= 16'h007d;
                        state           <= ST_PLL2_START;
                    end
                end

                ST_PLL2_START: begin
                    if (!read_busy) begin
                        read_start <= 1'b1;
                        state      <= ST_PLL2_WAIT;
                    end
                end

                ST_PLL2_WAIT: begin
                    if (read_done) begin
                        status_dbg[15:8] <= read_data;
                        read_addr        <= 16'h007e;
                        state            <= ST_ALARM_START;
                    end
                end

                ST_ALARM_START: begin
                    if (!read_busy) begin
                        read_start <= 1'b1;
                        state      <= ST_ALARM_WAIT;
                    end
                end

                ST_ALARM_WAIT: begin
                    if (read_done) begin
                        status_dbg[23:16] <= read_data;
                        read_addr         <= 16'h0082;
                        state             <= ST_FSM_START;
                    end
                end

                ST_FSM_START: begin
                    if (!read_busy) begin
                        read_start <= 1'b1;
                        state      <= ST_FSM_WAIT;
                    end
                end

                ST_FSM_WAIT: begin
                    if (read_done) begin
                        status_dbg[31:24] <= read_data;
                        read_addr         <= 16'h0085;
                        state             <= ST_MISC_START;
                    end
                end

                ST_MISC_START: begin
                    if (!read_busy) begin
                        read_start <= 1'b1;
                        state      <= ST_MISC_WAIT;
                    end
                end

                ST_MISC_WAIT: begin
                    if (read_done) begin
                        status_dbg[39:32] <= read_data;
                        if (pll1_locked && status_dbg[8] && status_dbg[26:24] == 3'b010) begin
                            verify_index <= 6'd0;
                            verify_group_fail <= 7'd0;
                            verify_mismatch_valid <= 1'b0;
                            state <= ST_VERIFY_START;
                        end else if (retry_count == MAX_RETRY - 1'b1) begin
                            state <= ST_FAIL;
                        end else begin
                            retry_count  <= retry_count + 1'b1;
                            wait_counter <= MS_TICKS;
                            read_addr    <= 16'h007c;
                            state        <= ST_RETRY_WAIT;
                        end
                    end
                end

                ST_VERIFY_START: begin
                    if (!read_busy) begin
                        read_addr  <= verify_addr_sel;
                        read_start <= 1'b1;
                        state      <= ST_VERIFY_WAIT;
                    end
                end

                ST_VERIFY_WAIT: begin
                    if (read_done) begin
                        case (verify_addr_sel)
                            16'h0004: ch4_snapshot_dbg[31:24] <= read_data;
                            16'h00f1: ch4_snapshot_dbg[23:16] <= read_data;
                            16'h00f7: ch4_snapshot_dbg[15:8]  <= read_data;
                            16'h00f8: ch4_snapshot_dbg[7:0]   <= read_data;
                            default: begin end
                        endcase

                        if (verify_mismatch_now) begin
                            verify_group_fail <= verify_fail_mask_now;
                            if (!verify_mismatch_valid) begin
                                verify_mismatch_valid   <= 1'b1;
                                verify_mismatch_addr    <= verify_addr_sel;
                                verify_mismatch_data    <= read_data;
                                verify_mismatch_expect  <= verify_expect_sel;
                            end
                        end

                        if (verify_index == 6'd37) begin
                            verify_group_ok <= ~verify_fail_mask_now;
                            verify_done     <= 1'b1;
                            verify_fail_any <= |verify_fail_mask_now;
                            if (verify_fail_mask_now == 7'd0) begin
                                state <= ST_DONE;
                            end else begin
                                state <= ST_FAIL;
                            end
                        end else begin
                            verify_index <= verify_index + 1'b1;
                            state        <= ST_VERIFY_START;
                        end
                    end
                end

                ST_RETRY_WAIT: begin
                    if (wait_counter == 32'd0) begin
                        state <= ST_PLL1_START;
                    end else begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end

                ST_DONE: begin
                    busy  <= 1'b0;
                    ok    <= 1'b1;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                ST_FAIL: begin
                    busy  <= 1'b0;
                    fail  <= 1'b1;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
