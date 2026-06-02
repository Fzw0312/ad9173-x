`timescale 1ns/1ps

module ku5p_bringup_top (
    input  wire       sys_clk_p,
    input  wire       sys_clk_n,
    input  wire       jesd_refclk_p,
    input  wire       jesd_refclk_n,
    input  wire       sysref2_p,
    input  wire       sysref2_n,
    input  wire       dac_sync0_p,
    input  wire       dac_sync0_n,
    input  wire       dac_sync1_p,
    input  wire       dac_sync1_n,
    output wire [7:0] dac_tx_p,
    output wire [7:0] dac_tx_n,
    output wire       clock_cs,
    output wire       clock_sclk,
    inout  wire       clock_sdio,
    output wire       dac_cs,
    output wire       dac_sclk,
    inout  wire       dac_sdio,
    input  wire       dac_sdo,
    output reg        txen_0,
    output reg        txen_1,
    output wire       phy1_txck,
    output wire       phy1_txctl,
    output wire [3:0] phy1_txd,
    input  wire       phy1_rxck,
    input  wire       phy1_rxctl,
    input  wire [3:0] phy1_rxd,
    output wire       phy1_mdc,
    inout  wire       phy1_mdio
);

    localparam integer SYS_CLK_HZ = 200_000_000;
    localparam integer MS_TICKS   = SYS_CLK_HZ / 1000;
    localparam integer SPI_CLK_DIV = 50;

    localparam integer BOOT_WAIT_MS = 5;
    localparam integer HOLD_WAIT_MS = 10;
    localparam integer JESD_RELEASE_STABLE_MS = 1;
    localparam integer JESD_READY_STABLE_MS   = 1;
    localparam integer JESD_RETRY_MISSING_MS  = 50;
    localparam integer JESD_RETRY_RESET_MS    = 5;
    localparam integer JESD_USE_QPLL          = 1;

    localparam integer BOOT_WAIT_TICKS = BOOT_WAIT_MS * MS_TICKS;
    localparam integer HOLD_WAIT_TICKS = HOLD_WAIT_MS * MS_TICKS;
    localparam integer JESD_RELEASE_STABLE_TICKS =
        JESD_RELEASE_STABLE_MS * MS_TICKS;
    localparam integer JESD_READY_STABLE_TICKS =
        JESD_READY_STABLE_MS * MS_TICKS;
    localparam integer JESD_RETRY_MISSING_TICKS =
        JESD_RETRY_MISSING_MS * MS_TICKS;
    localparam integer JESD_RETRY_RESET_TICKS =
        JESD_RETRY_RESET_MS * MS_TICKS;

    localparam [3:0] ST_BOOT       = 4'd0;
    localparam [3:0] ST_START_HMC  = 4'd1;
    localparam [3:0] ST_WAIT_HMC   = 4'd2;
    localparam [3:0] ST_HOLD_DAC   = 4'd3;
    localparam [3:0] ST_START_DAC  = 4'd4;
    localparam [3:0] ST_WAIT_DAC   = 4'd5;
    localparam [3:0] ST_START_JESD = 4'd6;
    localparam [3:0] ST_WAIT_JESD  = 4'd7;
    localparam [3:0] ST_RUN        = 4'd8;
    localparam [3:0] ST_FAIL       = 4'd9;

    wire sys_clk_ibuf;
    wire sys_clk;
    wire jesd_refclk;
    wire jesd_refclk_mon_clk;
    wire jesd_odiv2_clk;
    wire jesd_core_clk;
    wire jesd_txoutclk0;
    wire jesd_txoutclk1;
    wire jesd_txoutclk_mon_clk0;
    wire jesd_txoutclk_mon_clk1;
    wire eth_clk_125;
    wire eth_clk_125_90;
    wire eth_clk_locked;
    wire sysref2_i;
    wire dac_sync0_i;
    wire dac_sync1_raw_i;
    wire dac_sync1_i;

    wire init_rst;
    wire eth_rst;
    wire jesd_axi_aresetn;

    wire clock_sdio_i;
    wire clock_sdio_o;
    wire clock_sdio_oe;
    wire dac_sdio_i;
    wire dac_init_sdio_o;
    wire dac_init_sdio_oe;
    wire dac_init_sclk;
    wire dac_init_cs;

    reg [3:0]  state;
    reg [31:0] boot_count;
    reg [31:0] hold_count;
    reg        start_hmc;
    reg        start_dac;
    reg        start_jesd0;
    reg        start_jesd1;
    reg        jesd_release;
    reg        jesd_cfg_done_seen;
    reg [31:0] jesd_release_stable_count;
    reg [31:0] jesd_links_ready_stable_count;
    reg [31:0] jesd_pll_missing_count;
    reg [31:0] jesd_retry_reset_count;
    reg [15:0] jesd_retry_count;

    wire hmc_busy;
    wire hmc_done;
    wire hmc_ok;
    wire hmc_fail;
    wire dac_busy;
    wire dac_done;
    wire dac_init_ok;
    wire dac_init_fail;
    wire jesd_busy0;
    wire jesd_done0;
    wire jesd_busy1;
    wire jesd_done1;

    wire [11:0] jesd0_s_axi_awaddr;
    wire        jesd0_s_axi_awvalid;
    wire        jesd0_s_axi_awready;
    wire [31:0] jesd0_s_axi_wdata;
    wire [3:0]  jesd0_s_axi_wstrb;
    wire        jesd0_s_axi_wvalid;
    wire        jesd0_s_axi_wready;
    wire [1:0]  jesd0_s_axi_bresp;
    wire        jesd0_s_axi_bvalid;
    wire        jesd0_s_axi_bready;

    wire [11:0] jesd1_s_axi_awaddr;
    wire        jesd1_s_axi_awvalid;
    wire        jesd1_s_axi_awready;
    wire [31:0] jesd1_s_axi_wdata;
    wire [3:0]  jesd1_s_axi_wstrb;
    wire        jesd1_s_axi_wvalid;
    wire        jesd1_s_axi_wready;
    wire [1:0]  jesd1_s_axi_bresp;
    wire        jesd1_s_axi_bvalid;
    wire        jesd1_s_axi_bready;

    wire [11:0] phy0_s_axi_awaddr;
    wire        phy0_s_axi_awvalid;
    wire        phy0_s_axi_awready;
    wire [31:0] phy0_s_axi_wdata;
    wire        phy0_s_axi_wvalid;
    wire        phy0_s_axi_wready;
    wire [1:0]  phy0_s_axi_bresp;
    wire        phy0_s_axi_bvalid;
    wire        phy0_s_axi_bready;
    wire [11:0] phy1_s_axi_awaddr;
    wire        phy1_s_axi_awvalid;
    wire        phy1_s_axi_awready;
    wire [31:0] phy1_s_axi_wdata;
    wire        phy1_s_axi_wvalid;
    wire        phy1_s_axi_wready;
    wire [1:0]  phy1_s_axi_bresp;
    wire        phy1_s_axi_bvalid;
    wire        phy1_s_axi_bready;
    wire        phy0_axi_done_seen;
    wire        phy1_axi_done_seen;
    wire        phy_axi_cfg_done;

    wire [255:0] tx_pattern_data;
    wire [127:0] jesd_tx_data0;
    wire [127:0] jesd_tx_data1;
    wire [1:0]   tx_tone_advance;
    wire [1:0]   tx_tone_reset;

    wire        jesd_tx_ready0;
    wire        jesd_tx_ready1;
    wire        jesd_tx_aresetn0;
    wire        jesd_tx_aresetn1;
    wire        jesd_tx_reset_gt0;
    wire        jesd_tx_reset_gt1;
    wire        jesd_tx_reset_done0;
    wire        jesd_tx_reset_done1;
    wire        jesd_gt_powergood0;
    wire        jesd_gt_powergood1;
    wire [3:0]  jesd_gt_txresetdone0;
    wire [3:0]  jesd_gt_txresetdone1;
    wire [3:0]  jesd_gt_cplllock0;
    wire [3:0]  jesd_gt_cplllock1;
    wire        jesd_qpll0_lock0;
    wire        jesd_qpll1_lock0;
    wire        jesd_qpll0_lock1;
    wire        jesd_qpll1_lock1;
    wire [3:0]  jesd_qpll_lock_raw;
    wire [7:0]  jesd_gt_plllock;
    wire        jesd_cfg_done;
    wire        jesd_release_ready;
    wire        jesd_pll_ready;
    wire        jesd_links_ready;

    reg [1:0] jesd_aresetn_meta;
    reg [1:0] jesd_tready_meta;
    reg [1:0] jesd_tx_reset_done_meta;
    reg [1:0] jesd_gt_powergood_meta;
    reg [7:0] jesd_gt_txresetdone_meta;
    reg [7:0] jesd_cplllock_meta;
    reg [3:0] jesd_qpll_lock_meta;
    reg [1:0] jesd_aresetn_dbg;
    reg [1:0] jesd_tready_dbg;
    reg [1:0] jesd_tx_reset_done_dbg;
    reg [1:0] jesd_gt_powergood_dbg;
    reg [7:0] jesd_gt_txresetdone_dbg;
    reg [7:0] jesd_cplllock_dbg;
    reg [3:0] jesd_qpll_lock_dbg;
    (* keep = "true" *) reg [7:0] jesd_txoutclk_heartbeat0;
    (* keep = "true" *) reg [7:0] jesd_txoutclk_heartbeat1;

    wire [63:0] jesd0_gt0_txdata;
    wire [63:0] jesd0_gt1_txdata;
    wire [63:0] jesd0_gt2_txdata;
    wire [63:0] jesd0_gt3_txdata;
    wire [3:0]  jesd0_gt0_txcharisk;
    wire [3:0]  jesd0_gt1_txcharisk;
    wire [3:0]  jesd0_gt2_txcharisk;
    wire [3:0]  jesd0_gt3_txcharisk;
    wire [1:0]  jesd0_gt0_txheader;
    wire [1:0]  jesd0_gt1_txheader;
    wire [1:0]  jesd0_gt2_txheader;
    wire [1:0]  jesd0_gt3_txheader;
    wire [63:0] jesd1_gt0_txdata;
    wire [63:0] jesd1_gt1_txdata;
    wire [63:0] jesd1_gt2_txdata;
    wire [63:0] jesd1_gt3_txdata;
    wire [3:0]  jesd1_gt0_txcharisk;
    wire [3:0]  jesd1_gt1_txcharisk;
    wire [3:0]  jesd1_gt2_txcharisk;
    wire [3:0]  jesd1_gt3_txcharisk;
    wire [1:0]  jesd1_gt0_txheader;
    wire [1:0]  jesd1_gt1_txheader;
    wire [1:0]  jesd1_gt2_txheader;
    wire [1:0]  jesd1_gt3_txheader;

    wire [7:0]  phy1_rx_data;
    wire        phy1_rx_valid;
    wire        phy1_rx_error;
    wire        phy1_rx_rst;
    wire        dac_cfg_valid_rxclk;
    wire        dac_cfg_reset_phase_rxclk;
    wire [47:0] dac_cfg_phase_inc0_rxclk;
    wire [47:0] dac_cfg_phase_inc1_rxclk;
    wire [47:0] dac_cfg_phase_inc2_rxclk;
    wire [47:0] dac_cfg_phase_inc3_rxclk;
    wire [15:0] dac_cfg_scale0_rxclk;
    wire [15:0] dac_cfg_scale1_rxclk;
    wire [15:0] dac_cfg_scale2_rxclk;
    wire [15:0] dac_cfg_scale3_rxclk;
    wire        dac_wave_wr_en_rxclk;
    wire [11:0] dac_wave_wr_addr_rxclk;
    wire [31:0] dac_wave_wr_data_rxclk;
    wire [12:0] dac_wave_total_samples_rxclk;
    wire        dac_wave_commit_toggle_rxclk;

    reg         dac_cfg_toggle_rxclk;
    reg         dac_cfg_reset_phase_hold_rxclk;
    reg [47:0] dac_cfg_phase_inc0_hold_rxclk;
    reg [47:0] dac_cfg_phase_inc1_hold_rxclk;
    reg [47:0] dac_cfg_phase_inc2_hold_rxclk;
    reg [47:0] dac_cfg_phase_inc3_hold_rxclk;
    reg [15:0] dac_cfg_scale0_hold_rxclk;
    reg [15:0] dac_cfg_scale1_hold_rxclk;
    reg [15:0] dac_cfg_scale2_hold_rxclk;
    reg [15:0] dac_cfg_scale3_hold_rxclk;
    (* ASYNC_REG = "TRUE" *) reg [2:0] phy1_rx_rst_sync;
    (* ASYNC_REG = "TRUE" *) reg [2:0] dac_cfg_toggle_meta_jclk;
    reg        dac_cfg_reset_phase_jclk;
    reg [47:0] dac_cfg_phase_inc0_jclk;
    reg [47:0] dac_cfg_phase_inc1_jclk;
    reg [47:0] dac_cfg_phase_inc2_jclk;
    reg [47:0] dac_cfg_phase_inc3_jclk;
    reg [15:0] dac_cfg_scale0_jclk;
    reg [15:0] dac_cfg_scale1_jclk;
    reg [15:0] dac_cfg_scale2_jclk;
    reg [15:0] dac_cfg_scale3_jclk;
    reg        dac_cfg_apply_pulse_jclk;

    assign init_rst = (state == ST_BOOT);
    assign eth_rst = init_rst || !eth_clk_locked;
    assign jesd_axi_aresetn = !init_rst;

    assign clock_sdio = clock_sdio_oe ? clock_sdio_o : 1'bz;
    assign clock_sdio_i = clock_sdio;
    assign dac_sclk = dac_init_sclk;
    assign dac_cs = dac_init_cs;
    assign dac_sdio = dac_init_sdio_oe ? dac_init_sdio_o : 1'bz;
    assign dac_sdio_i = dac_sdio;
    assign phy1_mdc = 1'b0;
    assign phy1_mdio = 1'bz;

    assign jesd_cfg_done = jesd_done0 && jesd_done1;
    assign phy_axi_cfg_done = phy0_axi_done_seen && phy1_axi_done_seen;
    assign jesd_release_ready = jesd_cfg_done_seen && phy_axi_cfg_done;
    assign jesd_qpll_lock_raw = {
        jesd_qpll1_lock1,
        jesd_qpll0_lock1,
        jesd_qpll1_lock0,
        jesd_qpll0_lock0
    };
    assign jesd_gt_plllock = (JESD_USE_QPLL != 0) ?
        {{4{jesd_qpll0_lock1}}, {4{jesd_qpll0_lock0}}} :
        {jesd_gt_cplllock1, jesd_gt_cplllock0};
    assign jesd_pll_ready = (JESD_USE_QPLL != 0) ?
        (jesd_qpll_lock_dbg[0] && jesd_qpll_lock_dbg[2]) :
        (&jesd_cplllock_dbg);
    assign jesd_links_ready =
        jesd_release_ready &&
        jesd_pll_ready &&
        (&jesd_aresetn_dbg) &&
        (&jesd_tready_dbg) &&
        (&jesd_tx_reset_done_dbg) &&
        (&jesd_gt_txresetdone_dbg) &&
        (&jesd_gt_powergood_dbg);

    assign tx_tone_reset[0] = !jesd_release || !jesd_tx_aresetn0;
    assign tx_tone_reset[1] = !jesd_release || !jesd_tx_aresetn1;
    assign tx_tone_advance[0] = jesd_tx_ready0 && jesd_tx_aresetn0;
    assign tx_tone_advance[1] = jesd_tx_ready1 && jesd_tx_aresetn1;

    assign phy1_rx_rst = phy1_rx_rst_sync[2];

    IBUFDS u_sys_clk_buf (
        .I (sys_clk_p),
        .IB(sys_clk_n),
        .O (sys_clk_ibuf)
    );

    BUFG u_sys_clk_bufg (
        .I(sys_clk_ibuf),
        .O(sys_clk)
    );

    eth_clk_125 u_eth_clk_125 (
        .clk_200   (sys_clk),
        .rst       (init_rst),
        .clk_125   (eth_clk_125),
        .clk_125_90(eth_clk_125_90),
        .locked    (eth_clk_locked)
    );

    IBUFDS u_sysref2_buf (
        .I (sysref2_p),
        .IB(sysref2_n),
        .O (sysref2_i)
    );

    IBUFDS u_dac_sync0_buf (
        .I (dac_sync0_p),
        .IB(dac_sync0_n),
        .O (dac_sync0_i)
    );

    IBUFDS u_dac_sync1_buf (
        .I (dac_sync1_p),
        .IB(dac_sync1_n),
        .O (dac_sync1_raw_i)
    );

    assign dac_sync1_i = ~dac_sync1_raw_i;

    jesd_clock u_jesd_clock (
        .refclk_pad_n(jesd_refclk_n),
        .refclk_pad_p(jesd_refclk_p),
        .refclk      (jesd_refclk),
        .refclk_mon  (jesd_refclk_mon_clk),
        .coreclk     (jesd_odiv2_clk)
    );

    BUFG_GT #(
        .SIM_DEVICE("ULTRASCALE_PLUS")
    ) u_jesd_txoutclk_bufg0 (
        .I      (jesd_txoutclk0),
        .CE     (1'b1),
        .CEMASK (1'b1),
        .CLR    (1'b0),
        .CLRMASK(1'b1),
        .DIV    (3'b000),
        .O      (jesd_txoutclk_mon_clk0)
    );

    BUFG_GT #(
        .SIM_DEVICE("ULTRASCALE_PLUS")
    ) u_jesd_txoutclk_bufg1 (
        .I      (jesd_txoutclk1),
        .CE     (1'b1),
        .CEMASK (1'b1),
        .CLR    (1'b0),
        .CLRMASK(1'b1),
        .DIV    (3'b000),
        .O      (jesd_txoutclk_mon_clk1)
    );

    assign jesd_core_clk = jesd_refclk_mon_clk;

    hmc7044_init #(
        .CLK_DIV (SPI_CLK_DIV),
        .MS_TICKS(MS_TICKS)
    ) u_hmc7044_init (
        .clk  (sys_clk),
        .rst  (init_rst),
        .start(start_hmc),
        .busy (hmc_busy),
        .done (hmc_done),
        .ok   (hmc_ok),
        .fail (hmc_fail),
        .status_dbg(),
        .verify_group_ok(),
        .verify_done(),
        .verify_fail_any(),
        .verify_mismatch_addr(),
        .verify_mismatch_data(),
        .verify_mismatch_expect(),
        .ch4_snapshot_dbg(),
        .debug_state(),
        .debug_retry_count(),
        .debug_read_addr(),
        .debug_read_data(),
        .debug_read_busy(),
        .debug_read_done(),
        .debug_pll1_locked(),
        .sclk (clock_sclk),
        .cs_n (clock_cs),
        .sdio_i(clock_sdio_i),
        .sdio_o(clock_sdio_o),
        .sdio_oe(clock_sdio_oe)
    );

    ad9173_init #(
        .CLK_DIV (SPI_CLK_DIV),
        .MS_TICKS(MS_TICKS)
    ) u_ad9173_init (
        .clk       (sys_clk),
        .rst       (init_rst),
        .start     (start_dac),
        .sdo       (dac_sdo),
        .sdio_i    (dac_sdio_i),
        .busy      (dac_busy),
        .done      (dac_done),
        .ok        (dac_init_ok),
        .fail      (dac_init_fail),
        .status_dbg(),
        .sanity_dbg(),
        .debug_dbg (),
        .sclk      (dac_init_sclk),
        .cs_n      (dac_init_cs),
        .sdio_o    (dac_init_sdio_o),
        .sdio_oe   (dac_init_sdio_oe)
    );

    jesd204_tx_init_link0 #(
        .MS_TICKS(MS_TICKS)
    ) u_jesd204_tx_init_link0 (
        .clk          (sys_clk),
        .rst          (init_rst),
        .start        (start_jesd0),
        .busy         (jesd_busy0),
        .done         (jesd_done0),
        .s_axi_awaddr (jesd0_s_axi_awaddr),
        .s_axi_awvalid(jesd0_s_axi_awvalid),
        .s_axi_awready(jesd0_s_axi_awready),
        .s_axi_wdata  (jesd0_s_axi_wdata),
        .s_axi_wstrb  (jesd0_s_axi_wstrb),
        .s_axi_wvalid (jesd0_s_axi_wvalid),
        .s_axi_wready (jesd0_s_axi_wready),
        .s_axi_bresp  (jesd0_s_axi_bresp),
        .s_axi_bvalid (jesd0_s_axi_bvalid),
        .s_axi_bready (jesd0_s_axi_bready)
    );

    jesd204_tx_init_link1 #(
        .MS_TICKS(MS_TICKS)
    ) u_jesd204_tx_init_link1 (
        .clk          (sys_clk),
        .rst          (init_rst),
        .start        (start_jesd1),
        .busy         (jesd_busy1),
        .done         (jesd_done1),
        .s_axi_awaddr (jesd1_s_axi_awaddr),
        .s_axi_awvalid(jesd1_s_axi_awvalid),
        .s_axi_awready(jesd1_s_axi_awready),
        .s_axi_wdata  (jesd1_s_axi_wdata),
        .s_axi_wstrb  (jesd1_s_axi_wstrb),
        .s_axi_wvalid (jesd1_s_axi_wvalid),
        .s_axi_wready (jesd1_s_axi_wready),
        .s_axi_bresp  (jesd1_s_axi_bresp),
        .s_axi_bvalid (jesd1_s_axi_bvalid),
        .s_axi_bready (jesd1_s_axi_bready)
    );

    jesd_phy_tx_axi_init #(
        .USE_QPLL0(JESD_USE_QPLL)
    ) u_phy0_axi_init (
        .clk          (sys_clk),
        .rst          (!jesd_axi_aresetn),
        .enable       (jesd_cfg_done_seen),
        .busy         (),
        .done_seen    (phy0_axi_done_seen),
        .s_axi_awaddr (phy0_s_axi_awaddr),
        .s_axi_awvalid(phy0_s_axi_awvalid),
        .s_axi_awready(phy0_s_axi_awready),
        .s_axi_wdata  (phy0_s_axi_wdata),
        .s_axi_wvalid (phy0_s_axi_wvalid),
        .s_axi_wready (phy0_s_axi_wready),
        .s_axi_bresp  (phy0_s_axi_bresp),
        .s_axi_bvalid (phy0_s_axi_bvalid),
        .s_axi_bready (phy0_s_axi_bready)
    );

    jesd_phy_tx_axi_init #(
        .USE_QPLL0(JESD_USE_QPLL)
    ) u_phy1_axi_init (
        .clk          (sys_clk),
        .rst          (!jesd_axi_aresetn),
        .enable       (jesd_cfg_done_seen),
        .busy         (),
        .done_seen    (phy1_axi_done_seen),
        .s_axi_awaddr (phy1_s_axi_awaddr),
        .s_axi_awvalid(phy1_s_axi_awvalid),
        .s_axi_awready(phy1_s_axi_awready),
        .s_axi_wdata  (phy1_s_axi_wdata),
        .s_axi_wvalid (phy1_s_axi_wvalid),
        .s_axi_wready (phy1_s_axi_wready),
        .s_axi_bresp  (phy1_s_axi_bresp),
        .s_axi_bvalid (phy1_s_axi_bvalid),
        .s_axi_bready (phy1_s_axi_bready)
    );

    rgmii_rx #(
        .INPUT_DELAY_COUNT(511)
    ) u_phy1_rgmii_rx (
        .rx_clk      (phy1_rxck),
        .rst         (phy1_rx_rst),
        .rgmii_rxd   (phy1_rxd),
        .rgmii_rx_ctl(phy1_rxctl),
        .rx_data     (phy1_rx_data),
        .rx_valid    (phy1_rx_valid),
        .rx_error    (phy1_rx_error)
    );

    k5wg_udp_dac_config_rx #(
        .FPGA_IP (32'hC0A8_010A),
        .UDP_PORT(16'd5005),
        .WAVE_ADDR_WIDTH(12)
    ) u_k5wg_udp_dac_config_rx (
        .clk               (phy1_rxck),
        .rst               (phy1_rx_rst),
        .rx_data           (phy1_rx_data),
        .rx_valid          (phy1_rx_valid),
        .rx_error          (phy1_rx_error),
        .cfg_valid         (dac_cfg_valid_rxclk),
        .cfg_reset_phase   (dac_cfg_reset_phase_rxclk),
        .cfg_phase_inc0    (dac_cfg_phase_inc0_rxclk),
        .cfg_phase_inc1    (dac_cfg_phase_inc1_rxclk),
        .cfg_phase_inc2    (dac_cfg_phase_inc2_rxclk),
        .cfg_phase_inc3    (dac_cfg_phase_inc3_rxclk),
        .cfg_scale0        (dac_cfg_scale0_rxclk),
        .cfg_scale1        (dac_cfg_scale1_rxclk),
        .cfg_scale2        (dac_cfg_scale2_rxclk),
        .cfg_scale3        (dac_cfg_scale3_rxclk),
        .wave_wr_en        (dac_wave_wr_en_rxclk),
        .wave_wr_addr      (dac_wave_wr_addr_rxclk),
        .wave_wr_data      (dac_wave_wr_data_rxclk),
        .wave_total_samples(dac_wave_total_samples_rxclk),
        .wave_commit_toggle(dac_wave_commit_toggle_rxclk),
        .packet_count      (),
        .config_count      (),
        .data_count        (),
        .commit_count      (),
        .drop_count        (),
        .status_dbg        ()
    );

    rgmii_tx u_phy1_rgmii_tx (
        .tx_clk      (eth_clk_125),
        .tx_clk_90   (eth_clk_125_90),
        .rst         (eth_rst),
        .txd         (8'd0),
        .tx_en       (1'b0),
        .rgmii_tx_clk(phy1_txck),
        .rgmii_txd   (phy1_txd),
        .rgmii_tx_ctl(phy1_txctl)
    );

    pattern_gen_256 #(
        .WAVE_ADDR_WIDTH(12)
    ) u_pattern_gen_256 (
        .clk               (jesd_core_clk),
        .rst               (tx_tone_reset),
        .advance           (tx_tone_advance),
        .cfg_valid         (dac_cfg_apply_pulse_jclk),
        .cfg_reset_phase   (dac_cfg_reset_phase_jclk),
        .cfg_phase_inc0    (dac_cfg_phase_inc0_jclk),
        .cfg_phase_inc1    (dac_cfg_phase_inc1_jclk),
        .cfg_phase_inc2    (dac_cfg_phase_inc2_jclk),
        .cfg_phase_inc3    (dac_cfg_phase_inc3_jclk),
        .cfg_scale0        (dac_cfg_scale0_jclk),
        .cfg_scale1        (dac_cfg_scale1_jclk),
        .cfg_scale2        (dac_cfg_scale2_jclk),
        .cfg_scale3        (dac_cfg_scale3_jclk),
        .wave_clk          (phy1_rxck),
        .wave_rst          (phy1_rx_rst),
        .wave_wr_en        (dac_wave_wr_en_rxclk),
        .wave_wr_addr      (dac_wave_wr_addr_rxclk),
        .wave_wr_data      (dac_wave_wr_data_rxclk),
        .wave_total_samples(dac_wave_total_samples_rxclk),
        .wave_commit_toggle(dac_wave_commit_toggle_rxclk),
        .data_out          (tx_pattern_data)
    );

    tx_mapper u_tx_mapper (
        .data_in         (tx_pattern_data),
        .data_in_ready   (),
        .data_out0       (jesd_tx_data0),
        .data_out1       (jesd_tx_data1),
        .dac0_sample0_ila(),
        .dac1_sample0_ila(),
        .dac2_sample0_ila(),
        .dac3_sample0_ila()
    );

    jesd204c_tx_link0 u_jesd204c_tx_link0 (
        .s_axi_aclk    (sys_clk),
        .s_axi_aresetn (jesd_axi_aresetn),
        .s_axi_awaddr  (jesd0_s_axi_awaddr),
        .s_axi_awvalid (jesd0_s_axi_awvalid),
        .s_axi_awready (jesd0_s_axi_awready),
        .s_axi_wdata   (jesd0_s_axi_wdata),
        .s_axi_wstrb   (jesd0_s_axi_wstrb),
        .s_axi_wvalid  (jesd0_s_axi_wvalid),
        .s_axi_wready  (jesd0_s_axi_wready),
        .s_axi_bresp   (jesd0_s_axi_bresp),
        .s_axi_bvalid  (jesd0_s_axi_bvalid),
        .s_axi_bready  (jesd0_s_axi_bready),
        .s_axi_araddr  (12'd0),
        .s_axi_arvalid (1'b0),
        .s_axi_arready (),
        .s_axi_rdata   (),
        .s_axi_rresp   (),
        .s_axi_rvalid  (),
        .s_axi_rready  (1'b0),
        .tx_core_clk   (jesd_core_clk),
        .tx_core_reset (!jesd_release),
        .tx_sysref     (sysref2_i),
        .irq           (),
        .tx_tdata      (jesd_tx_data0),
        .tx_tready     (jesd_tx_ready0),
        .tx_aresetn    (jesd_tx_aresetn0),
        .tx_sof        (),
        .tx_somf       (),
        .tx_sync       (dac_sync0_i),
        .tx_reset_gt   (jesd_tx_reset_gt0),
        .tx_reset_done (jesd_tx_reset_done0),
        .gt0_txdata    (jesd0_gt0_txdata),
        .gt0_txcharisk (jesd0_gt0_txcharisk),
        .gt0_txheader  (jesd0_gt0_txheader),
        .gt1_txdata    (jesd0_gt1_txdata),
        .gt1_txcharisk (jesd0_gt1_txcharisk),
        .gt1_txheader  (jesd0_gt1_txheader),
        .gt2_txdata    (jesd0_gt2_txdata),
        .gt2_txcharisk (jesd0_gt2_txcharisk),
        .gt2_txheader  (jesd0_gt2_txheader),
        .gt3_txdata    (jesd0_gt3_txdata),
        .gt3_txcharisk (jesd0_gt3_txcharisk),
        .gt3_txheader  (jesd0_gt3_txheader)
    );

    jesd204c_tx_link1 u_jesd204c_tx_link1 (
        .s_axi_aclk    (sys_clk),
        .s_axi_aresetn (jesd_axi_aresetn),
        .s_axi_awaddr  (jesd1_s_axi_awaddr),
        .s_axi_awvalid (jesd1_s_axi_awvalid),
        .s_axi_awready (jesd1_s_axi_awready),
        .s_axi_wdata   (jesd1_s_axi_wdata),
        .s_axi_wstrb   (jesd1_s_axi_wstrb),
        .s_axi_wvalid  (jesd1_s_axi_wvalid),
        .s_axi_wready  (jesd1_s_axi_wready),
        .s_axi_bresp   (jesd1_s_axi_bresp),
        .s_axi_bvalid  (jesd1_s_axi_bvalid),
        .s_axi_bready  (jesd1_s_axi_bready),
        .s_axi_araddr  (12'd0),
        .s_axi_arvalid (1'b0),
        .s_axi_arready (),
        .s_axi_rdata   (),
        .s_axi_rresp   (),
        .s_axi_rvalid  (),
        .s_axi_rready  (1'b0),
        .tx_core_clk   (jesd_core_clk),
        .tx_core_reset (!jesd_release),
        .tx_sysref     (sysref2_i),
        .irq           (),
        .tx_tdata      (jesd_tx_data1),
        .tx_tready     (jesd_tx_ready1),
        .tx_aresetn    (jesd_tx_aresetn1),
        .tx_sof        (),
        .tx_somf       (),
        .tx_sync       (dac_sync1_i),
        .tx_reset_gt   (jesd_tx_reset_gt1),
        .tx_reset_done (jesd_tx_reset_done1),
        .gt0_txdata    (jesd1_gt0_txdata),
        .gt0_txcharisk (jesd1_gt0_txcharisk),
        .gt0_txheader  (jesd1_gt0_txheader),
        .gt1_txdata    (jesd1_gt1_txdata),
        .gt1_txcharisk (jesd1_gt1_txcharisk),
        .gt1_txheader  (jesd1_gt1_txheader),
        .gt2_txdata    (jesd1_gt2_txdata),
        .gt2_txcharisk (jesd1_gt2_txcharisk),
        .gt2_txheader  (jesd1_gt2_txheader),
        .gt3_txdata    (jesd1_gt3_txdata),
        .gt3_txcharisk (jesd1_gt3_txcharisk),
        .gt3_txheader  (jesd1_gt3_txheader)
    );

    jesd204_phy_tx_quad226 u_jesd204_phy_tx_quad226 (
        .cpll_refclk         (1'b0),
        .qpll0_refclk        (jesd_refclk),
        .qpll1_refclk        (1'b0),
        .drpclk              (sys_clk),
        .tx_reset_gt         (jesd_tx_reset_gt0),
        .rx_reset_gt         (1'b1),
        .tx_sys_reset        (!jesd_release),
        .rx_sys_reset        (1'b1),
        .txp_out             (dac_tx_p[3:0]),
        .txn_out             (dac_tx_n[3:0]),
        .rxp_in              (4'b0000),
        .rxn_in              (4'b0000),
        .tx_core_clk         (jesd_core_clk),
        .rx_core_clk         (jesd_core_clk),
        .txoutclk            (jesd_txoutclk0),
        .rxoutclk            (),
        .gt_cplllock         (jesd_gt_cplllock0),
        .gt_txresetdone      (jesd_gt_txresetdone0),
        .gt_rxresetdone      (),
        .gt_rxprbssel        (16'd0),
        .gt_txprbsforceerr   (4'd0),
        .gt_rxprbscntreset   (4'd0),
        .gt_rxprbserr        (),
        .gt_eyescantrigger   (4'd0),
        .gt_eyescanreset     (4'd0),
        .gt_eyescandataerror (),
        .gt_txpmareset       (4'd0),
        .gt_txpcsreset       (4'd0),
        .gt_txbufstatus      (),
        .gt_rxpmareset       (4'd0),
        .gt_rxpcsreset       (4'd0),
        .gt_rxpmaresetdone   (),
        .gt_rxcdrhold        (4'd0),
        .gt_rxcommadet       (),
        .gt_rxbufreset       (4'd0),
        .gt_rxbufstatus      (),
        .gt_rxrate           (12'd0),
        .gt_dmonitorclk      (4'd0),
        .gt_dmonitorout      (),
        .gt0_txdata          (jesd0_gt0_txdata),
        .gt0_txcharisk       (jesd0_gt0_txcharisk),
        .gt0_txheader        (jesd0_gt0_txheader),
        .gt1_txdata          (jesd0_gt1_txdata),
        .gt1_txcharisk       (jesd0_gt1_txcharisk),
        .gt1_txheader        (jesd0_gt1_txheader),
        .gt2_txdata          (jesd0_gt2_txdata),
        .gt2_txcharisk       (jesd0_gt2_txcharisk),
        .gt2_txheader        (jesd0_gt2_txheader),
        .gt3_txdata          (jesd0_gt3_txdata),
        .gt3_txcharisk       (jesd0_gt3_txcharisk),
        .gt3_txheader        (jesd0_gt3_txheader),
        .tx_reset_done       (jesd_tx_reset_done0),
        .gt_powergood        (jesd_gt_powergood0),
        .gt0_rxdata          (),
        .gt0_rxcharisk       (),
        .gt0_rxdisperr       (),
        .gt0_rxnotintable    (),
        .gt0_rxheader        (),
        .gt0_rxmisalign      (),
        .gt0_rxblock_sync    (),
        .gt1_rxdata          (),
        .gt1_rxcharisk       (),
        .gt1_rxdisperr       (),
        .gt1_rxnotintable    (),
        .gt1_rxheader        (),
        .gt1_rxmisalign      (),
        .gt1_rxblock_sync    (),
        .gt2_rxdata          (),
        .gt2_rxcharisk       (),
        .gt2_rxdisperr       (),
        .gt2_rxnotintable    (),
        .gt2_rxheader        (),
        .gt2_rxmisalign      (),
        .gt2_rxblock_sync    (),
        .gt3_rxdata          (),
        .gt3_rxcharisk       (),
        .gt3_rxdisperr       (),
        .gt3_rxnotintable    (),
        .gt3_rxheader        (),
        .gt3_rxmisalign      (),
        .gt3_rxblock_sync    (),
        .rx_reset_done       (),
        .rxencommaalign      (1'b0),
        .common0_qpll0_clk_out(),
        .common0_qpll0_refclk_out(),
        .common0_qpll0_lock_out(jesd_qpll0_lock0),
        .common0_qpll1_clk_out(),
        .common0_qpll1_refclk_out(),
        .common0_qpll1_lock_out(jesd_qpll1_lock0),
        .s_axi_aclk          (sys_clk),
        .s_axi_aresetn       (jesd_axi_aresetn),
        .s_axi_awaddr        (phy0_s_axi_awaddr),
        .s_axi_awvalid       (phy0_s_axi_awvalid),
        .s_axi_awready       (phy0_s_axi_awready),
        .s_axi_wdata         (phy0_s_axi_wdata),
        .s_axi_wvalid        (phy0_s_axi_wvalid),
        .s_axi_wready        (phy0_s_axi_wready),
        .s_axi_bresp         (phy0_s_axi_bresp),
        .s_axi_bvalid        (phy0_s_axi_bvalid),
        .s_axi_bready        (phy0_s_axi_bready),
        .s_axi_araddr        (12'd0),
        .s_axi_arvalid       (1'b0),
        .s_axi_arready       (),
        .s_axi_rdata         (),
        .s_axi_rresp         (),
        .s_axi_rvalid        (),
        .s_axi_rready        (1'b0)
    );

    jesd204_phy_tx_quad227 u_jesd204_phy_tx_quad227 (
        .cpll_refclk         (1'b0),
        .qpll0_refclk        (jesd_refclk),
        .qpll1_refclk        (1'b0),
        .drpclk              (sys_clk),
        .tx_reset_gt         (jesd_tx_reset_gt1),
        .rx_reset_gt         (1'b1),
        .tx_sys_reset        (!jesd_release),
        .rx_sys_reset        (1'b1),
        .txp_out             (dac_tx_p[7:4]),
        .txn_out             (dac_tx_n[7:4]),
        .rxp_in              (4'b0000),
        .rxn_in              (4'b0000),
        .tx_core_clk         (jesd_core_clk),
        .rx_core_clk         (jesd_core_clk),
        .txoutclk            (jesd_txoutclk1),
        .rxoutclk            (),
        .gt_cplllock         (jesd_gt_cplllock1),
        .gt_txresetdone      (jesd_gt_txresetdone1),
        .gt_rxresetdone      (),
        .gt_rxprbssel        (16'd0),
        .gt_txprbsforceerr   (4'd0),
        .gt_rxprbscntreset   (4'd0),
        .gt_rxprbserr        (),
        .gt_eyescantrigger   (4'd0),
        .gt_eyescanreset     (4'd0),
        .gt_eyescandataerror (),
        .gt_txpmareset       (4'd0),
        .gt_txpcsreset       (4'd0),
        .gt_txbufstatus      (),
        .gt_rxpmareset       (4'd0),
        .gt_rxpcsreset       (4'd0),
        .gt_rxpmaresetdone   (),
        .gt_rxcdrhold        (4'd0),
        .gt_rxcommadet       (),
        .gt_rxbufreset       (4'd0),
        .gt_rxbufstatus      (),
        .gt_rxrate           (12'd0),
        .gt_dmonitorclk      (4'd0),
        .gt_dmonitorout      (),
        .gt0_txdata          (jesd1_gt0_txdata),
        .gt0_txcharisk       (jesd1_gt0_txcharisk),
        .gt0_txheader        (jesd1_gt0_txheader),
        .gt1_txdata          (jesd1_gt1_txdata),
        .gt1_txcharisk       (jesd1_gt1_txcharisk),
        .gt1_txheader        (jesd1_gt1_txheader),
        .gt2_txdata          (jesd1_gt2_txdata),
        .gt2_txcharisk       (jesd1_gt2_txcharisk),
        .gt2_txheader        (jesd1_gt2_txheader),
        .gt3_txdata          (jesd1_gt3_txdata),
        .gt3_txcharisk       (jesd1_gt3_txcharisk),
        .gt3_txheader        (jesd1_gt3_txheader),
        .tx_reset_done       (jesd_tx_reset_done1),
        .gt_powergood        (jesd_gt_powergood1),
        .gt0_rxdata          (),
        .gt0_rxcharisk       (),
        .gt0_rxdisperr       (),
        .gt0_rxnotintable    (),
        .gt0_rxheader        (),
        .gt0_rxmisalign      (),
        .gt0_rxblock_sync    (),
        .gt1_rxdata          (),
        .gt1_rxcharisk       (),
        .gt1_rxdisperr       (),
        .gt1_rxnotintable    (),
        .gt1_rxheader        (),
        .gt1_rxmisalign      (),
        .gt1_rxblock_sync    (),
        .gt2_rxdata          (),
        .gt2_rxcharisk       (),
        .gt2_rxdisperr       (),
        .gt2_rxnotintable    (),
        .gt2_rxheader        (),
        .gt2_rxmisalign      (),
        .gt2_rxblock_sync    (),
        .gt3_rxdata          (),
        .gt3_rxcharisk       (),
        .gt3_rxdisperr       (),
        .gt3_rxnotintable    (),
        .gt3_rxheader        (),
        .gt3_rxmisalign      (),
        .gt3_rxblock_sync    (),
        .rx_reset_done       (),
        .rxencommaalign      (1'b0),
        .common0_qpll0_clk_out(),
        .common0_qpll0_refclk_out(),
        .common0_qpll0_lock_out(jesd_qpll0_lock1),
        .common0_qpll1_clk_out(),
        .common0_qpll1_refclk_out(),
        .common0_qpll1_lock_out(jesd_qpll1_lock1),
        .s_axi_aclk          (sys_clk),
        .s_axi_aresetn       (jesd_axi_aresetn),
        .s_axi_awaddr        (phy1_s_axi_awaddr),
        .s_axi_awvalid       (phy1_s_axi_awvalid),
        .s_axi_awready       (phy1_s_axi_awready),
        .s_axi_wdata         (phy1_s_axi_wdata),
        .s_axi_wvalid        (phy1_s_axi_wvalid),
        .s_axi_wready        (phy1_s_axi_wready),
        .s_axi_bresp         (phy1_s_axi_bresp),
        .s_axi_bvalid        (phy1_s_axi_bvalid),
        .s_axi_bready        (phy1_s_axi_bready),
        .s_axi_araddr        (12'd0),
        .s_axi_arvalid       (1'b0),
        .s_axi_arready       (),
        .s_axi_rdata         (),
        .s_axi_rresp         (),
        .s_axi_rvalid        (),
        .s_axi_rready        (1'b0)
    );

    always @(posedge phy1_rxck) begin
        if (eth_rst) begin
            phy1_rx_rst_sync <= 3'b111;
        end else begin
            phy1_rx_rst_sync <= {phy1_rx_rst_sync[1:0], 1'b0};
        end
    end

    always @(posedge phy1_rxck) begin
        if (phy1_rx_rst) begin
            dac_cfg_toggle_rxclk <= 1'b0;
            dac_cfg_reset_phase_hold_rxclk <= 1'b0;
            dac_cfg_phase_inc0_hold_rxclk <= 48'h053555555555;
            dac_cfg_phase_inc1_hold_rxclk <= 48'h07d000000000;
            dac_cfg_phase_inc2_hold_rxclk <= 48'h053555555555;
            dac_cfg_phase_inc3_hold_rxclk <= 48'h07d000000000;
            dac_cfg_scale0_hold_rxclk <= 16'h7fff;
            dac_cfg_scale1_hold_rxclk <= 16'h7fff;
            dac_cfg_scale2_hold_rxclk <= 16'h7fff;
            dac_cfg_scale3_hold_rxclk <= 16'h7fff;
        end else if (dac_cfg_valid_rxclk) begin
            dac_cfg_reset_phase_hold_rxclk <= dac_cfg_reset_phase_rxclk;
            dac_cfg_phase_inc0_hold_rxclk <= dac_cfg_phase_inc0_rxclk;
            dac_cfg_phase_inc1_hold_rxclk <= dac_cfg_phase_inc1_rxclk;
            dac_cfg_phase_inc2_hold_rxclk <= dac_cfg_phase_inc2_rxclk;
            dac_cfg_phase_inc3_hold_rxclk <= dac_cfg_phase_inc3_rxclk;
            dac_cfg_scale0_hold_rxclk <= dac_cfg_scale0_rxclk;
            dac_cfg_scale1_hold_rxclk <= dac_cfg_scale1_rxclk;
            dac_cfg_scale2_hold_rxclk <= dac_cfg_scale2_rxclk;
            dac_cfg_scale3_hold_rxclk <= dac_cfg_scale3_rxclk;
            dac_cfg_toggle_rxclk <= ~dac_cfg_toggle_rxclk;
        end
    end

    always @(posedge jesd_core_clk) begin
        if (init_rst) begin
            dac_cfg_toggle_meta_jclk <= 3'b000;
            dac_cfg_reset_phase_jclk <= 1'b0;
            dac_cfg_phase_inc0_jclk <= 48'h053555555555;
            dac_cfg_phase_inc1_jclk <= 48'h07d000000000;
            dac_cfg_phase_inc2_jclk <= 48'h053555555555;
            dac_cfg_phase_inc3_jclk <= 48'h07d000000000;
            dac_cfg_scale0_jclk <= 16'h7fff;
            dac_cfg_scale1_jclk <= 16'h7fff;
            dac_cfg_scale2_jclk <= 16'h7fff;
            dac_cfg_scale3_jclk <= 16'h7fff;
            dac_cfg_apply_pulse_jclk <= 1'b0;
        end else begin
            dac_cfg_apply_pulse_jclk <= 1'b0;
            dac_cfg_toggle_meta_jclk <= {
                dac_cfg_toggle_meta_jclk[1:0],
                dac_cfg_toggle_rxclk
            };
            if (dac_cfg_toggle_meta_jclk[2] ^ dac_cfg_toggle_meta_jclk[1]) begin
                dac_cfg_reset_phase_jclk <= dac_cfg_reset_phase_hold_rxclk;
                dac_cfg_phase_inc0_jclk <= dac_cfg_phase_inc0_hold_rxclk;
                dac_cfg_phase_inc1_jclk <= dac_cfg_phase_inc1_hold_rxclk;
                dac_cfg_phase_inc2_jclk <= dac_cfg_phase_inc2_hold_rxclk;
                dac_cfg_phase_inc3_jclk <= dac_cfg_phase_inc3_hold_rxclk;
                dac_cfg_scale0_jclk <= dac_cfg_scale0_hold_rxclk;
                dac_cfg_scale1_jclk <= dac_cfg_scale1_hold_rxclk;
                dac_cfg_scale2_jclk <= dac_cfg_scale2_hold_rxclk;
                dac_cfg_scale3_jclk <= dac_cfg_scale3_hold_rxclk;
                dac_cfg_apply_pulse_jclk <= 1'b1;
            end
        end
    end

    always @(posedge jesd_txoutclk_mon_clk0) begin
        jesd_txoutclk_heartbeat0 <= jesd_txoutclk_heartbeat0 + 1'b1;
    end

    always @(posedge jesd_txoutclk_mon_clk1) begin
        jesd_txoutclk_heartbeat1 <= jesd_txoutclk_heartbeat1 + 1'b1;
    end

    initial begin
        state <= ST_BOOT;
        boot_count <= 32'd0;
        hold_count <= 32'd0;
        start_hmc <= 1'b0;
        start_dac <= 1'b0;
        start_jesd0 <= 1'b0;
        start_jesd1 <= 1'b0;
        jesd_release <= 1'b0;
        jesd_cfg_done_seen <= 1'b0;
        jesd_release_stable_count <= 32'd0;
        jesd_links_ready_stable_count <= 32'd0;
        jesd_pll_missing_count <= 32'd0;
        jesd_retry_reset_count <= 32'd0;
        jesd_retry_count <= 16'd0;
        txen_0 <= 1'b0;
        txen_1 <= 1'b0;
        jesd_aresetn_meta <= 2'b00;
        jesd_tready_meta <= 2'b00;
        jesd_tx_reset_done_meta <= 2'b00;
        jesd_gt_powergood_meta <= 2'b00;
        jesd_gt_txresetdone_meta <= 8'd0;
        jesd_cplllock_meta <= 8'd0;
        jesd_qpll_lock_meta <= 4'd0;
        jesd_aresetn_dbg <= 2'b00;
        jesd_tready_dbg <= 2'b00;
        jesd_tx_reset_done_dbg <= 2'b00;
        jesd_gt_powergood_dbg <= 2'b00;
        jesd_gt_txresetdone_dbg <= 8'd0;
        jesd_cplllock_dbg <= 8'd0;
        jesd_qpll_lock_dbg <= 4'd0;
        jesd_txoutclk_heartbeat0 <= 8'd0;
        jesd_txoutclk_heartbeat1 <= 8'd0;
        phy1_rx_rst_sync <= 3'b111;
        dac_cfg_toggle_rxclk <= 1'b0;
        dac_cfg_reset_phase_hold_rxclk <= 1'b0;
        dac_cfg_phase_inc0_hold_rxclk <= 48'h053555555555;
        dac_cfg_phase_inc1_hold_rxclk <= 48'h07d000000000;
        dac_cfg_phase_inc2_hold_rxclk <= 48'h053555555555;
        dac_cfg_phase_inc3_hold_rxclk <= 48'h07d000000000;
        dac_cfg_scale0_hold_rxclk <= 16'h7fff;
        dac_cfg_scale1_hold_rxclk <= 16'h7fff;
        dac_cfg_scale2_hold_rxclk <= 16'h7fff;
        dac_cfg_scale3_hold_rxclk <= 16'h7fff;
        dac_cfg_toggle_meta_jclk <= 3'b000;
        dac_cfg_reset_phase_jclk <= 1'b0;
        dac_cfg_phase_inc0_jclk <= 48'h053555555555;
        dac_cfg_phase_inc1_jclk <= 48'h07d000000000;
        dac_cfg_phase_inc2_jclk <= 48'h053555555555;
        dac_cfg_phase_inc3_jclk <= 48'h07d000000000;
        dac_cfg_scale0_jclk <= 16'h7fff;
        dac_cfg_scale1_jclk <= 16'h7fff;
        dac_cfg_scale2_jclk <= 16'h7fff;
        dac_cfg_scale3_jclk <= 16'h7fff;
        dac_cfg_apply_pulse_jclk <= 1'b0;
    end

    always @(posedge sys_clk) begin
        start_hmc <= 1'b0;
        start_dac <= 1'b0;
        start_jesd0 <= 1'b0;
        start_jesd1 <= 1'b0;

        jesd_aresetn_meta <= {jesd_tx_aresetn1, jesd_tx_aresetn0};
        jesd_tready_meta <= {jesd_tx_ready1, jesd_tx_ready0};
        jesd_tx_reset_done_meta <= {jesd_tx_reset_done1, jesd_tx_reset_done0};
        jesd_gt_powergood_meta <= {jesd_gt_powergood1, jesd_gt_powergood0};
        jesd_gt_txresetdone_meta <= {jesd_gt_txresetdone1, jesd_gt_txresetdone0};
        jesd_cplllock_meta <= {jesd_gt_cplllock1, jesd_gt_cplllock0};
        jesd_qpll_lock_meta <= jesd_qpll_lock_raw;

        jesd_aresetn_dbg <= jesd_aresetn_meta;
        jesd_tready_dbg <= jesd_tready_meta;
        jesd_tx_reset_done_dbg <= jesd_tx_reset_done_meta;
        jesd_gt_powergood_dbg <= jesd_gt_powergood_meta;
        jesd_gt_txresetdone_dbg <= jesd_gt_txresetdone_meta;
        jesd_cplllock_dbg <= jesd_cplllock_meta;
        jesd_qpll_lock_dbg <= jesd_qpll_lock_meta;

        if (init_rst) begin
            jesd_cfg_done_seen <= 1'b0;
            jesd_release_stable_count <= 32'd0;
            jesd_links_ready_stable_count <= 32'd0;
            jesd_pll_missing_count <= 32'd0;
            jesd_retry_reset_count <= 32'd0;
            jesd_retry_count <= 16'd0;
        end else begin
            jesd_cfg_done_seen <= jesd_cfg_done_seen | jesd_cfg_done;
        end

        case (state)
            ST_BOOT: begin
                txen_0 <= 1'b0;
                txen_1 <= 1'b0;
                jesd_release <= 1'b0;
                if (boot_count == BOOT_WAIT_TICKS - 1) begin
                    boot_count <= 32'd0;
                    state <= ST_START_HMC;
                end else begin
                    boot_count <= boot_count + 1'b1;
                end
            end

            ST_START_HMC: begin
                start_hmc <= 1'b1;
                state <= ST_WAIT_HMC;
            end

            ST_WAIT_HMC: begin
                if (hmc_done && hmc_ok) begin
                    hold_count <= 32'd0;
                    state <= ST_HOLD_DAC;
                end else if (hmc_done && hmc_fail) begin
                    state <= ST_FAIL;
                end
            end

            ST_HOLD_DAC: begin
                if (hold_count == HOLD_WAIT_TICKS - 1) begin
                    hold_count <= 32'd0;
                    state <= ST_START_DAC;
                end else begin
                    hold_count <= hold_count + 1'b1;
                end
            end

            ST_START_DAC: begin
                start_dac <= 1'b1;
                state <= ST_WAIT_DAC;
            end

            ST_WAIT_DAC: begin
                if (dac_done && dac_init_ok) begin
                    txen_0 <= 1'b1;
                    txen_1 <= 1'b1;
                    state <= ST_START_JESD;
                end else if (dac_done && dac_init_fail) begin
                    state <= ST_FAIL;
                end
            end

            ST_START_JESD: begin
                start_jesd0 <= 1'b1;
                start_jesd1 <= 1'b1;
                jesd_release <= 1'b0;
                jesd_release_stable_count <= 32'd0;
                jesd_links_ready_stable_count <= 32'd0;
                jesd_pll_missing_count <= 32'd0;
                jesd_retry_reset_count <= 32'd0;
                state <= ST_WAIT_JESD;
            end

            ST_WAIT_JESD: begin
                if (jesd_retry_reset_count != 32'd0) begin
                    jesd_release <= 1'b0;
                    jesd_release_stable_count <= 32'd0;
                    jesd_links_ready_stable_count <= 32'd0;
                    jesd_pll_missing_count <= 32'd0;
                    if (jesd_retry_reset_count < JESD_RETRY_RESET_TICKS) begin
                        jesd_retry_reset_count <= jesd_retry_reset_count + 1'b1;
                    end else begin
                        jesd_retry_reset_count <= 32'd0;
                    end
                end else if (!jesd_release) begin
                    jesd_links_ready_stable_count <= 32'd0;
                    if (jesd_release_ready) begin
                        if (jesd_release_stable_count >=
                            (JESD_RELEASE_STABLE_TICKS - 1)) begin
                            jesd_release <= 1'b1;
                            jesd_release_stable_count <= 32'd0;
                        end else begin
                            jesd_release_stable_count <=
                                jesd_release_stable_count + 1'b1;
                        end
                    end else begin
                        jesd_release_stable_count <= 32'd0;
                    end
                end else if (jesd_links_ready) begin
                    jesd_pll_missing_count <= 32'd0;
                    if (jesd_links_ready_stable_count >=
                        (JESD_READY_STABLE_TICKS - 1)) begin
                        state <= ST_RUN;
                    end else begin
                        jesd_links_ready_stable_count <=
                            jesd_links_ready_stable_count + 1'b1;
                    end
                end else begin
                    jesd_links_ready_stable_count <= 32'd0;
                    if (!jesd_pll_ready) begin
                        if (jesd_pll_missing_count >=
                            (JESD_RETRY_MISSING_TICKS - 1)) begin
                            jesd_release <= 1'b0;
                            jesd_release_stable_count <= 32'd0;
                            jesd_pll_missing_count <= 32'd0;
                            jesd_retry_reset_count <= 32'd1;
                            jesd_retry_count <= jesd_retry_count + 1'b1;
                        end else begin
                            jesd_pll_missing_count <= jesd_pll_missing_count + 1'b1;
                        end
                    end else begin
                        jesd_pll_missing_count <= 32'd0;
                    end
                end
            end

            ST_RUN: begin
                jesd_release <= 1'b1;
                txen_0 <= 1'b1;
                txen_1 <= 1'b1;
            end

            ST_FAIL: begin
                jesd_release <= 1'b0;
                txen_0 <= 1'b0;
                txen_1 <= 1'b0;
            end

            default: begin
                state <= ST_BOOT;
            end
        endcase
    end

endmodule
