module jesd_phy_axi_probe #(
    parameter integer REPEAT_WAIT_CYCLES = 1000000,
    parameter integer USE_QPLL0 = 1,
    parameter integer ENABLE_RX_POLARITY_CFG = 0,
    parameter [3:0] RX_POLARITY_CFG = 4'h0,
    parameter integer ENABLE_RX_POLARITY_SWEEP = 0,
    parameter integer RX_POLARITY_SWEEP_HOLD_CYCLES = 4000000,
    parameter integer RX_POLARITY_SWEEP_SETTLE_CYCLES = 400000,
    parameter integer RX_POLARITY_SWEEP_AUTO_FREEZE = 1,
    parameter integer PULSE_RX_SYS_RESET_ON_POLARITY = 1,
    parameter integer ENABLE_RX_LPMEN_CFG = 0,
    parameter [0:0] RX_LPMEN_CFG = 1'b1,
    parameter integer PULSE_RXDFELPMRESET_ON_RX_LPMEN = 1,
    parameter integer PULSE_RX_SYS_RESET_ON_RX_LPMEN = 1
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        rx_polarity_freeze,
    input  wire [3:0]  rx_gt_disperr,
    input  wire [3:0]  rx_gt_notintable,
    input  wire [3:0]  rx_gt_commadet,
    input  wire [3:0]  rx_gt_block_sync,
    output reg         running,
    output reg         done_seen,
    output reg         error_seen,
    output reg  [7:0]  state_dbg,
    output reg  [11:0] last_addr_dbg,
    output reg  [31:0] status_dbg,
    output reg  [31:0] txlinerate_dbg,
    output reg  [31:0] txrefclk_dbg,
    output reg  [31:0] ctrl_dbg,
    output reg  [31:0] fsm_dbg,
    output reg  [31:0] txctrl_dbg,
    output reg  [31:0] rxsweep_dbg,

    output wire [11:0] s_axi_awaddr,
    output wire        s_axi_awvalid,
    input  wire        s_axi_awready,
    output wire [31:0] s_axi_wdata,
    output wire        s_axi_wvalid,
    input  wire        s_axi_wready,
    input  wire [1:0]  s_axi_bresp,
    input  wire        s_axi_bvalid,
    output wire        s_axi_bready,
    output wire [11:0] s_axi_araddr,
    output wire        s_axi_arvalid,
    input  wire        s_axi_arready,
    input  wire [31:0] s_axi_rdata,
    input  wire [1:0]  s_axi_rresp,
    input  wire        s_axi_rvalid,
    output wire        s_axi_rready
);

    localparam [7:0] ST_IDLE          = 8'd0;
    localparam [7:0] ST_READ_NUM_IF   = 8'd1;
    localparam [7:0] ST_READ_STATUS   = 8'd2;
    localparam [7:0] ST_READ_LINERATE = 8'd3;
    localparam [7:0] ST_READ_REFCLK   = 8'd4;
    localparam [7:0] ST_READ_TXPLL    = 8'd5;
    localparam [7:0] ST_WRITE_SEL     = 8'd6;
    localparam [7:0] ST_READ_CPLLPD   = 8'd7;
    localparam [7:0] ST_READ_TXSYSRST = 8'd8;
    localparam [7:0] ST_READ_RXSYSRST = 8'd9;
    localparam [7:0] ST_READ_TXPLLSEL = 8'd10;
    localparam [7:0] ST_READ_RXPLLSEL = 8'd11;
    localparam [7:0] ST_WAIT_DONE     = 8'd13;
    localparam [7:0] ST_REPEAT_WAIT   = 8'd14;
    localparam [7:0] ST_INIT_SEL_ON   = 8'd15;
    localparam [7:0] ST_INIT_CPLL_ON  = 8'd16;
    localparam [7:0] ST_INIT_NEXT_ON  = 8'd17;
    localparam [7:0] ST_INIT_TXRST_ON = 8'd18;
    localparam [7:0] ST_INIT_WAIT_ON  = 8'd19;
    localparam [7:0] ST_INIT_SEL_OFF  = 8'd20;
    localparam [7:0] ST_INIT_CPLL_OFF = 8'd21;
    localparam [7:0] ST_INIT_NEXT_OFF = 8'd22;
    localparam [7:0] ST_INIT_TXRST_OFF = 8'd23;
    localparam [7:0] ST_INIT_WAIT_OFF = 8'd24;
    localparam [7:0] ST_INIT_RXPLLSEL = 8'd25;
    localparam [7:0] ST_INIT_COMMON_SEL = 8'd26;
    localparam [7:0] ST_INIT_QPLL0_ON   = 8'd27;
    localparam [7:0] ST_INIT_QPLL1_OFF  = 8'd28;
    localparam [7:0] ST_INIT_TXPLLSEL   = 8'd29;
    localparam [7:0] ST_READ_COMMON_SEL = 8'd30;
    localparam [7:0] ST_READ_QPLL0_PD   = 8'd31;
    localparam [7:0] ST_READ_QPLL1_PD   = 8'd32;
    localparam [7:0] ST_READ_TXPD       = 8'd33;
    localparam [7:0] ST_READ_TXINHIBIT  = 8'd34;
    localparam [7:0] ST_READ_TXOUTCLKSEL = 8'd35;
    localparam [7:0] ST_APPLY_RXPOL_SEL = 8'd36;
    localparam [7:0] ST_APPLY_RXPOL_WRITE = 8'd37;
    localparam [7:0] ST_APPLY_RXPOL_NEXT = 8'd38;
    localparam [7:0] ST_APPLY_RXRST_ON = 8'd39;
    localparam [7:0] ST_APPLY_RXRST_WAIT_ON = 8'd40;
    localparam [7:0] ST_APPLY_RXRST_OFF = 8'd41;
    localparam [7:0] ST_READ_RXPOLARITY = 8'd42;
    localparam [7:0] ST_APPLY_RXRST_SEL = 8'd43;
    localparam [7:0] ST_READ_RXLPMEN = 8'd44;
    localparam [7:0] ST_READ_RXDFELPMRESET = 8'd45;
    localparam [7:0] ST_READ_RXDFEHOLD = 8'd46;
    localparam [7:0] ST_APPLY_RXLPMEN_SEL = 8'd47;
    localparam [7:0] ST_APPLY_RXLPMEN_WRITE = 8'd48;
    localparam [7:0] ST_APPLY_RXDFELPMRESET_ON = 8'd49;
    localparam [7:0] ST_APPLY_RXDFELPMRESET_WAIT = 8'd50;
    localparam [7:0] ST_APPLY_RXDFELPMRESET_OFF = 8'd51;

    localparam [11:0] ADDR_COMMON_SEL    = 12'h020;
    localparam [11:0] ADDR_GT_SEL       = 12'h024;
    localparam [11:0] ADDR_NUM_IF       = 12'h00c;
    localparam [11:0] ADDR_PLL_STATUS   = 12'h080;
    localparam [11:0] ADDR_TXLINERATE   = 12'h0b0;
    localparam [11:0] ADDR_TXREFCLK     = 12'h0b8;
    localparam [11:0] ADDR_TXPLL        = 12'h0c0;
    localparam [11:0] ADDR_QPLL0_PD      = 12'h304;
    localparam [11:0] ADDR_QPLL1_PD      = 12'h308;
    localparam [11:0] ADDR_CPLLPD       = 12'h408;
    localparam [11:0] ADDR_TXPLLCLKSEL  = 12'h40c;
    localparam [11:0] ADDR_RXPLLCLKSEL  = 12'h410;
    localparam [11:0] ADDR_TX_SYS_RESET = 12'h420;
    localparam [11:0] ADDR_RX_SYS_RESET = 12'h424;
    localparam [11:0] ADDR_TXPD         = 12'h504;
    localparam [11:0] ADDR_TXINHIBIT    = 12'h50c;
    localparam [11:0] ADDR_TXOUTCLKSEL  = 12'h524;
    localparam [11:0] ADDR_RXPOLARITY   = 12'h604;
    localparam [11:0] ADDR_RXLPMEN      = 12'h608;
    localparam [11:0] ADDR_RXDFELPMRESET = 12'h60c;
    localparam [11:0] ADDR_RXDFEHOLD    = 12'h614;

    reg        master_start;
    reg        master_is_read;
    reg [11:0] master_addr;
    reg [31:0] master_wdata;
    wire       master_busy;
    wire       master_done;
    wire       master_error;
    wire [31:0] master_rdata;
    wire [1:0]  master_bresp;
    wire [1:0]  master_rresp;

    reg [7:0] state;
    reg [1:0] lane_idx;
    reg [31:0] repeat_wait;
    reg        init_done;
    reg [7:0]  num_if_dbg;
    reg [7:0]  txpll_dbg;
    reg        qpll0_pd_dbg;
    reg        qpll1_pd_dbg;
    reg [3:0]  lane_cpllpd;
    reg [7:0]  lane_txpllclksel;
    reg [7:0]  lane_rxpllclksel;
    reg [3:0]  lane_txsysrst;
    reg [3:0]  lane_rxsysrst;
    reg [3:0]  lane_txpd_any;
    reg [3:0]  lane_txinhibit;
    reg [11:0] lane_txoutclksel;
    reg [3:0]  lane_rxpolarity;
    reg [3:0]  lane_rxlpmen;
    reg [3:0]  lane_rxdfelpmreset;
    reg [3:0]  lane_rxdfe_hold_any;
    reg [3:0]  lane_rxoshold;
    reg [3:0]  lane_rxdfeagchold;
    reg [3:0]  rx_polarity_active;
    reg [3:0]  rx_polarity_program_value;
    reg [3:0]  rx_polarity_sweep_value;
    reg        rx_polarity_freeze_seen;
    reg        rx_sweep_best_valid;
    reg [3:0]  rx_sweep_best_polarity;
    reg [3:0]  rx_sweep_best_block_seen;
    reg [3:0]  rx_sweep_best_commadet_seen;
    reg [3:0]  rx_sweep_best_error_seen;
    reg [3:0]  rx_sweep_window_block_seen;
    reg [3:0]  rx_sweep_window_commadet_seen;
    reg [3:0]  rx_sweep_window_error_seen;
    reg [31:0] rx_sweep_window_error_count;
    reg [31:0] rx_sweep_best_error_count_full;
    reg [31:0] rx_sweep_settle_count;
    reg        rx_sweep_pass_done;
    reg [3:0]  rx_sweep_candidate_count;
    reg [15:0] rx_sweep_candidate_clean_map;
    reg [15:0] rx_sweep_candidate_commadet_map;

    wire       rx_polarity_cfg_en;
    wire       rx_lpmen_cfg_en;
    wire       rx_dfelpmreset_pulse_en;
    wire       rx_config_requires_reset;
    wire       rx_polarity_sweep_en;
    wire       rx_polarity_sweep_auto_freeze_en;
    wire [3:0] rx_polarity_sweep_next;
    wire [3:0] rx_sweep_error_now;
    wire [3:0] rx_sweep_window_block_next;
    wire [3:0] rx_sweep_window_commadet_next;
    wire [3:0] rx_sweep_window_error_next;
    wire [2:0] rx_sweep_window_block_count;
    wire [2:0] rx_sweep_window_commadet_count;
    wire [2:0] rx_sweep_window_error_lane_count;
    wire [2:0] rx_sweep_best_block_count;
    wire [2:0] rx_sweep_best_commadet_count;
    wire [2:0] rx_sweep_best_error_lane_count;
    wire [2:0] rx_sweep_error_now_count;
    wire       rx_sweep_window_is_better;
    wire       rx_sweep_last_candidate;
    wire [3:0] rx_sweep_selected_polarity;
    wire [15:0] rx_sweep_candidate_bit;
    wire       rx_sweep_error_any_now;
    wire       rx_sweep_sample_enable;
    wire [31:0] rx_sweep_window_error_count_next;

    assign rx_polarity_cfg_en = (ENABLE_RX_POLARITY_CFG != 0) ||
                                (ENABLE_RX_POLARITY_SWEEP != 0);
    assign rx_lpmen_cfg_en = (ENABLE_RX_LPMEN_CFG != 0);
    assign rx_dfelpmreset_pulse_en =
        (ENABLE_RX_LPMEN_CFG != 0) &&
        (PULSE_RXDFELPMRESET_ON_RX_LPMEN != 0);
    assign rx_config_requires_reset =
        ((PULSE_RX_SYS_RESET_ON_POLARITY != 0) && rx_polarity_cfg_en) ||
        ((PULSE_RX_SYS_RESET_ON_RX_LPMEN != 0) && rx_lpmen_cfg_en);
    assign rx_polarity_sweep_en = (ENABLE_RX_POLARITY_SWEEP != 0);
    assign rx_polarity_sweep_auto_freeze_en =
        (ENABLE_RX_POLARITY_SWEEP != 0) &&
        (RX_POLARITY_SWEEP_AUTO_FREEZE != 0);
    assign rx_polarity_sweep_next = rx_polarity_sweep_value + 4'd1;
    assign rx_sweep_error_now = rx_gt_disperr | rx_gt_notintable;
    assign rx_sweep_window_block_next =
        rx_sweep_window_block_seen | rx_gt_block_sync;
    assign rx_sweep_window_commadet_next =
        rx_sweep_window_commadet_seen | rx_gt_commadet;
    assign rx_sweep_window_error_next =
        rx_sweep_window_error_seen | rx_sweep_error_now;
    assign rx_sweep_window_block_count =
        popcount4(rx_sweep_window_block_next);
    assign rx_sweep_window_commadet_count =
        popcount4(rx_sweep_window_commadet_next);
    assign rx_sweep_window_error_lane_count =
        popcount4(rx_sweep_window_error_next);
    assign rx_sweep_best_block_count =
        popcount4(rx_sweep_best_block_seen);
    assign rx_sweep_best_commadet_count =
        popcount4(rx_sweep_best_commadet_seen);
    assign rx_sweep_best_error_lane_count =
        popcount4(rx_sweep_best_error_seen);
    assign rx_sweep_error_now_count =
        popcount4(rx_sweep_error_now);
    assign rx_sweep_error_any_now = |rx_sweep_error_now;
    assign rx_sweep_sample_enable = (rx_sweep_settle_count == 32'd0);
    assign rx_sweep_window_error_count_next =
        rx_sweep_window_error_count +
        (rx_sweep_sample_enable ? {29'd0, rx_sweep_error_now_count} :
                                  32'd0);
    assign rx_sweep_window_is_better =
        !rx_sweep_best_valid ||
        (rx_sweep_window_error_count_next < rx_sweep_best_error_count_full) ||
        ((rx_sweep_window_error_count_next == rx_sweep_best_error_count_full) &&
         (rx_sweep_window_block_count > rx_sweep_best_block_count)) ||
        ((rx_sweep_window_error_count_next == rx_sweep_best_error_count_full) &&
         (rx_sweep_window_block_count == rx_sweep_best_block_count) &&
         (rx_sweep_window_commadet_count > rx_sweep_best_commadet_count)) ||
        ((rx_sweep_window_error_count_next == rx_sweep_best_error_count_full) &&
         (rx_sweep_window_block_count == rx_sweep_best_block_count) &&
         (rx_sweep_window_commadet_count == rx_sweep_best_commadet_count) &&
         (rx_sweep_window_error_lane_count < rx_sweep_best_error_lane_count));
    assign rx_sweep_last_candidate = (rx_sweep_candidate_count == 4'hf);
    assign rx_sweep_selected_polarity =
        rx_sweep_window_is_better ? rx_polarity_active :
                                    rx_sweep_best_polarity;
    assign rx_sweep_candidate_bit = 16'h0001 << rx_polarity_active;

    axi_lite_rdwr_master #(
        .ADDR_W(12)
    ) u_master (
        .clk           (clk),
        .rst           (rst),
        .start         (master_start),
        .is_read       (master_is_read),
        .addr          (master_addr),
        .wdata         (master_wdata),
        .busy          (master_busy),
        .done          (master_done),
        .error         (master_error),
        .rdata         (master_rdata),
        .last_bresp    (master_bresp),
        .last_rresp    (master_rresp),
        .m_axi_awaddr  (s_axi_awaddr),
        .m_axi_awvalid (s_axi_awvalid),
        .m_axi_awready (s_axi_awready),
        .m_axi_wdata   (s_axi_wdata),
        .m_axi_wvalid  (s_axi_wvalid),
        .m_axi_wready  (s_axi_wready),
        .m_axi_bresp   (s_axi_bresp),
        .m_axi_bvalid  (s_axi_bvalid),
        .m_axi_bready  (s_axi_bready),
        .m_axi_araddr  (s_axi_araddr),
        .m_axi_arvalid (s_axi_arvalid),
        .m_axi_arready (s_axi_arready),
        .m_axi_rdata   (s_axi_rdata),
        .m_axi_rresp   (s_axi_rresp),
        .m_axi_rvalid  (s_axi_rvalid),
        .m_axi_rready  (s_axi_rready)
    );

    always @(posedge clk) begin
        if (rst) begin
            state              <= ST_IDLE;
            running            <= 1'b0;
            done_seen          <= 1'b0;
            error_seen         <= 1'b0;
            state_dbg          <= ST_IDLE;
            last_addr_dbg      <= 12'd0;
            status_dbg         <= 32'd0;
            txlinerate_dbg     <= 32'd0;
            txrefclk_dbg       <= 32'd0;
            ctrl_dbg           <= 32'd0;
            fsm_dbg            <= 32'd0;
            txctrl_dbg         <= 32'd0;
            rxsweep_dbg        <= 32'd0;
            master_start       <= 1'b0;
            master_is_read     <= 1'b1;
            master_addr        <= 12'd0;
            master_wdata       <= 32'd0;
            lane_idx           <= 2'd0;
            repeat_wait        <= 32'd0;
            init_done          <= 1'b0;
            num_if_dbg         <= 8'd0;
            txpll_dbg          <= 8'd0;
            qpll0_pd_dbg       <= 1'b0;
            qpll1_pd_dbg       <= 1'b0;
            lane_cpllpd        <= 4'd0;
            lane_txpllclksel   <= 8'd0;
            lane_rxpllclksel   <= 8'd0;
            lane_txsysrst      <= 4'd0;
            lane_rxsysrst      <= 4'd0;
            lane_txpd_any      <= 4'd0;
            lane_txinhibit     <= 4'd0;
            lane_txoutclksel   <= 12'd0;
            lane_rxpolarity    <= 4'd0;
            lane_rxlpmen       <= 4'd0;
            lane_rxdfelpmreset <= 4'd0;
            lane_rxdfe_hold_any <= 4'd0;
            lane_rxoshold      <= 4'd0;
            lane_rxdfeagchold  <= 4'd0;
            rx_polarity_active <= RX_POLARITY_CFG;
            rx_polarity_program_value <= RX_POLARITY_CFG;
            rx_polarity_sweep_value <= RX_POLARITY_CFG;
            rx_polarity_freeze_seen <= 1'b0;
            rx_sweep_best_valid <= 1'b0;
            rx_sweep_best_polarity <= RX_POLARITY_CFG;
            rx_sweep_best_block_seen <= 4'd0;
            rx_sweep_best_commadet_seen <= 4'd0;
            rx_sweep_best_error_seen <= 4'hf;
            rx_sweep_window_block_seen <= 4'd0;
            rx_sweep_window_commadet_seen <= 4'd0;
            rx_sweep_window_error_seen <= 4'd0;
            rx_sweep_window_error_count <= 32'd0;
            rx_sweep_best_error_count_full <= 32'hffffffff;
            rx_sweep_settle_count <= 32'd0;
            rx_sweep_pass_done <= 1'b0;
            rx_sweep_candidate_count <= 4'd0;
            rx_sweep_candidate_clean_map <= 16'd0;
            rx_sweep_candidate_commadet_map <= 16'd0;
        end else begin
            master_start <= 1'b0;
            state_dbg    <= state;
            ctrl_dbg     <= {
                qpll1_pd_dbg,
                qpll0_pd_dbg,
                2'b00,
                lane_rxpllclksel,
                lane_txpllclksel,
                lane_rxsysrst,
                lane_txsysrst,
                lane_cpllpd
            };
            fsm_dbg      <= {
                2'b00,
                master_bresp,
                master_rresp,
                master_error,
                master_busy,
                done_seen,
                error_seen,
                lane_idx,
                state,
                last_addr_dbg
            };
            txctrl_dbg   <= {
                4'hc,
                rx_lpmen_cfg_en,
                RX_LPMEN_CFG[0],
                rx_polarity_cfg_en,
                rx_sweep_pass_done,
                rx_polarity_active,
                lane_rxpolarity,
                lane_rxlpmen,
                lane_rxdfelpmreset,
                lane_rxdfe_hold_any,
                rx_sweep_best_error_count_full[3:0]
            };
            rxsweep_dbg  <= {
                lane_rxlpmen,
                lane_rxdfelpmreset,
                lane_rxoshold,
                lane_rxdfeagchold,
                lane_rxdfe_hold_any,
                rx_sweep_candidate_clean_map[11:0]
            };

            if (master_done && master_error) begin
                error_seen <= 1'b1;
            end
            rx_polarity_freeze_seen <= rx_polarity_freeze_seen |
                                       rx_polarity_freeze;

            case (state)
                ST_IDLE: begin
                    running <= 1'b0;
                    if (enable) begin
                        running       <= 1'b1;
                        lane_idx      <= 2'd0;
                        if (init_done) begin
                            state          <= ST_READ_NUM_IF;
                            master_addr    <= ADDR_NUM_IF;
                            last_addr_dbg  <= ADDR_NUM_IF;
                            master_is_read <= 1'b1;
                            master_start   <= 1'b1;
                        end else if (USE_QPLL0 == 0) begin
                            state          <= ST_INIT_SEL_ON;
                            master_addr    <= ADDR_GT_SEL;
                            last_addr_dbg  <= ADDR_GT_SEL;
                            master_wdata   <= 32'd0;
                            master_is_read <= 1'b0;
                            master_start   <= 1'b1;
                        end else begin
                            state          <= ST_INIT_COMMON_SEL;
                            master_addr    <= ADDR_COMMON_SEL;
                            last_addr_dbg  <= ADDR_COMMON_SEL;
                            master_wdata   <= 32'd0;
                            master_is_read <= 1'b0;
                            master_start   <= 1'b1;
                        end
                    end
                end

                ST_INIT_COMMON_SEL: begin
                    if (master_done) begin
                        state          <= ST_INIT_QPLL0_ON;
                        master_addr    <= ADDR_QPLL0_PD;
                        last_addr_dbg  <= ADDR_QPLL0_PD;
                        master_wdata   <= (USE_QPLL0 != 0) ? 32'd0 : 32'd1;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_INIT_QPLL0_ON: begin
                    if (master_done) begin
                        state          <= ST_INIT_QPLL1_OFF;
                        master_addr    <= ADDR_QPLL1_PD;
                        last_addr_dbg  <= ADDR_QPLL1_PD;
                        master_wdata   <= 32'd1;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_INIT_QPLL1_OFF: begin
                    if (master_done) begin
                        lane_idx       <= 2'd0;
                        state          <= ST_INIT_SEL_ON;
                        master_addr    <= ADDR_GT_SEL;
                        last_addr_dbg  <= ADDR_GT_SEL;
                        master_wdata   <= 32'd0;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_INIT_SEL_ON: begin
                    if (master_done) begin
                        state         <= ST_INIT_TXPLLSEL;
                        master_addr   <= ADDR_TXPLLCLKSEL;
                        last_addr_dbg <= ADDR_TXPLLCLKSEL;
                        master_wdata  <= (USE_QPLL0 != 0) ? 32'd3 : 32'd0;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_INIT_TXPLLSEL: begin
                    if (master_done) begin
                        state          <= ST_INIT_RXPLLSEL;
                        master_addr    <= ADDR_RXPLLCLKSEL;
                        last_addr_dbg  <= ADDR_RXPLLCLKSEL;
                        master_wdata   <= (USE_QPLL0 != 0) ? 32'd3 : 32'd0;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_INIT_RXPLLSEL: begin
                    if (master_done) begin
                        state          <= ST_INIT_CPLL_ON;
                        master_addr    <= ADDR_CPLLPD;
                        last_addr_dbg  <= ADDR_CPLLPD;
                        master_wdata   <= 32'd1;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_INIT_CPLL_ON: begin
                    if (master_done) begin
                        state <= ST_INIT_NEXT_ON;
                    end
                end

                ST_INIT_NEXT_ON: begin
                    if (lane_idx == 2'd3) begin
                        state          <= ST_INIT_TXRST_ON;
                        master_addr    <= ADDR_TX_SYS_RESET;
                        last_addr_dbg  <= ADDR_TX_SYS_RESET;
                        master_wdata   <= 32'd1;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end else begin
                        lane_idx       <= lane_idx + 1'b1;
                        state          <= ST_INIT_SEL_ON;
                        master_addr    <= ADDR_GT_SEL;
                        last_addr_dbg  <= ADDR_GT_SEL;
                        master_wdata   <= {30'd0, lane_idx + 1'b1};
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_INIT_TXRST_ON: begin
                    if (master_done) begin
                        repeat_wait <= 32'd10000;
                        state       <= ST_INIT_WAIT_ON;
                    end
                end

                ST_INIT_WAIT_ON: begin
                    if (repeat_wait == 32'd0) begin
                        lane_idx       <= 2'd0;
                        state          <= ST_INIT_SEL_OFF;
                        master_addr    <= ADDR_GT_SEL;
                        last_addr_dbg  <= ADDR_GT_SEL;
                        master_wdata   <= 32'd0;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end else begin
                        repeat_wait <= repeat_wait - 1'b1;
                    end
                end

                ST_INIT_SEL_OFF: begin
                    if (master_done) begin
                        state          <= ST_INIT_CPLL_OFF;
                        master_addr    <= ADDR_CPLLPD;
                        last_addr_dbg  <= ADDR_CPLLPD;
                        master_wdata   <= (USE_QPLL0 != 0) ? 32'd1 : 32'd0;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_INIT_CPLL_OFF: begin
                    if (master_done) begin
                        state <= ST_INIT_NEXT_OFF;
                    end
                end

                ST_INIT_NEXT_OFF: begin
                    if (lane_idx == 2'd3) begin
                        state          <= ST_INIT_TXRST_OFF;
                        master_addr    <= ADDR_TX_SYS_RESET;
                        last_addr_dbg  <= ADDR_TX_SYS_RESET;
                        master_wdata   <= 32'd0;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end else begin
                        lane_idx       <= lane_idx + 1'b1;
                        state          <= ST_INIT_SEL_OFF;
                        master_addr    <= ADDR_GT_SEL;
                        last_addr_dbg  <= ADDR_GT_SEL;
                        master_wdata   <= {30'd0, lane_idx + 1'b1};
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_INIT_TXRST_OFF: begin
                    if (master_done) begin
                        if (rx_polarity_cfg_en) begin
                            lane_idx                  <= 2'd0;
                            rx_polarity_program_value <= rx_polarity_active;
                            state                     <= ST_APPLY_RXPOL_SEL;
                            master_addr               <= ADDR_GT_SEL;
                            last_addr_dbg             <= ADDR_GT_SEL;
                            master_wdata              <= 32'd0;
                            master_is_read            <= 1'b0;
                            master_start              <= 1'b1;
                        end else if (rx_lpmen_cfg_en) begin
                            state          <= ST_APPLY_RXLPMEN_SEL;
                            master_addr    <= ADDR_GT_SEL;
                            last_addr_dbg  <= ADDR_GT_SEL;
                            master_wdata   <= 32'd0;
                            master_is_read <= 1'b0;
                            master_start   <= 1'b1;
                        end else begin
                            repeat_wait <= REPEAT_WAIT_CYCLES;
                            state       <= ST_INIT_WAIT_OFF;
                        end
                    end
                end

                ST_INIT_WAIT_OFF: begin
                    if (repeat_wait == 32'd0) begin
                        if (rx_polarity_sweep_en && !rx_sweep_pass_done) begin
                            rx_sweep_candidate_count <=
                                rx_sweep_candidate_count + 1'b1;
                            if (rx_sweep_window_error_count_next == 32'd0) begin
                                rx_sweep_candidate_clean_map <=
                                    rx_sweep_candidate_clean_map |
                                    rx_sweep_candidate_bit;
                            end
                            if (|rx_sweep_window_commadet_next) begin
                                rx_sweep_candidate_commadet_map <=
                                    rx_sweep_candidate_commadet_map |
                                    rx_sweep_candidate_bit;
                            end
                        end
                        if (rx_polarity_cfg_en &&
                            !rx_sweep_pass_done &&
                            rx_sweep_window_is_better) begin
                            rx_sweep_best_valid <= 1'b1;
                            rx_sweep_best_polarity <=
                                rx_polarity_active;
                            rx_sweep_best_block_seen <=
                                rx_sweep_window_block_next;
                            rx_sweep_best_commadet_seen <=
                                rx_sweep_window_commadet_next;
                            rx_sweep_best_error_seen <=
                                rx_sweep_window_error_next;
                            rx_sweep_best_error_count_full <=
                                rx_sweep_window_error_count_next;
                        end
                        if (rx_polarity_sweep_auto_freeze_en &&
                            !rx_sweep_pass_done &&
                            rx_sweep_last_candidate) begin
                            rx_sweep_pass_done       <= 1'b1;
                            rx_polarity_active      <= rx_sweep_selected_polarity;
                            rx_polarity_program_value <=
                                rx_sweep_selected_polarity;
                            lane_idx                <= 2'd0;
                            state                   <= ST_APPLY_RXPOL_SEL;
                            master_addr             <= ADDR_GT_SEL;
                            last_addr_dbg           <= ADDR_GT_SEL;
                            master_wdata            <= 32'd0;
                            master_is_read          <= 1'b0;
                            master_start            <= 1'b1;
                        end else begin
                            init_done      <= 1'b1;
                            lane_idx       <= 2'd0;
                            state          <= ST_READ_NUM_IF;
                            master_addr    <= ADDR_NUM_IF;
                            last_addr_dbg  <= ADDR_NUM_IF;
                            master_is_read <= 1'b1;
                            master_start   <= 1'b1;
                        end
                    end else begin
                        if (rx_polarity_cfg_en && !rx_sweep_pass_done) begin
                            if (rx_sweep_settle_count != 32'd0) begin
                                rx_sweep_settle_count <=
                                    rx_sweep_settle_count - 1'b1;
                            end else begin
                                rx_sweep_window_block_seen <=
                                    rx_sweep_window_block_next;
                                rx_sweep_window_commadet_seen <=
                                    rx_sweep_window_commadet_next;
                                rx_sweep_window_error_seen <=
                                    rx_sweep_window_error_next;
                                rx_sweep_window_error_count <=
                                    rx_sweep_window_error_count_next;
                            end
                        end
                        repeat_wait <= repeat_wait - 1'b1;
                    end
                end

                ST_READ_NUM_IF: begin
                    if (master_done) begin
                        num_if_dbg     <= master_rdata[7:0];
                        state          <= ST_READ_STATUS;
                        master_addr    <= ADDR_PLL_STATUS;
                        last_addr_dbg  <= ADDR_PLL_STATUS;
                        master_is_read <= 1'b1;
                        master_start   <= 1'b1;
                    end
                end

                ST_READ_STATUS: begin
                    if (master_done) begin
                        status_dbg     <= master_rdata;
                        state          <= ST_READ_LINERATE;
                        master_addr    <= ADDR_TXLINERATE;
                        last_addr_dbg  <= ADDR_TXLINERATE;
                        master_is_read <= 1'b1;
                        master_start   <= 1'b1;
                    end
                end

                ST_READ_LINERATE: begin
                    if (master_done) begin
                        txlinerate_dbg <= master_rdata;
                        state          <= ST_READ_REFCLK;
                        master_addr    <= ADDR_TXREFCLK;
                        last_addr_dbg  <= ADDR_TXREFCLK;
                        master_is_read <= 1'b1;
                        master_start   <= 1'b1;
                    end
                end

                ST_READ_REFCLK: begin
                    if (master_done) begin
                        txrefclk_dbg   <= master_rdata;
                        state          <= ST_READ_TXPLL;
                        master_addr    <= ADDR_TXPLL;
                        last_addr_dbg  <= ADDR_TXPLL;
                        master_is_read <= 1'b1;
                        master_start   <= 1'b1;
                    end
                end

                ST_READ_TXPLL: begin
                    if (master_done) begin
                        txpll_dbg      <= master_rdata[7:0];
                        if (USE_QPLL0 != 0) begin
                            state          <= ST_READ_COMMON_SEL;
                            master_addr    <= ADDR_COMMON_SEL;
                            last_addr_dbg  <= ADDR_COMMON_SEL;
                            master_wdata   <= 32'd0;
                            master_is_read <= 1'b0;
                            master_start   <= 1'b1;
                        end else begin
                            lane_idx       <= 2'd0;
                            state          <= ST_WRITE_SEL;
                            master_addr    <= ADDR_GT_SEL;
                            last_addr_dbg  <= ADDR_GT_SEL;
                            master_wdata   <= 32'd0;
                            master_is_read <= 1'b0;
                            master_start   <= 1'b1;
                        end
                    end
                end

                ST_READ_COMMON_SEL: begin
                    if (master_done) begin
                        state          <= ST_READ_QPLL0_PD;
                        master_addr    <= ADDR_QPLL0_PD;
                        last_addr_dbg  <= ADDR_QPLL0_PD;
                        master_is_read <= 1'b1;
                        master_start   <= 1'b1;
                    end
                end

                ST_READ_QPLL0_PD: begin
                    if (master_done) begin
                        qpll0_pd_dbg   <= master_rdata[0];
                        state          <= ST_READ_QPLL1_PD;
                        master_addr    <= ADDR_QPLL1_PD;
                        last_addr_dbg  <= ADDR_QPLL1_PD;
                        master_is_read <= 1'b1;
                        master_start   <= 1'b1;
                    end
                end

                ST_READ_QPLL1_PD: begin
                    if (master_done) begin
                        qpll1_pd_dbg   <= master_rdata[0];
                        lane_idx       <= 2'd0;
                        state          <= ST_WRITE_SEL;
                        master_addr    <= ADDR_GT_SEL;
                        last_addr_dbg  <= ADDR_GT_SEL;
                        master_wdata   <= 32'd0;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_WRITE_SEL: begin
                    if (master_done) begin
                        state          <= ST_READ_CPLLPD;
                        master_addr    <= ADDR_CPLLPD;
                        last_addr_dbg  <= ADDR_CPLLPD;
                        master_is_read <= 1'b1;
                        master_start   <= 1'b1;
                    end
                end

                ST_READ_CPLLPD: begin
                    if (master_done) begin
                        lane_cpllpd[lane_idx] <= master_rdata[0];
                        state                 <= ST_READ_TXPLLSEL;
                        master_addr           <= ADDR_TXPLLCLKSEL;
                        last_addr_dbg         <= ADDR_TXPLLCLKSEL;
                        master_is_read        <= 1'b1;
                        master_start          <= 1'b1;
                    end
                end

                ST_READ_TXPLLSEL: begin
                    if (master_done) begin
                        lane_txpllclksel[{lane_idx, 1'b0} +: 2] <= master_rdata[1:0];
                        state                 <= ST_READ_RXPLLSEL;
                        master_addr           <= ADDR_RXPLLCLKSEL;
                        last_addr_dbg         <= ADDR_RXPLLCLKSEL;
                        master_is_read        <= 1'b1;
                        master_start          <= 1'b1;
                    end
                end

                ST_READ_RXPLLSEL: begin
                    if (master_done) begin
                        lane_rxpllclksel[{lane_idx, 1'b0} +: 2] <= master_rdata[1:0];
                        state                 <= ST_READ_TXSYSRST;
                        master_addr           <= ADDR_TX_SYS_RESET;
                        last_addr_dbg         <= ADDR_TX_SYS_RESET;
                        master_is_read        <= 1'b1;
                        master_start          <= 1'b1;
                    end
                end

                ST_READ_TXSYSRST: begin
                    if (master_done) begin
                        lane_txsysrst[lane_idx] <= master_rdata[0];
                        state                   <= ST_READ_RXSYSRST;
                        master_addr             <= ADDR_RX_SYS_RESET;
                        last_addr_dbg           <= ADDR_RX_SYS_RESET;
                        master_is_read          <= 1'b1;
                        master_start            <= 1'b1;
                    end
                end

                ST_READ_RXSYSRST: begin
                    if (master_done) begin
                        lane_rxsysrst[lane_idx] <= master_rdata[0];
                        state                 <= ST_READ_RXPOLARITY;
                        master_addr           <= ADDR_RXPOLARITY;
                        last_addr_dbg         <= ADDR_RXPOLARITY;
                        master_is_read        <= 1'b1;
                        master_start          <= 1'b1;
                    end
                end

                ST_READ_RXPOLARITY: begin
                    if (master_done) begin
                        lane_rxpolarity[lane_idx] <= master_rdata[0];
                        state                 <= ST_READ_RXLPMEN;
                        master_addr           <= ADDR_RXLPMEN;
                        last_addr_dbg         <= ADDR_RXLPMEN;
                        master_is_read        <= 1'b1;
                        master_start          <= 1'b1;
                    end
                end

                ST_READ_RXLPMEN: begin
                    if (master_done) begin
                        lane_rxlpmen[lane_idx] <= master_rdata[0];
                        state                 <= ST_READ_RXDFELPMRESET;
                        master_addr           <= ADDR_RXDFELPMRESET;
                        last_addr_dbg         <= ADDR_RXDFELPMRESET;
                        master_is_read        <= 1'b1;
                        master_start          <= 1'b1;
                    end
                end

                ST_READ_RXDFELPMRESET: begin
                    if (master_done) begin
                        lane_rxdfelpmreset[lane_idx] <= master_rdata[0];
                        state                 <= ST_READ_RXDFEHOLD;
                        master_addr           <= ADDR_RXDFEHOLD;
                        last_addr_dbg         <= ADDR_RXDFEHOLD;
                        master_is_read        <= 1'b1;
                        master_start          <= 1'b1;
                    end
                end

                ST_READ_RXDFEHOLD: begin
                    if (master_done) begin
                        lane_rxdfe_hold_any[lane_idx] <= |master_rdata[20:2];
                        lane_rxoshold[lane_idx] <= master_rdata[16];
                        lane_rxdfeagchold[lane_idx] <= master_rdata[17];
                        state                 <= ST_READ_TXPD;
                        master_addr           <= ADDR_TXPD;
                        last_addr_dbg         <= ADDR_TXPD;
                        master_is_read        <= 1'b1;
                        master_start          <= 1'b1;
                    end
                end

                ST_READ_TXPD: begin
                    if (master_done) begin
                        lane_txpd_any[lane_idx] <= |master_rdata[1:0];
                        state                   <= ST_READ_TXINHIBIT;
                        master_addr             <= ADDR_TXINHIBIT;
                        last_addr_dbg           <= ADDR_TXINHIBIT;
                        master_is_read          <= 1'b1;
                        master_start            <= 1'b1;
                    end
                end

                ST_READ_TXINHIBIT: begin
                    if (master_done) begin
                        lane_txinhibit[lane_idx] <= master_rdata[0];
                        state                    <= ST_READ_TXOUTCLKSEL;
                        master_addr              <= ADDR_TXOUTCLKSEL;
                        last_addr_dbg            <= ADDR_TXOUTCLKSEL;
                        master_is_read           <= 1'b1;
                        master_start             <= 1'b1;
                    end
                end

                ST_READ_TXOUTCLKSEL: begin
                    if (master_done) begin
                        case (lane_idx)
                            2'd0: lane_txoutclksel[2:0]   <= master_rdata[2:0];
                            2'd1: lane_txoutclksel[5:3]   <= master_rdata[2:0];
                            2'd2: lane_txoutclksel[8:6]   <= master_rdata[2:0];
                            default: lane_txoutclksel[11:9] <= master_rdata[2:0];
                        endcase
                        if (lane_idx == 2'd3) begin
                            state       <= ST_WAIT_DONE;
                            done_seen   <= 1'b1;
                        end else begin
                            lane_idx       <= lane_idx + 1'b1;
                            state          <= ST_WRITE_SEL;
                            master_addr    <= ADDR_GT_SEL;
                            last_addr_dbg  <= ADDR_GT_SEL;
                            master_wdata   <= {30'd0, lane_idx + 1'b1};
                            master_is_read <= 1'b0;
                            master_start   <= 1'b1;
                        end
                    end
                end

                ST_WAIT_DONE: begin
                    if (rx_polarity_sweep_en &&
                        !rx_sweep_pass_done) begin
                        lane_idx                  <= 2'd0;
                        rx_polarity_sweep_value   <= rx_polarity_sweep_next;
                        rx_polarity_active        <= rx_polarity_sweep_next;
                        rx_polarity_program_value <= rx_polarity_sweep_next;
                        state                     <= ST_APPLY_RXPOL_SEL;
                        master_addr               <= ADDR_GT_SEL;
                        last_addr_dbg             <= ADDR_GT_SEL;
                        master_wdata              <= 32'd0;
                        master_is_read            <= 1'b0;
                        master_start              <= 1'b1;
                    end else begin
                        repeat_wait <= REPEAT_WAIT_CYCLES;
                        state       <= ST_REPEAT_WAIT;
                    end
                end

                ST_REPEAT_WAIT: begin
                    if (!enable) begin
                        state <= ST_IDLE;
                    end else if (repeat_wait == 32'd0) begin
                        lane_idx       <= 2'd0;
                        state          <= ST_READ_NUM_IF;
                        master_addr    <= ADDR_NUM_IF;
                        last_addr_dbg  <= ADDR_NUM_IF;
                        master_is_read <= 1'b1;
                        master_start   <= 1'b1;
                    end else begin
                        repeat_wait <= repeat_wait - 1'b1;
                    end
                end

                ST_APPLY_RXPOL_SEL: begin
                    if (master_done) begin
                        state          <= ST_APPLY_RXPOL_WRITE;
                        master_addr    <= ADDR_RXPOLARITY;
                        last_addr_dbg  <= ADDR_RXPOLARITY;
                        master_wdata   <= {31'd0, rx_polarity_program_value[lane_idx]};
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_APPLY_RXPOL_WRITE: begin
                    if (master_done) begin
                        if (!master_error) begin
                            lane_rxpolarity[lane_idx] <=
                                rx_polarity_program_value[lane_idx];
                        end
                        state <= ST_APPLY_RXPOL_NEXT;
                    end
                end

                ST_APPLY_RXPOL_NEXT: begin
                    if (lane_idx == 2'd3) begin
                        if (rx_lpmen_cfg_en) begin
                            state          <= ST_APPLY_RXLPMEN_SEL;
                            master_addr    <= ADDR_GT_SEL;
                            last_addr_dbg  <= ADDR_GT_SEL;
                            master_wdata   <= 32'd0;
                            master_is_read <= 1'b0;
                            master_start   <= 1'b1;
                        end else if (PULSE_RX_SYS_RESET_ON_POLARITY != 0) begin
                            lane_idx       <= 2'd0;
                            state          <= ST_APPLY_RXRST_SEL;
                            master_addr    <= ADDR_GT_SEL;
                            last_addr_dbg  <= ADDR_GT_SEL;
                            master_wdata   <= 32'd0;
                            master_is_read <= 1'b0;
                            master_start   <= 1'b1;
                        end else begin
                            rx_sweep_window_block_seen <= 4'd0;
                            rx_sweep_window_commadet_seen <= 4'd0;
                            rx_sweep_window_error_seen <= 4'd0;
                            rx_sweep_window_error_count <= 32'd0;
                            rx_sweep_settle_count <=
                                (rx_polarity_sweep_en && !rx_sweep_pass_done) ?
                                RX_POLARITY_SWEEP_SETTLE_CYCLES : 32'd0;
                            repeat_wait <= (rx_polarity_sweep_en &&
                                            !rx_sweep_pass_done) ?
                                           RX_POLARITY_SWEEP_HOLD_CYCLES :
                                           REPEAT_WAIT_CYCLES;
                            state       <= ST_INIT_WAIT_OFF;
                        end
                    end else begin
                        lane_idx       <= lane_idx + 1'b1;
                        state          <= ST_APPLY_RXPOL_SEL;
                        master_addr    <= ADDR_GT_SEL;
                        last_addr_dbg  <= ADDR_GT_SEL;
                        master_wdata   <= {30'd0, lane_idx + 1'b1};
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_APPLY_RXLPMEN_SEL: begin
                    if (master_done) begin
                        state          <= ST_APPLY_RXLPMEN_WRITE;
                        master_addr    <= ADDR_RXLPMEN;
                        last_addr_dbg  <= ADDR_RXLPMEN;
                        master_wdata   <= {31'd0, RX_LPMEN_CFG[0]};
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_APPLY_RXLPMEN_WRITE: begin
                    if (master_done) begin
                        if (!master_error) begin
                            lane_rxlpmen <= {4{RX_LPMEN_CFG[0]}};
                        end
                        if (rx_dfelpmreset_pulse_en) begin
                            state          <= ST_APPLY_RXDFELPMRESET_ON;
                            master_addr    <= ADDR_RXDFELPMRESET;
                            last_addr_dbg  <= ADDR_RXDFELPMRESET;
                            master_wdata   <= 32'd1;
                            master_is_read <= 1'b0;
                            master_start   <= 1'b1;
                        end else if (rx_config_requires_reset) begin
                            lane_idx       <= 2'd0;
                            state          <= ST_APPLY_RXRST_SEL;
                            master_addr    <= ADDR_GT_SEL;
                            last_addr_dbg  <= ADDR_GT_SEL;
                            master_wdata   <= 32'd0;
                            master_is_read <= 1'b0;
                            master_start   <= 1'b1;
                        end else begin
                            rx_sweep_window_block_seen <= 4'd0;
                            rx_sweep_window_commadet_seen <= 4'd0;
                            rx_sweep_window_error_seen <= 4'd0;
                            rx_sweep_window_error_count <= 32'd0;
                            rx_sweep_settle_count <=
                                (rx_polarity_sweep_en && !rx_sweep_pass_done) ?
                                RX_POLARITY_SWEEP_SETTLE_CYCLES : 32'd0;
                            repeat_wait <= (rx_polarity_sweep_en &&
                                            !rx_sweep_pass_done) ?
                                           RX_POLARITY_SWEEP_HOLD_CYCLES :
                                           REPEAT_WAIT_CYCLES;
                            state       <= ST_INIT_WAIT_OFF;
                        end
                    end
                end

                ST_APPLY_RXDFELPMRESET_ON: begin
                    if (master_done) begin
                        if (!master_error) begin
                            lane_rxdfelpmreset <= 4'hf;
                        end
                        repeat_wait <= 32'd10000;
                        state       <= ST_APPLY_RXDFELPMRESET_WAIT;
                    end
                end

                ST_APPLY_RXDFELPMRESET_WAIT: begin
                    if (repeat_wait == 32'd0) begin
                        state          <= ST_APPLY_RXDFELPMRESET_OFF;
                        master_addr    <= ADDR_RXDFELPMRESET;
                        last_addr_dbg  <= ADDR_RXDFELPMRESET;
                        master_wdata   <= 32'd0;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end else begin
                        repeat_wait <= repeat_wait - 1'b1;
                    end
                end

                ST_APPLY_RXDFELPMRESET_OFF: begin
                    if (master_done) begin
                        if (!master_error) begin
                            lane_rxdfelpmreset <= 4'd0;
                        end
                        if (rx_config_requires_reset) begin
                            lane_idx       <= 2'd0;
                            state          <= ST_APPLY_RXRST_SEL;
                            master_addr    <= ADDR_GT_SEL;
                            last_addr_dbg  <= ADDR_GT_SEL;
                            master_wdata   <= 32'd0;
                            master_is_read <= 1'b0;
                            master_start   <= 1'b1;
                        end else begin
                            rx_sweep_window_block_seen <= 4'd0;
                            rx_sweep_window_commadet_seen <= 4'd0;
                            rx_sweep_window_error_seen <= 4'd0;
                            rx_sweep_window_error_count <= 32'd0;
                            rx_sweep_settle_count <=
                                (rx_polarity_sweep_en && !rx_sweep_pass_done) ?
                                RX_POLARITY_SWEEP_SETTLE_CYCLES : 32'd0;
                            repeat_wait <= (rx_polarity_sweep_en &&
                                            !rx_sweep_pass_done) ?
                                           RX_POLARITY_SWEEP_HOLD_CYCLES :
                                           REPEAT_WAIT_CYCLES;
                            state       <= ST_INIT_WAIT_OFF;
                        end
                    end
                end

                ST_APPLY_RXRST_SEL: begin
                    if (master_done) begin
                        state          <= ST_APPLY_RXRST_ON;
                        master_addr    <= ADDR_RX_SYS_RESET;
                        last_addr_dbg  <= ADDR_RX_SYS_RESET;
                        master_wdata   <= 32'd1;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end
                end

                ST_APPLY_RXRST_ON: begin
                    if (master_done) begin
                        repeat_wait <= 32'd10000;
                        state       <= ST_APPLY_RXRST_WAIT_ON;
                    end
                end

                ST_APPLY_RXRST_WAIT_ON: begin
                    if (repeat_wait == 32'd0) begin
                        state          <= ST_APPLY_RXRST_OFF;
                        master_addr    <= ADDR_RX_SYS_RESET;
                        last_addr_dbg  <= ADDR_RX_SYS_RESET;
                        master_wdata   <= 32'd0;
                        master_is_read <= 1'b0;
                        master_start   <= 1'b1;
                    end else begin
                        repeat_wait <= repeat_wait - 1'b1;
                    end
                end

                ST_APPLY_RXRST_OFF: begin
                    if (master_done) begin
                        if (lane_idx == 2'd3) begin
                            rx_sweep_window_block_seen <= 4'd0;
                            rx_sweep_window_commadet_seen <= 4'd0;
                            rx_sweep_window_error_seen <= 4'd0;
                            rx_sweep_window_error_count <= 32'd0;
                            rx_sweep_settle_count <=
                                (rx_polarity_sweep_en && !rx_sweep_pass_done) ?
                                RX_POLARITY_SWEEP_SETTLE_CYCLES : 32'd0;
                            repeat_wait <= (rx_polarity_sweep_en &&
                                            !rx_sweep_pass_done) ?
                                           RX_POLARITY_SWEEP_HOLD_CYCLES :
                                           REPEAT_WAIT_CYCLES;
                            state       <= ST_INIT_WAIT_OFF;
                        end else begin
                            lane_idx       <= lane_idx + 1'b1;
                            state          <= ST_APPLY_RXRST_SEL;
                            master_addr    <= ADDR_GT_SEL;
                            last_addr_dbg  <= ADDR_GT_SEL;
                            master_wdata   <= {30'd0, lane_idx + 1'b1};
                            master_is_read <= 1'b0;
                            master_start   <= 1'b1;
                        end
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    function [2:0] popcount4;
        input [3:0] value;
        begin
            popcount4 = {2'b00, value[0]} +
                        {2'b00, value[1]} +
                        {2'b00, value[2]} +
                        {2'b00, value[3]};
        end
    endfunction

endmodule
