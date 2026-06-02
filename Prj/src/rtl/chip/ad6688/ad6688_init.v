module ad6688_init #(
    parameter integer CLK_DIV  = 32,
    parameter integer MS_TICKS = 100000,
    // 0: normal SYNCINB pin control, 1: force CGS, 2: force ILAS/user data.
    parameter integer JESD_SYNCINB_DEBUG_MODE = 0,
    parameter integer JESD_SYNCINB_INVERT = 0,
    parameter integer JESD_ILAS_ALWAYS_ON = 0,
    parameter integer JESD_8B10B_BIT_INVERT = 0,
    parameter integer ENABLE_SERDOUT_INVERT = 0,
    parameter [7:0] SERDOUT_INVERT_MASK = 8'h00
) (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire runtime_patch_start,
    input  wire runtime_link_reinit_start,
    input  wire sdio_i,
    output reg  busy,
    output reg  done,
    output reg  ok,
    output reg  fail,
    output reg  [15:0] status_dbg,
    output wire [4:0]  debug_state,
    output wire [3:0]  debug_retry_count,
    output wire [31:0] debug_wait_counter,
    output wire [15:0] debug_read_addr,
    output wire [7:0]  debug_read_data,
    output wire        debug_read_busy,
    output wire        debug_read_done,
    output wire [23:0] debug_patch_word,
    output wire        debug_retry_clock_check,
    output wire [31:0] debug_clk_trace,
    output wire [31:0] debug_fail_detail,
    output wire [31:0] debug_jesd_ctrl,
    output wire [31:0] debug_jesd_param,
    output wire [31:0] debug_lane_map,
    output wire [31:0] debug_sysref,
    output wire [31:0] debug_serdes,
    output wire [31:0] debug_link_extra,
    output wire [31:0] debug_serdes_cfg,
    output wire [31:0] debug_serdes_emph,
    output wire [31:0] debug_jesd_param_ext,
    output wire [31:0] debug_checksum03,
    output wire [31:0] debug_checksum47,
    output wire [31:0] debug_lid03,
    output wire [31:0] debug_lid47,
    output wire [31:0] debug_runtime_patch,
    output wire [31:0] debug_runtime_link_reinit,
    output reg  runtime_patch_busy,
    output reg  runtime_patch_done,
    output reg  runtime_patch_fail,
    output reg  runtime_link_reinit_busy,
    output reg  runtime_link_reinit_done,
    output reg  runtime_link_reinit_fail,
    output wire sclk,
    output wire cs_n,
    output wire sdio_o,
    output wire sdio_oe
);

    localparam [4:0] ST_IDLE         = 5'd0;
    localparam [4:0] ST_RUN_TABLE    = 5'd1;
    localparam [4:0] ST_CLK_START    = 5'd2;
    localparam [4:0] ST_CLK_WAIT     = 5'd3;
    localparam [4:0] ST_PLL_START    = 5'd4;
    localparam [4:0] ST_PLL_WAIT     = 5'd5;
    localparam [4:0] ST_RELOCK_15    = 5'd6;
    localparam [4:0] ST_RELOCK_16    = 5'd7;
    localparam [4:0] ST_RETRY_WAIT   = 5'd8;
    localparam [4:0] ST_DONE         = 5'd9;
    localparam [4:0] ST_FAIL         = 5'd10;
    localparam [4:0] ST_ID_START     = 5'd11;
    localparam [4:0] ST_ID_WAIT      = 5'd12;
    localparam [4:0] ST_RELOCK_16_START = 5'd13;
    localparam [4:0] ST_RELOCK_16_WAIT  = 5'd14;
    localparam [4:0] ST_READBACK     = 5'd15;
    localparam [4:0] ST_SYNCDBG_START = 5'd16;
    localparam [4:0] ST_SYNCDBG_WAIT  = 5'd17;
    localparam [4:0] ST_ILAS_START    = 5'd18;
    localparam [4:0] ST_ILAS_WAIT     = 5'd19;
    localparam [4:0] ST_SERDINV_START = 5'd20;
    localparam [4:0] ST_SERDINV_WAIT  = 5'd21;
    localparam [4:0] ST_SERDINV_RESTART_START = 5'd22;
    localparam [4:0] ST_SERDINV_RESTART_WAIT  = 5'd23;
    localparam [4:0] ST_SERDINV_FINAL_START = 5'd24;
    localparam [4:0] ST_SERDINV_FINAL_WAIT  = 5'd25;
    localparam [4:0] ST_SERDINV_SETTLE      = 5'd26;
    localparam [4:0] ST_FINAL_PLL_START     = 5'd27;
    localparam [4:0] ST_FINAL_PLL_WAIT      = 5'd28;
    localparam [4:0] ST_FINAL_PLL_RETRY_WAIT = 5'd29;
    localparam [4:0] ST_LINK_REINIT_START   = 5'd30;
    localparam [4:0] ST_LINK_REINIT_WAIT    = 5'd31;

    localparam [3:0] MAX_RETRY = 4'd10;
    localparam [5:0] READBACK_LAST_INDEX = 6'd49;
    localparam [3:0] REINIT_LAST_INDEX = 4'd8;
    localparam [3:0] RUNTIME_REINIT_MAIN_LAST_INDEX = 4'd9;
    localparam [3:0] RUNTIME_REINIT_RESTART_LAST_INDEX = 4'd1;
    localparam [7:0] JESD_SYNCINB_MISC_BITS =
        (JESD_SYNCINB_INVERT != 0 ? 8'h20 : 8'h00) |
        (JESD_8B10B_BIT_INVERT != 0 ? 8'h02 : 8'h00);
    localparam [7:0] JESD_SYNCINB_BASE_REG = JESD_SYNCINB_MISC_BITS;
    localparam [7:0] JESD_SYNCINB_DEBUG_REG =
        (JESD_SYNCINB_DEBUG_MODE == 1) ? (8'h80 | JESD_SYNCINB_MISC_BITS) :
        (JESD_SYNCINB_DEBUG_MODE == 2) ? (8'hc0 | JESD_SYNCINB_MISC_BITS) :
                                         JESD_SYNCINB_BASE_REG;
    localparam [7:0] JESD_LINK_CTRL1_FINAL_REG =
        (JESD_ILAS_ALWAYS_ON != 0) ? 8'h1e : 8'h16;
    localparam [7:0] JESD_LINK_CTRL1_REINIT_REG = 8'h16;
    localparam [7:0] JESD_RUNTIME_LINK_CTRL1_REG = JESD_LINK_CTRL1_FINAL_REG;
    localparam [7:0] JESD_RUNTIME_SYNCINB_REG = JESD_SYNCINB_BASE_REG;

    wire [7:0]  table_addr;
    wire [31:0] table_cmd;
    wire        table_spi_start;
    wire [23:0] spi_word;
    wire        table_spi_busy;
    wire        table_spi_done;
    wire        table_busy;
    wire        table_done;
    wire        read_busy;
    wire        read_done;
    wire [7:0]  read_data;
    wire        patch_busy;
    wire        patch_done;
    wire        write_sclk;
    wire        write_cs_n;
    wire        write_sdio_o;
    wire        write_sdio_oe;
    wire        read_sclk;
    wire        read_cs_n;
    wire        read_sdio_o;
    wire        read_sdio_oe;
    wire        patch_sclk;
    wire        patch_cs_n;
    wire        patch_sdio_o;
    wire        patch_sdio_oe;

    reg         table_start;
    reg         read_start;
    reg         patch_start;
    reg [23:0]  patch_word;
    reg [14:0]  read_addr;
    reg [4:0]   state;
    reg [3:0]   retry_count;
    reg [31:0]  wait_counter;
    reg         retry_clock_check;
    reg         clkdet_first_valid;
    reg [7:0]   clkdet_first_read;
    reg [7:0]   clkdet_last_read;
    reg [9:0]   clkdet_bit0_mask;
    reg [9:0]   clkdet_bit7_mask;
    reg         pll_read_seen;
    reg [7:0]   pll_last_read;
    reg [7:0]   id_read_data;
    reg [5:0]   readback_index;
    reg [3:0]   reinit_index;
    reg         link_reinit_final_check;
    reg         readback_active;
    reg         final_pll_checked;
    reg         final_pll_lock_ok;
    reg         final_pll_readback_fail;
    reg [7:0]   rb_056e;
    reg [7:0]   rb_056f;
    reg [7:0]   rb_0570;
    reg [7:0]   rb_0571;
    reg [7:0]   rb_0572;
    reg [7:0]   rb_0573;
    reg [7:0]   rb_0574;
    reg [7:0]   rb_0583;
    reg [7:0]   rb_0584;
    reg [7:0]   rb_0585;
    reg [7:0]   rb_0586;
    reg [7:0]   rb_0587;
    reg [7:0]   rb_0588;
    reg [7:0]   rb_0589;
    reg [7:0]   rb_058a;
    reg [7:0]   rb_058b;
    reg [7:0]   rb_058c;
    reg [7:0]   rb_058d;
    reg [7:0]   rb_058e;
    reg [7:0]   rb_058f;
    reg [7:0]   rb_0590;
    reg [7:0]   rb_0591;
    reg [7:0]   rb_0592;
    reg [7:0]   rb_05a0;
    reg [7:0]   rb_05a1;
    reg [7:0]   rb_05a2;
    reg [7:0]   rb_05a3;
    reg [7:0]   rb_05a4;
    reg [7:0]   rb_05a5;
    reg [7:0]   rb_05a6;
    reg [7:0]   rb_05a7;
    reg [2:0]   runtime_patch_state;
    reg [1:0]   runtime_patch_index;
    reg [15:0]  runtime_patch_wait;
    reg [23:0]  runtime_patch_word_dbg;
    reg [7:0]   runtime_patch_rb_0571;
    reg [7:0]   runtime_patch_rb_0572;
    reg [7:0]   runtime_patch_rb_056f;
    reg [2:0]   runtime_link_reinit_state;
    reg [3:0]   runtime_link_reinit_index;
    reg [31:0]  runtime_link_reinit_wait;
    reg [23:0]  runtime_link_reinit_word_dbg;
    reg [7:0]   runtime_link_reinit_rb_0571;
    reg [7:0]   runtime_link_reinit_rb_0572;
    reg [7:0]   runtime_link_reinit_rb_056f;
    reg [3:0]   runtime_link_reinit_poll_count;
    reg         runtime_link_reinit_restart_only;
    reg [7:0]   rb_05b0;
    reg [7:0]   rb_05b2;
    reg [7:0]   rb_05b3;
    reg [7:0]   rb_05b5;
    reg [7:0]   rb_05b6;
    reg [7:0]   rb_05bf;
    reg [7:0]   rb_05c0;
    reg [7:0]   rb_05c1;
    reg [7:0]   rb_05c2;
    reg [7:0]   rb_05c3;
    reg [7:0]   rb_05c8;
    reg [7:0]   rb_05c9;
    reg [7:0]   rb_05ca;
    reg [7:0]   rb_05cb;
    reg [7:0]   rb_0120;
    reg [7:0]   rb_0128;
    reg [7:0]   rb_0129;
    reg [7:0]   rb_012a;
    reg [7:0]   rb_1262;

    assign debug_state             = state;
    assign debug_retry_count       = retry_count;
    assign debug_wait_counter      = wait_counter;
    assign debug_read_addr         = {1'b0, read_addr};
    assign debug_read_data         = read_data;
    assign debug_read_busy         = read_busy;
    assign debug_read_done         = read_done;
    assign debug_patch_word        = patch_word;
    assign debug_retry_clock_check = retry_clock_check | readback_active;
    assign debug_clk_trace         = {clkdet_first_read, clkdet_last_read, clkdet_bit0_mask, clkdet_bit7_mask[5:0]};
    assign debug_fail_detail       = {clkdet_bit7_mask, pll_last_read, id_read_data, clkdet_first_valid, pll_read_seen, retry_count};
    assign debug_jesd_ctrl         = {rb_0571, rb_0572, rb_058b, rb_0592};
    assign debug_jesd_param        = {rb_058e, rb_058d, rb_058c, rb_058b};
    assign debug_lane_map          = {rb_05b6, rb_05b5, rb_05b3, rb_05b2};
    assign debug_sysref            = {rb_012a, rb_0129, rb_0128, rb_0120};
    assign debug_serdes            = {rb_056e, rb_056f, rb_05bf, rb_0572};
    assign debug_link_extra        = {rb_1262, rb_0574, rb_0573, rb_05b0};
    assign debug_serdes_cfg        = {rb_05c3, rb_05c2, rb_05c1, rb_05c0};
    assign debug_serdes_emph       = {rb_05cb, rb_05ca, rb_05c9, rb_05c8};
    assign debug_jesd_param_ext    = {rb_0591, rb_0590, rb_058f, rb_0570};
    assign debug_checksum03        = {rb_05a3, rb_05a2, rb_05a1, rb_05a0};
    assign debug_checksum47        = {rb_05a7, rb_05a6, rb_05a5, rb_05a4};
    assign debug_lid03             = {rb_0586, rb_0585, rb_0584, rb_0583};
    assign debug_lid47             = {rb_058a, rb_0589, rb_0588, rb_0587};
    assign debug_runtime_patch     = {
        runtime_patch_state,
        runtime_patch_busy,
        runtime_patch_done,
        runtime_patch_fail,
        runtime_patch_rb_056f,
        runtime_patch_rb_0572,
        runtime_patch_rb_0571,
        2'b00
    };
    assign debug_runtime_link_reinit = {
        4'hc,
        runtime_link_reinit_state,
        runtime_link_reinit_busy,
        runtime_link_reinit_fail,
        runtime_link_reinit_restart_only,
        runtime_link_reinit_poll_count,
        runtime_link_reinit_index,
        runtime_link_reinit_rb_056f,
        runtime_link_reinit_rb_0572[2:0],
        runtime_link_reinit_rb_0571[2:0]
    };

    function [14:0] readback_addr;
        input [5:0] index;
        begin
            case (index)
                6'd0:  readback_addr = 15'h0571;
                6'd1:  readback_addr = 15'h0572;
                6'd2:  readback_addr = 15'h056e;
                6'd3:  readback_addr = 15'h056f;
                6'd4:  readback_addr = 15'h05bf;
                6'd5:  readback_addr = 15'h05b0;
                6'd6:  readback_addr = 15'h0573;
                6'd7:  readback_addr = 15'h0574;
                6'd8:  readback_addr = 15'h1262;
                6'd9:  readback_addr = 15'h05c0;
                6'd10: readback_addr = 15'h05c1;
                6'd11: readback_addr = 15'h05c2;
                6'd12: readback_addr = 15'h05c3;
                6'd13: readback_addr = 15'h0570;
                6'd14: readback_addr = 15'h0583;
                6'd15: readback_addr = 15'h0584;
                6'd16: readback_addr = 15'h0585;
                6'd17: readback_addr = 15'h0586;
                6'd18: readback_addr = 15'h0587;
                6'd19: readback_addr = 15'h0588;
                6'd20: readback_addr = 15'h0589;
                6'd21: readback_addr = 15'h058a;
                6'd22: readback_addr = 15'h058b;
                6'd23: readback_addr = 15'h058c;
                6'd24: readback_addr = 15'h058d;
                6'd25: readback_addr = 15'h058e;
                6'd26: readback_addr = 15'h058f;
                6'd27: readback_addr = 15'h0590;
                6'd28: readback_addr = 15'h0591;
                6'd29: readback_addr = 15'h0592;
                6'd30: readback_addr = 15'h05b2;
                6'd31: readback_addr = 15'h05b3;
                6'd32: readback_addr = 15'h05b5;
                6'd33: readback_addr = 15'h05b6;
                6'd34: readback_addr = 15'h0120;
                6'd35: readback_addr = 15'h0128;
                6'd36: readback_addr = 15'h0129;
                6'd37: readback_addr = 15'h012a;
                6'd38: readback_addr = 15'h05a0;
                6'd39: readback_addr = 15'h05a1;
                6'd40: readback_addr = 15'h05a2;
                6'd41: readback_addr = 15'h05a3;
                6'd42: readback_addr = 15'h05a4;
                6'd43: readback_addr = 15'h05a5;
                6'd44: readback_addr = 15'h05a6;
                6'd45: readback_addr = 15'h05a7;
                6'd46: readback_addr = 15'h05c8;
                6'd47: readback_addr = 15'h05c9;
                6'd48: readback_addr = 15'h05ca;
                6'd49: readback_addr = 15'h05cb;
                default: readback_addr = 15'h0571;
            endcase
        end
    endfunction

    function [23:0] link_reinit_word;
        input [3:0] index;
        begin
            case (index)
                4'd0: link_reinit_word = {16'h0571, 8'h15};
                4'd1: link_reinit_word = {16'h0571, JESD_LINK_CTRL1_REINIT_REG};
                4'd2: link_reinit_word = {16'h1228, 8'h4f};
                4'd3: link_reinit_word = {16'h1228, 8'h0f};
                4'd4: link_reinit_word = {16'h1222, 8'h00};
                4'd5: link_reinit_word = {16'h1222, 8'h04};
                4'd6: link_reinit_word = {16'h1222, 8'h00};
                4'd7: link_reinit_word = {16'h1262, 8'h80};
                4'd8: link_reinit_word = {16'h1262, 8'h00};
                default: link_reinit_word = {16'h0571, JESD_LINK_CTRL1_REINIT_REG};
            endcase
        end
    endfunction

    function [23:0] runtime_link_reinit_word;
        input       restart_only;
        input [3:0] index;
        begin
            if (restart_only) begin
                case (index)
                    4'd0: runtime_link_reinit_word = {16'h0571, 8'h15};
                    4'd1: runtime_link_reinit_word = {
                        16'h0571,
                        JESD_LINK_CTRL1_REINIT_REG
                    };
                    default: runtime_link_reinit_word = {
                        16'h0571,
                        JESD_LINK_CTRL1_REINIT_REG
                    };
                endcase
            end else begin
                case (index)
                    4'd0: runtime_link_reinit_word = {16'h0571, 8'h15};
                    4'd1: runtime_link_reinit_word = {16'h1228, 8'h4f};
                    4'd2: runtime_link_reinit_word = {16'h1228, 8'h0f};
                    4'd3: runtime_link_reinit_word = {16'h1222, 8'h00};
                    4'd4: runtime_link_reinit_word = {16'h1222, 8'h04};
                    4'd5: runtime_link_reinit_word = {16'h1222, 8'h00};
                    4'd6: runtime_link_reinit_word = {16'h1262, 8'h80};
                    4'd7: runtime_link_reinit_word = {16'h1262, 8'h00};
                    4'd8: runtime_link_reinit_word = {
                        16'h0572,
                        JESD_RUNTIME_SYNCINB_REG
                    };
                    4'd9: runtime_link_reinit_word = {
                        16'h0571,
                        JESD_LINK_CTRL1_REINIT_REG
                    };
                    default: runtime_link_reinit_word = {
                        16'h0571,
                        JESD_LINK_CTRL1_REINIT_REG
                    };
                endcase
            end
        end
    endfunction

    function [23:0] runtime_patch_word;
        input [1:0] index;
        begin
            case (index)
                2'd0: runtime_patch_word = {
                    16'h0571,
                    JESD_RUNTIME_LINK_CTRL1_REG
                };
                2'd1: runtime_patch_word = {16'h0572, JESD_RUNTIME_SYNCINB_REG};
                default: runtime_patch_word = {
                    16'h0571,
                    JESD_RUNTIME_LINK_CTRL1_REG
                };
            endcase
        end
    endfunction

    ad6688_init_table u_table (
        .addr(table_addr),
        .cmd (table_cmd)
    );

    spi_init_engine #(
        .TABLE_AW(8),
        .MS_TICKS(MS_TICKS)
    ) u_engine (
        .clk      (clk),
        .rst      (rst),
        .start    (table_start),
        .busy     (table_busy),
        .done     (table_done),
        .table_addr(table_addr),
        .table_cmd(table_cmd),
        .spi_start(table_spi_start),
        .spi_word (spi_word),
        .spi_busy (table_spi_busy),
        .spi_done (table_spi_done)
    );

    adi_spi_master #(
        .CLK_DIV(CLK_DIV),
        .SCLK_IDLE_HIGH(1)
    ) u_spi (
        .clk                 (clk),
        .rst                 (rst),
        .start               (table_spi_start),
        .read_en             (1'b0),
        .three_wire          (1'b1),
        .read_capture_falling(1'b1),
        .addr                (spi_word[22:8]),
        .wdata               (spi_word[7:0]),
        .sdio_i              (sdio_i),
        .sdo_i               (1'b0),
        .busy                (table_spi_busy),
        .done                (table_spi_done),
        .cs_n                (write_cs_n),
        .sclk                (write_sclk),
        .sdio_oe             (write_sdio_oe),
        .rdata               (),
        .rdata_valid         (),
        .sdio_o              (write_sdio_o)
    );

    adi_spi_master #(
        .CLK_DIV(CLK_DIV),
        .SCLK_IDLE_HIGH(1)
    ) u_read (
        .clk                 (clk),
        .rst                 (rst),
        .start               (read_start),
        .read_en             (1'b1),
        .three_wire          (1'b1),
        .read_capture_falling(1'b1),
        .addr                (read_addr),
        .wdata               (8'h00),
        .sdio_i              (sdio_i),
        .sdo_i               (1'b0),
        .busy                (read_busy),
        .done                (read_done),
        .cs_n                (read_cs_n),
        .sclk                (read_sclk),
        .sdio_oe             (read_sdio_oe),
        .rdata               (read_data),
        .rdata_valid         (),
        .sdio_o              (read_sdio_o)
    );

    adi_spi_master #(
        .CLK_DIV(CLK_DIV),
        .SCLK_IDLE_HIGH(1)
    ) u_patch_write (
        .clk                 (clk),
        .rst                 (rst),
        .start               (patch_start),
        .read_en             (1'b0),
        .three_wire          (1'b1),
        .read_capture_falling(1'b1),
        .addr                (patch_word[22:8]),
        .wdata               (patch_word[7:0]),
        .sdio_i              (sdio_i),
        .sdo_i               (1'b0),
        .busy                (patch_busy),
        .done                (patch_done),
        .cs_n                (patch_cs_n),
        .sclk                (patch_sclk),
        .sdio_oe             (patch_sdio_oe),
        .rdata               (),
        .rdata_valid         (),
        .sdio_o              (patch_sdio_o)
    );

    assign sclk    = read_busy ? read_sclk :
                     patch_busy ? patch_sclk :
                     write_sclk;
    assign cs_n    = read_busy ? read_cs_n :
                     patch_busy ? patch_cs_n :
                     write_cs_n;
    assign sdio_o  = read_busy ? read_sdio_o :
                     patch_busy ? patch_sdio_o :
                     write_sdio_o;
    assign sdio_oe = read_busy ? read_sdio_oe :
                     patch_busy ? patch_sdio_oe :
                     write_sdio_oe;

    always @(posedge clk) begin
        if (rst) begin
            table_start  <= 1'b0;
            read_start   <= 1'b0;
            patch_start  <= 1'b0;
            patch_word   <= 24'd0;
            read_addr    <= 15'h011b;
            busy         <= 1'b0;
            done         <= 1'b0;
            ok           <= 1'b0;
            fail         <= 1'b0;
            status_dbg   <= 16'd0;
            state        <= ST_IDLE;
            retry_count  <= 4'd0;
            wait_counter <= 32'd0;
            retry_clock_check <= 1'b1;
            clkdet_first_valid <= 1'b0;
            clkdet_first_read  <= 8'd0;
            clkdet_last_read   <= 8'd0;
            clkdet_bit0_mask   <= 10'd0;
            clkdet_bit7_mask   <= 10'd0;
            pll_read_seen      <= 1'b0;
            pll_last_read      <= 8'd0;
            id_read_data       <= 8'd0;
            readback_index     <= 6'd0;
            reinit_index       <= 4'd0;
            link_reinit_final_check <= 1'b0;
            readback_active    <= 1'b0;
            final_pll_checked  <= 1'b0;
            final_pll_lock_ok  <= 1'b0;
            final_pll_readback_fail <= 1'b0;
            rb_056e            <= 8'd0;
            rb_056f            <= 8'd0;
            rb_0570            <= 8'd0;
            rb_0571            <= 8'd0;
            rb_0572            <= 8'd0;
            rb_0573            <= 8'd0;
            rb_0574            <= 8'd0;
            rb_0583            <= 8'd0;
            rb_0584            <= 8'd0;
            rb_0585            <= 8'd0;
            rb_0586            <= 8'd0;
            rb_0587            <= 8'd0;
            rb_0588            <= 8'd0;
            rb_0589            <= 8'd0;
            rb_058a            <= 8'd0;
            rb_058b            <= 8'd0;
            rb_058c            <= 8'd0;
            rb_058d            <= 8'd0;
            rb_058e            <= 8'd0;
            rb_058f            <= 8'd0;
            rb_0590            <= 8'd0;
            rb_0591            <= 8'd0;
            rb_0592            <= 8'd0;
            rb_05a0            <= 8'd0;
            rb_05a1            <= 8'd0;
            rb_05a2            <= 8'd0;
            rb_05a3            <= 8'd0;
            rb_05a4            <= 8'd0;
            rb_05a5            <= 8'd0;
            rb_05a6            <= 8'd0;
            rb_05a7            <= 8'd0;
            rb_05b0            <= 8'd0;
            rb_05b2            <= 8'd0;
            rb_05b3            <= 8'd0;
            rb_05b5            <= 8'd0;
            rb_05b6            <= 8'd0;
            rb_05bf            <= 8'd0;
            rb_05c0            <= 8'd0;
            rb_05c1            <= 8'd0;
            rb_05c2            <= 8'd0;
            rb_05c3            <= 8'd0;
            rb_05c8            <= 8'd0;
            rb_05c9            <= 8'd0;
            rb_05ca            <= 8'd0;
            rb_05cb            <= 8'd0;
            rb_0120            <= 8'd0;
            rb_0128            <= 8'd0;
            rb_0129            <= 8'd0;
            rb_012a            <= 8'd0;
            rb_1262            <= 8'd0;
            runtime_patch_state <= 3'd0;
            runtime_patch_index <= 2'd0;
            runtime_patch_wait  <= 16'd0;
            runtime_patch_word_dbg <= 24'd0;
            runtime_patch_rb_0571 <= 8'd0;
            runtime_patch_rb_0572 <= 8'd0;
            runtime_patch_rb_056f <= 8'd0;
            runtime_patch_busy  <= 1'b0;
            runtime_patch_done  <= 1'b0;
            runtime_patch_fail  <= 1'b0;
            runtime_link_reinit_state <= 3'd0;
            runtime_link_reinit_index <= 4'd0;
            runtime_link_reinit_wait <= 32'd0;
            runtime_link_reinit_word_dbg <= 24'd0;
            runtime_link_reinit_rb_0571 <= 8'd0;
            runtime_link_reinit_rb_0572 <= 8'd0;
            runtime_link_reinit_rb_056f <= 8'd0;
            runtime_link_reinit_poll_count <= 4'd0;
            runtime_link_reinit_restart_only <= 1'b0;
            runtime_link_reinit_busy <= 1'b0;
            runtime_link_reinit_done <= 1'b0;
            runtime_link_reinit_fail <= 1'b0;
        end else begin
            table_start <= 1'b0;
            read_start  <= 1'b0;
            patch_start <= 1'b0;
            done        <= 1'b0;
            runtime_patch_done <= 1'b0;
            runtime_link_reinit_done <= 1'b0;
            readback_active <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy        <= 1'b0;
                    ok          <= 1'b0;
                    fail        <= 1'b0;
                    status_dbg  <= 16'd0;
                    retry_count <= 4'd0;
                    retry_clock_check <= 1'b1;
                    if (start) begin
                        read_addr <= 15'h011b;
                        clkdet_first_valid <= 1'b0;
                        clkdet_first_read  <= 8'd0;
                        clkdet_last_read   <= 8'd0;
                        clkdet_bit0_mask   <= 10'd0;
                        clkdet_bit7_mask   <= 10'd0;
                        pll_read_seen      <= 1'b0;
                        pll_last_read      <= 8'd0;
                        id_read_data       <= 8'd0;
                        readback_index     <= 6'd0;
                        reinit_index       <= 4'd0;
                        link_reinit_final_check <= 1'b0;
                        readback_active    <= 1'b0;
                        final_pll_checked  <= 1'b0;
                        final_pll_lock_ok  <= 1'b0;
                        final_pll_readback_fail <= 1'b0;
                        rb_056e            <= 8'd0;
                        rb_056f            <= 8'd0;
                        rb_0570            <= 8'd0;
                        rb_0571            <= 8'd0;
                        rb_0572            <= 8'd0;
                        rb_0573            <= 8'd0;
                        rb_0574            <= 8'd0;
                        rb_0583            <= 8'd0;
                        rb_0584            <= 8'd0;
                        rb_0585            <= 8'd0;
                        rb_0586            <= 8'd0;
                        rb_0587            <= 8'd0;
                        rb_0588            <= 8'd0;
                        rb_0589            <= 8'd0;
                        rb_058a            <= 8'd0;
                        rb_058b            <= 8'd0;
                        rb_058c            <= 8'd0;
                        rb_058d            <= 8'd0;
                        rb_058e            <= 8'd0;
                        rb_058f            <= 8'd0;
                        rb_0590            <= 8'd0;
                        rb_0591            <= 8'd0;
                        rb_0592            <= 8'd0;
                        rb_05a0            <= 8'd0;
                        rb_05a1            <= 8'd0;
                        rb_05a2            <= 8'd0;
                        rb_05a3            <= 8'd0;
                        rb_05a4            <= 8'd0;
                        rb_05a5            <= 8'd0;
                        rb_05a6            <= 8'd0;
                        rb_05a7            <= 8'd0;
                        rb_05b0            <= 8'd0;
                        rb_05b2            <= 8'd0;
                        rb_05b3            <= 8'd0;
                        rb_05b5            <= 8'd0;
                        rb_05b6            <= 8'd0;
                        rb_05bf            <= 8'd0;
                        rb_05c0            <= 8'd0;
                        rb_05c1            <= 8'd0;
                        rb_05c2            <= 8'd0;
                        rb_05c3            <= 8'd0;
                        rb_05c8            <= 8'd0;
                        rb_05c9            <= 8'd0;
                        rb_05ca            <= 8'd0;
                        rb_05cb            <= 8'd0;
                        rb_0120            <= 8'd0;
                        rb_0128            <= 8'd0;
                        rb_0129            <= 8'd0;
                        rb_012a            <= 8'd0;
                        rb_1262            <= 8'd0;
                        busy        <= 1'b1;
                        table_start <= 1'b1;
                        state       <= ST_RUN_TABLE;
                    end
                end

                ST_RUN_TABLE: begin
                    if (table_done) begin
                        retry_count <= 4'd0;
                        state       <= ST_CLK_START;
                    end
                end

                ST_CLK_START: begin
                    if (!read_busy) begin
                        read_addr  <= 15'h011b;
                        read_start <= 1'b1;
                        state      <= ST_CLK_WAIT;
                    end
                end

                ST_CLK_WAIT: begin
                    if (read_done) begin
                        status_dbg[7:0] <= read_data;
                        if (!clkdet_first_valid) begin
                            clkdet_first_valid <= 1'b1;
                            clkdet_first_read  <= read_data;
                        end
                        clkdet_last_read <= read_data;
                        if (read_data[0]) begin
                            clkdet_bit0_mask <= clkdet_bit0_mask | (10'b0000000001 << retry_count);
                        end
                        if (read_data[7]) begin
                            clkdet_bit7_mask <= clkdet_bit7_mask | (10'b0000000001 << retry_count);
                        end
                        if ((read_data & 8'h01) == 8'h01) begin
                            retry_count <= 4'd0;
                            retry_clock_check <= 1'b0;
                            state       <= ST_PLL_START;
                        end else if (retry_count == MAX_RETRY - 1'b1) begin
                            state <= ST_ID_START;
                        end else begin
                            retry_count  <= retry_count + 1'b1;
                            wait_counter <= MS_TICKS;
                            retry_clock_check <= 1'b1;
                            state        <= ST_RETRY_WAIT;
                        end
                    end
                end

                ST_PLL_START: begin
                    if (!read_busy) begin
                        read_addr  <= 15'h056f;
                        read_start <= 1'b1;
                        state      <= ST_PLL_WAIT;
                    end
                end

                ST_PLL_WAIT: begin
                    if (read_done) begin
                        status_dbg[15:8] <= read_data;
                        pll_read_seen <= 1'b1;
                        pll_last_read <= read_data;
                        if ((read_data & 8'h80) == 8'h80) begin
                            if (JESD_ILAS_ALWAYS_ON != 0) begin
                                patch_word <= {
                                    16'h0571,
                                    JESD_LINK_CTRL1_FINAL_REG
                                };
                                state      <= ST_ILAS_START;
                            end else if ((JESD_SYNCINB_DEBUG_MODE != 0) ||
                                         (JESD_SYNCINB_INVERT != 0) ||
                                         (JESD_8B10B_BIT_INVERT != 0)) begin
                                patch_word <= {
                                    16'h0572,
                                    JESD_SYNCINB_DEBUG_REG
                                };
                                state      <= ST_SYNCDBG_START;
                            end else if (ENABLE_SERDOUT_INVERT != 0) begin
                                patch_word <= {16'h05bf, SERDOUT_INVERT_MASK};
                                state      <= ST_SERDINV_START;
                            end else begin
                                retry_count  <= 4'd0;
                                wait_counter <= MS_TICKS;
                                state        <= ST_FINAL_PLL_RETRY_WAIT;
                            end
                        end else if (((read_data & 8'h08) == 8'h08) &&
                                     (retry_count != MAX_RETRY - 1'b1)) begin
                            reinit_index <= 4'd0;
                            link_reinit_final_check <= 1'b0;
                            patch_word   <= link_reinit_word(4'd0);
                            state        <= ST_LINK_REINIT_START;
                        end else if (retry_count == MAX_RETRY - 1'b1) begin
                            state <= ST_FAIL;
                        end else begin
                            retry_count  <= retry_count + 1'b1;
                            wait_counter <= MS_TICKS;
                            retry_clock_check <= 1'b0;
                            state        <= ST_RETRY_WAIT;
                        end
                    end
                end

                ST_ILAS_START: begin
                    if (!patch_busy) begin
                        patch_start <= 1'b1;
                        state       <= ST_ILAS_WAIT;
                    end
                end

                ST_ILAS_WAIT: begin
                    if (patch_done) begin
                        if ((JESD_SYNCINB_DEBUG_MODE != 0) ||
                            (JESD_SYNCINB_INVERT != 0) ||
                            (JESD_8B10B_BIT_INVERT != 0)) begin
                            patch_word <= {
                                16'h0572,
                                JESD_SYNCINB_DEBUG_REG
                            };
                            state      <= ST_SYNCDBG_START;
                        end else if (ENABLE_SERDOUT_INVERT != 0) begin
                            patch_word <= {16'h05bf, SERDOUT_INVERT_MASK};
                            state      <= ST_SERDINV_START;
                        end else begin
                            reinit_index <= 4'd0;
                            link_reinit_final_check <= 1'b1;
                            patch_word   <= link_reinit_word(4'd0);
                            state        <= ST_LINK_REINIT_START;
                        end
                    end
                end

                ST_SYNCDBG_START: begin
                    if (!patch_busy) begin
                        patch_start <= 1'b1;
                        state       <= ST_SYNCDBG_WAIT;
                    end
                end

                ST_SYNCDBG_WAIT: begin
                    if (patch_done) begin
                        if (ENABLE_SERDOUT_INVERT != 0) begin
                            patch_word <= {16'h05bf, SERDOUT_INVERT_MASK};
                            state      <= ST_SERDINV_START;
                        end else begin
                            retry_count  <= 4'd0;
                            wait_counter <= MS_TICKS;
                            state        <= ST_FINAL_PLL_RETRY_WAIT;
                        end
                    end
                end

                ST_SERDINV_START: begin
                    if (!patch_busy) begin
                        patch_start <= 1'b1;
                        state       <= ST_SERDINV_WAIT;
                    end
                end

                ST_SERDINV_WAIT: begin
                    if (patch_done) begin
                        retry_count  <= 4'd0;
                        wait_counter <= MS_TICKS;
                        state        <= ST_FINAL_PLL_RETRY_WAIT;
                    end
                end

                ST_LINK_REINIT_START: begin
                    if (!patch_busy) begin
                        patch_start <= 1'b1;
                        state       <= ST_LINK_REINIT_WAIT;
                    end
                end

                ST_LINK_REINIT_WAIT: begin
                    if (patch_done) begin
                        if (reinit_index == REINIT_LAST_INDEX) begin
                            wait_counter <= MS_TICKS;
                            if (link_reinit_final_check) begin
                                state        <= ST_FINAL_PLL_RETRY_WAIT;
                            end else begin
                                retry_count  <= retry_count + 1'b1;
                                retry_clock_check <= 1'b0;
                                state        <= ST_RETRY_WAIT;
                            end
                        end else begin
                            reinit_index <= reinit_index + 1'b1;
                            patch_word   <= link_reinit_word(reinit_index + 1'b1);
                            state        <= ST_LINK_REINIT_START;
                        end
                    end
                end

                ST_FINAL_PLL_START: begin
                    if (!read_busy) begin
                        read_addr  <= 15'h056f;
                        read_start <= 1'b1;
                        state      <= ST_FINAL_PLL_WAIT;
                    end
                end

                ST_FINAL_PLL_WAIT: begin
                    if (read_done) begin
                        status_dbg[15:8] <= read_data;
                        pll_read_seen     <= 1'b1;
                        pll_last_read     <= read_data;
                        final_pll_checked <= 1'b1;
                        rb_056f           <= read_data;
                        if ((read_data & 8'h80) == 8'h80) begin
                            final_pll_lock_ok <= 1'b1;
                            final_pll_readback_fail <= 1'b0;
                            readback_index    <= 6'd0;
                            read_addr         <= readback_addr(6'd0);
                            state             <= ST_READBACK;
                        end else if (((read_data & 8'h08) == 8'h08) &&
                                     (retry_count != MAX_RETRY - 1'b1)) begin
                            final_pll_lock_ok <= 1'b0;
                            retry_count       <= retry_count + 1'b1;
                            reinit_index      <= 4'd0;
                            link_reinit_final_check <= 1'b1;
                            patch_word        <= link_reinit_word(4'd0);
                            state             <= ST_LINK_REINIT_START;
                        end else if (retry_count == MAX_RETRY - 1'b1) begin
                            final_pll_lock_ok <= 1'b0;
                            final_pll_readback_fail <= 1'b1;
                            readback_index    <= 6'd0;
                            read_addr         <= readback_addr(6'd0);
                            state             <= ST_READBACK;
                        end else begin
                            final_pll_lock_ok <= 1'b0;
                            retry_count       <= retry_count + 1'b1;
                            wait_counter      <= MS_TICKS;
                            state             <= ST_FINAL_PLL_RETRY_WAIT;
                        end
                    end
                end

                ST_FINAL_PLL_RETRY_WAIT: begin
                    if (wait_counter == 32'd0) begin
                        state <= ST_FINAL_PLL_START;
                    end else begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end

                ST_RELOCK_15: begin
                    if (!patch_busy) begin
                        patch_start <= 1'b1;
                        state       <= ST_RELOCK_16;
                    end
                end

                ST_RELOCK_16: begin
                    if (patch_done) begin
                        patch_word  <= {
                            16'h0571,
                            JESD_LINK_CTRL1_FINAL_REG
                        };
                        state       <= ST_RELOCK_16_START;
                    end
                end

                ST_RELOCK_16_START: begin
                    if (!patch_busy) begin
                        patch_start <= 1'b1;
                        state       <= ST_RELOCK_16_WAIT;
                    end
                end

                ST_RELOCK_16_WAIT: begin
                    if (patch_done) begin
                        retry_count <= retry_count + 1'b1;
                        wait_counter <= MS_TICKS;
                        retry_clock_check <= 1'b0;
                        state       <= ST_RETRY_WAIT;
                    end
                end

                ST_RETRY_WAIT: begin
                    if (wait_counter == 32'd0) begin
                        if (retry_clock_check) begin
                            state <= ST_CLK_START;
                        end else begin
                            state <= ST_PLL_START;
                        end
                    end else begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end

                ST_READBACK: begin
                    if (read_done) begin
                        case (readback_index)
                            6'd0:  rb_0571 <= read_data;
                            6'd1:  rb_0572 <= read_data;
                            6'd2:  rb_056e <= read_data;
                            6'd3:  rb_056f <= read_data;
                            6'd4:  rb_05bf <= read_data;
                            6'd5:  rb_05b0 <= read_data;
                            6'd6:  rb_0573 <= read_data;
                            6'd7:  rb_0574 <= read_data;
                            6'd8:  rb_1262 <= read_data;
                            6'd9:  rb_05c0 <= read_data;
                            6'd10: rb_05c1 <= read_data;
                            6'd11: rb_05c2 <= read_data;
                            6'd12: rb_05c3 <= read_data;
                            6'd13: rb_0570 <= read_data;
                            6'd14: rb_0583 <= read_data;
                            6'd15: rb_0584 <= read_data;
                            6'd16: rb_0585 <= read_data;
                            6'd17: rb_0586 <= read_data;
                            6'd18: rb_0587 <= read_data;
                            6'd19: rb_0588 <= read_data;
                            6'd20: rb_0589 <= read_data;
                            6'd21: rb_058a <= read_data;
                            6'd22: rb_058b <= read_data;
                            6'd23: rb_058c <= read_data;
                            6'd24: rb_058d <= read_data;
                            6'd25: rb_058e <= read_data;
                            6'd26: rb_058f <= read_data;
                            6'd27: rb_0590 <= read_data;
                            6'd28: rb_0591 <= read_data;
                            6'd29: rb_0592 <= read_data;
                            6'd30: rb_05b2 <= read_data;
                            6'd31: rb_05b3 <= read_data;
                            6'd32: rb_05b5 <= read_data;
                            6'd33: rb_05b6 <= read_data;
                            6'd34: rb_0120 <= read_data;
                            6'd35: rb_0128 <= read_data;
                            6'd36: rb_0129 <= read_data;
                            6'd37: rb_012a <= read_data;
                            6'd38: rb_05a0 <= read_data;
                            6'd39: rb_05a1 <= read_data;
                            6'd40: rb_05a2 <= read_data;
                            6'd41: rb_05a3 <= read_data;
                            6'd42: rb_05a4 <= read_data;
                            6'd43: rb_05a5 <= read_data;
                            6'd44: rb_05a6 <= read_data;
                            6'd45: rb_05a7 <= read_data;
                            6'd46: rb_05c8 <= read_data;
                            6'd47: rb_05c9 <= read_data;
                            6'd48: rb_05ca <= read_data;
                            6'd49: rb_05cb <= read_data;
                            default: begin
                            end
                        endcase

                        if (readback_index == READBACK_LAST_INDEX) begin
                            state <= final_pll_readback_fail ? ST_FAIL : ST_DONE;
                        end else begin
                            readback_index <= readback_index + 1'b1;
                            read_addr      <= readback_addr(readback_index + 1'b1);
                        end
                    end else if (!read_busy) begin
                        read_addr       <= readback_addr(readback_index);
                        read_start      <= 1'b1;
                        readback_active <= 1'b1;
                    end
                end

                ST_ID_START: begin
                    if (!read_busy) begin
                        read_addr  <= 15'h0003;
                        read_start <= 1'b1;
                        state      <= ST_ID_WAIT;
                    end
                end

                ST_ID_WAIT: begin
                    if (read_done) begin
                        status_dbg[15:8] <= read_data;
                        id_read_data <= read_data;
                        state <= ST_FAIL;
                    end
                end

                ST_DONE: begin
                    busy <= 1'b0;
                    ok   <= 1'b1;
                    fail <= 1'b0;
                    done <= 1'b1;
                    if (runtime_link_reinit_state != 3'd0) begin
                        case (runtime_link_reinit_state)
                            3'd1: begin
                                if (!patch_busy && !read_busy) begin
                                    patch_start <= 1'b1;
                                    runtime_link_reinit_state <= 3'd2;
                                end
                            end

                            3'd2: begin
                                if (patch_done) begin
                                    if ((!runtime_link_reinit_restart_only &&
                                         (runtime_link_reinit_index ==
                                          RUNTIME_REINIT_MAIN_LAST_INDEX)) ||
                                        (runtime_link_reinit_restart_only &&
                                         (runtime_link_reinit_index ==
                                          RUNTIME_REINIT_RESTART_LAST_INDEX))) begin
                                        runtime_link_reinit_wait <=
                                            runtime_link_reinit_restart_only ?
                                            MS_TICKS : (MS_TICKS * 5);
                                        runtime_link_reinit_state <= 3'd3;
                                    end else begin
                                        runtime_link_reinit_index <=
                                            runtime_link_reinit_index + 1'b1;
                                        runtime_link_reinit_word_dbg <=
                                            runtime_link_reinit_word(
                                                runtime_link_reinit_restart_only,
                                                runtime_link_reinit_index +
                                                1'b1
                                            );
                                        patch_word <=
                                            runtime_link_reinit_word(
                                                runtime_link_reinit_restart_only,
                                                runtime_link_reinit_index +
                                                1'b1
                                            );
                                        runtime_link_reinit_state <= 3'd1;
                                    end
                                end
                            end

                            3'd3: begin
                                if (runtime_link_reinit_wait == 32'd0) begin
                                    runtime_link_reinit_index <= 4'hf;
                                    read_addr <= 15'h056f;
                                    runtime_link_reinit_state <= 3'd4;
                                end else begin
                                    runtime_link_reinit_wait <=
                                        runtime_link_reinit_wait - 1'b1;
                                end
                            end

                            3'd4: begin
                                if (!read_busy && !patch_busy) begin
                                    read_start <= 1'b1;
                                    runtime_link_reinit_state <= 3'd5;
                                end
                            end

                            3'd5: begin
                                if (read_done) begin
                                    case (runtime_link_reinit_index)
                                        4'd0: runtime_link_reinit_rb_0571 <=
                                            read_data;
                                        4'd1: runtime_link_reinit_rb_0572 <=
                                            read_data;
                                        4'hf: runtime_link_reinit_rb_056f <=
                                            read_data;
                                        default: runtime_link_reinit_rb_056f <=
                                            read_data;
                                    endcase
                                    if (runtime_link_reinit_index == 4'hf) begin
                                        rb_056f <= read_data;
                                        if ((read_data & 8'h80) == 8'h80) begin
                                            runtime_link_reinit_index <= 4'd0;
                                            read_addr <= 15'h0571;
                                            runtime_link_reinit_state <= 3'd4;
                                        end else if (runtime_link_reinit_poll_count ==
                                                     (MAX_RETRY - 1'b1)) begin
                                            runtime_link_reinit_fail <= 1'b1;
                                            runtime_link_reinit_done <= 1'b1;
                                            runtime_link_reinit_busy <= 1'b0;
                                            runtime_link_reinit_state <= 3'd0;
                                        end else if ((read_data & 8'h08) == 8'h08) begin
                                            runtime_link_reinit_poll_count <=
                                                runtime_link_reinit_poll_count +
                                                1'b1;
                                            runtime_link_reinit_restart_only <=
                                                1'b1;
                                            runtime_link_reinit_index <= 4'd0;
                                            runtime_link_reinit_word_dbg <=
                                                runtime_link_reinit_word(
                                                    1'b1,
                                                    4'd0
                                                );
                                            patch_word <= runtime_link_reinit_word(
                                                1'b1,
                                                4'd0
                                            );
                                            runtime_link_reinit_state <= 3'd1;
                                        end else begin
                                            runtime_link_reinit_poll_count <=
                                                runtime_link_reinit_poll_count +
                                                1'b1;
                                            runtime_link_reinit_wait <= MS_TICKS;
                                            runtime_link_reinit_state <= 3'd3;
                                        end
                                    end else if (runtime_link_reinit_index ==
                                                 4'd0) begin
                                        runtime_link_reinit_index <= 4'd1;
                                        read_addr <= 15'h0572;
                                        runtime_link_reinit_state <= 3'd4;
                                    end else if (runtime_link_reinit_index ==
                                                 4'd1) begin
                                        runtime_link_reinit_fail <=
                                            (runtime_link_reinit_rb_0571 !=
                                             JESD_LINK_CTRL1_REINIT_REG) ||
                                            (read_data !=
                                             JESD_RUNTIME_SYNCINB_REG);
                                        runtime_link_reinit_done <= 1'b1;
                                        runtime_link_reinit_busy <= 1'b0;
                                        rb_0571 <= runtime_link_reinit_rb_0571;
                                        rb_0572 <= read_data;
                                        rb_1262 <= 8'h00;
                                        runtime_link_reinit_state <= 3'd0;
                                    end else begin
                                        runtime_link_reinit_fail <= 1'b1;
                                        runtime_link_reinit_done <= 1'b1;
                                        runtime_link_reinit_busy <= 1'b0;
                                        runtime_link_reinit_state <= 3'd0;
                                    end
                                end
                            end

                            default: begin
                                runtime_link_reinit_busy <= 1'b0;
                                runtime_link_reinit_fail <= 1'b1;
                                runtime_link_reinit_done <= 1'b1;
                                runtime_link_reinit_state <= 3'd0;
                            end
                        endcase
                    end else begin
                        case (runtime_patch_state)
                            3'd0: begin
                                if (runtime_link_reinit_start) begin
                                    runtime_link_reinit_busy <= 1'b1;
                                    runtime_link_reinit_fail <= 1'b0;
                                    runtime_link_reinit_index <= 4'd0;
                                    runtime_link_reinit_wait <= 32'd0;
                                    runtime_link_reinit_rb_0571 <= 8'd0;
                                    runtime_link_reinit_rb_0572 <= 8'd0;
                                    runtime_link_reinit_rb_056f <= 8'd0;
                                    runtime_link_reinit_poll_count <= 4'd0;
                                    runtime_link_reinit_restart_only <= 1'b0;
                                    runtime_link_reinit_word_dbg <=
                                        runtime_link_reinit_word(1'b0, 4'd0);
                                    patch_word <= runtime_link_reinit_word(
                                        1'b0,
                                        4'd0
                                    );
                                    runtime_link_reinit_state <= 3'd1;
                                end
                                runtime_patch_busy <= 1'b0;
                                if (!runtime_link_reinit_start &&
                                    runtime_patch_start) begin
                                    runtime_patch_busy <= 1'b1;
                                    runtime_patch_fail <= 1'b0;
                                    runtime_patch_index <= 2'd0;
                                    runtime_patch_rb_0571 <= 8'd0;
                                    runtime_patch_rb_0572 <= 8'd0;
                                    runtime_patch_rb_056f <= 8'd0;
                                    runtime_patch_word_dbg <=
                                        runtime_patch_word(2'd0);
                                    patch_word <= runtime_patch_word(2'd0);
                                    runtime_patch_state <= 3'd1;
                                end
                            end

                            3'd1: begin
                                if (!patch_busy && !read_busy) begin
                                    patch_start <= 1'b1;
                                    runtime_patch_state <= 3'd2;
                                end
                            end

                            3'd2: begin
                                if (patch_done) begin
                                    if (runtime_patch_index == 2'd1) begin
                                        runtime_patch_wait <= 16'd50000;
                                        runtime_patch_state <= 3'd4;
                                    end else begin
                                        runtime_patch_index <=
                                            runtime_patch_index + 1'b1;
                                        runtime_patch_word_dbg <=
                                            runtime_patch_word(
                                                runtime_patch_index + 1'b1);
                                        patch_word <=
                                            runtime_patch_word(
                                                runtime_patch_index + 1'b1);
                                        runtime_patch_state <= 3'd1;
                                    end
                                end
                            end

                            3'd4: begin
                                if (runtime_patch_wait == 16'd0) begin
                                    runtime_patch_index <= 2'd0;
                                    read_addr <= 15'h0571;
                                    runtime_patch_state <= 3'd5;
                                end else begin
                                    runtime_patch_wait <=
                                        runtime_patch_wait - 1'b1;
                                end
                            end

                            3'd5: begin
                                if (!read_busy && !patch_busy) begin
                                    read_start <= 1'b1;
                                    runtime_patch_state <= 3'd6;
                                end
                            end

                            3'd6: begin
                                if (read_done) begin
                                    case (runtime_patch_index)
                                        2'd0: runtime_patch_rb_0571 <=
                                            read_data;
                                        2'd1: runtime_patch_rb_0572 <=
                                            read_data;
                                        2'd2: runtime_patch_rb_056f <=
                                            read_data;
                                        default: runtime_patch_rb_056f <=
                                            read_data;
                                    endcase
                                    if (runtime_patch_index == 2'd2) begin
                                        runtime_patch_fail <=
                                            (runtime_patch_rb_0571 !=
                                             JESD_RUNTIME_LINK_CTRL1_REG) ||
                                            (runtime_patch_rb_0572 !=
                                             JESD_RUNTIME_SYNCINB_REG) ||
                                            ((read_data & 8'h80) != 8'h80);
                                        runtime_patch_done <= 1'b1;
                                        runtime_patch_busy <= 1'b0;
                                        rb_0571 <= runtime_patch_rb_0571;
                                        rb_0572 <= runtime_patch_rb_0572;
                                        rb_056f <= read_data;
                                        runtime_patch_rb_056f <= read_data;
                                        runtime_patch_state <= 3'd0;
                                    end else begin
                                        runtime_patch_index <=
                                            runtime_patch_index + 1'b1;
                                        if (runtime_patch_index == 2'd0) begin
                                            read_addr <= 15'h0572;
                                        end else begin
                                            read_addr <= 15'h056f;
                                        end
                                        runtime_patch_state <= 3'd5;
                                    end
                                end
                            end

                            default: begin
                                runtime_patch_busy <= 1'b0;
                                runtime_patch_fail <= 1'b1;
                                runtime_patch_state <= 3'd0;
                            end
                        endcase
                    end
                    if (start) begin
                        done         <= 1'b0;
                        ok           <= 1'b0;
                        runtime_patch_busy <= 1'b0;
                        runtime_patch_done <= 1'b0;
                        runtime_patch_fail <= 1'b0;
                        runtime_patch_state <= 3'd0;
                        runtime_link_reinit_busy <= 1'b0;
                        runtime_link_reinit_done <= 1'b0;
                        runtime_link_reinit_fail <= 1'b0;
                        runtime_link_reinit_state <= 3'd0;
                        runtime_link_reinit_index <= 4'd0;
                        runtime_link_reinit_wait <= 32'd0;
                        runtime_link_reinit_word_dbg <= 24'd0;
                        runtime_link_reinit_rb_0571 <= 8'd0;
                        runtime_link_reinit_rb_0572 <= 8'd0;
                        runtime_link_reinit_rb_056f <= 8'd0;
                        runtime_link_reinit_poll_count <= 4'd0;
                        runtime_link_reinit_restart_only <= 1'b0;
                        status_dbg   <= 16'd0;
                        read_addr    <= 15'h011b;
                        retry_count  <= 4'd0;
                        retry_clock_check <= 1'b1;
                        clkdet_first_valid <= 1'b0;
                        clkdet_first_read  <= 8'd0;
                        clkdet_last_read   <= 8'd0;
                        clkdet_bit0_mask   <= 10'd0;
                        clkdet_bit7_mask   <= 10'd0;
                        pll_read_seen      <= 1'b0;
                        pll_last_read      <= 8'd0;
                        id_read_data       <= 8'd0;
                        readback_index     <= 6'd0;
                        reinit_index       <= 4'd0;
                        link_reinit_final_check <= 1'b0;
                        readback_active    <= 1'b0;
                        final_pll_checked  <= 1'b0;
                        final_pll_lock_ok  <= 1'b0;
                        final_pll_readback_fail <= 1'b0;
                        rb_056e            <= 8'd0;
                        rb_056f            <= 8'd0;
                        rb_0570            <= 8'd0;
                        rb_0571            <= 8'd0;
                        rb_0572            <= 8'd0;
                        rb_0573            <= 8'd0;
                        rb_0574            <= 8'd0;
                        rb_0583            <= 8'd0;
                        rb_0584            <= 8'd0;
                        rb_0585            <= 8'd0;
                        rb_0586            <= 8'd0;
                        rb_0587            <= 8'd0;
                        rb_0588            <= 8'd0;
                        rb_0589            <= 8'd0;
                        rb_058a            <= 8'd0;
                        rb_058b            <= 8'd0;
                        rb_058c            <= 8'd0;
                        rb_058d            <= 8'd0;
                        rb_058e            <= 8'd0;
                        rb_058f            <= 8'd0;
                        rb_0590            <= 8'd0;
                        rb_0591            <= 8'd0;
                        rb_0592            <= 8'd0;
                        rb_05a0            <= 8'd0;
                        rb_05a1            <= 8'd0;
                        rb_05a2            <= 8'd0;
                        rb_05a3            <= 8'd0;
                        rb_05a4            <= 8'd0;
                        rb_05a5            <= 8'd0;
                        rb_05a6            <= 8'd0;
                        rb_05a7            <= 8'd0;
                        rb_05b0            <= 8'd0;
                        rb_05b2            <= 8'd0;
                        rb_05b3            <= 8'd0;
                        rb_05b5            <= 8'd0;
                        rb_05b6            <= 8'd0;
                        rb_05bf            <= 8'd0;
                        rb_05c0            <= 8'd0;
                        rb_05c1            <= 8'd0;
                        rb_05c2            <= 8'd0;
                        rb_05c3            <= 8'd0;
                        rb_05c8            <= 8'd0;
                        rb_05c9            <= 8'd0;
                        rb_05ca            <= 8'd0;
                        rb_05cb            <= 8'd0;
                        rb_0120            <= 8'd0;
                        rb_0128            <= 8'd0;
                        rb_0129            <= 8'd0;
                        rb_012a            <= 8'd0;
                        rb_1262            <= 8'd0;
                        busy         <= 1'b1;
                        table_start  <= 1'b1;
                        state        <= ST_RUN_TABLE;
                    end
                end

                ST_FAIL: begin
                    busy <= 1'b0;
                    ok   <= 1'b0;
                    fail <= 1'b1;
                    done <= 1'b1;
                    if (start) begin
                        done         <= 1'b0;
                        fail         <= 1'b0;
                        status_dbg   <= 16'd0;
                        read_addr    <= 15'h011b;
                        retry_count  <= 4'd0;
                        retry_clock_check <= 1'b1;
                        clkdet_first_valid <= 1'b0;
                        clkdet_first_read  <= 8'd0;
                        clkdet_last_read   <= 8'd0;
                        clkdet_bit0_mask   <= 10'd0;
                        clkdet_bit7_mask   <= 10'd0;
                        pll_read_seen      <= 1'b0;
                        pll_last_read      <= 8'd0;
                        id_read_data       <= 8'd0;
                        readback_index     <= 6'd0;
                        reinit_index       <= 4'd0;
                        link_reinit_final_check <= 1'b0;
                        readback_active    <= 1'b0;
                        final_pll_checked  <= 1'b0;
                        final_pll_lock_ok  <= 1'b0;
                        final_pll_readback_fail <= 1'b0;
                        rb_056e            <= 8'd0;
                        rb_056f            <= 8'd0;
                        rb_0570            <= 8'd0;
                        rb_0571            <= 8'd0;
                        rb_0572            <= 8'd0;
                        rb_0573            <= 8'd0;
                        rb_0574            <= 8'd0;
                        rb_0583            <= 8'd0;
                        rb_0584            <= 8'd0;
                        rb_0585            <= 8'd0;
                        rb_0586            <= 8'd0;
                        rb_0587            <= 8'd0;
                        rb_0588            <= 8'd0;
                        rb_0589            <= 8'd0;
                        rb_058a            <= 8'd0;
                        rb_058b            <= 8'd0;
                        rb_058c            <= 8'd0;
                        rb_058d            <= 8'd0;
                        rb_058e            <= 8'd0;
                        rb_058f            <= 8'd0;
                        rb_0590            <= 8'd0;
                        rb_0591            <= 8'd0;
                        rb_0592            <= 8'd0;
                        rb_05a0            <= 8'd0;
                        rb_05a1            <= 8'd0;
                        rb_05a2            <= 8'd0;
                        rb_05a3            <= 8'd0;
                        rb_05a4            <= 8'd0;
                        rb_05a5            <= 8'd0;
                        rb_05a6            <= 8'd0;
                        rb_05a7            <= 8'd0;
                        rb_05b0            <= 8'd0;
                        rb_05b2            <= 8'd0;
                        rb_05b3            <= 8'd0;
                        rb_05b5            <= 8'd0;
                        rb_05b6            <= 8'd0;
                        rb_05bf            <= 8'd0;
                        rb_05c0            <= 8'd0;
                        rb_05c1            <= 8'd0;
                        rb_05c2            <= 8'd0;
                        rb_05c3            <= 8'd0;
                        rb_05c8            <= 8'd0;
                        rb_05c9            <= 8'd0;
                        rb_05ca            <= 8'd0;
                        rb_05cb            <= 8'd0;
                        rb_0120            <= 8'd0;
                        rb_0128            <= 8'd0;
                        rb_0129            <= 8'd0;
                        rb_012a            <= 8'd0;
                        rb_1262            <= 8'd0;
                        busy         <= 1'b1;
                        table_start  <= 1'b1;
                        state        <= ST_RUN_TABLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
