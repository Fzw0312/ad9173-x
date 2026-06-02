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
    input  wire [7:0] adc_rx_p,
    input  wire [7:0] adc_rx_n,
    output wire       adc_sync_p,
    output wire       adc_sync_n,
    output wire       clock_cs,
    output wire       clock_sclk,
    inout  wire       clock_sdio,
    output wire       dac_cs,
    output wire       dac_sclk,
    inout  wire       dac_sdio,
    input  wire       dac_sdo,
    output wire       adc_csb,
    output wire       adc_sclk,
    inout  wire       adc_sdio,
    output reg        adc_pdwn,
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

    localparam integer SYS_CLK_HZ   = 200_000_000;
    localparam integer BOOT_WAIT_MS = 5;
    localparam integer HOLD_WAIT_MS = 10;
    localparam integer ADC_HOLD_WAIT_MS = 100;
    localparam integer ADC_START_TIMEOUT_MS = 1;
    localparam integer ADC_INIT_TIMEOUT_MS = 1000;
    localparam integer MS_TICKS     = SYS_CLK_HZ / 1000;
    localparam integer SPI_CLK_DIV  = 50;
    localparam integer ENABLE_AD6688_INIT = 0;
    localparam integer JESD_USE_QPLL = 1;
    localparam integer JESD_RELEASE_STABLE_MS = 1;
    localparam integer JESD_READY_STABLE_MS   = 1;
    localparam integer JESD_RETRY_MISSING_MS  = 50;
    localparam integer JESD_RETRY_RESET_MS    = 5;
    localparam integer ADC_RX_REARM_ENABLE = 1;
    localparam integer ADC_RX_AUTO_REINIT_ENABLE = 0;
    localparam integer ADC_RX_REARM_LOCK_TIMEOUT_MS = 500;
    localparam integer ADC_RX_REARM_DROP_TIMEOUT_MS = 100;
    localparam integer ADC_RX_REARM_RESET_MS = 5;
    localparam integer ADC_RX_CORE_REINIT_TIMEOUT_MS = 20;
    localparam integer ADC_RX_REARM_GOOD_STABLE_MS = 5;
    localparam integer ADC_RX_REARM_MAX_COUNT = 8;
    localparam integer ADC_RX_REARM_LINK_REINIT_THRESHOLD = 2;
    localparam integer ADC_RX_GT_RESET_MS = 5;
    localparam integer ADC_RX_GT_WAIT_TIMEOUT_MS = 50;
    localparam integer ADC_RX_LINK_REINIT_TIMEOUT_MS = 50;
    localparam integer ADC_RX_LINK_REINIT_SETTLE_MS = 20;
    // Diagnostic build: start AD6688 in forced CGS, then release 0x0572 back
    // to the physical SYNCINB loop after the FPGA RX has had time to align.
    localparam integer ADC_JESD_SYNCINB_DEBUG_MODE = 1;
    localparam integer ADC_JESD_SYNCINB_INVERT = 0;
    localparam integer ADC_JESD_ILAS_ALWAYS_ON = 0;
    localparam integer ADC_JESD_8B10B_BIT_INVERT = 0;
    // Diagnostic gate: let the AD6688 SPI sequence run when TX is blocked only
    // by a non-sticky AXI4-Stream tready, while keeping all normal counters live.
    localparam integer ADC_DIAG_BYPASS_TX_READY = 1;
    localparam integer ADC_SERDOUT_INVERT_ENABLE = 1;
    localparam [7:0]   ADC_SERDOUT_INVERT_MASK = 8'h10;
    localparam integer ADC_SYNC_OUTPUT_INVERT = 0;
    // 0: follow JESD RX sync, 1: invert, 2/3: force final low/high,
    // 4/5: timed final low-to-high/high-to-low release after RX enable,
    // 6: timed SYNC assert for CGS, then follow JESD RX sync for resync.
    localparam integer ADC_SYNC_OUTPUT_DEBUG_MODE = 4;
    localparam integer ADC_SYNC_FORCE_ASSERT_MS = 40;
    localparam integer JESD_CORE_MS_TICKS = 245760;
    localparam integer ADC_SYNC_FORCE_ASSERT_TICKS =
        ADC_SYNC_FORCE_ASSERT_MS * JESD_CORE_MS_TICKS;
    localparam integer ADC_SYNC_HOLD_ENABLE = 1;
    localparam integer ADC_SYNC_HOLD_LOCK_STABLE_CYCLES = 64;
    localparam integer ADC_SYNC_HOLD_DROP_MS = 100;
    localparam integer ADC_SYNC_HOLD_DROP_TICKS =
        ADC_SYNC_HOLD_DROP_MS * JESD_CORE_MS_TICKS;
    localparam [1:0] ADC_JESD_SYNCINB_DEBUG_MODE_BITS = ADC_JESD_SYNCINB_DEBUG_MODE;
    localparam [2:0] ADC_SYNC_OUTPUT_DEBUG_MODE_BITS = ADC_SYNC_OUTPUT_DEBUG_MODE;
    localparam [0:0] ADC_JESD_SYNCINB_INVERT_BIT = (ADC_JESD_SYNCINB_INVERT != 0);
    localparam [0:0] ADC_SYNC_OUTPUT_INVERT_BIT = (ADC_SYNC_OUTPUT_INVERT != 0);
    localparam [0:0] ADC_SYNC_HOLD_ENABLE_BIT =
        (ADC_SYNC_HOLD_ENABLE != 0);
    localparam integer ADC_RX_POLARITY_CFG_ENABLE = 1;
    localparam integer ADC_RX_POLARITY_SWEEP_ENABLE = 0;
    localparam integer ADC_RX_LPMEN_PHY0_CFG_ENABLE = 1;
    localparam integer ADC_RX_LPMEN_PHY1_CFG_ENABLE = 1;
    localparam [0:0]   ADC_RX_LPMEN_CFG = 1'b0;
    localparam [0:0] ADC_JESD_ILAS_ALWAYS_ON_BIT = (ADC_JESD_ILAS_ALWAYS_ON != 0);
    localparam [0:0] ADC_RX_POLARITY_SWEEP_ENABLE_BIT = (ADC_RX_POLARITY_SWEEP_ENABLE != 0);
    localparam [0:0] ADC_DIAG_BYPASS_TX_READY_BIT = (ADC_DIAG_BYPASS_TX_READY != 0);
    localparam [0:0] ADC_RX_REARM_ENABLE_BIT = (ADC_RX_REARM_ENABLE != 0);
    localparam [0:0] ADC_RX_AUTO_REINIT_ENABLE_BIT =
        (ADC_RX_AUTO_REINIT_ENABLE != 0);
    localparam integer ADC_RX_SYSREF_GATE_ENABLE = 0;
    localparam integer ADC_RX_SYSREF_PULSE_MAX = 4;
    localparam integer ENABLE_ADC_UDP_RGMII = 0;
    localparam integer ENABLE_DEBUG_ILA = 0;
    localparam integer ADC_UDP_CAPTURE_BEATS = 2048;
    localparam integer ADC_UDP_DATA_PAYLOAD_SAMPLES = 512;
    localparam integer ADC_UDP_REPEAT_MS = 20;
    localparam integer ADC_UDP_LINK_GOOD_MS = 1;
    localparam integer ADC_UDP_SAMPLE_GAP_TICKS = 1;
    localparam integer ADC_UDP_CAPTURE_ADDR_W = 11;
    localparam integer ADC_UDP_REPEAT_TICKS =
        ADC_UDP_REPEAT_MS * JESD_CORE_MS_TICKS;
    localparam integer ADC_UDP_LINK_GOOD_TICKS =
        ADC_UDP_LINK_GOOD_MS * JESD_CORE_MS_TICKS;
    localparam [0:0] ADC_RX_SYSREF_GATE_ENABLE_BIT =
        (ADC_RX_SYSREF_GATE_ENABLE != 0);
    localparam [0:0] ADC_RX_LINK_REINIT_ENABLE_BIT =
        ADC_RX_AUTO_REINIT_ENABLE_BIT &&
        (ADC_RX_REARM_LINK_REINIT_THRESHOLD < ADC_RX_REARM_MAX_COUNT);
    localparam [0:0] ADC_RX_GT_RESET_ENABLE_BIT =
        ADC_RX_AUTO_REINIT_ENABLE_BIT;
    localparam [3:0]   ADC_RX_POLARITY_PHY0_INIT = 4'h9;
    localparam [3:0]   ADC_RX_POLARITY_PHY1_INIT = 4'h1;
    localparam integer ADC_RX_POLARITY_PHY0_HOLD_MS = 250;
    localparam integer ADC_RX_POLARITY_PHY1_HOLD_MS = 4000;
    // Release the AD6688 from forced CGS first, then keep the board-level
    // SYNC asserted for ADC_SYNC_FORCE_ASSERT_MS after the runtime patch.
    localparam integer ADC_CGS_ALIGN_WAIT_MS = 60;
    localparam integer ADC_RUNTIME_PATCH_TIMEOUT_MS = 20;
    localparam integer BOOT_WAIT_TICKS        = BOOT_WAIT_MS * MS_TICKS;
    localparam integer HOLD_WAIT_TICKS        = HOLD_WAIT_MS * MS_TICKS;
    localparam integer ADC_HOLD_WAIT_TICKS    = ADC_HOLD_WAIT_MS * MS_TICKS;
    localparam integer ADC_START_TIMEOUT_TICKS = ADC_START_TIMEOUT_MS * MS_TICKS;
    localparam integer ADC_INIT_TIMEOUT_TICKS  = ADC_INIT_TIMEOUT_MS * MS_TICKS;
    localparam integer JESD_RELEASE_STABLE_TICKS = JESD_RELEASE_STABLE_MS * MS_TICKS;
    localparam integer JESD_READY_STABLE_TICKS   = JESD_READY_STABLE_MS * MS_TICKS;
    localparam integer JESD_RETRY_MISSING_TICKS  = JESD_RETRY_MISSING_MS * MS_TICKS;
    localparam integer JESD_RETRY_RESET_TICKS    = JESD_RETRY_RESET_MS * MS_TICKS;
    localparam integer ADC_RX_REARM_LOCK_TIMEOUT_TICKS =
        ADC_RX_REARM_LOCK_TIMEOUT_MS * MS_TICKS;
    localparam integer ADC_RX_REARM_DROP_TIMEOUT_TICKS =
        ADC_RX_REARM_DROP_TIMEOUT_MS * MS_TICKS;
    localparam integer ADC_RX_REARM_RESET_TICKS =
        ADC_RX_REARM_RESET_MS * MS_TICKS;
    localparam integer ADC_RX_CORE_REINIT_TIMEOUT_TICKS =
        ADC_RX_CORE_REINIT_TIMEOUT_MS * MS_TICKS;
    localparam integer ADC_RX_REARM_GOOD_STABLE_TICKS =
        ADC_RX_REARM_GOOD_STABLE_MS * MS_TICKS;
    localparam integer ADC_RX_GT_RESET_TICKS =
        ADC_RX_GT_RESET_MS * MS_TICKS;
    localparam integer ADC_RX_GT_WAIT_TIMEOUT_TICKS =
        ADC_RX_GT_WAIT_TIMEOUT_MS * MS_TICKS;
    localparam integer ADC_RX_LINK_REINIT_TIMEOUT_TICKS =
        ADC_RX_LINK_REINIT_TIMEOUT_MS * MS_TICKS;
    localparam integer ADC_RX_LINK_REINIT_SETTLE_TICKS =
        ADC_RX_LINK_REINIT_SETTLE_MS * MS_TICKS;
    localparam integer ADC_RX_POLARITY_PHY0_HOLD_TICKS =
        ADC_RX_POLARITY_PHY0_HOLD_MS * MS_TICKS;
    localparam integer ADC_RX_POLARITY_PHY1_HOLD_TICKS =
        ADC_RX_POLARITY_PHY1_HOLD_MS * MS_TICKS;
    localparam integer ADC_CGS_ALIGN_WAIT_TICKS =
        ADC_CGS_ALIGN_WAIT_MS * MS_TICKS;
    localparam integer ADC_RUNTIME_PATCH_TIMEOUT_TICKS =
        ADC_RUNTIME_PATCH_TIMEOUT_MS * MS_TICKS;

    localparam [3:0] ST_BOOT       = 4'd0;
    localparam [3:0] ST_START_HMC  = 4'd1;
    localparam [3:0] ST_WAIT_HMC   = 4'd2;
    localparam [3:0] ST_HOLD_DAC   = 4'd3;
    localparam [3:0] ST_START_DAC  = 4'd4;
    localparam [3:0] ST_WAIT_DAC   = 4'd5;
    localparam [3:0] ST_START_JESD = 4'd6;
    localparam [3:0] ST_WAIT_JESD  = 4'd7;
    localparam [3:0] ST_HOLD_ADC   = 4'd8;
    localparam [3:0] ST_START_ADC  = 4'd9;
    localparam [3:0] ST_WAIT_ADC   = 4'd10;
    localparam [3:0] ST_RUN        = 4'd11;
    localparam [3:0] ST_ADC_FAIL   = 4'd12;
    localparam [3:0] ST_START_RX   = 4'd13;
    localparam [3:0] ST_WAIT_RX    = 4'd14;
    localparam [3:0] ST_RX_ALIGN_WAIT = 4'd15;

    localparam [3:0] JESD_WAIT_NONE         = 4'd0;
    localparam [3:0] JESD_WAIT_CFG          = 4'd1;
    localparam [3:0] JESD_WAIT_PLL          = 4'd2;
    localparam [3:0] JESD_WAIT_ARESETN      = 4'd3;
    localparam [3:0] JESD_WAIT_TREADY       = 4'd4;
    localparam [3:0] JESD_WAIT_RESET_DONE   = 4'd5;
    localparam [3:0] JESD_WAIT_GT_RESETDONE = 4'd6;
    localparam [3:0] JESD_WAIT_POWERGOOD    = 4'd7;

    localparam [7:0] JESD_FAULT_NONE         = 8'h00;
    localparam [7:0] JESD_FAULT_CFG          = 8'h01;
    localparam [7:0] JESD_FAULT_PLL          = 8'h02;
    localparam [7:0] JESD_FAULT_ARESETN      = 8'h03;
    localparam [7:0] JESD_FAULT_TREADY       = 8'h04;
    localparam [7:0] JESD_FAULT_RESET_DONE   = 8'h05;
    localparam [7:0] JESD_FAULT_GT_RESETDONE = 8'h06;
    localparam [7:0] JESD_FAULT_POWERGOOD    = 8'h07;

    localparam [3:0] ADC_RX_REARM_REASON_NONE         = 4'd0;
    localparam [3:0] ADC_RX_REARM_REASON_LOCK_TIMEOUT = 4'd1;
    localparam [3:0] ADC_RX_REARM_REASON_RUN_DROP     = 4'd2;
    localparam [3:0] ADC_RX_REARM_REASON_RETRY_LIMIT  = 4'd3;
    localparam [3:0] ADC_RX_REARM_REASON_LINK_FAIL    = 4'd4;
    localparam [3:0] ADC_RX_REARM_REASON_LINK_TIMEOUT = 4'd5;
    localparam [3:0] ADC_RX_REARM_REASON_CORE_TIMEOUT = 4'd6;
    localparam [3:0] ADC_RX_REARM_REASON_GT_TIMEOUT   = 4'd7;

    localparam [2:0] ADC_RX_REARM_ST_IDLE        = 3'd0;
    localparam [2:0] ADC_RX_REARM_ST_RX_RESET    = 3'd1;
    localparam [2:0] ADC_RX_REARM_ST_LINK_RESET  = 3'd2;
    localparam [2:0] ADC_RX_REARM_ST_LINK_WAIT   = 3'd3;
    localparam [2:0] ADC_RX_REARM_ST_LINK_SETTLE = 3'd4;
    localparam [2:0] ADC_RX_REARM_ST_CORE_REINIT = 3'd5;
    localparam [2:0] ADC_RX_REARM_ST_GT_RESET    = 3'd6;
    localparam [2:0] ADC_RX_REARM_ST_GT_WAIT     = 3'd7;

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
    wire jesd_rx_sysref;
    wire init_rst;
    wire jesd_axi_aresetn;
    wire clock_sdio_i;
    wire clock_sdio_o;
    wire clock_sdio_oe;
    wire adc_sdio_i;
    wire adc_sdio_o;
    wire adc_sdio_oe;
    wire dac_sdio_i;
    wire dac_sdio_o;
    wire dac_sdio_oe;
    wire adc_sync_out;
    wire adc_sync_out_raw;
    wire dac_init_sclk;
    wire dac_init_cs;
    wire dac_init_sdio_o;
    wire dac_init_sdio_oe;
    wire dac_diag_sclk;
    wire dac_diag_cs;
    wire dac_diag_sdio_o;
    wire dac_diag_sdio_oe;
    wire adc_csb_init;
    wire adc_sclk_init;

    reg  adc_sync_drive;
    reg  start_hmc;
    reg  start_dac;
    reg  start_jesd0;
    reg  start_jesd1;
    reg  start_jesd_rx;
    reg  start_adc;
    reg  adc_runtime_patch_start;
    reg  adc_runtime_link_reinit_start;
    reg  adc_runtime_patch_requested;
    reg  adc_runtime_patch_done_latched;
    reg  adc_runtime_patch_fail_latched;
    reg  resetb;
    reg  jesd_rx_cfg_done_seen;
    reg  [15:0] heartbeat;
    reg  [7:0]  jesd_refclk_mon_heartbeat;
    reg  [7:0]  jesd_core_heartbeat;
    reg  [7:0]  jesd_txoutclk_heartbeat0;
    reg  [7:0]  jesd_txoutclk_heartbeat1;
    wire        jesd_refclk_mon_alive_raw;
    wire        jesd_core_alive_raw;
    wire        jesd_txoutclk_alive_raw0;
    wire        jesd_txoutclk_alive_raw1;

    (* mark_debug = "true" *) reg [31:0] boot_count;
    (* mark_debug = "true" *) reg [31:0] hold_count;
    (* mark_debug = "true" *) reg [3:0]  state;
    (* mark_debug = "true" *) reg [15:0] sysref_edge_count;
    (* mark_debug = "true" *) reg [15:0] jesd_refclk_mon_edge_count;
    (* mark_debug = "true" *) reg [15:0] jesd_core_alive_edge_count;
    (* mark_debug = "true" *) reg [15:0] jesd_txoutclk_edge_count0;
    (* mark_debug = "true" *) reg [15:0] jesd_txoutclk_edge_count1;
    (* mark_debug = "true" *) reg [31:0] jesd_refclk_mon_cycles_1ms;
    (* mark_debug = "true" *) reg [15:0] dac_sync0_edge_count;
    (* mark_debug = "true" *) reg [15:0] dac_sync1_edge_count;
    (* mark_debug = "true" *) reg        sysref2_d;
    (* mark_debug = "true" *) reg        dac_sync0_d;
    (* mark_debug = "true" *) reg        dac_sync1_raw_d;
    (* mark_debug = "true" *) reg        dac_sync1_d;
    (* mark_debug = "true" *) reg        dac_sdo_d;
    (* mark_debug = "true" *) reg        jesd_refclk_mon_dbg;
    (* mark_debug = "true" *) reg        jesd_core_alive_dbg;
    (* mark_debug = "true" *) reg        jesd_txoutclk_dbg0;
    (* mark_debug = "true" *) reg        jesd_txoutclk_dbg1;
    (* mark_debug = "true" *) reg        jesd_release;
    (* mark_debug = "true" *) reg        jesd_release_seen;
    (* mark_debug = "true" *) reg        jesd_cfg_done_seen;
    (* mark_debug = "true" *) reg        jesd_links_ready_seen;
    (* mark_debug = "true" *) reg        jesd_links_ready_stable_seen;
    (* mark_debug = "true" *) reg [31:0] jesd_release_stable_count;
    (* mark_debug = "true" *) reg [31:0] jesd_links_ready_stable_count;
    (* mark_debug = "true" *) reg [15:0] jesd_links_ready_drop_count;
    (* mark_debug = "true" *) reg [31:0] jesd_pll_missing_count;
    (* mark_debug = "true" *) reg [31:0] jesd_retry_reset_count;
    (* mark_debug = "true" *) reg [15:0] jesd_retry_count;
    (* mark_debug = "true" *) reg [1:0]  jesd_start_seen;
    (* mark_debug = "true" *) reg [1:0]  jesd_done_seen;
    (* mark_debug = "true" *) reg        jesd_refclk_mon_seen;
    (* mark_debug = "true" *) reg        jesd_core_alive_seen;
    (* mark_debug = "true" *) reg        jesd_txoutclk_seen0;
    (* mark_debug = "true" *) reg        jesd_txoutclk_seen1;
    (* mark_debug = "true" *) reg [3:0]  jesd_wait_reason_dbg;
    (* mark_debug = "true" *) reg [3:0]  jesd_wait_reason_latched;
    (* mark_debug = "true" *) reg [7:0]  jesd_fault_code_dbg;
    (* mark_debug = "true" *) reg [7:0]  jesd_fault_code_latched;
    (* mark_debug = "true" *) reg        adc_diag_bypass_taken;

    reg [31:0] refclk_mon_counter;
    reg [31:0] refclk_mon_gray_src;
    wire [31:0] refclk_mon_counter_next;
    wire [31:0] refclk_mon_gray_next;
    (* ASYNC_REG = "TRUE" *) reg [31:0] refclk_mon_gray_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] refclk_mon_gray_sync;
    wire [31:0] refclk_mon_count_sync;
    reg [31:0] refclk_mon_count_prev;
    reg [17:0] refclk_measure_count;

    function [31:0] gray_to_bin32;
        input [31:0] gray;
        integer i;
        begin
            gray_to_bin32[31] = gray[31];
            for (i = 30; i >= 0; i = i - 1) begin
                gray_to_bin32[i] = gray_to_bin32[i + 1] ^ gray[i];
            end
        end
    endfunction

    (* mark_debug = "true" *) wire hmc_busy;
    (* mark_debug = "true" *) wire hmc_done;
    (* mark_debug = "true" *) wire hmc_ok;
    (* mark_debug = "true" *) wire hmc_fail;
    (* mark_debug = "true" *) wire dac_busy;
    (* mark_debug = "true" *) wire dac_done;
    (* mark_debug = "true" *) wire adc_busy;
    (* mark_debug = "true" *) wire adc_done;
    (* mark_debug = "true" *) wire dac_init_ok;
    (* mark_debug = "true" *) wire dac_init_fail;
    (* mark_debug = "true" *) wire adc_init_ok;
    (* mark_debug = "true" *) wire adc_init_fail;

    (* mark_debug = "true" *) reg  hmc_ok_latched;
    (* mark_debug = "true" *) reg  hmc_fail_latched;
    (* mark_debug = "true" *) reg  [39:0] hmc_status_latched;
    (* mark_debug = "true" *) reg  adc_ok_latched;
    (* mark_debug = "true" *) reg  adc_fail_latched;
    (* mark_debug = "true" *) reg  [15:0] adc_status_latched;
    (* mark_debug = "true" *) reg  dac_ok_latched;
    (* mark_debug = "true" *) reg  dac_fail_latched;
    (* mark_debug = "true" *) reg  [31:0] dac_status_latched;
    (* mark_debug = "true" *) reg  [31:0] dac_sanity_latched;
    (* mark_debug = "true" *) reg  [31:0] dac_debug_latched;

    wire [39:0] hmc_status_dbg;
    wire [6:0]  hmc_verify_group_ok;
    wire        hmc_verify_done;
    wire        hmc_verify_fail_any;
    wire [15:0] hmc_verify_mismatch_addr;
    wire [7:0]  hmc_verify_mismatch_data;
    wire [7:0]  hmc_verify_mismatch_expect;
    wire [31:0] hmc_ch4_snapshot_dbg;
    wire [4:0]  hmc_debug_state;
    wire [13:0] hmc_debug_retry_count;
    wire [15:0] hmc_debug_read_addr;
    wire [7:0]  hmc_debug_read_data;
    wire        hmc_debug_read_busy;
    wire        hmc_debug_read_done;
    wire        hmc_debug_pll1_locked;
    wire [31:0] dac_init_status_dbg;
    wire [31:0] dac_init_sanity_dbg;
    wire [31:0] dac_init_debug_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_spi_live_dbg;
    wire [15:0] adc_init_status_dbg;
    wire [4:0]  adc_debug_state;
    wire [3:0]  adc_debug_retry_count;
    wire [31:0] adc_debug_wait_counter;
    wire [15:0] adc_debug_read_addr;
    wire [7:0]  adc_debug_read_data;
    wire        adc_debug_read_busy;
    wire        adc_debug_read_done;
    wire [23:0] adc_debug_patch_word;
    wire        adc_debug_retry_clock_check;
    wire [31:0] adc_debug_clk_trace;
    wire [31:0] adc_debug_fail_detail;
    wire [31:0] adc_init_fsm_dbg;
    wire [31:0] adc_init_read_dbg;
    wire [31:0] adc_init_patch_dbg;
    wire [31:0] adc_debug_jesd_ctrl;
    wire [31:0] adc_debug_jesd_param;
    wire [31:0] adc_debug_lane_map;
    wire [31:0] adc_debug_sysref;
    wire [31:0] adc_debug_serdes;
    wire [31:0] adc_debug_link_extra;
    wire [31:0] adc_debug_serdes_cfg;
    wire [31:0] adc_debug_serdes_emph;
    wire [31:0] adc_debug_jesd_param_ext;
    wire [31:0] adc_debug_checksum03;
    wire [31:0] adc_debug_checksum47;
    wire [31:0] adc_debug_lid03;
    wire [31:0] adc_debug_lid47;
    wire [31:0] adc_debug_runtime_patch;
    wire [31:0] adc_debug_runtime_link_reinit;
    wire        adc_runtime_patch_busy;
    wire        adc_runtime_patch_done;
    wire        adc_runtime_patch_fail;
    wire        adc_runtime_link_reinit_busy;
    wire        adc_runtime_link_reinit_done;
    wire        adc_runtime_link_reinit_fail;
    (* mark_debug = "true" *) reg [31:0] adc_init_patch_dbg_q;
    wire [31:0] hmc_verify_status_dbg;
    wire [31:0] hmc_verify_mismatch_dbg;

    wire jesd_busy0;
    wire jesd_done0;
    wire jesd_busy1;
    wire jesd_done1;
    wire jesd_rx_busy;
    wire jesd_rx_done;

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
    wire [11:0] jesd0_s_axi_araddr;
    wire        jesd0_s_axi_arvalid;
    wire        jesd0_s_axi_arready;
    wire [31:0] jesd0_s_axi_rdata;
    wire [1:0]  jesd0_s_axi_rresp;
    wire        jesd0_s_axi_rvalid;
    wire        jesd0_s_axi_rready;

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
    wire [11:0] jesd1_s_axi_araddr;
    wire        jesd1_s_axi_arvalid;
    wire        jesd1_s_axi_arready;
    wire [31:0] jesd1_s_axi_rdata;
    wire [1:0]  jesd1_s_axi_rresp;
    wire        jesd1_s_axi_rvalid;
    wire        jesd1_s_axi_rready;

    wire [11:0] jesdrx_s_axi_awaddr;
    wire        jesdrx_s_axi_awvalid;
    wire        jesdrx_s_axi_awready;
    wire [31:0] jesdrx_s_axi_wdata;
    wire [3:0]  jesdrx_s_axi_wstrb;
    wire        jesdrx_s_axi_wvalid;
    wire        jesdrx_s_axi_wready;
    wire [1:0]  jesdrx_s_axi_bresp;
    wire        jesdrx_s_axi_bvalid;
    wire        jesdrx_s_axi_bready;
    wire [11:0] jesdrx_s_axi_araddr;
    wire        jesdrx_s_axi_arvalid;
    wire        jesdrx_s_axi_arready;
    wire [31:0] jesdrx_s_axi_rdata;
    wire [1:0]  jesdrx_s_axi_rresp;
    wire        jesdrx_s_axi_rvalid;
    wire        jesdrx_s_axi_rready;

    wire [11:0] phy0_s_axi_awaddr;
    wire        phy0_s_axi_awvalid;
    wire        phy0_s_axi_awready;
    wire [31:0] phy0_s_axi_wdata;
    wire        phy0_s_axi_wvalid;
    wire        phy0_s_axi_wready;
    wire [1:0]  phy0_s_axi_bresp;
    wire        phy0_s_axi_bvalid;
    wire        phy0_s_axi_bready;
    wire [11:0] phy0_s_axi_araddr;
    wire        phy0_s_axi_arvalid;
    wire        phy0_s_axi_arready;
    wire [31:0] phy0_s_axi_rdata;
    wire [1:0]  phy0_s_axi_rresp;
    wire        phy0_s_axi_rvalid;
    wire        phy0_s_axi_rready;

    wire [11:0] phy1_s_axi_awaddr;
    wire        phy1_s_axi_awvalid;
    wire        phy1_s_axi_awready;
    wire [31:0] phy1_s_axi_wdata;
    wire        phy1_s_axi_wvalid;
    wire        phy1_s_axi_wready;
    wire [1:0]  phy1_s_axi_bresp;
    wire        phy1_s_axi_bvalid;
    wire        phy1_s_axi_bready;
    wire [11:0] phy1_s_axi_araddr;
    wire        phy1_s_axi_arvalid;
    wire        phy1_s_axi_arready;
    wire [31:0] phy1_s_axi_rdata;
    wire [1:0]  phy1_s_axi_rresp;
    wire        phy1_s_axi_rvalid;
    wire        phy1_s_axi_rready;

    wire [255:0] tx_pattern_data;
    wire [127:0] jesd_tx_data0;
    wire [127:0] jesd_tx_data1;
    wire [15:0]  tone_dac0_sample0;
    wire [15:0]  tone_dac1_sample0;
    wire [15:0]  tone_dac2_sample0;
    wire [15:0]  tone_dac3_sample0;

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
    wire [3:0]  jesd_gt_rxresetdone0;
    wire [3:0]  jesd_gt_rxresetdone1;
    wire [3:0]  jesd_gt_rxpmaresetdone0;
    wire [3:0]  jesd_gt_rxpmaresetdone1;
    wire [3:0]  jesd_gt_rxcommadet0;
    wire [3:0]  jesd_gt_rxcommadet1;
    wire [11:0] jesd_gt_rxbufstatus0;
    wire [11:0] jesd_gt_rxbufstatus1;
    wire        jesd_phy_rx_reset_done0;
    wire        jesd_phy_rx_reset_done1;
    wire [3:0]  jesd_gt_cplllock0;
    wire [3:0]  jesd_gt_cplllock1;
    wire        jesd_qpll0_lock0;
    wire        jesd_qpll1_lock0;
    wire        jesd_qpll0_lock1;
    wire        jesd_qpll1_lock1;
    wire [7:0]  jesd_gt_plllock;
    wire [3:0]  jesd_qpll_lock_raw;
    wire        jesd_cfg_done;
    wire        jesd_links_ready;
    wire        jesd_release_ready;
    wire        jesd_pll_ready_dbg;
    wire [1:0]  tx_tone_advance;
    wire [1:0]  tx_tone_reset;
    wire        phy0_axi_done_seen;
    wire        phy1_axi_done_seen;
    wire        phy_axi_cfg_done;
    wire        jesd_rx_release_ready_sys;
    wire        adc_rx_rearm_monitor_ready;
    wire        adc_rx_rearm_gt_live_clean;
    wire        adc_rx_diag_base_ready;
    wire        adc_rx_gt_reset_ready;
    wire        adc_rx_gt_reset_control_active;
    wire        adc_rx_rearm_good_now;
    wire        adc_rx_rearm_bad_now;
    wire        adc_rx_diag_gt_live_clean_q;
    wire        adc_rx_diag_good_now;
    wire        adc_rx_diag_bad_now;
    wire [7:0]  adc_rx_first_drop_cause_now;
    wire        sysref2_rise_sys;
    wire        jesd_rx_enable;
    wire        jesd_rx_core_reset;
    wire        jesd_rx_aresetn;
    wire        jesd_rx_reset_gt_core;
    wire        jesd_rx_reset_gt;
    wire        jesd_rx_reset_done;
    wire        jesd_rx_sync;
    wire        jesd_rx_encommaalign;
    wire        jesd_rx_tvalid;
    wire [255:0] jesd_rx_tdata;
    wire [255:0] jesd_rx_tdata_logical;
    wire [3:0]  jesd_rx_sof;
    wire [3:0]  jesd_rx_somf;
    wire [31:0] jesd_rx_frm_err;
    wire [7:0]  jesd_gt_rxresetdone;
    wire [7:0]  jesd_gt_rxdisperr_any;
    wire [7:0]  jesd_gt_rxnotintable_any;
    wire [7:0]  jesd_gt_rxcharisk_any;
    wire [7:0]  jesd_gt_rxblock_sync;
    wire [7:0]  jesd_gt_rxmisalign;
    wire [7:0]  jesd_gt_rxcommadet;
    wire [7:0]  jesd_gt_rxcommadet_current;
    wire [7:0]  jesd_gt_rxpmaresetdone;
    wire [23:0] jesd_gt_rxbufstatus;
    wire [31:0] jesd_gt_rxcharisk_full;
    wire [31:0] jesd_gt_rxdisperr_full;
    wire [31:0] jesd_gt_rxnotintable_full;
    wire [31:0] jesd_rx_lane01_data_low;
    wire [31:0] jesd_rx_lane23_data_low;
    wire [31:0] jesd_rx_lane45_data_low;
    wire [31:0] jesd_rx_lane67_data_low;
    wire [63:0] jesd_rx_snapshot_lane_data;
    wire [3:0]  jesd_rx_snapshot_lane_charisk;
    wire [3:0]  jesd_rx_snapshot_lane_disperr;
    wire [3:0]  jesd_rx_snapshot_lane_notintable;
    wire        jesd_rx_snapshot_lane_block_sync;
    wire [15:0] jesd_rx_snapshot_data_word;
    wire [1:0]  jesd_rx_snapshot_charisk_word;
    wire [1:0]  jesd_rx_snapshot_disperr_word;
    wire [1:0]  jesd_rx_snapshot_notintable_word;
    reg  [7:0]  jesd_gt_rxdisperr_seen_jclk;
    reg  [7:0]  jesd_gt_rxnotintable_seen_jclk;
    reg  [7:0]  jesd_gt_rxcharisk_seen_jclk;
    reg  [7:0]  jesd_gt_rxblock_sync_seen_jclk;
    reg  [7:0]  jesd_gt_rxcommadet_seen_jclk;

    wire        adc0_sample_valid;
    wire [63:0] adc0_sample_data;
    wire [31:0] adc0_sample_beat_count;
    wire [15:0] adc0_first_sample_dbg;
    wire [13:0] adc_udp_ram_rd_addr;
    wire        adc_udp_ram_rd_req;
    wire        adc_udp_ram_rd_ready;
    wire        adc_udp_ram_rd_valid;
    wire [7:0]  adc_udp_ram_rd_byte;
    wire        adc_udp_pkt_busy;
    wire        adc_udp_pkt_done;
    wire [31:0] adc_udp_packet_count;
    wire [31:0] adc_udp_prefetch_count;
    wire [7:0]  adc_udp_tx_data;
    wire        adc_udp_tx_valid;
    wire        adc_udp_rst;
    wire        adc_udp_capture_active_jclk;
    wire        adc_udp_wait_pkt_done_jclk;
    wire        adc_udp_pkt_done_seen_jclk;
    wire [31:0] adc_udp_capture_good_count_jclk;
    wire [31:0] adc_udp_repeat_count_jclk;
    wire [ADC_UDP_CAPTURE_ADDR_W-1:0] adc_udp_wr_addr_jclk;
    wire [31:0] adc_udp_capture_id_jclk;
    wire [31:0] adc_udp_capture_count_jclk;
    wire [31:0] adc_udp_drop_count_jclk;
    wire [31:0] adc_udp_good_window_count_jclk;
    wire [31:0] adc_udp_pkt_capture_id_eth;
    wire        adc_udp_pkt_start_eth;
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
    wire [31:0] dac_cfg_rx_packet_count;
    wire [31:0] dac_cfg_rx_config_count;
    wire [31:0] dac_cfg_rx_data_count;
    wire [31:0] dac_cfg_rx_commit_count;
    wire [31:0] dac_cfg_rx_drop_count;
    wire [31:0] dac_cfg_rx_status_dbg;
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
    reg         dac_cfg_reset_phase_jclk;
    reg [47:0] dac_cfg_phase_inc0_jclk;
    reg [47:0] dac_cfg_phase_inc1_jclk;
    reg [47:0] dac_cfg_phase_inc2_jclk;
    reg [47:0] dac_cfg_phase_inc3_jclk;
    reg [15:0] dac_cfg_scale0_jclk;
    reg [15:0] dac_cfg_scale1_jclk;
    reg [15:0] dac_cfg_scale2_jclk;
    reg [15:0] dac_cfg_scale3_jclk;
    reg [31:0] dac_cfg_apply_count_jclk;
    reg        dac_cfg_apply_pulse_jclk;
    wire        dac_cfg_valid_jclk;
    wire [31:0] dac_cfg_status_dbg;

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

    wire [63:0] jesd_rx_gt0_rxdata;
    wire [63:0] jesd_rx_gt1_rxdata;
    wire [63:0] jesd_rx_gt2_rxdata;
    wire [63:0] jesd_rx_gt3_rxdata;
    wire [63:0] jesd_rx_gt4_rxdata;
    wire [63:0] jesd_rx_gt5_rxdata;
    wire [63:0] jesd_rx_gt6_rxdata;
    wire [63:0] jesd_rx_gt7_rxdata;
    wire [3:0]  jesd_rx_gt0_rxcharisk;
    wire [3:0]  jesd_rx_gt1_rxcharisk;
    wire [3:0]  jesd_rx_gt2_rxcharisk;
    wire [3:0]  jesd_rx_gt3_rxcharisk;
    wire [3:0]  jesd_rx_gt4_rxcharisk;
    wire [3:0]  jesd_rx_gt5_rxcharisk;
    wire [3:0]  jesd_rx_gt6_rxcharisk;
    wire [3:0]  jesd_rx_gt7_rxcharisk;
    wire [3:0]  jesd_rx_gt0_rxdisperr;
    wire [3:0]  jesd_rx_gt1_rxdisperr;
    wire [3:0]  jesd_rx_gt2_rxdisperr;
    wire [3:0]  jesd_rx_gt3_rxdisperr;
    wire [3:0]  jesd_rx_gt4_rxdisperr;
    wire [3:0]  jesd_rx_gt5_rxdisperr;
    wire [3:0]  jesd_rx_gt6_rxdisperr;
    wire [3:0]  jesd_rx_gt7_rxdisperr;
    wire [3:0]  jesd_rx_gt0_rxnotintable;
    wire [3:0]  jesd_rx_gt1_rxnotintable;
    wire [3:0]  jesd_rx_gt2_rxnotintable;
    wire [3:0]  jesd_rx_gt3_rxnotintable;
    wire [3:0]  jesd_rx_gt4_rxnotintable;
    wire [3:0]  jesd_rx_gt5_rxnotintable;
    wire [3:0]  jesd_rx_gt6_rxnotintable;
    wire [3:0]  jesd_rx_gt7_rxnotintable;
    wire [1:0]  jesd_rx_gt0_rxheader;
    wire [1:0]  jesd_rx_gt1_rxheader;
    wire [1:0]  jesd_rx_gt2_rxheader;
    wire [1:0]  jesd_rx_gt3_rxheader;
    wire [1:0]  jesd_rx_gt4_rxheader;
    wire [1:0]  jesd_rx_gt5_rxheader;
    wire [1:0]  jesd_rx_gt6_rxheader;
    wire [1:0]  jesd_rx_gt7_rxheader;
    wire        jesd_rx_gt0_rxmisalign;
    wire        jesd_rx_gt1_rxmisalign;
    wire        jesd_rx_gt2_rxmisalign;
    wire        jesd_rx_gt3_rxmisalign;
    wire        jesd_rx_gt4_rxmisalign;
    wire        jesd_rx_gt5_rxmisalign;
    wire        jesd_rx_gt6_rxmisalign;
    wire        jesd_rx_gt7_rxmisalign;
    wire        jesd_rx_gt0_rxblock_sync;
    wire        jesd_rx_gt1_rxblock_sync;
    wire        jesd_rx_gt2_rxblock_sync;
    wire        jesd_rx_gt3_rxblock_sync;
    wire        jesd_rx_gt4_rxblock_sync;
    wire        jesd_rx_gt5_rxblock_sync;
    wire        jesd_rx_gt6_rxblock_sync;
    wire        jesd_rx_gt7_rxblock_sync;

    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_aresetn_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_tready_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_tx_reset_done_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_gt_powergood_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_tx_reset_gt_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_txresetdone_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_cplllock_meta;
    (* ASYNC_REG = "TRUE" *) reg [3:0] jesd_qpll_lock_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_refclk_mon_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_core_alive_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_txoutclk_meta0;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_txoutclk_meta1;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_rx_tvalid_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_rx_sync_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_rx_aresetn_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_rx_reset_gt_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_rx_enable_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_rx_encommaalign_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxresetdone_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxresetdone_sync;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxdisperr_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxnotintable_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxcharisk_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxblock_sync_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxmisalign_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxcommadet_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxpmaresetdone_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxpmaresetdone_sync;
    (* ASYNC_REG = "TRUE" *) reg [23:0] jesd_gt_rxbufstatus_meta;
    (* ASYNC_REG = "TRUE" *) reg [23:0] jesd_gt_rxbufstatus_sync;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxdisperr_seen_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxnotintable_seen_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxcharisk_seen_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxblock_sync_seen_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0] jesd_gt_rxcommadet_seen_meta;
    (* ASYNC_REG = "TRUE" *) reg [2:0] adc_runtime_patch_done_meta_jclk;
    (* ASYNC_REG = "TRUE" *) reg [2:0] adc_runtime_patch_fail_meta_jclk;
    reg adc_runtime_gt_seen_cleared_jclk;

    assign jesd_refclk_mon_alive_raw = jesd_refclk_mon_heartbeat[7];
    assign jesd_core_alive_raw = jesd_core_heartbeat[7];
    assign jesd_txoutclk_alive_raw0 = jesd_txoutclk_heartbeat0[7];
    assign jesd_txoutclk_alive_raw1 = jesd_txoutclk_heartbeat1[7];
    assign jesd_qpll_lock_raw = (JESD_USE_QPLL != 0) ? {
        jesd_qpll1_lock1,
        jesd_qpll0_lock1,
        jesd_qpll1_lock0,
        jesd_qpll0_lock0
    } : 4'd0;
    assign jesd_gt_plllock = (JESD_USE_QPLL != 0) ?
        {{4{jesd_qpll0_lock1}}, {4{jesd_qpll0_lock0}}} :
        {jesd_gt_cplllock1, jesd_gt_cplllock0};
    assign refclk_mon_counter_next = refclk_mon_counter + 1'b1;
    assign refclk_mon_gray_next = refclk_mon_counter_next ^ {1'b0, refclk_mon_counter_next[31:1]};
    assign refclk_mon_count_sync = gray_to_bin32(refclk_mon_gray_sync);

    (* mark_debug = "true" *) reg [1:0] jesd_busy_dbg;
    (* mark_debug = "true" *) reg [1:0] jesd_done_dbg;
    (* mark_debug = "true" *) reg [1:0] jesd_aresetn_dbg;
    (* mark_debug = "true" *) reg [1:0] jesd_tready_dbg;
    (* mark_debug = "true" *) reg [1:0] jesd_tx_reset_done_dbg;
    (* mark_debug = "true" *) reg [1:0] jesd_gt_powergood_dbg;
    (* mark_debug = "true" *) reg [1:0] jesd_tx_reset_gt_dbg;
    (* mark_debug = "true" *) reg [7:0] jesd_gt_txresetdone_dbg;
    (* mark_debug = "true" *) reg [7:0] jesd_cplllock_dbg;
    (* mark_debug = "true" *) reg [7:0] jesd_cplllock_seen;
    (* mark_debug = "true" *) reg [7:0] jesd_gt_txresetdone_seen;
    (* mark_debug = "true" *) reg [15:0] jesd_cplllock_rise_count;
    (* mark_debug = "true" *) reg [15:0] jesd_gt_txresetdone_rise_count;
    (* mark_debug = "true" *) reg [3:0] jesd_qpll_lock_dbg;
    (* mark_debug = "true" *) reg [3:0] jesd_qpll_lock_seen;
    (* mark_debug = "true" *) reg [15:0] jesd_qpll_lock_rise_count;
    (* mark_debug = "true" *) wire [31:0] phy0_axi_status_dbg;
    (* mark_debug = "true" *) wire [31:0] phy0_axi_txlinerate_dbg;
    (* mark_debug = "true" *) wire [31:0] phy0_axi_txrefclk_dbg;
    (* mark_debug = "true" *) wire [31:0] phy0_axi_ctrl_dbg;
    (* mark_debug = "true" *) wire [31:0] phy0_axi_fsm_dbg;
    (* mark_debug = "true" *) wire [31:0] phy0_axi_txctrl_dbg;
    (* mark_debug = "true" *) wire [31:0] phy0_axi_rxsweep_dbg;
    (* mark_debug = "true" *) wire [31:0] phy1_axi_status_dbg;
    (* mark_debug = "true" *) wire [31:0] phy1_axi_txlinerate_dbg;
    (* mark_debug = "true" *) wire [31:0] phy1_axi_txrefclk_dbg;
    (* mark_debug = "true" *) wire [31:0] phy1_axi_ctrl_dbg;
    (* mark_debug = "true" *) wire [31:0] phy1_axi_fsm_dbg;
    (* mark_debug = "true" *) wire [31:0] phy1_axi_txctrl_dbg;
    (* mark_debug = "true" *) wire [31:0] phy1_axi_rxsweep_dbg;
    (* mark_debug = "true" *) wire        dac_link_diag_running;
    (* mark_debug = "true" *) wire        dac_link_diag_done_seen;
    (* mark_debug = "true" *) wire [31:0] dac_link0_status_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link1_status_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link0_error_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link1_error_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link0_ilas0_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link1_ilas0_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link0_ilas1_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link1_ilas1_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link0_lid_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link1_lid_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link0_checksum_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link1_checksum_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link0_compsum_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link1_compsum_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_datapath_cfg_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_nco_ftw_low_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_nco_ftw_high_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_lane_cfg_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_serdes_cfg_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_polarity_cfg_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_sweep_ctrl_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_sweep_result_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd0_tx_status_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd1_tx_status_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd0_tx_reset_lanes_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd1_tx_reset_lanes_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd0_tx_cfg_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd1_tx_cfg_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd0_tx_ila1_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd1_tx_ila1_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd0_tx_ila2_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd1_tx_ila2_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd0_tx_laneids_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd1_tx_laneids_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd0_tx_axi_live_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd1_tx_axi_live_dbg;
    (* mark_debug = "true" *) reg         jesd_rx_tvalid_dbg;
    (* mark_debug = "true" *) reg         jesd_rx_tvalid_seen;
    (* mark_debug = "true" *) reg         jesd_rx_sync_dbg;
    (* mark_debug = "true" *) reg         jesd_rx_sync_seen_low;
    (* mark_debug = "true" *) reg         jesd_rx_sync_seen_high;
    (* mark_debug = "true" *) reg         jesd_rx_sync_at_patch_start;
    (* mark_debug = "true" *) reg         jesd_rx_sync_at_patch_done;
    (* mark_debug = "true" *) reg         jesd_rx_encommaalign_dbg;
    (* mark_debug = "true" *) reg         jesd_rx_aresetn_dbg;
    (* mark_debug = "true" *) reg         jesd_rx_reset_gt_dbg;
    (* mark_debug = "true" *) reg         jesd_rx_enable_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxresetdone_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxresetdone_seen;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxdisperr_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxnotintable_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxcharisk_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxblock_sync_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxmisalign_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxcommadet_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxpmaresetdone_dbg;
    (* mark_debug = "true" *) reg [23:0]  jesd_gt_rxbufstatus_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxdisperr_seen_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxnotintable_seen_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxcharisk_seen_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxblock_sync_seen_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxcommadet_seen_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxdisperr_post_patch_seen_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxnotintable_post_patch_seen_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxcharisk_post_patch_seen_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxblock_sync_post_patch_seen_dbg;
    (* mark_debug = "true" *) reg [7:0]   jesd_gt_rxcommadet_post_patch_seen_dbg;
    (* mark_debug = "true" *) wire [7:0]  jesd_gt_rxbufstatus_nonzero_dbg;
    wire [7:0]  jesd_gt_rxbufstatus_nonzero_sync;
    (* mark_debug = "true" *) reg [15:0]  jesd_gt_rxresetdone_rise_count;
    (* mark_debug = "true" *) reg [15:0]  jesd_rx_tvalid_rise_count;
    (* mark_debug = "true" *) reg [15:0]  jesd_rx_sync_toggle_count;
    (* mark_debug = "true" *) reg [7:0]   jesd_rx_sync_rise_count;
    (* mark_debug = "true" *) reg [7:0]   jesd_rx_sync_fall_count;
    (* mark_debug = "true" *) reg [15:0]  jesd_rx_disperr_event_count;
    (* mark_debug = "true" *) reg [15:0]  jesd_rx_notintable_event_count;
    (* mark_debug = "true" *) reg         adc_rx_diag_sync_q;
    (* mark_debug = "true" *) reg         adc_rx_diag_tvalid_q;
    (* mark_debug = "true" *) reg         adc_rx_diag_encommaalign_q;
    (* mark_debug = "true" *) reg         adc_rx_diag_aresetn_q;
    (* mark_debug = "true" *) reg         adc_rx_diag_reset_gt_q;
    (* mark_debug = "true" *) reg [7:0]   adc_rx_diag_gt_disperr_q;
    (* mark_debug = "true" *) reg [7:0]   adc_rx_diag_gt_notintable_q;
    (* mark_debug = "true" *) reg [7:0]   adc_rx_diag_gt_rxbufstatus_nonzero_q;
    (* mark_debug = "true" *) reg [15:0]  adc_rx_diag_sysref_count_q;
    (* mark_debug = "true" *) reg         adc_rx_first_good_seen;
    (* mark_debug = "true" *) reg         adc_rx_first_drop_seen;
    (* mark_debug = "true" *) reg [31:0]  adc_rx_first_good_age_count;
    (* mark_debug = "true" *) reg [31:0]  adc_rx_first_drop_age_count;
    (* mark_debug = "true" *) reg [15:0]  adc_rx_first_good_sysref_count;
    (* mark_debug = "true" *) reg [15:0]  adc_rx_first_drop_sysref_count;
    (* mark_debug = "true" *) reg [7:0]   adc_rx_first_drop_cause;
    (* mark_debug = "true" *) reg [31:0]  jesd_rx_first_good_dbg;
    (* mark_debug = "true" *) reg [31:0]  jesd_rx_first_drop_dbg;
    (* mark_debug = "true" *) reg [31:0]  jesd_rx_first_drop_age_dbg;
    (* mark_debug = "true" *) reg [31:0]  jesd_rx_first_drop_sysref_dbg;
    (* mark_debug = "true" *) reg [31:0]  jesd_rx_data_snapshot_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_status_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_err_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_debug_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_cfg_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lanes_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane0_ilas0_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane0_ilas1_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane0_ilas2_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane0_ilas3_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane0_ilas4_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane0_ilas5_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane1_ilas3_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane2_ilas3_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane3_ilas0_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane3_ilas1_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane3_ilas2_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane3_ilas3_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane3_ilas4_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane3_ilas5_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane4_ilas3_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane5_ilas3_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane6_ilas3_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_lane7_ilas3_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_ilas3_lanes03_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_ilas3_lanes47_dbg;
    wire [31:0] jesd_rx_axi_live_raw_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_axi_live_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_link_summary_dbg;
    wire [31:0] adc_rx_rearm_dbg;
    (* mark_debug = "true" *) reg [31:0] adc_rx_rearm_dbg_q;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_gt_summary_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_gt_detail0_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_rx_gt_detail1_dbg;
    (* mark_debug = "true" *) wire [31:0] adc_udp_ctrl_dbg;
    (* mark_debug = "true" *) wire [31:0] adc_udp_capture_count_dbg;
    (* mark_debug = "true" *) wire [31:0] adc_udp_drop_count_dbg;
    (* mark_debug = "true" *) wire [31:0] adc_udp_packet_count_dbg;
    (* mark_debug = "true" *) wire [31:0] adc_udp_eth_dbg;
    wire [7:0] jesd_gt_rxdisperr_summary_seen_dbg;
    wire [7:0] jesd_gt_rxnotintable_summary_seen_dbg;
    wire [7:0] jesd_gt_rxblock_sync_summary_seen_dbg;
    wire [7:0] jesd_gt_rxcommadet_summary_seen_dbg;
    (* mark_debug = "true" *) reg [31:0] jesd_rx_gt_octets01_dbg;
    (* mark_debug = "true" *) reg [31:0] jesd_rx_gt_octets23_dbg;
    (* mark_debug = "true" *) reg [31:0] jesd_rx_gt_octets45_dbg;
    (* mark_debug = "true" *) reg [31:0] jesd_rx_gt_octets67_dbg;
    wire        jesd_aresetn_ready_dbg;
    wire        jesd_tready_ready_dbg;
    wire        jesd_links_ready_no_tready;
    wire        adc_diag_bypass_ready;
    wire        adc_start_gate_ready;
    wire        jesd_tx_reset_done_ready_dbg;
    wire        jesd_gt_txresetdone_ready_dbg;
    wire        jesd_gt_powergood_ready_dbg;
    wire        jesd_tx_clock_observed_dbg;
    wire [3:0]  jesd_wait_reason_next;
    wire [7:0]  jesd_fault_code_next;
    (* mark_debug = "true" *) wire [15:0] jesd_ready_flags_dbg;
    (* mark_debug = "true" *) wire [31:0] jesd_ready_summary_dbg;
    (* mark_debug = "true" *) wire [31:0] adc_diag_bypass_dbg;
    wire [31:0] adc_sync_loop_dbg;
    (* mark_debug = "true" *) reg [31:0] adc_sync_loop_dbg_q;
    reg  [4:0]  tone_snapshot_div;
    reg  [31:0] tone_dac0_pair01_jclk;
    reg  [31:0] tone_dac0_pair23_jclk;
    reg  [31:0] tone_dac1_pair01_jclk;
    reg  [31:0] tone_dac1_pair23_jclk;
    reg         tone_snapshot_toggle_jclk;
    reg  [4:0]  jesd_rx_snapshot_div;
    reg  [2:0]  jesd_rx_snapshot_lane_jclk;
    reg         jesd_rx_snapshot_group_jclk;
    reg  [31:0] jesd_rx_data_snapshot_jclk;
    reg  [31:0] jesd_rx_gt_octets01_jclk;
    reg  [31:0] jesd_rx_gt_octets23_jclk;
    reg  [31:0] jesd_rx_gt_octets45_jclk;
    reg  [31:0] jesd_rx_gt_octets67_jclk;
    reg         jesd_rx_snapshot_toggle_jclk;
    (* ASYNC_REG = "TRUE" *) reg [2:0] jesd_rx_release_meta_jclk;
    (* ASYNC_REG = "TRUE" *) reg [2:0] sysref2_meta_jclk;
    (* ASYNC_REG = "TRUE" *) reg [1:0] adc_sync_drive_meta_jclk;
    reg         jesd_rx_enable_jclk;
    reg         jesd_rx_sysref_gated_jclk;
    reg  [3:0]  jesd_rx_sysref_pulse_count_jclk;
    reg         jesd_rx_sysref_gate_done_jclk;
    reg         adc_sync_out_jclk;
    reg  [31:0] adc_sync_force_count_jclk;
    reg         adc_sync_force_active_jclk;
    reg         adc_sync_hold_locked_jclk;
    reg  [31:0] adc_sync_hold_good_count_jclk;
    reg  [31:0] adc_sync_hold_drop_count_jclk;
    reg         adc_sync_hold_drop_seen_jclk;
    wire        adc_runtime_patch_finished_jclk;
    wire        adc_sync_follow_jclk;
    wire        adc_sync_follow_filtered_jclk;
    wire        adc_sync_rx_good_jclk;
    wire        adc_sync_rx_bad_jclk;
    wire        adc_sync_hold_active_jclk;
    wire        adc_udp_link_good_jclk;
    wire        adc_sync_force_low_raw;
    wire        adc_sync_force_high_raw;
    wire        adc_sync_out_next_jclk;
    wire        adc_sync_timed_release_active;
    wire        sysref2_rise_jclk;
    (* ASYNC_REG = "TRUE" *) reg [1:0] adc_sync_force_active_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] adc_sync_out_raw_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] adc_sync_out_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] adc_sync_follow_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] adc_sync_out_next_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] adc_sync_hold_locked_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] adc_sync_hold_active_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] adc_sync_hold_drop_seen_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_rx_sysref_gated_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] jesd_rx_sysref_gate_done_meta;
    (* ASYNC_REG = "TRUE" *) reg [3:0] jesd_rx_sysref_pulse_count_meta0;
    (* ASYNC_REG = "TRUE" *) reg [3:0] jesd_rx_sysref_pulse_count_meta1;
    (* ASYNC_REG = "TRUE" *) reg [2:0] tone_snapshot_toggle_meta;
    (* ASYNC_REG = "TRUE" *) reg [2:0] jesd_rx_snapshot_toggle_meta;
    (* mark_debug = "true" *) reg [31:0] adc_udp_tx_byte_count;
    (* mark_debug = "true" *) reg [15:0] adc_udp_tx_burst_count;
    (* mark_debug = "true" *) reg [7:0]  adc_udp_tx_last_data;
    reg adc_udp_tx_valid_q;
    (* mark_debug = "true" *) reg [31:0] tone_dac0_pair01_dbg;
    (* mark_debug = "true" *) reg [31:0] tone_dac0_pair23_dbg;
    (* mark_debug = "true" *) reg [31:0] tone_dac1_pair01_dbg;
    (* mark_debug = "true" *) reg [31:0] tone_dac1_pair23_dbg;
    (* mark_debug = "true" *) reg [31:0] tone_snapshot_count_dbg;
    wire [3:0]  dac_link0_status_bits_dbg;
    wire [3:0]  dac_link1_status_bits_dbg;
    wire        dac_link0_error_clean_dbg;
    wire        dac_link1_error_clean_dbg;
    wire        dac_nco_ftw_zero_dbg;
    wire        dac_mode8_no_translate_dbg;
    wire        dac_link0_lid_seen_dbg;
    wire        dac_link1_lid_seen_dbg;
    wire        dac_link0_ilas_seen_dbg;
    wire        dac_link1_ilas_seen_dbg;
    (* mark_debug = "true" *) wire [31:0] dac_link_evidence_dbg;
    (* mark_debug = "true" *) reg         adc_rx_rearm_inhibit;
    (* mark_debug = "true" *) reg         adc_rx_rearm_good_latched;
    (* mark_debug = "true" *) reg         adc_rx_rearm_limit_latched;
    (* mark_debug = "true" *) reg [3:0]   adc_rx_rearm_reason_dbg;
    (* mark_debug = "true" *) reg [7:0]   adc_rx_rearm_count;
    (* mark_debug = "true" *) reg [31:0]  adc_rx_rearm_wait_count;
    (* mark_debug = "true" *) reg [31:0]  adc_rx_rearm_drop_count;
    (* mark_debug = "true" *) reg [31:0]  adc_rx_rearm_reset_count;
    (* mark_debug = "true" *) reg [31:0]  adc_rx_rearm_good_count;
    (* mark_debug = "true" *) reg [2:0]   adc_rx_rearm_state;
    (* mark_debug = "true" *) reg [7:0]   adc_rx_link_reinit_count;
    (* mark_debug = "true" *) reg         adc_rx_link_reinit_done_latched;
    (* mark_debug = "true" *) reg         adc_rx_link_reinit_fail_latched;
    (* mark_debug = "true" *) reg         adc_rx_link_reinit_timeout_latched;
    (* mark_debug = "true" *) reg         adc_rx_core_reinit_pending;
    (* mark_debug = "true" *) reg [7:0]   adc_rx_core_reinit_count;
    (* mark_debug = "true" *) reg         adc_rx_core_reinit_done_latched;
    (* mark_debug = "true" *) reg         adc_rx_gt_reset_req;
    (* mark_debug = "true" *) reg [7:0]   adc_rx_gt_reset_count;
    (* mark_debug = "true" *) reg         adc_rx_gt_reset_done_latched;
    (* mark_debug = "true" *) reg         adc_rx_gt_reset_timeout_latched;

    assign init_rst        = (state == ST_BOOT);
    assign jesd_axi_aresetn = !init_rst;
    assign clock_sdio      = clock_sdio_oe ? clock_sdio_o : 1'bz;
    assign clock_sdio_i    = clock_sdio;
    assign adc_csb         = (ENABLE_AD6688_INIT != 0) ? adc_csb_init : 1'b1;
    assign adc_sclk        = (ENABLE_AD6688_INIT != 0) ? adc_sclk_init : 1'b0;
    assign adc_sdio        = ((ENABLE_AD6688_INIT != 0) && adc_sdio_oe) ? adc_sdio_o : 1'bz;
    assign adc_sdio_i      = (ENABLE_AD6688_INIT != 0) ? adc_sdio : 1'b0;
    assign dac_sclk        = dac_link_diag_running ? dac_diag_sclk : dac_init_sclk;
    assign dac_cs          = dac_link_diag_running ? dac_diag_cs   : dac_init_cs;
    assign dac_sdio_o      = dac_link_diag_running ? dac_diag_sdio_o  : dac_init_sdio_o;
    assign dac_sdio_oe     = dac_link_diag_running ? dac_diag_sdio_oe : dac_init_sdio_oe;
    assign dac_sdio        = dac_sdio_oe ? dac_sdio_o : 1'bz;
    assign dac_sdio_i      = dac_sdio;
    assign jesd_cfg_done   = jesd_done0 && jesd_done1;
    assign jesd_rx_enable  = jesd_rx_enable_jclk;
    assign jesd_rx_core_reset = !jesd_rx_enable_jclk;
    assign jesd_rx_reset_done = jesd_phy_rx_reset_done0 && jesd_phy_rx_reset_done1;
    assign adc_sync_follow_jclk =
        jesd_rx_enable_jclk ? jesd_rx_sync : adc_sync_drive_meta_jclk[1];
    assign adc_sync_rx_good_jclk =
        jesd_rx_enable_jclk &&
        adc_runtime_patch_done_meta_jclk[2] &&
        jesd_rx_aresetn &&
        !jesd_rx_reset_gt &&
        jesd_rx_sync &&
        !jesd_rx_encommaalign &&
        jesd_rx_tvalid;
    assign adc_sync_rx_bad_jclk =
        jesd_rx_enable_jclk &&
        adc_runtime_patch_done_meta_jclk[2] &&
        (!jesd_rx_aresetn ||
         jesd_rx_reset_gt ||
         !jesd_rx_sync ||
         jesd_rx_encommaalign ||
         !jesd_rx_tvalid);
    assign adc_sync_hold_active_jclk =
        ADC_SYNC_HOLD_ENABLE_BIT &&
        adc_sync_hold_locked_jclk &&
        adc_sync_rx_bad_jclk &&
        (adc_sync_hold_drop_count_jclk < ADC_SYNC_HOLD_DROP_TICKS);
    // Use the held link indication for capture scheduling so a short SYNC
    // dip does not permanently stop UDP preview.  The capture controller
    // still aborts any active window on the first missing sample_valid beat.
    assign adc_udp_link_good_jclk = adc_sync_rx_good_jclk ||
                                    adc_sync_hold_active_jclk;
    assign adc_sync_follow_filtered_jclk =
        adc_sync_hold_active_jclk ? adc_sync_force_high_raw :
                                    adc_sync_follow_jclk;
    assign adc_sync_force_low_raw = ADC_SYNC_OUTPUT_INVERT ? 1'b1 : 1'b0;
    assign adc_sync_force_high_raw = ADC_SYNC_OUTPUT_INVERT ? 1'b0 : 1'b1;
    assign adc_sync_timed_release_active =
        (ADC_SYNC_OUTPUT_DEBUG_MODE == 4) ||
        (ADC_SYNC_OUTPUT_DEBUG_MODE == 5) ||
        (ADC_SYNC_OUTPUT_DEBUG_MODE == 6);
    assign adc_runtime_patch_finished_jclk =
        adc_runtime_patch_done_meta_jclk[2] ||
        adc_runtime_patch_fail_meta_jclk[2];
    assign sysref2_rise_jclk = sysref2_meta_jclk[1] &&
                               !sysref2_meta_jclk[2];
    assign sysref2_rise_sys = !sysref2_d && sysref2_i;
    assign jesd_rx_sysref = ADC_RX_SYSREF_GATE_ENABLE_BIT ?
                            jesd_rx_sysref_gated_jclk :
                            sysref2_i;
    assign adc_sync_out_next_jclk =
        (ADC_SYNC_OUTPUT_DEBUG_MODE == 1) ? !adc_sync_follow_jclk :
        (ADC_SYNC_OUTPUT_DEBUG_MODE == 2) ? adc_sync_force_low_raw :
        (ADC_SYNC_OUTPUT_DEBUG_MODE == 3) ? adc_sync_force_high_raw :
        (ADC_SYNC_OUTPUT_DEBUG_MODE == 4) ?
            (adc_sync_force_active_jclk ? adc_sync_force_low_raw :
                                          adc_sync_force_high_raw) :
        (ADC_SYNC_OUTPUT_DEBUG_MODE == 5) ?
            (adc_sync_force_active_jclk ? adc_sync_force_high_raw :
                                          adc_sync_force_low_raw) :
        (ADC_SYNC_OUTPUT_DEBUG_MODE == 6) ?
            (adc_sync_force_active_jclk ? adc_sync_force_low_raw :
                                          adc_sync_follow_filtered_jclk) :
                                           adc_sync_follow_filtered_jclk;
    assign adc_sync_out_raw = adc_sync_out_jclk;
    assign adc_sync_out     = ADC_SYNC_OUTPUT_INVERT ? !adc_sync_out_raw :
                                                       adc_sync_out_raw;
    assign adc_udp_rst = init_rst || !eth_clk_locked;
    assign adc_udp_ctrl_dbg = {
        4'ha,
        eth_clk_locked,
        adc_udp_rst,
        adc_udp_pkt_busy,
        adc_udp_pkt_done,
        adc_udp_pkt_start_eth,
        adc_udp_pkt_done_seen_jclk,
        adc_udp_wait_pkt_done_jclk,
        adc_udp_capture_active_jclk,
        adc_udp_ram_rd_req,
        adc_udp_ram_rd_valid,
        adc0_sample_valid,
        adc_udp_link_good_jclk,
        adc_udp_wr_addr_jclk[ADC_UDP_CAPTURE_ADDR_W-1:0]
    };
    assign adc_udp_capture_count_dbg = {
        adc_udp_capture_count_jclk[15:0],
        adc_udp_drop_count_jclk[15:0]
    };
    assign adc_udp_drop_count_dbg    = adc_udp_drop_count_jclk;
    assign adc_udp_packet_count_dbg  = adc_udp_packet_count;
    assign adc_udp_eth_dbg = {
        4'hd,
        adc_udp_tx_valid,
        adc_udp_tx_valid_q,
        adc_udp_tx_burst_count[9:0],
        adc_udp_tx_last_data,
        adc_udp_tx_byte_count[7:0]
    };
    assign dac_cfg_valid_jclk =
        dac_cfg_toggle_meta_jclk[2] ^ dac_cfg_toggle_meta_jclk[1];
    assign dac_cfg_status_dbg = {
        4'he,
        dac_cfg_apply_pulse_jclk,
        dac_cfg_reset_phase_jclk,
        dac_cfg_apply_count_jclk[7:0],
        dac_cfg_rx_config_count[7:0],
        dac_cfg_rx_drop_count[7:0],
        phy1_rx_valid,
        phy1_rx_error
    };
    assign phy1_rx_rst = phy1_rx_rst_sync[2];
    assign phy1_mdc = 1'b0;
    assign phy1_mdio = 1'bz;
    assign jesd_rx_axi_live_dbg = {
        4'hb,
        jesd_rx_encommaalign_meta[1],
        jesd_rx_sync_dbg,
        jesd_rx_tvalid_dbg,
        jesd_rx_enable_dbg,
        jesd_gt_rxcommadet_dbg,
        jesd_gt_rxcharisk_dbg,
        jesd_gt_rxblock_sync_dbg
    };
    assign tx_tone_reset[0] = !jesd_release || !jesd_tx_aresetn0;
    assign tx_tone_reset[1] = !jesd_release || !jesd_tx_aresetn1;
    assign tx_tone_advance[0] = jesd_tx_ready0 && jesd_tx_aresetn0;
    assign tx_tone_advance[1] = jesd_tx_ready1 && jesd_tx_aresetn1;
    assign jesd_pll_ready_dbg = (JESD_USE_QPLL != 0) ?
        (jesd_qpll_lock_dbg[0] && jesd_qpll_lock_dbg[2]) :
        (&jesd_cplllock_dbg);
    assign jesd_release_ready =
        jesd_cfg_done_seen &&
        phy_axi_cfg_done;
    assign jesd_links_ready =
        jesd_release_ready &&
        jesd_pll_ready_dbg &&
        (&jesd_aresetn_dbg) &&
        (&jesd_tready_dbg) &&
        (&jesd_tx_reset_done_dbg) &&
        (&jesd_gt_txresetdone_dbg) &&
        (&jesd_gt_powergood_dbg);
    assign jesd_links_ready_no_tready =
        jesd_release_ready &&
        jesd_pll_ready_dbg &&
        (&jesd_aresetn_dbg) &&
        (&jesd_tx_reset_done_dbg) &&
        (&jesd_gt_txresetdone_dbg) &&
        (&jesd_gt_powergood_dbg);
    assign adc_diag_bypass_ready =
        ADC_DIAG_BYPASS_TX_READY_BIT &&
        jesd_release &&
        jesd_links_ready_no_tready;
    assign adc_start_gate_ready =
        (jesd_links_ready_stable_count >= JESD_READY_STABLE_TICKS) ||
        adc_diag_bypass_ready;
    assign phy_axi_cfg_done = phy0_axi_done_seen && phy1_axi_done_seen;
    assign adc_rx_gt_reset_control_active =
        ADC_RX_AUTO_REINIT_ENABLE_BIT && (
        (adc_rx_rearm_state == ADC_RX_REARM_ST_GT_RESET) ||
        (adc_rx_rearm_state == ADC_RX_REARM_ST_GT_WAIT) ||
        (adc_rx_rearm_state == ADC_RX_REARM_ST_LINK_SETTLE));
    assign jesd_rx_reset_gt =
        (adc_rx_gt_reset_control_active ? 1'b0 : jesd_rx_reset_gt_core) |
        adc_rx_gt_reset_req;
    assign adc_rx_gt_reset_ready =
        (&jesd_gt_rxresetdone_sync) &&
        (&jesd_gt_rxpmaresetdone_sync);
    assign jesd_rx_release_ready_sys =
        jesd_rx_cfg_done_seen &&
        adc_init_ok &&
        phy_axi_cfg_done &&
        !adc_rx_rearm_inhibit;
    assign adc_rx_diag_base_ready =
        ADC_RX_REARM_ENABLE_BIT &&
        (state == ST_RUN) &&
        adc_runtime_patch_done_latched &&
        !adc_runtime_patch_fail_latched &&
        jesd_rx_enable_meta[1] &&
        !adc_sync_force_active_meta[1] &&
        !adc_rx_rearm_inhibit;
    assign adc_rx_rearm_monitor_ready =
        adc_rx_diag_base_ready &&
        adc_rx_rearm_gt_live_clean;
    assign adc_rx_rearm_gt_live_clean =
        !(|jesd_gt_rxdisperr_meta) &&
        !(|jesd_gt_rxnotintable_meta) &&
        !(|jesd_gt_rxbufstatus_nonzero_sync);
    assign adc_rx_rearm_good_now =
        adc_rx_rearm_monitor_ready &&
        jesd_rx_tvalid_meta[1] &&
        jesd_rx_sync_meta[1] &&
        !jesd_rx_encommaalign_meta[1] &&
        jesd_rx_aresetn_meta[1];
    assign adc_rx_rearm_bad_now =
        adc_rx_rearm_monitor_ready &&
        !adc_rx_rearm_good_now;
    assign adc_rx_diag_gt_live_clean_q =
        !(|adc_rx_diag_gt_disperr_q) &&
        !(|adc_rx_diag_gt_notintable_q) &&
        !(|adc_rx_diag_gt_rxbufstatus_nonzero_q);
    assign adc_rx_diag_good_now =
        adc_rx_diag_base_ready &&
        adc_rx_diag_gt_live_clean_q &&
        adc_rx_diag_tvalid_q &&
        adc_rx_diag_sync_q &&
        !adc_rx_diag_encommaalign_q &&
        adc_rx_diag_aresetn_q &&
        !adc_rx_diag_reset_gt_q;
    assign adc_rx_diag_bad_now =
        adc_rx_diag_base_ready &&
        !adc_rx_diag_good_now;
    assign adc_rx_first_drop_cause_now = {
        adc_rx_diag_gt_rxbufstatus_nonzero_q != 8'd0,
        |adc_rx_diag_gt_notintable_q,
        |adc_rx_diag_gt_disperr_q,
        adc_rx_diag_encommaalign_q,
        !adc_rx_diag_tvalid_q,
        !adc_rx_diag_sync_q,
        !adc_rx_diag_aresetn_q,
        adc_rx_diag_reset_gt_q
    };
    assign jesd_aresetn_ready_dbg       = &jesd_aresetn_dbg;
    assign jesd_tready_ready_dbg        = &jesd_tready_dbg;
    assign jesd_tx_reset_done_ready_dbg = &jesd_tx_reset_done_dbg;
    assign jesd_gt_txresetdone_ready_dbg = &jesd_gt_txresetdone_dbg;
    assign jesd_gt_powergood_ready_dbg  = &jesd_gt_powergood_dbg;
    assign jesd_tx_clock_observed_dbg   = jesd_txoutclk_seen0 && jesd_txoutclk_seen1;
    assign jesd_wait_reason_next =
        (!jesd_release_ready)             ? JESD_WAIT_CFG :
        (!jesd_pll_ready_dbg)             ? JESD_WAIT_PLL :
        (!jesd_aresetn_ready_dbg)         ? JESD_WAIT_ARESETN :
        (!jesd_tready_ready_dbg)          ? JESD_WAIT_TREADY :
        (!jesd_tx_reset_done_ready_dbg)   ? JESD_WAIT_RESET_DONE :
        (!jesd_gt_txresetdone_ready_dbg)  ? JESD_WAIT_GT_RESETDONE :
        (!jesd_gt_powergood_ready_dbg)    ? JESD_WAIT_POWERGOOD :
                                            JESD_WAIT_NONE;
    assign jesd_fault_code_next =
        (jesd_wait_reason_next == JESD_WAIT_CFG)          ? JESD_FAULT_CFG :
        (jesd_wait_reason_next == JESD_WAIT_PLL)          ? JESD_FAULT_PLL :
        (jesd_wait_reason_next == JESD_WAIT_ARESETN)      ? JESD_FAULT_ARESETN :
        (jesd_wait_reason_next == JESD_WAIT_TREADY)       ? JESD_FAULT_TREADY :
        (jesd_wait_reason_next == JESD_WAIT_RESET_DONE)   ? JESD_FAULT_RESET_DONE :
        (jesd_wait_reason_next == JESD_WAIT_GT_RESETDONE) ? JESD_FAULT_GT_RESETDONE :
        (jesd_wait_reason_next == JESD_WAIT_POWERGOOD)    ? JESD_FAULT_POWERGOOD :
                                                            JESD_FAULT_NONE;
    assign jesd_ready_flags_dbg = {
        jesd_tx_clock_observed_dbg,
        phy_axi_cfg_done,
        jesd_cfg_done_seen,
        jesd_release_ready,
        jesd_pll_ready_dbg,
        jesd_gt_powergood_ready_dbg,
        jesd_gt_txresetdone_ready_dbg,
        jesd_tx_reset_done_ready_dbg,
        jesd_tready_ready_dbg,
        jesd_aresetn_ready_dbg,
        jesd_tready_dbg[1],
        jesd_tready_dbg[0],
        jesd_tx_reset_done_dbg[1],
        jesd_tx_reset_done_dbg[0],
        jesd_aresetn_dbg[1],
        jesd_aresetn_dbg[0]
    };
    assign jesd_ready_summary_dbg = {
        jesd_fault_code_latched,
        jesd_fault_code_dbg,
        jesd_wait_reason_latched,
        jesd_wait_reason_dbg,
        jesd_ready_flags_dbg[7:0]
    };
    assign adc_diag_bypass_dbg = {
        4'hd,
        4'd0,
        adc_runtime_patch_requested,
        adc_runtime_patch_busy,
        adc_runtime_patch_done_latched,
        adc_runtime_patch_fail_latched,
        ADC_DIAG_BYPASS_TX_READY_BIT,
        adc_diag_bypass_taken,
        adc_diag_bypass_ready,
        jesd_links_ready_no_tready,
        jesd_tready_dbg,
        jesd_aresetn_dbg,
        jesd_tx_reset_done_dbg,
        jesd_qpll_lock_dbg,
        jesd_fault_code_dbg[5:0]
    };
    assign adc_sync_loop_dbg = {
        4'ha,
        ADC_SYNC_OUTPUT_DEBUG_MODE_BITS,
        ADC_SYNC_OUTPUT_INVERT_BIT,
        ADC_JESD_SYNCINB_DEBUG_MODE_BITS,
        ADC_JESD_SYNCINB_INVERT_BIT,
        adc_sync_force_active_meta[1],
        adc_sync_out_raw_meta[1],
        adc_sync_out_meta[1],
        adc_sync_follow_meta[1],
        adc_sync_out_next_meta[1],
        adc_sync_drive,
        adc_runtime_patch_requested,
        adc_runtime_patch_done_latched,
        adc_runtime_patch_fail_latched,
        jesd_rx_sync_meta[1],
        jesd_rx_enable_meta[1],
        jesd_rx_tvalid_meta[1],
        jesd_rx_encommaalign_meta[1],
        jesd_rx_aresetn_meta[1],
        jesd_rx_reset_gt_meta[1],
        jesd_rx_sync_seen_high,
        jesd_rx_sync_seen_low,
        ADC_SYNC_HOLD_ENABLE_BIT,
        adc_sync_hold_locked_meta[1],
        adc_sync_hold_active_meta[1],
        adc_sync_hold_drop_seen_meta[1]
    };
    assign adc_rx_rearm_dbg = {
        4'he,
        ADC_RX_REARM_ENABLE_BIT,
        ADC_RX_LINK_REINIT_ENABLE_BIT,
        adc_rx_core_reinit_pending,
        adc_rx_gt_reset_done_latched,
        jesd_rx_busy,
        adc_rx_core_reinit_done_latched,
        adc_rx_rearm_monitor_ready,
        adc_rx_rearm_gt_live_clean,
        adc_rx_rearm_good_now,
        adc_rx_rearm_bad_now,
        adc_rx_rearm_inhibit,
        adc_rx_rearm_good_latched,
        adc_rx_rearm_limit_latched,
        adc_rx_rearm_state,
        adc_rx_rearm_reason_dbg,
        adc_rx_rearm_count[3:0],
        adc_runtime_link_reinit_busy,
        adc_rx_link_reinit_done_latched,
        (adc_rx_link_reinit_fail_latched |
         adc_rx_link_reinit_timeout_latched),
        adc_rx_gt_reset_timeout_latched
    };
    assign dac_link0_status_bits_dbg = {
        &dac_link0_status_dbg[27:24],
        &dac_link0_status_dbg[19:16],
        &dac_link0_status_dbg[11:8],
        &dac_link0_status_dbg[3:0]
    };
    assign dac_link1_status_bits_dbg = {
        &dac_link1_status_dbg[27:24],
        &dac_link1_status_dbg[19:16],
        &dac_link1_status_dbg[11:8],
        &dac_link1_status_dbg[3:0]
    };
    assign dac_link0_error_clean_dbg = (dac_link0_error_dbg[31:8] == 24'd0);
    assign dac_link1_error_clean_dbg = (dac_link1_error_dbg[31:8] == 24'd0);
    assign dac_nco_ftw_zero_dbg      = (dac_nco_ftw_low_dbg == 32'd0) &&
                                      (dac_nco_ftw_high_dbg[15:0] == 16'd0);
    assign dac_mode8_no_translate_dbg = (dac_datapath_cfg_dbg[7:0] == 8'h28) &&
                                       (dac_datapath_cfg_dbg[23:16] == 8'h08) &&
                                       dac_nco_ftw_zero_dbg;
    assign dac_link0_lid_seen_dbg    = |dac_link0_lid_dbg;
    assign dac_link1_lid_seen_dbg    = |dac_link1_lid_dbg;
    assign dac_link0_ilas_seen_dbg   = |{dac_link0_ilas0_dbg, dac_link0_ilas1_dbg};
    assign dac_link1_ilas_seen_dbg   = |{dac_link1_ilas0_dbg, dac_link1_ilas1_dbg};
    assign dac_link_evidence_dbg = {
        6'd0,
        dac_mode8_no_translate_dbg,
        dac_nco_ftw_zero_dbg,
        dac_link_diag_done_seen,
        dac_link_diag_running,
        dac_link1_error_clean_dbg,
        dac_link0_error_clean_dbg,
        dac_link1_ilas_seen_dbg,
        dac_link0_ilas_seen_dbg,
        dac_link1_lid_seen_dbg,
        dac_link0_lid_seen_dbg,
        dac_link1_status_bits_dbg,
        dac_link0_status_bits_dbg,
        dac_link1_status_dbg[3:0],
        dac_link0_status_dbg[3:0]
    };
    assign jesd_gt_rxresetdone = {jesd_gt_rxresetdone1, jesd_gt_rxresetdone0};
    assign jesd_gt_rxpmaresetdone = {
        jesd_gt_rxpmaresetdone1,
        jesd_gt_rxpmaresetdone0
    };
    assign jesd_gt_rxbufstatus = {jesd_gt_rxbufstatus1, jesd_gt_rxbufstatus0};
    assign jesd_gt_rxdisperr_any = {
        |jesd_rx_gt7_rxdisperr,
        |jesd_rx_gt6_rxdisperr,
        |jesd_rx_gt5_rxdisperr,
        |jesd_rx_gt4_rxdisperr,
        |jesd_rx_gt3_rxdisperr,
        |jesd_rx_gt2_rxdisperr,
        |jesd_rx_gt1_rxdisperr,
        |jesd_rx_gt0_rxdisperr
    };
    assign jesd_gt_rxnotintable_any = {
        |jesd_rx_gt7_rxnotintable,
        |jesd_rx_gt6_rxnotintable,
        |jesd_rx_gt5_rxnotintable,
        |jesd_rx_gt4_rxnotintable,
        |jesd_rx_gt3_rxnotintable,
        |jesd_rx_gt2_rxnotintable,
        |jesd_rx_gt1_rxnotintable,
        |jesd_rx_gt0_rxnotintable
    };
    assign jesd_gt_rxcharisk_any = {
        |jesd_rx_gt7_rxcharisk,
        |jesd_rx_gt6_rxcharisk,
        |jesd_rx_gt5_rxcharisk,
        |jesd_rx_gt4_rxcharisk,
        |jesd_rx_gt3_rxcharisk,
        |jesd_rx_gt2_rxcharisk,
        |jesd_rx_gt1_rxcharisk,
        |jesd_rx_gt0_rxcharisk
    };
    assign jesd_gt_rxblock_sync = {
        jesd_rx_gt7_rxblock_sync,
        jesd_rx_gt6_rxblock_sync,
        jesd_rx_gt5_rxblock_sync,
        jesd_rx_gt4_rxblock_sync,
        jesd_rx_gt3_rxblock_sync,
        jesd_rx_gt2_rxblock_sync,
        jesd_rx_gt1_rxblock_sync,
        jesd_rx_gt0_rxblock_sync
    };
    assign jesd_gt_rxmisalign = {
        jesd_rx_gt7_rxmisalign,
        jesd_rx_gt6_rxmisalign,
        jesd_rx_gt5_rxmisalign,
        jesd_rx_gt4_rxmisalign,
        jesd_rx_gt3_rxmisalign,
        jesd_rx_gt2_rxmisalign,
        jesd_rx_gt1_rxmisalign,
        jesd_rx_gt0_rxmisalign
    };
    assign jesd_gt_rxcommadet = {
        jesd_gt_rxcommadet1,
        jesd_gt_rxcommadet0
    };
    assign jesd_gt_rxcommadet_current = jesd_gt_rxcommadet;
    assign jesd_gt_rxbufstatus_nonzero_dbg = {
        |jesd_gt_rxbufstatus_dbg[23:21],
        |jesd_gt_rxbufstatus_dbg[20:18],
        |jesd_gt_rxbufstatus_dbg[17:15],
        |jesd_gt_rxbufstatus_dbg[14:12],
        |jesd_gt_rxbufstatus_dbg[11:9],
        |jesd_gt_rxbufstatus_dbg[8:6],
        |jesd_gt_rxbufstatus_dbg[5:3],
        |jesd_gt_rxbufstatus_dbg[2:0]
    };
    assign jesd_gt_rxbufstatus_nonzero_sync = {
        |jesd_gt_rxbufstatus_sync[23:21],
        |jesd_gt_rxbufstatus_sync[20:18],
        |jesd_gt_rxbufstatus_sync[17:15],
        |jesd_gt_rxbufstatus_sync[14:12],
        |jesd_gt_rxbufstatus_sync[11:9],
        |jesd_gt_rxbufstatus_sync[8:6],
        |jesd_gt_rxbufstatus_sync[5:3],
        |jesd_gt_rxbufstatus_sync[2:0]
    };
    assign jesd_gt_rxcharisk_full = {
        jesd_rx_gt7_rxcharisk,
        jesd_rx_gt6_rxcharisk,
        jesd_rx_gt5_rxcharisk,
        jesd_rx_gt4_rxcharisk,
        jesd_rx_gt3_rxcharisk,
        jesd_rx_gt2_rxcharisk,
        jesd_rx_gt1_rxcharisk,
        jesd_rx_gt0_rxcharisk
    };
    assign jesd_gt_rxdisperr_full = {
        jesd_rx_gt7_rxdisperr,
        jesd_rx_gt6_rxdisperr,
        jesd_rx_gt5_rxdisperr,
        jesd_rx_gt4_rxdisperr,
        jesd_rx_gt3_rxdisperr,
        jesd_rx_gt2_rxdisperr,
        jesd_rx_gt1_rxdisperr,
        jesd_rx_gt0_rxdisperr
    };
    assign jesd_gt_rxnotintable_full = {
        jesd_rx_gt7_rxnotintable,
        jesd_rx_gt6_rxnotintable,
        jesd_rx_gt5_rxnotintable,
        jesd_rx_gt4_rxnotintable,
        jesd_rx_gt3_rxnotintable,
        jesd_rx_gt2_rxnotintable,
        jesd_rx_gt1_rxnotintable,
        jesd_rx_gt0_rxnotintable
    };
    assign jesd_rx_lane01_data_low = {
        jesd_rx_gt1_rxdata[7:0],
        jesd_rx_gt1_rxdata[15:8],
        jesd_rx_gt0_rxdata[7:0],
        jesd_rx_gt0_rxdata[15:8]
    };
    assign jesd_rx_lane23_data_low = {
        jesd_rx_gt3_rxdata[7:0],
        jesd_rx_gt3_rxdata[15:8],
        jesd_rx_gt2_rxdata[7:0],
        jesd_rx_gt2_rxdata[15:8]
    };
    assign jesd_rx_lane45_data_low = {
        jesd_rx_gt5_rxdata[7:0],
        jesd_rx_gt5_rxdata[15:8],
        jesd_rx_gt4_rxdata[7:0],
        jesd_rx_gt4_rxdata[15:8]
    };
    assign jesd_rx_lane67_data_low = {
        jesd_rx_gt7_rxdata[7:0],
        jesd_rx_gt7_rxdata[15:8],
        jesd_rx_gt6_rxdata[7:0],
        jesd_rx_gt6_rxdata[15:8]
    };
    assign jesd_rx_snapshot_lane_data =
        (jesd_rx_snapshot_lane_jclk == 3'd0) ? jesd_rx_gt0_rxdata :
        (jesd_rx_snapshot_lane_jclk == 3'd1) ? jesd_rx_gt1_rxdata :
        (jesd_rx_snapshot_lane_jclk == 3'd2) ? jesd_rx_gt2_rxdata :
        (jesd_rx_snapshot_lane_jclk == 3'd3) ? jesd_rx_gt3_rxdata :
        (jesd_rx_snapshot_lane_jclk == 3'd4) ? jesd_rx_gt4_rxdata :
        (jesd_rx_snapshot_lane_jclk == 3'd5) ? jesd_rx_gt5_rxdata :
        (jesd_rx_snapshot_lane_jclk == 3'd6) ? jesd_rx_gt6_rxdata :
                                               jesd_rx_gt7_rxdata;
    assign jesd_rx_snapshot_lane_charisk =
        (jesd_rx_snapshot_lane_jclk == 3'd0) ? jesd_rx_gt0_rxcharisk :
        (jesd_rx_snapshot_lane_jclk == 3'd1) ? jesd_rx_gt1_rxcharisk :
        (jesd_rx_snapshot_lane_jclk == 3'd2) ? jesd_rx_gt2_rxcharisk :
        (jesd_rx_snapshot_lane_jclk == 3'd3) ? jesd_rx_gt3_rxcharisk :
        (jesd_rx_snapshot_lane_jclk == 3'd4) ? jesd_rx_gt4_rxcharisk :
        (jesd_rx_snapshot_lane_jclk == 3'd5) ? jesd_rx_gt5_rxcharisk :
        (jesd_rx_snapshot_lane_jclk == 3'd6) ? jesd_rx_gt6_rxcharisk :
                                               jesd_rx_gt7_rxcharisk;
    assign jesd_rx_snapshot_lane_disperr =
        (jesd_rx_snapshot_lane_jclk == 3'd0) ? jesd_rx_gt0_rxdisperr :
        (jesd_rx_snapshot_lane_jclk == 3'd1) ? jesd_rx_gt1_rxdisperr :
        (jesd_rx_snapshot_lane_jclk == 3'd2) ? jesd_rx_gt2_rxdisperr :
        (jesd_rx_snapshot_lane_jclk == 3'd3) ? jesd_rx_gt3_rxdisperr :
        (jesd_rx_snapshot_lane_jclk == 3'd4) ? jesd_rx_gt4_rxdisperr :
        (jesd_rx_snapshot_lane_jclk == 3'd5) ? jesd_rx_gt5_rxdisperr :
        (jesd_rx_snapshot_lane_jclk == 3'd6) ? jesd_rx_gt6_rxdisperr :
                                               jesd_rx_gt7_rxdisperr;
    assign jesd_rx_snapshot_lane_notintable =
        (jesd_rx_snapshot_lane_jclk == 3'd0) ? jesd_rx_gt0_rxnotintable :
        (jesd_rx_snapshot_lane_jclk == 3'd1) ? jesd_rx_gt1_rxnotintable :
        (jesd_rx_snapshot_lane_jclk == 3'd2) ? jesd_rx_gt2_rxnotintable :
        (jesd_rx_snapshot_lane_jclk == 3'd3) ? jesd_rx_gt3_rxnotintable :
        (jesd_rx_snapshot_lane_jclk == 3'd4) ? jesd_rx_gt4_rxnotintable :
        (jesd_rx_snapshot_lane_jclk == 3'd5) ? jesd_rx_gt5_rxnotintable :
        (jesd_rx_snapshot_lane_jclk == 3'd6) ? jesd_rx_gt6_rxnotintable :
                                               jesd_rx_gt7_rxnotintable;
    assign jesd_rx_snapshot_lane_block_sync =
        (jesd_rx_snapshot_lane_jclk == 3'd0) ? jesd_rx_gt0_rxblock_sync :
        (jesd_rx_snapshot_lane_jclk == 3'd1) ? jesd_rx_gt1_rxblock_sync :
        (jesd_rx_snapshot_lane_jclk == 3'd2) ? jesd_rx_gt2_rxblock_sync :
        (jesd_rx_snapshot_lane_jclk == 3'd3) ? jesd_rx_gt3_rxblock_sync :
        (jesd_rx_snapshot_lane_jclk == 3'd4) ? jesd_rx_gt4_rxblock_sync :
        (jesd_rx_snapshot_lane_jclk == 3'd5) ? jesd_rx_gt5_rxblock_sync :
        (jesd_rx_snapshot_lane_jclk == 3'd6) ? jesd_rx_gt6_rxblock_sync :
                                               jesd_rx_gt7_rxblock_sync;
    assign jesd_rx_snapshot_data_word =
        jesd_rx_snapshot_group_jclk ? jesd_rx_snapshot_lane_data[31:16] :
                                      jesd_rx_snapshot_lane_data[15:0];
    assign jesd_rx_snapshot_charisk_word =
        jesd_rx_snapshot_group_jclk ? jesd_rx_snapshot_lane_charisk[3:2] :
                                      jesd_rx_snapshot_lane_charisk[1:0];
    assign jesd_rx_snapshot_disperr_word =
        jesd_rx_snapshot_group_jclk ? jesd_rx_snapshot_lane_disperr[3:2] :
                                      jesd_rx_snapshot_lane_disperr[1:0];
    assign jesd_rx_snapshot_notintable_word =
        jesd_rx_snapshot_group_jclk ? jesd_rx_snapshot_lane_notintable[3:2] :
                                      jesd_rx_snapshot_lane_notintable[1:0];
    assign jesd_gt_rxdisperr_summary_seen_dbg =
        adc_runtime_patch_done_latched ?
            jesd_gt_rxdisperr_post_patch_seen_dbg :
            jesd_gt_rxdisperr_seen_dbg;
    assign jesd_gt_rxnotintable_summary_seen_dbg =
        adc_runtime_patch_done_latched ?
            jesd_gt_rxnotintable_post_patch_seen_dbg :
            jesd_gt_rxnotintable_seen_dbg;
    assign jesd_gt_rxblock_sync_summary_seen_dbg =
        adc_runtime_patch_done_latched ?
            jesd_gt_rxblock_sync_post_patch_seen_dbg :
            jesd_gt_rxblock_sync_seen_dbg;
    assign jesd_gt_rxcommadet_summary_seen_dbg =
        adc_runtime_patch_done_latched ?
            jesd_gt_rxcommadet_post_patch_seen_dbg :
            jesd_gt_rxcommadet_seen_dbg;
    assign jesd_rx_gt_summary_dbg = {
        jesd_gt_rxnotintable_summary_seen_dbg,
        jesd_gt_rxdisperr_summary_seen_dbg,
        jesd_gt_rxnotintable_dbg,
        jesd_gt_rxdisperr_dbg
    };
    assign jesd_rx_gt_detail0_dbg = {
        jesd_gt_rxresetdone_sync,
        jesd_gt_rxpmaresetdone_sync,
        jesd_gt_rxbufstatus_nonzero_sync,
        jesd_gt_rxcharisk_dbg
    };
    assign jesd_rx_gt_detail1_dbg = {
        jesd_rx_notintable_event_count[7:0],
        jesd_rx_disperr_event_count[7:0],
        jesd_gt_rxblock_sync_summary_seen_dbg,
        jesd_gt_rxcommadet_summary_seen_dbg
    };
    assign jesd_rx_link_summary_dbg = {
        4'h3,
        adc_runtime_patch_requested,
        adc_runtime_patch_busy,
        adc_runtime_patch_done_latched,
        adc_runtime_patch_fail_latched,
        jesd_rx_sync_at_patch_start,
        jesd_rx_sync_at_patch_done,
        jesd_rx_sync_seen_high,
        jesd_rx_sync_seen_low,
        jesd_rx_sync_dbg,
        jesd_rx_encommaalign_dbg,
        jesd_rx_tvalid_seen,
        jesd_rx_tvalid_dbg,
        jesd_rx_enable_dbg,
        jesd_rx_reset_gt_dbg,
        jesd_rx_aresetn_dbg,
        jesd_rx_reset_done,
        jesd_rx_sync_rise_count[3:0],
        jesd_rx_sync_fall_count[3:0],
        jesd_rx_tvalid_rise_count[3:0]
    };
    assign dac_spi_live_dbg = {
        5'd0,
        dac_fail_latched,
        dac_ok_latched,
        start_dac,
        dac_sdo_d,
        dac_sdo,
        dac_sdio,
        dac_sclk,
        dac_cs,
        txen_1,
        txen_0,
        resetb,
        dac_init_fail,
        dac_init_ok,
        dac_done,
        dac_busy,
        dac_init_debug_dbg[31:28],
        dac_init_debug_dbg[27:24],
        dac_init_debug_dbg[23:20]
    };
    assign adc_init_fsm_dbg = {
        adc_debug_wait_counter[30:22],
        adc_debug_retry_clock_check,
        adc_debug_read_done,
        adc_debug_read_busy,
        adc_sdio_i,
        adc_sdio_o,
        adc_sdio_oe,
        adc_sclk_init,
        adc_csb_init,
        adc_pdwn,
        start_adc,
        adc_init_fail,
        adc_init_ok,
        adc_done,
        adc_busy,
        adc_debug_retry_count,
        adc_debug_state
    };
    assign adc_init_read_dbg = {
        adc_debug_read_addr,
        adc_debug_read_data,
        adc_init_status_dbg[7:0]
    };
    assign adc_init_patch_dbg = {
        adc_debug_runtime_link_reinit
    };
    assign hmc_verify_status_dbg = {
        hmc_status_dbg[39:32],
        hmc_verify_done,
        hmc_verify_fail_any,
        hmc_debug_pll1_locked,
        hmc_debug_read_done,
        hmc_debug_read_busy,
        hmc_debug_state,
        hmc_verify_group_ok,
        hmc_debug_retry_count[6:0]
    };
    assign hmc_verify_mismatch_dbg = {
        hmc_verify_mismatch_addr,
        hmc_verify_mismatch_data,
        hmc_verify_mismatch_expect
    };

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
        .clk_200(sys_clk),
        .rst    (init_rst),
        .clk_125(eth_clk_125),
        .clk_125_90(eth_clk_125_90),
        .locked (eth_clk_locked)
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

    // Latest mezzanine netlist routes SYNCOUT1 P/N opposite to carrier FMC
    // LA32 P/N. Keep the IBUFDS on FPGA package P/N and invert the output so
    // the JESD TX core still sees active-low SYNC1.
    assign dac_sync1_i = ~dac_sync1_raw_i;

    OBUFDS u_adc_sync_buf (
        .I (adc_sync_out),
        .O (adc_sync_p),
        .OB(adc_sync_n)
    );

    jesd_clock u_jesd_clock (
        .refclk_pad_n(jesd_refclk_n),
        .refclk_pad_p(jesd_refclk_p),
        .refclk      (jesd_refclk),
        .refclk_mon  (jesd_refclk_mon_clk),
        .coreclk     (jesd_odiv2_clk)
    );

    // Keep a TXOUTCLK monitor path for debug only. The JESD core and PHY user
    // clock below stay on the refclk ODIV2-derived fabric clock.
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

    // Keep the JESD core and GT TXUSRCLK on the fabric-visible refclk clock,
    // matching the VCK190 baseline. Driving the core from txoutclk creates a
    // reset loop: the JESD core needs a live clock to release tx_reset_gt, but
    // the PHY cannot produce txoutclk while tx_reset_gt is asserted.
    assign jesd_core_clk = jesd_refclk_mon_clk;

    ad6688_lane_reorder u_ad6688_lane_reorder (
        .physical_tdata(jesd_rx_tdata),
        .logical_tdata (jesd_rx_tdata_logical)
    );

    adc0_sample_packer #(
        .ADC_INDEX(1),
        .COMPONENT_SELECT(0)
    ) u_adc0_sample_packer (
        .clk             (jesd_core_clk),
        .rst             (init_rst),
        .link_good       (adc_sync_rx_good_jclk),
        .jesd_valid      (jesd_rx_tvalid),
        .jesd_data       (jesd_rx_tdata_logical),
        .sample_valid    (adc0_sample_valid),
        .sample_data     (adc0_sample_data),
        .beat_count      (adc0_sample_beat_count),
        .first_sample_dbg(adc0_first_sample_dbg)
    );

    adc_capture_ddr64_model #(
        .ADDR_WIDTH(ADC_UDP_CAPTURE_ADDR_W),
        .READ_LATENCY(6)
    ) u_adc_udp_capture_ddr (
        .wr_clk      (jesd_core_clk),
        .wr_en       (adc_udp_capture_active_jclk && adc0_sample_valid),
        .wr_addr     (adc_udp_wr_addr_jclk),
        .wr_data     (adc0_sample_data),
        .rd_clk      (eth_clk_125),
        .rd_rst      (adc_udp_rst),
        .rd_req      (adc_udp_ram_rd_req),
        .rd_ready    (adc_udp_ram_rd_ready),
        .rd_byte_addr(adc_udp_ram_rd_addr),
        .rd_valid    (adc_udp_ram_rd_valid),
        .rd_byte     (adc_udp_ram_rd_byte)
    );

    adc_udp_capture_ctrl #(
        .CAPTURE_BEATS   (ADC_UDP_CAPTURE_BEATS),
        .CAPTURE_ADDR_W  (ADC_UDP_CAPTURE_ADDR_W),
        .REPEAT_TICKS    (ADC_UDP_REPEAT_TICKS),
        .LINK_GOOD_TICKS (ADC_UDP_LINK_GOOD_TICKS),
        .SAMPLE_GAP_TICKS(ADC_UDP_SAMPLE_GAP_TICKS)
    ) u_adc_udp_capture_ctrl (
        .jclk              (jesd_core_clk),
        .jrst              (init_rst),
        .eth_clk           (eth_clk_125),
        .eth_rst           (adc_udp_rst),
        .enable            (ENABLE_ADC_UDP_RGMII != 0),
        .eth_ready_async   (eth_clk_locked),
        .link_good         (adc_udp_link_good_jclk),
        .sample_valid      (adc0_sample_valid),
        .capture_active    (adc_udp_capture_active_jclk),
        .wait_pkt_done     (adc_udp_wait_pkt_done_jclk),
        .pkt_done_seen     (adc_udp_pkt_done_seen_jclk),
        .wr_addr           (adc_udp_wr_addr_jclk),
        .capture_id        (adc_udp_capture_id_jclk),
        .capture_count     (adc_udp_capture_count_jclk),
        .drop_count        (adc_udp_drop_count_jclk),
        .good_window_count (adc_udp_good_window_count_jclk),
        .capture_good_count(adc_udp_capture_good_count_jclk),
        .repeat_count      (adc_udp_repeat_count_jclk),
        .pkt_busy          (adc_udp_pkt_busy),
        .pkt_done          (adc_udp_pkt_done),
        .pkt_start         (adc_udp_pkt_start_eth),
        .pkt_capture_id    (adc_udp_pkt_capture_id_eth)
    );

    k5ad_udp_packetizer_ddr #(
        .CAPTURE_BEATS(ADC_UDP_CAPTURE_BEATS),
        .DATA_PAYLOAD_SAMPLES(ADC_UDP_DATA_PAYLOAD_SAMPLES),
        .SRC_MAC(48'h02_00_00_00_5a_01),
        .SRC_IP(32'hC0A8_010A),
        .SRC_PORT(16'd6006),
        .DST_PORT(16'd6006)
    ) u_k5ad_udp_packetizer (
        .clk             (eth_clk_125),
        .rst             (adc_udp_rst),
        .start           (adc_udp_pkt_start_eth),
        .capture_id      (adc_udp_pkt_capture_id_eth),
        .ram_rd_req      (adc_udp_ram_rd_req),
        .ram_rd_ready    (adc_udp_ram_rd_ready),
        .ram_rd_valid    (adc_udp_ram_rd_valid),
        .ram_rd_byte     (adc_udp_ram_rd_byte),
        .ram_rd_byte_addr(adc_udp_ram_rd_addr),
        .busy            (adc_udp_pkt_busy),
        .done            (adc_udp_pkt_done),
        .packet_count    (adc_udp_packet_count),
        .tx_data         (adc_udp_tx_data),
        .tx_valid        (adc_udp_tx_valid),
        .prefetch_count  (adc_udp_prefetch_count)
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
        .UDP_PORT(16'd5005)
    ) u_k5wg_udp_dac_config_rx (
        .clk            (phy1_rxck),
        .rst            (phy1_rx_rst),
        .rx_data        (phy1_rx_data),
        .rx_valid       (phy1_rx_valid),
        .rx_error       (phy1_rx_error),
        .cfg_valid      (dac_cfg_valid_rxclk),
        .cfg_reset_phase(dac_cfg_reset_phase_rxclk),
        .cfg_phase_inc0 (dac_cfg_phase_inc0_rxclk),
        .cfg_phase_inc1 (dac_cfg_phase_inc1_rxclk),
        .cfg_phase_inc2 (dac_cfg_phase_inc2_rxclk),
        .cfg_phase_inc3 (dac_cfg_phase_inc3_rxclk),
        .cfg_scale0     (dac_cfg_scale0_rxclk),
        .cfg_scale1     (dac_cfg_scale1_rxclk),
        .cfg_scale2     (dac_cfg_scale2_rxclk),
        .cfg_scale3     (dac_cfg_scale3_rxclk),
        .wave_wr_en     (dac_wave_wr_en_rxclk),
        .wave_wr_addr   (dac_wave_wr_addr_rxclk),
        .wave_wr_data   (dac_wave_wr_data_rxclk),
        .wave_total_samples(dac_wave_total_samples_rxclk),
        .wave_commit_toggle(dac_wave_commit_toggle_rxclk),
        .packet_count   (dac_cfg_rx_packet_count),
        .config_count   (dac_cfg_rx_config_count),
        .data_count     (dac_cfg_rx_data_count),
        .commit_count   (dac_cfg_rx_commit_count),
        .drop_count     (dac_cfg_rx_drop_count),
        .status_dbg     (dac_cfg_rx_status_dbg)
    );

    always @(posedge phy1_rxck) begin
        if (adc_udp_rst) begin
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
            dac_cfg_apply_count_jclk <= 32'd0;
            dac_cfg_apply_pulse_jclk <= 1'b0;
        end else begin
            dac_cfg_apply_pulse_jclk <= 1'b0;
            dac_cfg_toggle_meta_jclk <= {
                dac_cfg_toggle_meta_jclk[1:0],
                dac_cfg_toggle_rxclk
            };
            if (dac_cfg_valid_jclk) begin
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
                dac_cfg_apply_count_jclk <= dac_cfg_apply_count_jclk + 1'b1;
            end
        end
    end

    rgmii_tx u_phy1_rgmii_tx (
        .tx_clk      (eth_clk_125),
        .tx_clk_90   (eth_clk_125_90),
        .rst         (adc_udp_rst),
        .txd         (adc_udp_tx_data),
        .tx_en       (adc_udp_tx_valid),
        .rgmii_tx_clk(phy1_txck),
        .rgmii_txd   (phy1_txd),
        .rgmii_tx_ctl(phy1_txctl)
    );

    always @(posedge eth_clk_125) begin
        if (adc_udp_rst) begin
            adc_udp_tx_byte_count  <= 32'd0;
            adc_udp_tx_burst_count <= 16'd0;
            adc_udp_tx_last_data   <= 8'd0;
            adc_udp_tx_valid_q     <= 1'b0;
        end else begin
            adc_udp_tx_valid_q <= adc_udp_tx_valid;
            if (adc_udp_tx_valid) begin
                adc_udp_tx_byte_count <= adc_udp_tx_byte_count + 1'b1;
                adc_udp_tx_last_data  <= adc_udp_tx_data;
            end
            if (adc_udp_tx_valid && !adc_udp_tx_valid_q) begin
                adc_udp_tx_burst_count <= adc_udp_tx_burst_count + 1'b1;
            end
        end
    end

    always @(posedge jesd_core_clk) begin
        if (&tx_tone_reset) begin
            tone_snapshot_div         <= 5'd0;
            tone_dac0_pair01_jclk    <= 32'd0;
            tone_dac0_pair23_jclk    <= 32'd0;
            tone_dac1_pair01_jclk    <= 32'd0;
            tone_dac1_pair23_jclk    <= 32'd0;
            tone_snapshot_toggle_jclk <= 1'b0;
        end else if (|tx_tone_advance) begin
            tone_snapshot_div <= tone_snapshot_div + 1'b1;
            if (tone_snapshot_div == 5'd15) begin
                tone_snapshot_div         <= 5'd0;
                tone_dac0_pair01_jclk    <= {tx_pattern_data[223:208], tx_pattern_data[207:192]};
                tone_dac0_pair23_jclk    <= {tx_pattern_data[255:240], tx_pattern_data[239:224]};
                tone_dac1_pair01_jclk    <= {tx_pattern_data[159:144], tx_pattern_data[143:128]};
                tone_dac1_pair23_jclk    <= {tx_pattern_data[191:176], tx_pattern_data[175:160]};
                tone_snapshot_toggle_jclk <= ~tone_snapshot_toggle_jclk;
            end
        end
    end

    always @(posedge jesd_refclk_mon_clk) begin
        jesd_refclk_mon_heartbeat <= jesd_refclk_mon_heartbeat + 1'b1;
        refclk_mon_counter <= refclk_mon_counter_next;
        refclk_mon_gray_src <= refclk_mon_gray_next;
    end

    always @(posedge jesd_core_clk) begin
        jesd_core_heartbeat <= jesd_core_heartbeat + 1'b1;
    end

    always @(posedge jesd_core_clk) begin
        sysref2_meta_jclk <= {sysref2_meta_jclk[1:0], sysref2_i};
        jesd_rx_release_meta_jclk <= {
            jesd_rx_release_meta_jclk[1:0],
            jesd_rx_release_ready_sys
        };
        adc_runtime_patch_done_meta_jclk <= {
            adc_runtime_patch_done_meta_jclk[1:0],
            adc_runtime_patch_done_latched
        };
        adc_runtime_patch_fail_meta_jclk <= {
            adc_runtime_patch_fail_meta_jclk[1:0],
            adc_runtime_patch_fail_latched
        };
        adc_sync_drive_meta_jclk <= {adc_sync_drive_meta_jclk[0], adc_sync_drive};
        jesd_rx_enable_jclk <= jesd_rx_release_meta_jclk[2];
        jesd_rx_sysref_gated_jclk <= 1'b0;
        if (!jesd_rx_enable_jclk) begin
            jesd_rx_sysref_pulse_count_jclk <= 4'd0;
            jesd_rx_sysref_gate_done_jclk <= 1'b0;
        end else if (jesd_rx_tvalid) begin
            jesd_rx_sysref_gate_done_jclk <= 1'b1;
        end else if (ADC_RX_SYSREF_GATE_ENABLE_BIT &&
                     !jesd_rx_sysref_gate_done_jclk &&
                     sysref2_rise_jclk) begin
            jesd_rx_sysref_gated_jclk <= 1'b1;
            if (jesd_rx_sysref_pulse_count_jclk != 4'hf) begin
                jesd_rx_sysref_pulse_count_jclk <=
                    jesd_rx_sysref_pulse_count_jclk + 1'b1;
            end
            if (jesd_rx_sysref_pulse_count_jclk >=
                (ADC_RX_SYSREF_PULSE_MAX - 1)) begin
                jesd_rx_sysref_gate_done_jclk <= 1'b1;
            end
        end
        if (!jesd_rx_enable_jclk) begin
            adc_sync_force_count_jclk  <= 32'd0;
            adc_sync_force_active_jclk <= 1'b1;
            adc_sync_hold_locked_jclk <= 1'b0;
            adc_sync_hold_good_count_jclk <= 32'd0;
            adc_sync_hold_drop_count_jclk <= 32'd0;
            adc_sync_hold_drop_seen_jclk <= 1'b0;
        end else if (adc_sync_force_active_jclk) begin
            if (!adc_runtime_patch_finished_jclk) begin
                adc_sync_force_count_jclk <= 32'd0;
            end else if (adc_sync_force_count_jclk >=
                         (ADC_SYNC_FORCE_ASSERT_TICKS - 1)) begin
                adc_sync_force_active_jclk <= 1'b0;
            end else begin
                adc_sync_force_count_jclk <= adc_sync_force_count_jclk + 1'b1;
            end
        end
        if (!jesd_rx_enable_jclk ||
            adc_sync_force_active_jclk ||
            !adc_runtime_patch_done_meta_jclk[2]) begin
            adc_sync_hold_locked_jclk <= 1'b0;
            adc_sync_hold_good_count_jclk <= 32'd0;
            adc_sync_hold_drop_count_jclk <= 32'd0;
            adc_sync_hold_drop_seen_jclk <= 1'b0;
        end else if (adc_sync_rx_good_jclk) begin
            adc_sync_hold_drop_count_jclk <= 32'd0;
            if (adc_sync_hold_good_count_jclk >=
                (ADC_SYNC_HOLD_LOCK_STABLE_CYCLES - 1)) begin
                adc_sync_hold_locked_jclk <= 1'b1;
            end else begin
                adc_sync_hold_good_count_jclk <=
                    adc_sync_hold_good_count_jclk + 1'b1;
            end
        end else if (adc_sync_rx_bad_jclk) begin
            adc_sync_hold_good_count_jclk <= 32'd0;
            if (adc_sync_hold_locked_jclk) begin
                adc_sync_hold_drop_seen_jclk <= 1'b1;
                if (adc_sync_hold_drop_count_jclk < ADC_SYNC_HOLD_DROP_TICKS) begin
                    adc_sync_hold_drop_count_jclk <=
                        adc_sync_hold_drop_count_jclk + 1'b1;
                end
            end else begin
                adc_sync_hold_drop_count_jclk <= 32'd0;
            end
        end else begin
            adc_sync_hold_good_count_jclk <= 32'd0;
            adc_sync_hold_drop_count_jclk <= 32'd0;
        end
        adc_sync_out_jclk <= adc_sync_out_next_jclk;
        if (!jesd_rx_enable_jclk || adc_sync_force_active_jclk) begin
            jesd_gt_rxdisperr_seen_jclk    <= 8'd0;
            jesd_gt_rxnotintable_seen_jclk <= 8'd0;
            jesd_gt_rxcharisk_seen_jclk    <= 8'd0;
            jesd_gt_rxblock_sync_seen_jclk <= 8'd0;
            jesd_gt_rxcommadet_seen_jclk <= 8'd0;
            adc_runtime_gt_seen_cleared_jclk <= 1'b0;
        end else if (adc_runtime_patch_done_meta_jclk[2] &&
                     !adc_runtime_gt_seen_cleared_jclk) begin
            jesd_gt_rxdisperr_seen_jclk    <= 8'd0;
            jesd_gt_rxnotintable_seen_jclk <= 8'd0;
            jesd_gt_rxcharisk_seen_jclk    <= 8'd0;
            jesd_gt_rxblock_sync_seen_jclk <= 8'd0;
            jesd_gt_rxcommadet_seen_jclk   <= 8'd0;
            adc_runtime_gt_seen_cleared_jclk <= 1'b1;
        end else begin
            jesd_gt_rxdisperr_seen_jclk <= jesd_gt_rxdisperr_seen_jclk |
                                           jesd_gt_rxdisperr_any;
            jesd_gt_rxnotintable_seen_jclk <= jesd_gt_rxnotintable_seen_jclk |
                                              jesd_gt_rxnotintable_any;
            jesd_gt_rxcharisk_seen_jclk <= jesd_gt_rxcharisk_seen_jclk |
                                           jesd_gt_rxcharisk_any;
            jesd_gt_rxblock_sync_seen_jclk <= jesd_gt_rxblock_sync_seen_jclk |
                                              jesd_gt_rxblock_sync;
            jesd_gt_rxcommadet_seen_jclk <= jesd_gt_rxcommadet_seen_jclk |
                                            jesd_gt_rxcommadet;
        end
    end

    always @(posedge jesd_txoutclk_mon_clk0) begin
        jesd_txoutclk_heartbeat0 <= jesd_txoutclk_heartbeat0 + 1'b1;
    end

    always @(posedge jesd_txoutclk_mon_clk1) begin
        jesd_txoutclk_heartbeat1 <= jesd_txoutclk_heartbeat1 + 1'b1;
    end

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
        .status_dbg(hmc_status_dbg),
        .verify_group_ok(hmc_verify_group_ok),
        .verify_done(hmc_verify_done),
        .verify_fail_any(hmc_verify_fail_any),
        .verify_mismatch_addr(hmc_verify_mismatch_addr),
        .verify_mismatch_data(hmc_verify_mismatch_data),
        .verify_mismatch_expect(hmc_verify_mismatch_expect),
        .ch4_snapshot_dbg(hmc_ch4_snapshot_dbg),
        .debug_state(hmc_debug_state),
        .debug_retry_count(hmc_debug_retry_count),
        .debug_read_addr(hmc_debug_read_addr),
        .debug_read_data(hmc_debug_read_data),
        .debug_read_busy(hmc_debug_read_busy),
        .debug_read_done(hmc_debug_read_done),
        .debug_pll1_locked(hmc_debug_pll1_locked),
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
        .status_dbg(dac_init_status_dbg),
        .sanity_dbg(dac_init_sanity_dbg),
        .debug_dbg (dac_init_debug_dbg),
        .sclk      (dac_init_sclk),
        .cs_n      (dac_init_cs),
        .sdio_o    (dac_init_sdio_o),
        .sdio_oe   (dac_init_sdio_oe)
    );

    ad9173_link_diag #(
        .CLK_DIV (SPI_CLK_DIV),
        .MS_TICKS(MS_TICKS),
        .REPEAT_MS(2),
        .ENABLE_LINK0_POLARITY_SWEEP(0),
        .ENABLE_LINK0_XBAR_SWEEP(0),
        .LINK0_XBAR_SWEEP_POLARITY(8'h00)
    ) u_ad9173_link_diag (
        .clk             (sys_clk),
        .rst             (init_rst),
        .enable          ((state == ST_RUN) || (state == ST_WAIT_ADC)),
        .sdio_i          (dac_sdio_i),
        .running         (dac_link_diag_running),
        .done_seen       (dac_link_diag_done_seen),
        .link0_status_dbg(dac_link0_status_dbg),
        .link1_status_dbg(dac_link1_status_dbg),
        .link0_error_dbg (dac_link0_error_dbg),
        .link1_error_dbg (dac_link1_error_dbg),
        .link0_ilas0_dbg (dac_link0_ilas0_dbg),
        .link1_ilas0_dbg (dac_link1_ilas0_dbg),
        .link0_ilas1_dbg (dac_link0_ilas1_dbg),
        .link1_ilas1_dbg (dac_link1_ilas1_dbg),
        .link0_lid_dbg   (dac_link0_lid_dbg),
        .link1_lid_dbg   (dac_link1_lid_dbg),
        .link0_checksum_dbg(dac_link0_checksum_dbg),
        .link1_checksum_dbg(dac_link1_checksum_dbg),
        .link0_compsum_dbg(dac_link0_compsum_dbg),
        .link1_compsum_dbg(dac_link1_compsum_dbg),
        .datapath_cfg_dbg(dac_datapath_cfg_dbg),
        .nco_ftw_low_dbg (dac_nco_ftw_low_dbg),
        .nco_ftw_high_dbg(dac_nco_ftw_high_dbg),
        .lane_cfg_dbg    (dac_lane_cfg_dbg),
        .serdes_cfg_dbg  (dac_serdes_cfg_dbg),
        .polarity_cfg_dbg(dac_polarity_cfg_dbg),
        .sweep_ctrl_dbg  (dac_sweep_ctrl_dbg),
        .sweep_result_dbg(dac_sweep_result_dbg),
        .live_dbg        (),
        .sclk            (dac_diag_sclk),
        .cs_n            (dac_diag_cs),
        .sdio_o          (dac_diag_sdio_o),
        .sdio_oe         (dac_diag_sdio_oe)
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

    jesd204_rx_init #(
        .MS_TICKS(MS_TICKS)
    ) u_jesd204_rx_init (
        .clk          (sys_clk),
        .rst          (init_rst),
        .start        (start_jesd_rx),
        .busy         (jesd_rx_busy),
        .done         (jesd_rx_done),
        .s_axi_awaddr (jesdrx_s_axi_awaddr),
        .s_axi_awvalid(jesdrx_s_axi_awvalid),
        .s_axi_awready(jesdrx_s_axi_awready),
        .s_axi_wdata  (jesdrx_s_axi_wdata),
        .s_axi_wstrb  (jesdrx_s_axi_wstrb),
        .s_axi_wvalid (jesdrx_s_axi_wvalid),
        .s_axi_wready (jesdrx_s_axi_wready),
        .s_axi_bresp  (jesdrx_s_axi_bresp),
        .s_axi_bvalid (jesdrx_s_axi_bvalid),
        .s_axi_bready (jesdrx_s_axi_bready)
    );

    ad6688_init #(
        .CLK_DIV (SPI_CLK_DIV),
        .MS_TICKS(MS_TICKS),
        .JESD_SYNCINB_DEBUG_MODE(ADC_JESD_SYNCINB_DEBUG_MODE),
        .JESD_SYNCINB_INVERT(ADC_JESD_SYNCINB_INVERT),
        .JESD_ILAS_ALWAYS_ON(ADC_JESD_ILAS_ALWAYS_ON),
        .JESD_8B10B_BIT_INVERT(ADC_JESD_8B10B_BIT_INVERT),
        .ENABLE_SERDOUT_INVERT(ADC_SERDOUT_INVERT_ENABLE),
        .SERDOUT_INVERT_MASK(ADC_SERDOUT_INVERT_MASK)
    ) u_ad6688_init (
        .clk       (sys_clk),
        .rst       (init_rst),
        .start     (start_adc),
        .runtime_patch_start(adc_runtime_patch_start),
        .runtime_link_reinit_start(adc_runtime_link_reinit_start),
        .sdio_i    (adc_sdio_i),
        .busy      (adc_busy),
        .done      (adc_done),
        .ok        (adc_init_ok),
        .fail      (adc_init_fail),
        .status_dbg(adc_init_status_dbg),
        .debug_state(adc_debug_state),
        .debug_retry_count(adc_debug_retry_count),
        .debug_wait_counter(adc_debug_wait_counter),
        .debug_read_addr(adc_debug_read_addr),
        .debug_read_data(adc_debug_read_data),
        .debug_read_busy(adc_debug_read_busy),
        .debug_read_done(adc_debug_read_done),
        .debug_patch_word(adc_debug_patch_word),
        .debug_retry_clock_check(adc_debug_retry_clock_check),
        .debug_clk_trace(adc_debug_clk_trace),
        .debug_fail_detail(adc_debug_fail_detail),
        .debug_jesd_ctrl(adc_debug_jesd_ctrl),
        .debug_jesd_param(adc_debug_jesd_param),
        .debug_lane_map(adc_debug_lane_map),
        .debug_sysref(adc_debug_sysref),
        .debug_serdes(adc_debug_serdes),
        .debug_link_extra(adc_debug_link_extra),
        .debug_serdes_cfg(adc_debug_serdes_cfg),
        .debug_serdes_emph(adc_debug_serdes_emph),
        .debug_jesd_param_ext(adc_debug_jesd_param_ext),
        .debug_checksum03(adc_debug_checksum03),
        .debug_checksum47(adc_debug_checksum47),
        .debug_lid03(adc_debug_lid03),
        .debug_lid47(adc_debug_lid47),
        .debug_runtime_patch(adc_debug_runtime_patch),
        .debug_runtime_link_reinit(adc_debug_runtime_link_reinit),
        .runtime_patch_busy(adc_runtime_patch_busy),
        .runtime_patch_done(adc_runtime_patch_done),
        .runtime_patch_fail(adc_runtime_patch_fail),
        .runtime_link_reinit_busy(adc_runtime_link_reinit_busy),
        .runtime_link_reinit_done(adc_runtime_link_reinit_done),
        .runtime_link_reinit_fail(adc_runtime_link_reinit_fail),
        .sclk      (adc_sclk_init),
        .cs_n      (adc_csb_init),
        .sdio_o    (adc_sdio_o),
        .sdio_oe   (adc_sdio_oe)
    );

    jesd_tx_axi_probe u_jesd0_tx_axi_probe (
        .clk              (sys_clk),
        .rst              (!jesd_axi_aresetn),
        .enable           (jesd_cfg_done_seen),
        .running          (),
        .done_seen        (),
        .error_seen       (),
        .status_dbg       (jesd0_tx_status_dbg),
        .reset_lanes_dbg  (jesd0_tx_reset_lanes_dbg),
        .cfg_dbg          (jesd0_tx_cfg_dbg),
        .ila1_dbg         (jesd0_tx_ila1_dbg),
        .ila2_dbg         (jesd0_tx_ila2_dbg),
        .laneids_dbg      (jesd0_tx_laneids_dbg),
        .live_dbg         (jesd0_tx_axi_live_dbg),
        .s_axi_araddr     (jesd0_s_axi_araddr),
        .s_axi_arvalid    (jesd0_s_axi_arvalid),
        .s_axi_arready    (jesd0_s_axi_arready),
        .s_axi_rdata      (jesd0_s_axi_rdata),
        .s_axi_rresp      (jesd0_s_axi_rresp),
        .s_axi_rvalid     (jesd0_s_axi_rvalid),
        .s_axi_rready     (jesd0_s_axi_rready)
    );

    jesd_tx_axi_probe u_jesd1_tx_axi_probe (
        .clk              (sys_clk),
        .rst              (!jesd_axi_aresetn),
        .enable           (jesd_cfg_done_seen),
        .running          (),
        .done_seen        (),
        .error_seen       (),
        .status_dbg       (jesd1_tx_status_dbg),
        .reset_lanes_dbg  (jesd1_tx_reset_lanes_dbg),
        .cfg_dbg          (jesd1_tx_cfg_dbg),
        .ila1_dbg         (jesd1_tx_ila1_dbg),
        .ila2_dbg         (jesd1_tx_ila2_dbg),
        .laneids_dbg      (jesd1_tx_laneids_dbg),
        .live_dbg         (jesd1_tx_axi_live_dbg),
        .s_axi_araddr     (jesd1_s_axi_araddr),
        .s_axi_arvalid    (jesd1_s_axi_arvalid),
        .s_axi_arready    (jesd1_s_axi_arready),
        .s_axi_rdata      (jesd1_s_axi_rdata),
        .s_axi_rresp      (jesd1_s_axi_rresp),
        .s_axi_rvalid     (jesd1_s_axi_rvalid),
        .s_axi_rready     (jesd1_s_axi_rready)
    );

    jesd_rx_axi_probe u_jesd_rx_axi_probe (
        .clk              (sys_clk),
        .rst              (!jesd_axi_aresetn),
        .enable           (jesd_rx_cfg_done_seen),
        .running          (),
        .done_seen        (),
        .error_seen       (),
        .status_dbg       (jesd_rx_status_dbg),
        .rxerr_dbg        (jesd_rx_err_dbg),
        .rxdebug_dbg      (jesd_rx_debug_dbg),
        .cfg_dbg          (jesd_rx_cfg_dbg),
        .lanes_dbg        (jesd_rx_lanes_dbg),
        .lane0_ilas0_dbg  (jesd_rx_lane0_ilas0_dbg),
        .lane0_ilas1_dbg  (jesd_rx_lane0_ilas1_dbg),
        .lane0_ilas2_dbg  (jesd_rx_lane0_ilas2_dbg),
        .lane0_ilas3_dbg  (jesd_rx_lane0_ilas3_dbg),
        .lane0_ilas4_dbg  (jesd_rx_lane0_ilas4_dbg),
        .lane0_ilas5_dbg  (jesd_rx_lane0_ilas5_dbg),
        .lane1_ilas3_dbg  (jesd_rx_lane1_ilas3_dbg),
        .lane2_ilas3_dbg  (jesd_rx_lane2_ilas3_dbg),
        .lane3_ilas0_dbg  (jesd_rx_lane3_ilas0_dbg),
        .lane3_ilas1_dbg  (jesd_rx_lane3_ilas1_dbg),
        .lane3_ilas2_dbg  (jesd_rx_lane3_ilas2_dbg),
        .lane3_ilas3_dbg  (jesd_rx_lane3_ilas3_dbg),
        .lane3_ilas4_dbg  (jesd_rx_lane3_ilas4_dbg),
        .lane3_ilas5_dbg  (jesd_rx_lane3_ilas5_dbg),
        .lane4_ilas3_dbg  (jesd_rx_lane4_ilas3_dbg),
        .lane5_ilas3_dbg  (jesd_rx_lane5_ilas3_dbg),
        .lane6_ilas3_dbg  (jesd_rx_lane6_ilas3_dbg),
        .lane7_ilas3_dbg  (jesd_rx_lane7_ilas3_dbg),
        .ilas3_lanes03_dbg(jesd_rx_ilas3_lanes03_dbg),
        .ilas3_lanes47_dbg(jesd_rx_ilas3_lanes47_dbg),
        .live_dbg         (jesd_rx_axi_live_raw_dbg),
        .s_axi_araddr     (jesdrx_s_axi_araddr),
        .s_axi_arvalid    (jesdrx_s_axi_arvalid),
        .s_axi_arready    (jesdrx_s_axi_arready),
        .s_axi_rdata      (jesdrx_s_axi_rdata),
        .s_axi_rresp      (jesdrx_s_axi_rresp),
        .s_axi_rvalid     (jesdrx_s_axi_rvalid),
        .s_axi_rready     (jesdrx_s_axi_rready)
    );

    pattern_gen_256 #(
        .WAVE_ADDR_WIDTH(12)
    ) u_pattern_gen_256 (
        .clk            (jesd_core_clk),
        .rst            (tx_tone_reset),
        .advance        (tx_tone_advance),
        .cfg_valid      (dac_cfg_apply_pulse_jclk),
        .cfg_reset_phase(dac_cfg_reset_phase_jclk),
        .cfg_phase_inc0 (dac_cfg_phase_inc0_jclk),
        .cfg_phase_inc1 (dac_cfg_phase_inc1_jclk),
        .cfg_phase_inc2 (dac_cfg_phase_inc2_jclk),
        .cfg_phase_inc3 (dac_cfg_phase_inc3_jclk),
        .cfg_scale0     (dac_cfg_scale0_jclk),
        .cfg_scale1     (dac_cfg_scale1_jclk),
        .cfg_scale2     (dac_cfg_scale2_jclk),
        .cfg_scale3     (dac_cfg_scale3_jclk),
        .wave_clk       (phy1_rxck),
        .wave_rst       (phy1_rx_rst),
        .wave_wr_en     (dac_wave_wr_en_rxclk),
        .wave_wr_addr   (dac_wave_wr_addr_rxclk),
        .wave_wr_data   (dac_wave_wr_data_rxclk),
        .wave_total_samples(dac_wave_total_samples_rxclk),
        .wave_commit_toggle(dac_wave_commit_toggle_rxclk),
        .data_out(tx_pattern_data)
    );

    always @(posedge jesd_core_clk) begin
        if (jesd_rx_core_reset) begin
            jesd_rx_snapshot_div         <= 5'd0;
            jesd_rx_snapshot_lane_jclk   <= 3'd0;
            jesd_rx_snapshot_group_jclk  <= 1'b0;
            jesd_rx_data_snapshot_jclk  <= 32'd0;
            jesd_rx_gt_octets01_jclk    <= 32'd0;
            jesd_rx_gt_octets23_jclk    <= 32'd0;
            jesd_rx_gt_octets45_jclk    <= 32'd0;
            jesd_rx_gt_octets67_jclk    <= 32'd0;
            jesd_rx_snapshot_toggle_jclk <= 1'b0;
        end else begin
            jesd_rx_snapshot_div <= jesd_rx_snapshot_div + 1'b1;
            if (jesd_rx_snapshot_div == 5'd15) begin
                jesd_rx_snapshot_div         <= 5'd0;
                jesd_rx_snapshot_toggle_jclk <= ~jesd_rx_snapshot_toggle_jclk;
                jesd_rx_snapshot_group_jclk <= ~jesd_rx_snapshot_group_jclk;
                if (jesd_rx_snapshot_group_jclk) begin
                    jesd_rx_snapshot_lane_jclk <= jesd_rx_snapshot_lane_jclk + 1'b1;
                end
                jesd_rx_data_snapshot_jclk <= {
                    4'hc,
                    jesd_rx_snapshot_lane_jclk,
                    jesd_rx_snapshot_group_jclk,
                    jesd_rx_sync,
                    jesd_rx_snapshot_lane_block_sync,
                    jesd_rx_snapshot_charisk_word,
                    jesd_rx_snapshot_disperr_word,
                    jesd_rx_snapshot_notintable_word,
                    jesd_rx_snapshot_data_word
                };
                jesd_rx_gt_octets01_jclk <= jesd_rx_lane01_data_low;
                jesd_rx_gt_octets23_jclk <= jesd_rx_lane23_data_low;
                jesd_rx_gt_octets45_jclk <= jesd_rx_lane45_data_low;
                jesd_rx_gt_octets67_jclk <= jesd_rx_lane67_data_low;
            end
        end
    end

    tx_mapper u_tx_mapper (
        .data_in        (tx_pattern_data),
        .data_in_ready  (),
        .data_out0      (jesd_tx_data0),
        .data_out1      (jesd_tx_data1),
        .dac0_sample0_ila(tone_dac0_sample0),
        .dac1_sample0_ila(tone_dac1_sample0),
        .dac2_sample0_ila(tone_dac2_sample0),
        .dac3_sample0_ila(tone_dac3_sample0)
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
        .s_axi_araddr  (jesd0_s_axi_araddr),
        .s_axi_arvalid (jesd0_s_axi_arvalid),
        .s_axi_arready (jesd0_s_axi_arready),
        .s_axi_rdata   (jesd0_s_axi_rdata),
        .s_axi_rresp   (jesd0_s_axi_rresp),
        .s_axi_rvalid  (jesd0_s_axi_rvalid),
        .s_axi_rready  (jesd0_s_axi_rready),
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
        .s_axi_araddr  (jesd1_s_axi_araddr),
        .s_axi_arvalid (jesd1_s_axi_arvalid),
        .s_axi_arready (jesd1_s_axi_arready),
        .s_axi_rdata   (jesd1_s_axi_rdata),
        .s_axi_rresp   (jesd1_s_axi_rresp),
        .s_axi_rvalid  (jesd1_s_axi_rvalid),
        .s_axi_rready  (jesd1_s_axi_rready),
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

    jesd204c_rx_link0 u_jesd204c_rx_link0 (
        .s_axi_aclk       (sys_clk),
        .s_axi_aresetn    (jesd_axi_aresetn),
        .s_axi_awaddr     (jesdrx_s_axi_awaddr),
        .s_axi_awvalid    (jesdrx_s_axi_awvalid),
        .s_axi_awready    (jesdrx_s_axi_awready),
        .s_axi_wdata      (jesdrx_s_axi_wdata),
        .s_axi_wstrb      (jesdrx_s_axi_wstrb),
        .s_axi_wvalid     (jesdrx_s_axi_wvalid),
        .s_axi_wready     (jesdrx_s_axi_wready),
        .s_axi_bresp      (jesdrx_s_axi_bresp),
        .s_axi_bvalid     (jesdrx_s_axi_bvalid),
        .s_axi_bready     (jesdrx_s_axi_bready),
        .s_axi_araddr     (jesdrx_s_axi_araddr),
        .s_axi_arvalid    (jesdrx_s_axi_arvalid),
        .s_axi_arready    (jesdrx_s_axi_arready),
        .s_axi_rdata      (jesdrx_s_axi_rdata),
        .s_axi_rresp      (jesdrx_s_axi_rresp),
        .s_axi_rvalid     (jesdrx_s_axi_rvalid),
        .s_axi_rready     (jesdrx_s_axi_rready),
        .rx_core_clk      (jesd_core_clk),
        .rx_core_reset    (jesd_rx_core_reset),
        .rx_sysref        (jesd_rx_sysref),
        .irq              (),
        .rx_tdata         (jesd_rx_tdata),
        .rx_tvalid        (jesd_rx_tvalid),
        .rx_aresetn       (jesd_rx_aresetn),
        .rx_sof           (jesd_rx_sof),
        .rx_somf          (jesd_rx_somf),
        .rx_frm_err       (jesd_rx_frm_err),
        .rx_sync          (jesd_rx_sync),
        .encommaalign     (jesd_rx_encommaalign),
        .rx_reset_gt      (jesd_rx_reset_gt_core),
        .rx_reset_done    (jesd_rx_reset_done),
        .gt0_rxdata       (jesd_rx_gt0_rxdata),
        .gt0_rxcharisk    (jesd_rx_gt0_rxcharisk),
        .gt0_rxdisperr    (jesd_rx_gt0_rxdisperr),
        .gt0_rxnotintable (jesd_rx_gt0_rxnotintable),
        .gt0_rxheader     (jesd_rx_gt0_rxheader),
        .gt0_rxmisalign   (jesd_rx_gt0_rxmisalign),
        .gt0_rxblock_sync (jesd_rx_gt0_rxblock_sync),
        .gt1_rxdata       (jesd_rx_gt1_rxdata),
        .gt1_rxcharisk    (jesd_rx_gt1_rxcharisk),
        .gt1_rxdisperr    (jesd_rx_gt1_rxdisperr),
        .gt1_rxnotintable (jesd_rx_gt1_rxnotintable),
        .gt1_rxheader     (jesd_rx_gt1_rxheader),
        .gt1_rxmisalign   (jesd_rx_gt1_rxmisalign),
        .gt1_rxblock_sync (jesd_rx_gt1_rxblock_sync),
        .gt2_rxdata       (jesd_rx_gt2_rxdata),
        .gt2_rxcharisk    (jesd_rx_gt2_rxcharisk),
        .gt2_rxdisperr    (jesd_rx_gt2_rxdisperr),
        .gt2_rxnotintable (jesd_rx_gt2_rxnotintable),
        .gt2_rxheader     (jesd_rx_gt2_rxheader),
        .gt2_rxmisalign   (jesd_rx_gt2_rxmisalign),
        .gt2_rxblock_sync (jesd_rx_gt2_rxblock_sync),
        .gt3_rxdata       (jesd_rx_gt3_rxdata),
        .gt3_rxcharisk    (jesd_rx_gt3_rxcharisk),
        .gt3_rxdisperr    (jesd_rx_gt3_rxdisperr),
        .gt3_rxnotintable (jesd_rx_gt3_rxnotintable),
        .gt3_rxheader     (jesd_rx_gt3_rxheader),
        .gt3_rxmisalign   (jesd_rx_gt3_rxmisalign),
        .gt3_rxblock_sync (jesd_rx_gt3_rxblock_sync),
        .gt4_rxdata       (jesd_rx_gt4_rxdata),
        .gt4_rxcharisk    (jesd_rx_gt4_rxcharisk),
        .gt4_rxdisperr    (jesd_rx_gt4_rxdisperr),
        .gt4_rxnotintable (jesd_rx_gt4_rxnotintable),
        .gt4_rxheader     (jesd_rx_gt4_rxheader),
        .gt4_rxmisalign   (jesd_rx_gt4_rxmisalign),
        .gt4_rxblock_sync (jesd_rx_gt4_rxblock_sync),
        .gt5_rxdata       (jesd_rx_gt5_rxdata),
        .gt5_rxcharisk    (jesd_rx_gt5_rxcharisk),
        .gt5_rxdisperr    (jesd_rx_gt5_rxdisperr),
        .gt5_rxnotintable (jesd_rx_gt5_rxnotintable),
        .gt5_rxheader     (jesd_rx_gt5_rxheader),
        .gt5_rxmisalign   (jesd_rx_gt5_rxmisalign),
        .gt5_rxblock_sync (jesd_rx_gt5_rxblock_sync),
        .gt6_rxdata       (jesd_rx_gt6_rxdata),
        .gt6_rxcharisk    (jesd_rx_gt6_rxcharisk),
        .gt6_rxdisperr    (jesd_rx_gt6_rxdisperr),
        .gt6_rxnotintable (jesd_rx_gt6_rxnotintable),
        .gt6_rxheader     (jesd_rx_gt6_rxheader),
        .gt6_rxmisalign   (jesd_rx_gt6_rxmisalign),
        .gt6_rxblock_sync (jesd_rx_gt6_rxblock_sync),
        .gt7_rxdata       (jesd_rx_gt7_rxdata),
        .gt7_rxcharisk    (jesd_rx_gt7_rxcharisk),
        .gt7_rxdisperr    (jesd_rx_gt7_rxdisperr),
        .gt7_rxnotintable (jesd_rx_gt7_rxnotintable),
        .gt7_rxheader     (jesd_rx_gt7_rxheader),
        .gt7_rxmisalign   (jesd_rx_gt7_rxmisalign),
        .gt7_rxblock_sync (jesd_rx_gt7_rxblock_sync)
    );

    jesd_phy_axi_probe #(
        .USE_QPLL0(JESD_USE_QPLL),
        .ENABLE_RX_POLARITY_CFG(ADC_RX_POLARITY_CFG_ENABLE),
        .RX_POLARITY_CFG(ADC_RX_POLARITY_PHY0_INIT),
        .ENABLE_RX_POLARITY_SWEEP(ADC_RX_POLARITY_SWEEP_ENABLE),
        .RX_POLARITY_SWEEP_HOLD_CYCLES(ADC_RX_POLARITY_PHY0_HOLD_TICKS),
        .PULSE_RX_SYS_RESET_ON_POLARITY(1),
        .ENABLE_RX_LPMEN_CFG(ADC_RX_LPMEN_PHY0_CFG_ENABLE),
        .RX_LPMEN_CFG(ADC_RX_LPMEN_CFG),
        .PULSE_RXDFELPMRESET_ON_RX_LPMEN(1),
        .PULSE_RX_SYS_RESET_ON_RX_LPMEN(1)
    ) u_phy0_axi_probe (
        .clk            (sys_clk),
        .rst            (!jesd_axi_aresetn),
        .enable         (jesd_cfg_done_seen),
        .rx_polarity_freeze(jesd_rx_tvalid_seen),
        .rx_gt_disperr  (jesd_gt_rxdisperr_dbg[3:0]),
        .rx_gt_notintable(jesd_gt_rxnotintable_dbg[3:0]),
        .rx_gt_commadet (jesd_gt_rxcommadet_dbg[3:0]),
        .rx_gt_block_sync(jesd_gt_rxblock_sync_dbg[3:0]),
        .running        (),
        .done_seen      (phy0_axi_done_seen),
        .error_seen     (),
        .state_dbg      (),
        .last_addr_dbg  (),
        .status_dbg     (phy0_axi_status_dbg),
        .txlinerate_dbg (phy0_axi_txlinerate_dbg),
        .txrefclk_dbg   (phy0_axi_txrefclk_dbg),
        .ctrl_dbg       (phy0_axi_ctrl_dbg),
        .fsm_dbg        (phy0_axi_fsm_dbg),
        .txctrl_dbg     (phy0_axi_txctrl_dbg),
        .rxsweep_dbg    (phy0_axi_rxsweep_dbg),
        .s_axi_awaddr   (phy0_s_axi_awaddr),
        .s_axi_awvalid  (phy0_s_axi_awvalid),
        .s_axi_awready  (phy0_s_axi_awready),
        .s_axi_wdata    (phy0_s_axi_wdata),
        .s_axi_wvalid   (phy0_s_axi_wvalid),
        .s_axi_wready   (phy0_s_axi_wready),
        .s_axi_bresp    (phy0_s_axi_bresp),
        .s_axi_bvalid   (phy0_s_axi_bvalid),
        .s_axi_bready   (phy0_s_axi_bready),
        .s_axi_araddr   (phy0_s_axi_araddr),
        .s_axi_arvalid  (phy0_s_axi_arvalid),
        .s_axi_arready  (phy0_s_axi_arready),
        .s_axi_rdata    (phy0_s_axi_rdata),
        .s_axi_rresp    (phy0_s_axi_rresp),
        .s_axi_rvalid   (phy0_s_axi_rvalid),
        .s_axi_rready   (phy0_s_axi_rready)
    );

    jesd_phy_axi_probe #(
        .USE_QPLL0(JESD_USE_QPLL),
        .ENABLE_RX_POLARITY_CFG(ADC_RX_POLARITY_CFG_ENABLE),
        .RX_POLARITY_CFG(ADC_RX_POLARITY_PHY1_INIT),
        .ENABLE_RX_POLARITY_SWEEP(ADC_RX_POLARITY_SWEEP_ENABLE),
        .RX_POLARITY_SWEEP_HOLD_CYCLES(ADC_RX_POLARITY_PHY1_HOLD_TICKS),
        .PULSE_RX_SYS_RESET_ON_POLARITY(1),
        .ENABLE_RX_LPMEN_CFG(ADC_RX_LPMEN_PHY1_CFG_ENABLE),
        .RX_LPMEN_CFG(ADC_RX_LPMEN_CFG),
        .PULSE_RXDFELPMRESET_ON_RX_LPMEN(1),
        .PULSE_RX_SYS_RESET_ON_RX_LPMEN(1)
    ) u_phy1_axi_probe (
        .clk            (sys_clk),
        .rst            (!jesd_axi_aresetn),
        .enable         (jesd_cfg_done_seen),
        .rx_polarity_freeze(jesd_rx_tvalid_seen),
        .rx_gt_disperr  (jesd_gt_rxdisperr_dbg[7:4]),
        .rx_gt_notintable(jesd_gt_rxnotintable_dbg[7:4]),
        .rx_gt_commadet (jesd_gt_rxcommadet_dbg[7:4]),
        .rx_gt_block_sync(jesd_gt_rxblock_sync_dbg[7:4]),
        .running        (),
        .done_seen      (phy1_axi_done_seen),
        .error_seen     (),
        .state_dbg      (),
        .last_addr_dbg  (),
        .status_dbg     (phy1_axi_status_dbg),
        .txlinerate_dbg (phy1_axi_txlinerate_dbg),
        .txrefclk_dbg   (phy1_axi_txrefclk_dbg),
        .ctrl_dbg       (phy1_axi_ctrl_dbg),
        .fsm_dbg        (phy1_axi_fsm_dbg),
        .txctrl_dbg     (phy1_axi_txctrl_dbg),
        .rxsweep_dbg    (phy1_axi_rxsweep_dbg),
        .s_axi_awaddr   (phy1_s_axi_awaddr),
        .s_axi_awvalid  (phy1_s_axi_awvalid),
        .s_axi_awready  (phy1_s_axi_awready),
        .s_axi_wdata    (phy1_s_axi_wdata),
        .s_axi_wvalid   (phy1_s_axi_wvalid),
        .s_axi_wready   (phy1_s_axi_wready),
        .s_axi_bresp    (phy1_s_axi_bresp),
        .s_axi_bvalid   (phy1_s_axi_bvalid),
        .s_axi_bready   (phy1_s_axi_bready),
        .s_axi_araddr   (phy1_s_axi_araddr),
        .s_axi_arvalid  (phy1_s_axi_arvalid),
        .s_axi_arready  (phy1_s_axi_arready),
        .s_axi_rdata    (phy1_s_axi_rdata),
        .s_axi_rresp    (phy1_s_axi_rresp),
        .s_axi_rvalid   (phy1_s_axi_rvalid),
        .s_axi_rready   (phy1_s_axi_rready)
    );

    jesd204_phy_tx_quad226 u_jesd204_phy_tx_quad226 (
        .cpll_refclk         (1'b0),
        .qpll0_refclk        (jesd_refclk),
        .qpll1_refclk        (1'b0),
        .drpclk              (sys_clk),
        .tx_reset_gt         (jesd_tx_reset_gt0),
        .rx_reset_gt         (jesd_rx_reset_gt),
        .tx_sys_reset        (!jesd_release),
        .rx_sys_reset        (jesd_rx_core_reset),
        .txp_out             (dac_tx_p[3:0]),
        .txn_out             (dac_tx_n[3:0]),
        .rxp_in              (adc_rx_p[3:0]),
        .rxn_in              (adc_rx_n[3:0]),
        .tx_core_clk         (jesd_core_clk),
        .rx_core_clk         (jesd_core_clk),
        .txoutclk            (jesd_txoutclk0),
        .rxoutclk            (),
        .gt_cplllock         (jesd_gt_cplllock0),
        .gt_txresetdone      (jesd_gt_txresetdone0),
        .gt_rxresetdone      (jesd_gt_rxresetdone0),
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
        .gt_rxpmaresetdone   (jesd_gt_rxpmaresetdone0),
        .gt_rxcdrhold        (4'd0),
        .gt_rxcommadet       (jesd_gt_rxcommadet0),
        .gt_rxbufreset       (4'd0),
        .gt_rxbufstatus      (jesd_gt_rxbufstatus0),
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
        .gt0_rxdata          (jesd_rx_gt0_rxdata),
        .gt0_rxcharisk       (jesd_rx_gt0_rxcharisk),
        .gt0_rxdisperr       (jesd_rx_gt0_rxdisperr),
        .gt0_rxnotintable    (jesd_rx_gt0_rxnotintable),
        .gt0_rxheader        (jesd_rx_gt0_rxheader),
        .gt0_rxmisalign      (jesd_rx_gt0_rxmisalign),
        .gt0_rxblock_sync    (jesd_rx_gt0_rxblock_sync),
        .gt1_rxdata          (jesd_rx_gt1_rxdata),
        .gt1_rxcharisk       (jesd_rx_gt1_rxcharisk),
        .gt1_rxdisperr       (jesd_rx_gt1_rxdisperr),
        .gt1_rxnotintable    (jesd_rx_gt1_rxnotintable),
        .gt1_rxheader        (jesd_rx_gt1_rxheader),
        .gt1_rxmisalign      (jesd_rx_gt1_rxmisalign),
        .gt1_rxblock_sync    (jesd_rx_gt1_rxblock_sync),
        .gt2_rxdata          (jesd_rx_gt2_rxdata),
        .gt2_rxcharisk       (jesd_rx_gt2_rxcharisk),
        .gt2_rxdisperr       (jesd_rx_gt2_rxdisperr),
        .gt2_rxnotintable    (jesd_rx_gt2_rxnotintable),
        .gt2_rxheader        (jesd_rx_gt2_rxheader),
        .gt2_rxmisalign      (jesd_rx_gt2_rxmisalign),
        .gt2_rxblock_sync    (jesd_rx_gt2_rxblock_sync),
        .gt3_rxdata          (jesd_rx_gt3_rxdata),
        .gt3_rxcharisk       (jesd_rx_gt3_rxcharisk),
        .gt3_rxdisperr       (jesd_rx_gt3_rxdisperr),
        .gt3_rxnotintable    (jesd_rx_gt3_rxnotintable),
        .gt3_rxheader        (jesd_rx_gt3_rxheader),
        .gt3_rxmisalign      (jesd_rx_gt3_rxmisalign),
        .gt3_rxblock_sync    (jesd_rx_gt3_rxblock_sync),
        .rx_reset_done       (jesd_phy_rx_reset_done0),
        .rxencommaalign      (jesd_rx_encommaalign),
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
        .s_axi_araddr        (phy0_s_axi_araddr),
        .s_axi_arvalid       (phy0_s_axi_arvalid),
        .s_axi_arready       (phy0_s_axi_arready),
        .s_axi_rdata         (phy0_s_axi_rdata),
        .s_axi_rresp         (phy0_s_axi_rresp),
        .s_axi_rvalid        (phy0_s_axi_rvalid),
        .s_axi_rready        (phy0_s_axi_rready)
    );

    jesd204_phy_tx_quad227 u_jesd204_phy_tx_quad227 (
        .cpll_refclk         (1'b0),
        .qpll0_refclk        (jesd_refclk),
        .qpll1_refclk        (1'b0),
        .drpclk              (sys_clk),
        .tx_reset_gt         (jesd_tx_reset_gt1),
        .rx_reset_gt         (jesd_rx_reset_gt),
        .tx_sys_reset        (!jesd_release),
        .rx_sys_reset        (jesd_rx_core_reset),
        .txp_out             (dac_tx_p[7:4]),
        .txn_out             (dac_tx_n[7:4]),
        .rxp_in              (adc_rx_p[7:4]),
        .rxn_in              (adc_rx_n[7:4]),
        .tx_core_clk         (jesd_core_clk),
        .rx_core_clk         (jesd_core_clk),
        .txoutclk            (jesd_txoutclk1),
        .rxoutclk            (),
        .gt_cplllock         (jesd_gt_cplllock1),
        .gt_txresetdone      (jesd_gt_txresetdone1),
        .gt_rxresetdone      (jesd_gt_rxresetdone1),
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
        .gt_rxpmaresetdone   (jesd_gt_rxpmaresetdone1),
        .gt_rxcdrhold        (4'd0),
        .gt_rxcommadet       (jesd_gt_rxcommadet1),
        .gt_rxbufreset       (4'd0),
        .gt_rxbufstatus      (jesd_gt_rxbufstatus1),
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
        .gt0_rxdata          (jesd_rx_gt4_rxdata),
        .gt0_rxcharisk       (jesd_rx_gt4_rxcharisk),
        .gt0_rxdisperr       (jesd_rx_gt4_rxdisperr),
        .gt0_rxnotintable    (jesd_rx_gt4_rxnotintable),
        .gt0_rxheader        (jesd_rx_gt4_rxheader),
        .gt0_rxmisalign      (jesd_rx_gt4_rxmisalign),
        .gt0_rxblock_sync    (jesd_rx_gt4_rxblock_sync),
        .gt1_rxdata          (jesd_rx_gt5_rxdata),
        .gt1_rxcharisk       (jesd_rx_gt5_rxcharisk),
        .gt1_rxdisperr       (jesd_rx_gt5_rxdisperr),
        .gt1_rxnotintable    (jesd_rx_gt5_rxnotintable),
        .gt1_rxheader        (jesd_rx_gt5_rxheader),
        .gt1_rxmisalign      (jesd_rx_gt5_rxmisalign),
        .gt1_rxblock_sync    (jesd_rx_gt5_rxblock_sync),
        .gt2_rxdata          (jesd_rx_gt6_rxdata),
        .gt2_rxcharisk       (jesd_rx_gt6_rxcharisk),
        .gt2_rxdisperr       (jesd_rx_gt6_rxdisperr),
        .gt2_rxnotintable    (jesd_rx_gt6_rxnotintable),
        .gt2_rxheader        (jesd_rx_gt6_rxheader),
        .gt2_rxmisalign      (jesd_rx_gt6_rxmisalign),
        .gt2_rxblock_sync    (jesd_rx_gt6_rxblock_sync),
        .gt3_rxdata          (jesd_rx_gt7_rxdata),
        .gt3_rxcharisk       (jesd_rx_gt7_rxcharisk),
        .gt3_rxdisperr       (jesd_rx_gt7_rxdisperr),
        .gt3_rxnotintable    (jesd_rx_gt7_rxnotintable),
        .gt3_rxheader        (jesd_rx_gt7_rxheader),
        .gt3_rxmisalign      (jesd_rx_gt7_rxmisalign),
        .gt3_rxblock_sync    (jesd_rx_gt7_rxblock_sync),
        .rx_reset_done       (jesd_phy_rx_reset_done1),
        .rxencommaalign      (jesd_rx_encommaalign),
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
        .s_axi_araddr        (phy1_s_axi_araddr),
        .s_axi_arvalid       (phy1_s_axi_arvalid),
        .s_axi_arready       (phy1_s_axi_arready),
        .s_axi_rdata         (phy1_s_axi_rdata),
        .s_axi_rresp         (phy1_s_axi_rresp),
        .s_axi_rvalid        (phy1_s_axi_rvalid),
        .s_axi_rready        (phy1_s_axi_rready)
    );

    generate
    if (ENABLE_DEBUG_ILA != 0) begin : g_debug_ila
    ku5p_bringup_ila u_ila_0 (
        .clk   (sys_clk),
        .probe0(state),
        .probe1({jesd_txoutclk_edge_count1, jesd_txoutclk_edge_count0}),
        .probe2(jesd_refclk_mon_edge_count),
        .probe3(jesd_core_alive_edge_count),
        .probe4({
            dac_sync0_d,
            jesd_txoutclk_dbg1,
            jesd_txoutclk_dbg0,
            jesd_refclk_mon_dbg,
            jesd_core_alive_dbg,
            sysref2_d,
            jesd_release,
            jesd_cfg_done,
            jesd_cfg_done_seen,
            jesd_links_ready
        }),
        .probe5(hmc_status_latched[31:0]),
        .probe6(jesd_ready_summary_dbg),
        .probe7(jesd_ready_flags_dbg),
        .probe8(jesd_aresetn_dbg),
        .probe9(jesd_tready_dbg),
        .probe10(jesd_tx_reset_done_dbg),
        .probe11(jesd_gt_powergood_dbg),
        .probe12(jesd_cplllock_dbg),
        .probe13({
            jesd_busy_dbg,
            jesd_done_dbg,
            jesd_start_seen,
            jesd_done_seen
        }),
        .probe14({
            hmc_debug_state,
            hmc_debug_read_busy,
            hmc_debug_read_done,
            hmc_debug_pll1_locked
        }),
        .probe15({
            dac_sync1_raw_d,
            dac_sync1_d,
            jesd_tx_reset_done_dbg,
            jesd_tready_dbg,
            jesd_aresetn_dbg,
            jesd_links_ready_seen,
            jesd_release_seen,
            jesd_txoutclk_seen1,
            jesd_txoutclk_seen0,
            jesd_core_alive_seen,
            jesd_refclk_mon_seen
        }),
        .probe16({hmc_debug_read_addr, hmc_debug_read_data}),
        .probe17({jesd_gt_txresetdone_dbg, jesd_tx_reset_gt_dbg}),
        .probe18(sysref_edge_count),
        .probe19(phy0_axi_status_dbg),
        .probe20(phy0_axi_txlinerate_dbg),
        .probe21(phy0_axi_txrefclk_dbg),
        .probe22(phy0_axi_ctrl_dbg),
        .probe23(phy0_axi_fsm_dbg),
        .probe24(phy1_axi_status_dbg),
        .probe25(phy1_axi_txlinerate_dbg),
        .probe26(phy1_axi_txrefclk_dbg),
        .probe27(phy1_axi_ctrl_dbg),
        .probe28(phy1_axi_fsm_dbg),
        .probe29(jesd_refclk_mon_cycles_1ms),
        .probe30({
            start_adc,
            txen_1,
            txen_0,
            resetb,
            dac_init_fail,
            dac_init_ok,
            dac_done,
            dac_busy,
            adc_init_fail,
            adc_init_ok,
            adc_done,
            adc_busy,
            adc_sdio_oe,
            adc_sclk,
            adc_csb,
            adc_pdwn
        }),
        .probe31({adc_status_latched, adc_init_status_dbg}),
        .probe32(jesd_cplllock_seen),
        .probe33(jesd_gt_txresetdone_seen),
        .probe34({jesd_gt_txresetdone_rise_count, jesd_cplllock_rise_count}),
        .probe35({
            jesd_qpll_lock_rise_count[7:0],
            jesd_qpll_lock_rise_count,
            jesd_qpll_lock_seen,
            jesd_qpll_lock_dbg
        }),
        .probe36(jesd_release_stable_count),
        .probe37(jesd_links_ready_stable_count),
        .probe38({
            jesd_links_ready_drop_count[11:0],
            jesd_fault_code_latched,
            jesd_fault_code_dbg,
            jesd_links_ready_stable_seen,
            jesd_release_ready,
            jesd_pll_ready_dbg,
            jesd_links_ready
        }),
        .probe39(phy0_axi_txctrl_dbg),
        .probe40(phy1_axi_txctrl_dbg),
        .probe41(dac_sanity_latched),
        .probe42(dac_debug_latched),
        .probe43(dac_spi_live_dbg),
        .probe44(dac_init_debug_dbg),
        .probe45({dac_sync1_edge_count, dac_sync0_edge_count}),
        .probe46({
            jesd_retry_count,
            jesd_retry_reset_count[7:0],
            jesd_pll_missing_count[7:0]
        }),
        .probe47(dac_link0_status_dbg),
        .probe48(dac_link1_status_dbg),
        .probe49(dac_link0_error_dbg),
        .probe50(dac_link1_error_dbg),
        .probe51(dac_link_evidence_dbg),
        .probe52(jesd0_tx_status_dbg),
        .probe53(jesd1_tx_status_dbg),
        .probe54(jesd0_tx_reset_lanes_dbg),
        .probe55(jesd1_tx_reset_lanes_dbg),
        .probe56(jesd0_tx_cfg_dbg),
        .probe57(jesd1_tx_cfg_dbg),
        .probe58(jesd0_tx_ila1_dbg),
        .probe59(jesd1_tx_ila1_dbg),
        .probe60(jesd0_tx_ila2_dbg),
        .probe61(jesd1_tx_ila2_dbg),
        .probe62(jesd0_tx_laneids_dbg),
        .probe63(jesd1_tx_laneids_dbg),
        .probe64(jesd0_tx_axi_live_dbg),
        .probe65(jesd1_tx_axi_live_dbg),
        .probe66(adc_init_fsm_dbg),
        .probe67(adc_init_read_dbg),
        .probe68(adc_debug_jesd_ctrl),
        .probe69(adc_debug_jesd_param),
        .probe70(adc_debug_lane_map),
        .probe71(hmc_verify_status_dbg),
        .probe72(adc_debug_serdes_emph),
        .probe73(hmc_ch4_snapshot_dbg),
        .probe74(adc_init_patch_dbg_q),
        .probe75(adc_debug_sysref),
        .probe76(jesd_rx_link_summary_dbg),
        .probe77(jesd_rx_gt_summary_dbg),
        .probe78(jesd_rx_status_dbg),
        .probe79(jesd_rx_err_dbg),
        .probe80(jesd_rx_debug_dbg),
        .probe81(jesd_rx_first_good_dbg),
        .probe82(jesd_rx_cfg_dbg),
        .probe83(jesd_rx_lanes_dbg),
        .probe84(jesd_rx_lane0_ilas0_dbg),
        .probe85(jesd_rx_lane0_ilas1_dbg),
        .probe86(jesd_rx_axi_live_dbg),
        .probe87(jesd_rx_gt_detail0_dbg),
        .probe88(jesd_rx_gt_detail1_dbg),
        .probe89(jesd_rx_lane0_ilas2_dbg),
        .probe90(jesd_rx_lane0_ilas3_dbg),
        .probe91(jesd_rx_lane0_ilas4_dbg),
        .probe92(jesd_rx_lane0_ilas5_dbg),
        .probe93(jesd_rx_ilas3_lanes03_dbg),
        .probe94(jesd_rx_ilas3_lanes47_dbg),
        .probe95(jesd_rx_lane3_ilas0_dbg),
        .probe96(jesd_rx_lane3_ilas1_dbg),
        .probe97(jesd_rx_lane3_ilas2_dbg),
        .probe98(jesd_rx_lane3_ilas3_dbg),
        .probe99(jesd_rx_lane3_ilas4_dbg),
        .probe100(adc_debug_serdes_cfg),
        .probe101(adc_debug_serdes),
        .probe102(adc_sync_loop_dbg_q),
        .probe103(adc_rx_rearm_dbg_q),
        .probe104(jesd_rx_first_drop_dbg),
        .probe105(jesd_rx_first_drop_age_dbg),
        .probe106(jesd_rx_first_drop_sysref_dbg),
        .probe107(adc_udp_ctrl_dbg),
        .probe108(adc_udp_capture_count_dbg),
        .probe109(adc_udp_eth_dbg),
        .probe110(dac_cfg_status_dbg)
    );
    end
    endgenerate

    initial begin
        adc_pdwn               = 1'b1;
        resetb                 = 1'b0;
        txen_0                 = 1'b0;
        txen_1                 = 1'b0;
        adc_sync_drive         = 1'b0;
        start_hmc              = 1'b0;
        start_dac              = 1'b0;
        start_jesd0            = 1'b0;
        start_jesd1            = 1'b0;
        start_jesd_rx          = 1'b0;
        start_adc              = 1'b0;
        adc_runtime_patch_start = 1'b0;
        adc_runtime_link_reinit_start = 1'b0;
        adc_runtime_patch_requested = 1'b0;
        adc_runtime_patch_done_latched = 1'b0;
        adc_runtime_patch_fail_latched = 1'b0;
        jesd_rx_cfg_done_seen  = 1'b0;
        heartbeat              = 16'd0;
        jesd_refclk_mon_heartbeat = 8'd0;
        jesd_txoutclk_heartbeat0 = 8'd0;
        jesd_txoutclk_heartbeat1 = 8'd0;
        boot_count             = 32'd0;
        hold_count             = 32'd0;
        state                  = ST_BOOT;
        sysref_edge_count      = 16'd0;
        jesd_refclk_mon_edge_count = 16'd0;
        jesd_core_alive_edge_count = 16'd0;
        jesd_txoutclk_edge_count0 = 16'd0;
        jesd_txoutclk_edge_count1 = 16'd0;
        jesd_refclk_mon_cycles_1ms = 32'd0;
        refclk_mon_counter     = 32'd0;
        refclk_mon_gray_src    = 32'd0;
        refclk_mon_gray_meta   = 32'd0;
        refclk_mon_gray_sync   = 32'd0;
        refclk_mon_count_prev  = 32'd0;
        refclk_measure_count   = 18'd0;
        dac_sync0_edge_count   = 16'd0;
        dac_sync1_edge_count   = 16'd0;
        sysref2_d              = 1'b0;
        dac_sync0_d            = 1'b0;
        dac_sync1_raw_d        = 1'b0;
        dac_sync1_d            = 1'b0;
        dac_sdo_d              = 1'b0;
        jesd_refclk_mon_dbg    = 1'b0;
        jesd_core_alive_dbg    = 1'b0;
        jesd_txoutclk_dbg0     = 1'b0;
        jesd_txoutclk_dbg1     = 1'b0;
        jesd_release           = 1'b0;
        jesd_release_seen      = 1'b0;
        jesd_cfg_done_seen     = 1'b0;
        jesd_links_ready_seen  = 1'b0;
        jesd_links_ready_stable_seen = 1'b0;
        jesd_release_stable_count = 32'd0;
        jesd_links_ready_stable_count = 32'd0;
        jesd_links_ready_drop_count = 16'd0;
        jesd_pll_missing_count = 32'd0;
        jesd_retry_reset_count = 32'd0;
        jesd_retry_count       = 16'd0;
        jesd_start_seen        = 2'b00;
        jesd_done_seen         = 2'b00;
        jesd_refclk_mon_seen   = 1'b0;
        jesd_core_alive_seen   = 1'b0;
        jesd_txoutclk_seen0    = 1'b0;
        jesd_txoutclk_seen1    = 1'b0;
        jesd_wait_reason_dbg   = JESD_WAIT_NONE;
        jesd_wait_reason_latched = JESD_WAIT_NONE;
        jesd_fault_code_dbg    = JESD_FAULT_NONE;
        jesd_fault_code_latched = JESD_FAULT_NONE;
        adc_diag_bypass_taken  = 1'b0;
        hmc_ok_latched         = 1'b0;
        hmc_fail_latched       = 1'b0;
        hmc_status_latched     = 40'd0;
        adc_ok_latched         = 1'b0;
        adc_fail_latched       = 1'b0;
        adc_status_latched     = 16'd0;
        dac_ok_latched         = 1'b0;
        dac_fail_latched       = 1'b0;
        dac_status_latched     = 32'd0;
        dac_sanity_latched     = 32'd0;
        dac_debug_latched      = 32'd0;
        jesd_core_heartbeat    = 8'd0;
        jesd_refclk_mon_meta   = 2'b00;
        jesd_core_alive_meta   = 2'b00;
        jesd_txoutclk_meta0    = 2'b00;
        jesd_txoutclk_meta1    = 2'b00;
        jesd_rx_tvalid_meta    = 2'b00;
        jesd_rx_sync_meta      = 2'b00;
        jesd_rx_aresetn_meta   = 2'b00;
        jesd_rx_reset_gt_meta  = 2'b00;
        jesd_rx_enable_meta    = 2'b00;
        jesd_rx_encommaalign_meta = 2'b00;
        jesd_gt_rxresetdone_meta = 8'd0;
        jesd_gt_rxresetdone_sync = 8'd0;
        jesd_gt_rxdisperr_meta = 8'd0;
        jesd_gt_rxnotintable_meta = 8'd0;
        jesd_gt_rxcharisk_meta = 8'd0;
        jesd_gt_rxblock_sync_meta = 8'd0;
        jesd_gt_rxmisalign_meta = 8'd0;
        jesd_gt_rxcommadet_meta = 8'd0;
        jesd_gt_rxpmaresetdone_meta = 8'd0;
        jesd_gt_rxpmaresetdone_sync = 8'd0;
        jesd_gt_rxbufstatus_meta = 24'd0;
        jesd_gt_rxbufstatus_sync = 24'd0;
        jesd_gt_rxdisperr_seen_meta = 8'd0;
        jesd_gt_rxnotintable_seen_meta = 8'd0;
        jesd_gt_rxcharisk_seen_meta = 8'd0;
        jesd_gt_rxblock_sync_seen_meta = 8'd0;
        jesd_gt_rxcommadet_seen_meta = 8'd0;
        adc_runtime_patch_done_meta_jclk = 3'd0;
        adc_runtime_patch_fail_meta_jclk = 3'd0;
        adc_runtime_gt_seen_cleared_jclk = 1'b0;
        jesd_aresetn_meta      = 2'b00;
        jesd_tready_meta       = 2'b00;
        jesd_tx_reset_done_meta = 2'b00;
        jesd_gt_powergood_meta = 2'b00;
        jesd_tx_reset_gt_meta  = 2'b00;
        jesd_gt_txresetdone_meta = 8'd0;
        jesd_cplllock_meta     = 8'd0;
        jesd_qpll_lock_meta    = 4'd0;
        tone_snapshot_toggle_meta = 3'd0;
        jesd_rx_snapshot_toggle_meta = 3'd0;
        adc_udp_tx_byte_count = 32'd0;
        adc_udp_tx_burst_count = 16'd0;
        adc_udp_tx_last_data = 8'd0;
        adc_udp_tx_valid_q = 1'b0;
        phy1_rx_rst_sync = 3'b111;
        dac_cfg_toggle_rxclk = 1'b0;
        dac_cfg_reset_phase_hold_rxclk = 1'b0;
        dac_cfg_phase_inc0_hold_rxclk = 48'h053555555555;
        dac_cfg_phase_inc1_hold_rxclk = 48'h07d000000000;
        dac_cfg_phase_inc2_hold_rxclk = 48'h053555555555;
        dac_cfg_phase_inc3_hold_rxclk = 48'h07d000000000;
        dac_cfg_scale0_hold_rxclk = 16'h7fff;
        dac_cfg_scale1_hold_rxclk = 16'h7fff;
        dac_cfg_scale2_hold_rxclk = 16'h7fff;
        dac_cfg_scale3_hold_rxclk = 16'h7fff;
        dac_cfg_toggle_meta_jclk = 3'b000;
        dac_cfg_reset_phase_jclk = 1'b0;
        dac_cfg_phase_inc0_jclk = 48'h053555555555;
        dac_cfg_phase_inc1_jclk = 48'h07d000000000;
        dac_cfg_phase_inc2_jclk = 48'h053555555555;
        dac_cfg_phase_inc3_jclk = 48'h07d000000000;
        dac_cfg_scale0_jclk = 16'h7fff;
        dac_cfg_scale1_jclk = 16'h7fff;
        dac_cfg_scale2_jclk = 16'h7fff;
        dac_cfg_scale3_jclk = 16'h7fff;
        dac_cfg_apply_count_jclk = 32'd0;
        dac_cfg_apply_pulse_jclk = 1'b0;
        jesd_rx_release_meta_jclk = 3'd0;
        sysref2_meta_jclk = 3'd0;
        adc_sync_drive_meta_jclk = 2'b00;
        jesd_rx_enable_jclk = 1'b0;
        jesd_rx_sysref_gated_jclk = 1'b0;
        jesd_rx_sysref_pulse_count_jclk = 4'd0;
        jesd_rx_sysref_gate_done_jclk = 1'b0;
        adc_sync_out_jclk = 1'b0;
        adc_sync_force_count_jclk = 32'd0;
        adc_sync_force_active_jclk = 1'b1;
        adc_sync_hold_locked_jclk = 1'b0;
        adc_sync_hold_good_count_jclk = 32'd0;
        adc_sync_hold_drop_count_jclk = 32'd0;
        adc_sync_hold_drop_seen_jclk = 1'b0;
        adc_sync_force_active_meta = 2'b00;
        adc_sync_out_raw_meta = 2'b00;
        adc_sync_out_meta = 2'b00;
        adc_sync_follow_meta = 2'b00;
        adc_sync_out_next_meta = 2'b00;
        adc_sync_hold_locked_meta = 2'b00;
        adc_sync_hold_active_meta = 2'b00;
        adc_sync_hold_drop_seen_meta = 2'b00;
        jesd_rx_sysref_gated_meta = 2'b00;
        jesd_rx_sysref_gate_done_meta = 2'b00;
        jesd_rx_sysref_pulse_count_meta0 = 4'd0;
        jesd_rx_sysref_pulse_count_meta1 = 4'd0;
        jesd_rx_snapshot_div   = 5'd0;
        jesd_rx_snapshot_lane_jclk = 3'd0;
        jesd_rx_snapshot_group_jclk = 1'b0;
        jesd_rx_data_snapshot_jclk = 32'd0;
        jesd_rx_gt_octets01_jclk = 32'd0;
        jesd_rx_gt_octets23_jclk = 32'd0;
        jesd_rx_gt_octets45_jclk = 32'd0;
        jesd_rx_gt_octets67_jclk = 32'd0;
        jesd_rx_snapshot_toggle_jclk = 1'b0;
        jesd_gt_rxdisperr_seen_jclk = 8'd0;
        jesd_gt_rxnotintable_seen_jclk = 8'd0;
        jesd_gt_rxcharisk_seen_jclk = 8'd0;
        jesd_gt_rxblock_sync_seen_jclk = 8'd0;
        jesd_gt_rxcommadet_seen_jclk = 8'd0;
        adc_runtime_patch_done_meta_jclk = 3'd0;
        adc_runtime_patch_fail_meta_jclk = 3'd0;
        adc_runtime_gt_seen_cleared_jclk = 1'b0;
        tone_dac0_pair01_dbg   = 32'd0;
        tone_dac0_pair23_dbg   = 32'd0;
        tone_dac1_pair01_dbg   = 32'd0;
        tone_dac1_pair23_dbg   = 32'd0;
        tone_snapshot_count_dbg = 32'd0;
        jesd_busy_dbg          = 2'b00;
        jesd_done_dbg          = 2'b00;
        jesd_aresetn_dbg       = 2'b00;
        jesd_tready_dbg        = 2'b00;
        jesd_tx_reset_done_dbg = 2'b00;
        jesd_gt_powergood_dbg  = 2'b00;
        jesd_tx_reset_gt_dbg   = 2'b00;
        jesd_gt_txresetdone_dbg = 8'd0;
        jesd_cplllock_dbg      = 8'd0;
        jesd_cplllock_seen     = 8'd0;
        jesd_gt_txresetdone_seen = 8'd0;
        jesd_cplllock_rise_count = 16'd0;
        jesd_gt_txresetdone_rise_count = 16'd0;
        jesd_qpll_lock_dbg     = 4'd0;
        jesd_qpll_lock_seen    = 4'd0;
        jesd_qpll_lock_rise_count = 16'd0;
        jesd_rx_tvalid_dbg     = 1'b0;
        jesd_rx_tvalid_seen    = 1'b0;
        jesd_rx_sync_dbg       = 1'b1;
        jesd_rx_sync_seen_low  = 1'b0;
        jesd_rx_sync_seen_high = 1'b0;
        jesd_rx_sync_at_patch_start = 1'b0;
        jesd_rx_sync_at_patch_done = 1'b0;
        jesd_rx_encommaalign_dbg = 1'b0;
        jesd_rx_aresetn_dbg    = 1'b0;
        jesd_rx_reset_gt_dbg   = 1'b1;
        jesd_rx_enable_dbg     = 1'b0;
        jesd_gt_rxresetdone_dbg = 8'd0;
        jesd_gt_rxresetdone_seen = 8'd0;
        jesd_gt_rxdisperr_dbg  = 8'd0;
        jesd_gt_rxnotintable_dbg = 8'd0;
        jesd_gt_rxcharisk_dbg  = 8'd0;
        jesd_gt_rxblock_sync_dbg = 8'd0;
        jesd_gt_rxmisalign_dbg = 8'd0;
        jesd_gt_rxcommadet_dbg = 8'd0;
        jesd_gt_rxpmaresetdone_dbg = 8'd0;
        jesd_gt_rxbufstatus_dbg = 24'd0;
        jesd_gt_rxdisperr_seen_dbg = 8'd0;
        jesd_gt_rxnotintable_seen_dbg = 8'd0;
        jesd_gt_rxcharisk_seen_dbg = 8'd0;
        jesd_gt_rxblock_sync_seen_dbg = 8'd0;
        jesd_gt_rxcommadet_seen_dbg = 8'd0;
        jesd_gt_rxdisperr_post_patch_seen_dbg = 8'd0;
        jesd_gt_rxnotintable_post_patch_seen_dbg = 8'd0;
        jesd_gt_rxcharisk_post_patch_seen_dbg = 8'd0;
        jesd_gt_rxblock_sync_post_patch_seen_dbg = 8'd0;
        jesd_gt_rxcommadet_post_patch_seen_dbg = 8'd0;
        jesd_gt_rxresetdone_rise_count = 16'd0;
        jesd_rx_tvalid_rise_count = 16'd0;
        jesd_rx_sync_toggle_count = 16'd0;
        jesd_rx_sync_rise_count = 8'd0;
        jesd_rx_sync_fall_count = 8'd0;
        jesd_rx_disperr_event_count = 16'd0;
        jesd_rx_notintable_event_count = 16'd0;
        adc_rx_diag_sync_q = 1'b0;
        adc_rx_diag_tvalid_q = 1'b0;
        adc_rx_diag_encommaalign_q = 1'b0;
        adc_rx_diag_aresetn_q = 1'b0;
        adc_rx_diag_reset_gt_q = 1'b0;
        adc_rx_diag_gt_disperr_q = 8'd0;
        adc_rx_diag_gt_notintable_q = 8'd0;
        adc_rx_diag_gt_rxbufstatus_nonzero_q = 8'd0;
        adc_rx_diag_sysref_count_q = 16'd0;
        adc_rx_first_good_seen = 1'b0;
        adc_rx_first_drop_seen = 1'b0;
        adc_rx_first_good_age_count = 32'd0;
        adc_rx_first_drop_age_count = 32'd0;
        adc_rx_first_good_sysref_count = 16'd0;
        adc_rx_first_drop_sysref_count = 16'd0;
        adc_rx_first_drop_cause = 8'd0;
        jesd_rx_first_good_dbg = 32'd0;
        jesd_rx_first_drop_dbg = 32'd0;
        jesd_rx_first_drop_age_dbg = 32'd0;
        jesd_rx_first_drop_sysref_dbg = 32'd0;
        jesd_rx_data_snapshot_dbg = 32'd0;
        jesd_rx_gt_octets01_dbg = 32'd0;
        jesd_rx_gt_octets23_dbg = 32'd0;
        jesd_rx_gt_octets45_dbg = 32'd0;
        jesd_rx_gt_octets67_dbg = 32'd0;
        adc_rx_rearm_inhibit = 1'b0;
        adc_rx_rearm_good_latched = 1'b0;
        adc_rx_rearm_limit_latched = 1'b0;
        adc_rx_rearm_reason_dbg = ADC_RX_REARM_REASON_NONE;
        adc_rx_rearm_count = 8'd0;
        adc_rx_rearm_wait_count = 32'd0;
        adc_rx_rearm_drop_count = 32'd0;
        adc_rx_rearm_reset_count = 32'd0;
        adc_rx_rearm_good_count = 32'd0;
        adc_rx_rearm_state = ADC_RX_REARM_ST_IDLE;
        adc_rx_link_reinit_count = 8'd0;
        adc_rx_link_reinit_done_latched = 1'b0;
        adc_rx_link_reinit_fail_latched = 1'b0;
        adc_rx_link_reinit_timeout_latched = 1'b0;
        adc_rx_core_reinit_pending = 1'b0;
        adc_rx_core_reinit_count = 8'd0;
        adc_rx_core_reinit_done_latched = 1'b0;
        adc_rx_gt_reset_req = 1'b0;
        adc_rx_gt_reset_count = 8'd0;
        adc_rx_gt_reset_done_latched = 1'b0;
        adc_rx_gt_reset_timeout_latched = 1'b0;
        adc_init_patch_dbg_q = 32'd0;
        adc_sync_loop_dbg_q = 32'd0;
        adc_rx_rearm_dbg_q = 32'd0;
    end

    always @(posedge sys_clk) begin
        start_hmc   <= 1'b0;
        start_dac   <= 1'b0;
        start_jesd0 <= 1'b0;
        start_jesd1 <= 1'b0;
        start_jesd_rx <= 1'b0;
        start_adc   <= 1'b0;
        adc_runtime_patch_start <= 1'b0;
        adc_runtime_link_reinit_start <= 1'b0;
        adc_init_patch_dbg_q <= adc_init_patch_dbg;
        adc_sync_loop_dbg_q <= adc_sync_loop_dbg;
        adc_rx_rearm_dbg_q <= adc_rx_rearm_dbg;
        if ((state == ST_RUN) &&
            adc_rx_first_good_seen &&
            !adc_rx_first_drop_seen &&
            (adc_rx_first_good_age_count != 32'hffffffff)) begin
            adc_rx_first_good_age_count <=
                adc_rx_first_good_age_count + 1'b1;
        end

        dac_sdo_d   <= dac_sdo;
        sysref2_d   <= sysref2_i;
        dac_sync0_d <= dac_sync0_i;
        dac_sync1_raw_d <= dac_sync1_raw_i;
        dac_sync1_d <= dac_sync1_i;
        jesd_refclk_mon_meta <= {jesd_refclk_mon_meta[0], jesd_refclk_mon_alive_raw};
        jesd_core_alive_meta <= {jesd_core_alive_meta[0], jesd_core_alive_raw};
        jesd_txoutclk_meta0 <= {jesd_txoutclk_meta0[0], jesd_txoutclk_alive_raw0};
        jesd_txoutclk_meta1 <= {jesd_txoutclk_meta1[0], jesd_txoutclk_alive_raw1};
        jesd_rx_tvalid_meta <= {jesd_rx_tvalid_meta[0], jesd_rx_tvalid};
        jesd_rx_sync_meta <= {jesd_rx_sync_meta[0], jesd_rx_sync};
        jesd_rx_aresetn_meta <= {jesd_rx_aresetn_meta[0], jesd_rx_aresetn};
        jesd_rx_reset_gt_meta <= {jesd_rx_reset_gt_meta[0], jesd_rx_reset_gt};
        jesd_rx_enable_meta <= {jesd_rx_enable_meta[0], jesd_rx_enable};
        jesd_rx_encommaalign_meta <= {
            jesd_rx_encommaalign_meta[0],
            jesd_rx_encommaalign
        };
        adc_sync_force_active_meta <= {
            adc_sync_force_active_meta[0],
            adc_sync_force_active_jclk
        };
        adc_sync_out_raw_meta <= {adc_sync_out_raw_meta[0], adc_sync_out_raw};
        adc_sync_out_meta <= {adc_sync_out_meta[0], adc_sync_out};
        adc_sync_follow_meta <= {adc_sync_follow_meta[0], adc_sync_follow_jclk};
        adc_sync_out_next_meta <= {
            adc_sync_out_next_meta[0],
            adc_sync_out_next_jclk
        };
        adc_sync_hold_locked_meta <= {
            adc_sync_hold_locked_meta[0],
            adc_sync_hold_locked_jclk
        };
        adc_sync_hold_active_meta <= {
            adc_sync_hold_active_meta[0],
            adc_sync_hold_active_jclk
        };
        adc_sync_hold_drop_seen_meta <= {
            adc_sync_hold_drop_seen_meta[0],
            adc_sync_hold_drop_seen_jclk
        };
        jesd_rx_sysref_gated_meta <= {
            jesd_rx_sysref_gated_meta[0],
            jesd_rx_sysref_gated_jclk
        };
        jesd_rx_sysref_gate_done_meta <= {
            jesd_rx_sysref_gate_done_meta[0],
            jesd_rx_sysref_gate_done_jclk
        };
        jesd_rx_sysref_pulse_count_meta0 <=
            jesd_rx_sysref_pulse_count_jclk;
        jesd_rx_sysref_pulse_count_meta1 <=
            jesd_rx_sysref_pulse_count_meta0;
        jesd_gt_rxresetdone_meta <= jesd_gt_rxresetdone;
        jesd_gt_rxresetdone_sync <= jesd_gt_rxresetdone_meta;
        jesd_gt_rxdisperr_meta <= jesd_gt_rxdisperr_any;
        jesd_gt_rxnotintable_meta <= jesd_gt_rxnotintable_any;
        jesd_gt_rxcharisk_meta <= jesd_gt_rxcharisk_any;
        jesd_gt_rxblock_sync_meta <= jesd_gt_rxblock_sync;
        jesd_gt_rxmisalign_meta <= jesd_gt_rxmisalign;
        jesd_gt_rxcommadet_meta <= jesd_gt_rxcommadet_current;
        jesd_gt_rxpmaresetdone_meta <= jesd_gt_rxpmaresetdone;
        jesd_gt_rxpmaresetdone_sync <= jesd_gt_rxpmaresetdone_meta;
        jesd_gt_rxbufstatus_meta <= jesd_gt_rxbufstatus;
        jesd_gt_rxbufstatus_sync <= jesd_gt_rxbufstatus_meta;
        jesd_gt_rxdisperr_seen_meta <= jesd_gt_rxdisperr_seen_jclk;
        jesd_gt_rxnotintable_seen_meta <= jesd_gt_rxnotintable_seen_jclk;
        jesd_gt_rxcharisk_seen_meta <= jesd_gt_rxcharisk_seen_jclk;
        jesd_gt_rxblock_sync_seen_meta <= jesd_gt_rxblock_sync_seen_jclk;
        jesd_gt_rxcommadet_seen_meta <= jesd_gt_rxcommadet_seen_jclk;
        tone_snapshot_toggle_meta <= {tone_snapshot_toggle_meta[1:0], tone_snapshot_toggle_jclk};
        jesd_rx_snapshot_toggle_meta <= {
            jesd_rx_snapshot_toggle_meta[1:0],
            jesd_rx_snapshot_toggle_jclk
        };
        refclk_mon_gray_meta <= refclk_mon_gray_src;
        refclk_mon_gray_sync <= refclk_mon_gray_meta;

        if (tone_snapshot_toggle_meta[2] ^ tone_snapshot_toggle_meta[1]) begin
            tone_dac0_pair01_dbg <= tone_dac0_pair01_jclk;
            tone_dac0_pair23_dbg <= tone_dac0_pair23_jclk;
            tone_dac1_pair01_dbg <= tone_dac1_pair01_jclk;
            tone_dac1_pair23_dbg <= tone_dac1_pair23_jclk;
            tone_snapshot_count_dbg <= tone_snapshot_count_dbg + 1'b1;
        end
        if (jesd_rx_snapshot_toggle_meta[2] ^ jesd_rx_snapshot_toggle_meta[1]) begin
            jesd_rx_data_snapshot_dbg <= jesd_rx_data_snapshot_jclk;
            jesd_rx_gt_octets01_dbg <= jesd_rx_gt_octets01_jclk;
            jesd_rx_gt_octets23_dbg <= jesd_rx_gt_octets23_jclk;
            jesd_rx_gt_octets45_dbg <= jesd_rx_gt_octets45_jclk;
            jesd_rx_gt_octets67_dbg <= jesd_rx_gt_octets67_jclk;
        end

        if (refclk_measure_count == (MS_TICKS - 1)) begin
            refclk_measure_count <= 18'd0;
            jesd_refclk_mon_cycles_1ms <= refclk_mon_count_sync - refclk_mon_count_prev;
            refclk_mon_count_prev <= refclk_mon_count_sync;
        end else begin
            refclk_measure_count <= refclk_measure_count + 1'b1;
        end

        if (sysref2_rise_sys) begin
            sysref_edge_count <= sysref_edge_count + 1'b1;
        end
        if (jesd_refclk_mon_dbg ^ jesd_refclk_mon_meta[1]) begin
            jesd_refclk_mon_edge_count <= jesd_refclk_mon_edge_count + 1'b1;
        end
        if (jesd_core_alive_dbg ^ jesd_core_alive_meta[1]) begin
            jesd_core_alive_edge_count <= jesd_core_alive_edge_count + 1'b1;
        end
        if (jesd_txoutclk_dbg0 ^ jesd_txoutclk_meta0[1]) begin
            jesd_txoutclk_edge_count0 <= jesd_txoutclk_edge_count0 + 1'b1;
        end
        if (jesd_txoutclk_dbg1 ^ jesd_txoutclk_meta1[1]) begin
            jesd_txoutclk_edge_count1 <= jesd_txoutclk_edge_count1 + 1'b1;
        end
        if (!dac_sync0_d && dac_sync0_i) begin
            dac_sync0_edge_count <= dac_sync0_edge_count + 1'b1;
        end
        if (!dac_sync1_d && dac_sync1_i) begin
            dac_sync1_edge_count <= dac_sync1_edge_count + 1'b1;
        end

        heartbeat <= heartbeat + 1'b1;
        jesd_refclk_mon_dbg <= jesd_refclk_mon_meta[1];
        jesd_core_alive_dbg <= jesd_core_alive_meta[1];
        jesd_txoutclk_dbg0 <= jesd_txoutclk_meta0[1];
        jesd_txoutclk_dbg1 <= jesd_txoutclk_meta1[1];

        jesd_busy_dbg <= {jesd_busy1, jesd_busy0};
        jesd_done_dbg <= {jesd_done1, jesd_done0};
        jesd_start_seen <= jesd_start_seen | {start_jesd1, start_jesd0};
        jesd_done_seen <= jesd_done_seen | {jesd_done1, jesd_done0};
        jesd_cfg_done_seen <= jesd_cfg_done_seen | jesd_cfg_done;
        jesd_release_seen <= jesd_release_seen | jesd_release;
        jesd_links_ready_seen <= jesd_links_ready_seen | jesd_links_ready;
        jesd_wait_reason_dbg <= jesd_wait_reason_next;
        jesd_fault_code_dbg <= jesd_fault_code_next;
        if ((state != ST_WAIT_JESD) || jesd_links_ready) begin
            jesd_wait_reason_latched <= JESD_WAIT_NONE;
            jesd_fault_code_latched <= JESD_FAULT_NONE;
        end else if ((jesd_wait_reason_latched == JESD_WAIT_NONE) &&
                     (jesd_wait_reason_next != JESD_WAIT_NONE)) begin
            jesd_wait_reason_latched <= jesd_wait_reason_next;
            jesd_fault_code_latched <= jesd_fault_code_next;
        end
        if (!jesd_release) begin
            if (jesd_release_ready) begin
                if (jesd_release_stable_count < JESD_RELEASE_STABLE_TICKS) begin
                    jesd_release_stable_count <= jesd_release_stable_count + 1'b1;
                end
            end else begin
                jesd_release_stable_count <= 32'd0;
            end
        end
        if (jesd_links_ready) begin
            if (jesd_links_ready_stable_count < JESD_READY_STABLE_TICKS) begin
                jesd_links_ready_stable_count <= jesd_links_ready_stable_count + 1'b1;
            end
            if (jesd_links_ready_stable_count >= (JESD_READY_STABLE_TICKS - 1)) begin
                jesd_links_ready_stable_seen <= 1'b1;
            end
        end else begin
            if (jesd_links_ready_stable_count != 32'd0) begin
                jesd_links_ready_drop_count <= jesd_links_ready_drop_count + 1'b1;
            end
            jesd_links_ready_stable_count <= 32'd0;
        end
        jesd_refclk_mon_seen <= jesd_refclk_mon_seen | jesd_refclk_mon_meta[1];
        jesd_core_alive_seen <= jesd_core_alive_seen | jesd_core_alive_meta[1];
        jesd_txoutclk_seen0 <= jesd_txoutclk_seen0 | jesd_txoutclk_meta0[1];
        jesd_txoutclk_seen1 <= jesd_txoutclk_seen1 | jesd_txoutclk_meta1[1];

        jesd_aresetn_meta       <= {jesd_tx_aresetn1, jesd_tx_aresetn0};
        jesd_tready_meta        <= {jesd_tx_ready1, jesd_tx_ready0};
        jesd_tx_reset_done_meta <= {jesd_tx_reset_done1, jesd_tx_reset_done0};
        jesd_gt_powergood_meta  <= {jesd_gt_powergood1, jesd_gt_powergood0};
        jesd_tx_reset_gt_meta   <= {jesd_tx_reset_gt1, jesd_tx_reset_gt0};
        jesd_gt_txresetdone_meta <= {jesd_gt_txresetdone1, jesd_gt_txresetdone0};
        jesd_cplllock_meta      <= {jesd_gt_cplllock1, jesd_gt_cplllock0};
        jesd_qpll_lock_meta     <= jesd_qpll_lock_raw;
        jesd_cplllock_seen      <= jesd_cplllock_seen | jesd_cplllock_meta;
        jesd_gt_txresetdone_seen <= jesd_gt_txresetdone_seen | jesd_gt_txresetdone_meta;
        jesd_qpll_lock_seen     <= jesd_qpll_lock_seen | jesd_qpll_lock_meta;
        if (|(jesd_cplllock_meta & ~jesd_cplllock_dbg)) begin
            jesd_cplllock_rise_count <= jesd_cplllock_rise_count + 1'b1;
        end
        if (|(jesd_gt_txresetdone_meta & ~jesd_gt_txresetdone_dbg)) begin
            jesd_gt_txresetdone_rise_count <= jesd_gt_txresetdone_rise_count + 1'b1;
        end
        if (|(jesd_qpll_lock_meta & ~jesd_qpll_lock_dbg)) begin
            jesd_qpll_lock_rise_count <= jesd_qpll_lock_rise_count + 1'b1;
        end
        if (|(jesd_gt_rxresetdone_meta & ~jesd_gt_rxresetdone_dbg)) begin
            jesd_gt_rxresetdone_rise_count <= jesd_gt_rxresetdone_rise_count + 1'b1;
        end
        if (jesd_rx_tvalid_meta[1] && !jesd_rx_tvalid_dbg) begin
            jesd_rx_tvalid_rise_count <= jesd_rx_tvalid_rise_count + 1'b1;
        end
        if (jesd_rx_sync_meta[1] ^ jesd_rx_sync_dbg) begin
            jesd_rx_sync_toggle_count <= jesd_rx_sync_toggle_count + 1'b1;
        end
        if (jesd_rx_sync_meta[1] && !jesd_rx_sync_dbg) begin
            jesd_rx_sync_rise_count <= jesd_rx_sync_rise_count + 1'b1;
        end
        if (!jesd_rx_sync_meta[1] && jesd_rx_sync_dbg) begin
            jesd_rx_sync_fall_count <= jesd_rx_sync_fall_count + 1'b1;
        end
        if (adc_runtime_patch_start) begin
            jesd_rx_sync_at_patch_start <= jesd_rx_sync_meta[1];
        end
        if (adc_runtime_patch_done) begin
            jesd_rx_sync_at_patch_done <= jesd_rx_sync_meta[1];
        end
        if (adc_runtime_patch_done) begin
            jesd_rx_disperr_event_count <= 16'd0;
            jesd_rx_notintable_event_count <= 16'd0;
            jesd_gt_rxdisperr_post_patch_seen_dbg <= 8'd0;
            jesd_gt_rxnotintable_post_patch_seen_dbg <= 8'd0;
            jesd_gt_rxcharisk_post_patch_seen_dbg <= 8'd0;
            jesd_gt_rxblock_sync_post_patch_seen_dbg <= 8'd0;
            jesd_gt_rxcommadet_post_patch_seen_dbg <= 8'd0;
        end else if (adc_runtime_patch_done_latched) begin
            if (|jesd_gt_rxdisperr_meta) begin
                jesd_rx_disperr_event_count <=
                    jesd_rx_disperr_event_count + 1'b1;
            end
            if (|jesd_gt_rxnotintable_meta) begin
                jesd_rx_notintable_event_count <=
                    jesd_rx_notintable_event_count + 1'b1;
            end
            jesd_gt_rxdisperr_post_patch_seen_dbg <=
                jesd_gt_rxdisperr_post_patch_seen_dbg |
                jesd_gt_rxdisperr_meta;
            jesd_gt_rxnotintable_post_patch_seen_dbg <=
                jesd_gt_rxnotintable_post_patch_seen_dbg |
                jesd_gt_rxnotintable_meta;
            jesd_gt_rxcharisk_post_patch_seen_dbg <=
                jesd_gt_rxcharisk_post_patch_seen_dbg |
                jesd_gt_rxcharisk_meta;
            jesd_gt_rxblock_sync_post_patch_seen_dbg <=
                jesd_gt_rxblock_sync_post_patch_seen_dbg |
                jesd_gt_rxblock_sync_meta;
            jesd_gt_rxcommadet_post_patch_seen_dbg <=
                jesd_gt_rxcommadet_post_patch_seen_dbg |
                jesd_gt_rxcommadet_meta;
        end

        adc_rx_diag_sync_q <= jesd_rx_sync_meta[1];
        adc_rx_diag_tvalid_q <= jesd_rx_tvalid_meta[1];
        adc_rx_diag_encommaalign_q <= jesd_rx_encommaalign_meta[1];
        adc_rx_diag_aresetn_q <= jesd_rx_aresetn_meta[1];
        adc_rx_diag_reset_gt_q <= jesd_rx_reset_gt_meta[1];
        adc_rx_diag_gt_disperr_q <= jesd_gt_rxdisperr_meta;
        adc_rx_diag_gt_notintable_q <= jesd_gt_rxnotintable_meta;
        adc_rx_diag_gt_rxbufstatus_nonzero_q <=
            jesd_gt_rxbufstatus_nonzero_sync;
        adc_rx_diag_sysref_count_q <= sysref_edge_count +
            (sysref2_rise_sys ? 16'd1 : 16'd0);

        if (!adc_rx_diag_base_ready || !adc_runtime_patch_done_latched) begin
            adc_rx_first_good_seen <= 1'b0;
            adc_rx_first_drop_seen <= 1'b0;
            adc_rx_first_good_age_count <= 32'd0;
            adc_rx_first_drop_age_count <= 32'd0;
            adc_rx_first_good_sysref_count <= 16'd0;
            adc_rx_first_drop_sysref_count <= 16'd0;
            adc_rx_first_drop_cause <= 8'd0;
            jesd_rx_first_good_dbg <= 32'd0;
            jesd_rx_first_drop_dbg <= 32'd0;
            jesd_rx_first_drop_age_dbg <= 32'd0;
            jesd_rx_first_drop_sysref_dbg <= 32'd0;
        end else if (!adc_rx_first_good_seen && adc_rx_diag_good_now) begin
            adc_rx_first_good_seen <= 1'b1;
            adc_rx_first_good_age_count <= 32'd0;
            adc_rx_first_good_sysref_count <= adc_rx_diag_sysref_count_q;
            jesd_rx_first_good_dbg <= {
                4'h4,
                adc_rx_diag_sync_q,
                adc_rx_diag_tvalid_q,
                adc_rx_diag_encommaalign_q,
                adc_rx_diag_aresetn_q,
                adc_rx_diag_reset_gt_q,
                adc_rx_diag_gt_rxbufstatus_nonzero_q != 8'd0,
                |adc_rx_diag_gt_notintable_q,
                |adc_rx_diag_gt_disperr_q,
                adc_rx_diag_sysref_count_q[7:0],
                jesd_rx_sync_rise_count[3:0],
                jesd_rx_sync_fall_count[3:0],
                jesd_rx_tvalid_rise_count[3:0]
            };
        end else if (adc_rx_first_good_seen &&
                     !adc_rx_first_drop_seen &&
                     adc_rx_diag_bad_now) begin
            adc_rx_first_drop_seen <= 1'b1;
            adc_rx_first_drop_age_count <= adc_rx_first_good_age_count;
            adc_rx_first_drop_sysref_count <= adc_rx_diag_sysref_count_q;
            adc_rx_first_drop_cause <= adc_rx_first_drop_cause_now;
            jesd_rx_first_drop_dbg <= {
                4'h5,
                adc_rx_diag_sync_q,
                adc_rx_diag_tvalid_q,
                adc_rx_diag_encommaalign_q,
                adc_rx_diag_aresetn_q,
                adc_rx_diag_reset_gt_q,
                adc_rx_diag_gt_rxbufstatus_nonzero_q != 8'd0,
                |adc_rx_diag_gt_notintable_q,
                |adc_rx_diag_gt_disperr_q,
                adc_rx_first_drop_cause_now,
                adc_rx_diag_sysref_count_q[7:0],
                jesd_rx_tvalid_rise_count[3:0]
            };
            jesd_rx_first_drop_age_dbg <= adc_rx_first_good_age_count;
            jesd_rx_first_drop_sysref_dbg <= {
                adc_rx_first_good_sysref_count,
                adc_rx_diag_sysref_count_q
            };
        end

        jesd_aresetn_dbg        <= jesd_aresetn_meta;
        jesd_tready_dbg         <= jesd_tready_meta;
        jesd_tx_reset_done_dbg  <= jesd_tx_reset_done_meta;
        jesd_gt_powergood_dbg   <= jesd_gt_powergood_meta;
        jesd_tx_reset_gt_dbg    <= jesd_tx_reset_gt_meta;
        jesd_gt_txresetdone_dbg <= jesd_gt_txresetdone_meta;
        jesd_cplllock_dbg       <= jesd_cplllock_meta;
        jesd_qpll_lock_dbg      <= jesd_qpll_lock_meta;
        jesd_rx_tvalid_dbg      <= jesd_rx_tvalid_meta[1];
        jesd_rx_tvalid_seen     <= jesd_rx_tvalid_seen | jesd_rx_tvalid_meta[1];
        jesd_rx_sync_dbg        <= jesd_rx_sync_meta[1];
        jesd_rx_sync_seen_low   <= jesd_rx_sync_seen_low |
                                   (jesd_rx_enable_meta[1] &&
                                    !jesd_rx_sync_meta[1]);
        jesd_rx_sync_seen_high  <= jesd_rx_sync_seen_high |
                                   (jesd_rx_enable_meta[1] &&
                                    jesd_rx_sync_meta[1]);
        jesd_rx_encommaalign_dbg <= jesd_rx_encommaalign_meta[1];
        jesd_rx_aresetn_dbg     <= jesd_rx_aresetn_meta[1];
        jesd_rx_reset_gt_dbg    <= jesd_rx_reset_gt_meta[1];
        jesd_rx_enable_dbg      <= jesd_rx_enable_meta[1];
        jesd_gt_rxresetdone_dbg <= jesd_gt_rxresetdone_meta;
        jesd_gt_rxresetdone_seen <= jesd_gt_rxresetdone_seen | jesd_gt_rxresetdone_meta;
        jesd_gt_rxdisperr_dbg   <= jesd_gt_rxdisperr_meta;
        jesd_gt_rxnotintable_dbg <= jesd_gt_rxnotintable_meta;
        jesd_gt_rxcharisk_dbg   <= jesd_gt_rxcharisk_meta;
        jesd_gt_rxblock_sync_dbg <= jesd_gt_rxblock_sync_meta;
        jesd_gt_rxmisalign_dbg  <= jesd_gt_rxmisalign_meta;
        jesd_gt_rxcommadet_dbg  <= jesd_gt_rxcommadet_meta;
        jesd_gt_rxpmaresetdone_dbg <= jesd_gt_rxpmaresetdone_sync;
        jesd_gt_rxbufstatus_dbg <= jesd_gt_rxbufstatus_sync;
        jesd_gt_rxdisperr_seen_dbg <= jesd_gt_rxdisperr_seen_meta;
        jesd_gt_rxnotintable_seen_dbg <= jesd_gt_rxnotintable_seen_meta;
        jesd_gt_rxcharisk_seen_dbg <= jesd_gt_rxcharisk_seen_meta;
        jesd_gt_rxblock_sync_seen_dbg <= jesd_gt_rxblock_sync_seen_meta;
        jesd_gt_rxcommadet_seen_dbg <= jesd_gt_rxcommadet_seen_meta;
        if (!jesd_rx_enable_meta[1]) begin
            jesd_rx_data_snapshot_dbg <= 32'd0;
            jesd_rx_gt_octets01_dbg <= 32'd0;
            jesd_rx_gt_octets23_dbg <= 32'd0;
            jesd_rx_gt_octets45_dbg <= 32'd0;
            jesd_rx_gt_octets67_dbg <= 32'd0;
            jesd_gt_rxdisperr_seen_dbg <= 8'd0;
            jesd_gt_rxnotintable_seen_dbg <= 8'd0;
            jesd_gt_rxcharisk_seen_dbg <= 8'd0;
            jesd_gt_rxblock_sync_seen_dbg <= 8'd0;
            jesd_gt_rxcommadet_seen_dbg <= 8'd0;
            jesd_gt_rxdisperr_post_patch_seen_dbg <= 8'd0;
            jesd_gt_rxnotintable_post_patch_seen_dbg <= 8'd0;
            jesd_gt_rxcharisk_post_patch_seen_dbg <= 8'd0;
            jesd_gt_rxblock_sync_post_patch_seen_dbg <= 8'd0;
            jesd_gt_rxcommadet_post_patch_seen_dbg <= 8'd0;
            jesd_gt_rxpmaresetdone_dbg <= 8'd0;
            jesd_gt_rxbufstatus_dbg <= 24'd0;
            jesd_rx_sync_seen_low <= 1'b0;
            jesd_rx_sync_seen_high <= 1'b0;
            jesd_rx_sync_at_patch_start <= 1'b0;
            jesd_rx_sync_at_patch_done <= 1'b0;
            jesd_rx_sync_rise_count <= 8'd0;
            jesd_rx_sync_fall_count <= 8'd0;
        end
        if (init_rst) begin
            hmc_ok_latched     <= 1'b0;
            hmc_fail_latched   <= 1'b0;
            hmc_status_latched <= 40'd0;
            adc_ok_latched     <= 1'b0;
            adc_fail_latched   <= 1'b0;
            adc_status_latched <= 16'd0;
            dac_ok_latched     <= 1'b0;
            dac_fail_latched   <= 1'b0;
            dac_status_latched <= 32'd0;
            dac_sanity_latched <= 32'd0;
            dac_debug_latched  <= 32'd0;
            jesd_release_seen  <= 1'b0;
            jesd_cfg_done_seen <= 1'b0;
            jesd_links_ready_seen <= 1'b0;
            jesd_links_ready_stable_seen <= 1'b0;
            jesd_release_stable_count <= 32'd0;
            jesd_links_ready_stable_count <= 32'd0;
            jesd_links_ready_drop_count <= 16'd0;
            jesd_pll_missing_count <= 32'd0;
            jesd_retry_reset_count <= 32'd0;
            jesd_retry_count <= 16'd0;
            jesd_start_seen    <= 2'b00;
            jesd_done_seen     <= 2'b00;
            jesd_refclk_mon_seen <= 1'b0;
            jesd_core_alive_seen <= 1'b0;
            jesd_txoutclk_seen0  <= 1'b0;
            jesd_txoutclk_seen1  <= 1'b0;
            jesd_wait_reason_dbg <= JESD_WAIT_NONE;
            jesd_wait_reason_latched <= JESD_WAIT_NONE;
            jesd_fault_code_dbg <= JESD_FAULT_NONE;
            jesd_fault_code_latched <= JESD_FAULT_NONE;
            adc_diag_bypass_taken <= 1'b0;
            adc_runtime_patch_requested <= 1'b0;
            adc_runtime_patch_done_latched <= 1'b0;
            adc_runtime_patch_fail_latched <= 1'b0;
            jesd_refclk_mon_cycles_1ms <= 32'd0;
            refclk_mon_count_prev <= refclk_mon_count_sync;
            refclk_measure_count <= 18'd0;
            jesd_cplllock_seen <= 8'd0;
            jesd_gt_txresetdone_seen <= 8'd0;
            jesd_cplllock_rise_count <= 16'd0;
            jesd_gt_txresetdone_rise_count <= 16'd0;
            jesd_qpll_lock_seen <= 4'd0;
            jesd_qpll_lock_rise_count <= 16'd0;
            jesd_rx_tvalid_seen <= 1'b0;
            jesd_rx_sync_seen_low <= 1'b0;
            jesd_rx_sync_seen_high <= 1'b0;
            jesd_rx_sync_at_patch_start <= 1'b0;
            jesd_rx_sync_at_patch_done <= 1'b0;
            jesd_rx_cfg_done_seen <= 1'b0;
            adc_runtime_patch_requested <= 1'b0;
            adc_runtime_patch_done_latched <= 1'b0;
            adc_runtime_patch_fail_latched <= 1'b0;
            jesd_gt_rxresetdone_sync <= 8'd0;
            jesd_gt_rxresetdone_seen <= 8'd0;
            jesd_gt_rxresetdone_rise_count <= 16'd0;
            jesd_rx_tvalid_rise_count <= 16'd0;
            jesd_rx_sync_toggle_count <= 16'd0;
            jesd_rx_sync_rise_count <= 8'd0;
            jesd_rx_sync_fall_count <= 8'd0;
            jesd_rx_disperr_event_count <= 16'd0;
            jesd_rx_notintable_event_count <= 16'd0;
            adc_rx_diag_sync_q <= 1'b0;
            adc_rx_diag_tvalid_q <= 1'b0;
            adc_rx_diag_encommaalign_q <= 1'b0;
            adc_rx_diag_aresetn_q <= 1'b0;
            adc_rx_diag_reset_gt_q <= 1'b0;
            adc_rx_diag_gt_disperr_q <= 8'd0;
            adc_rx_diag_gt_notintable_q <= 8'd0;
            adc_rx_diag_gt_rxbufstatus_nonzero_q <= 8'd0;
            adc_rx_diag_sysref_count_q <= 16'd0;
            adc_rx_first_good_seen <= 1'b0;
            adc_rx_first_drop_seen <= 1'b0;
            adc_rx_first_good_age_count <= 32'd0;
            adc_rx_first_drop_age_count <= 32'd0;
            adc_rx_first_good_sysref_count <= 16'd0;
            adc_rx_first_drop_sysref_count <= 16'd0;
            adc_rx_first_drop_cause <= 8'd0;
            jesd_rx_first_good_dbg <= 32'd0;
            jesd_rx_first_drop_dbg <= 32'd0;
            jesd_rx_first_drop_age_dbg <= 32'd0;
            jesd_rx_first_drop_sysref_dbg <= 32'd0;
            jesd_rx_data_snapshot_dbg <= 32'd0;
            jesd_rx_gt_octets01_dbg <= 32'd0;
            jesd_rx_gt_octets23_dbg <= 32'd0;
            jesd_rx_gt_octets45_dbg <= 32'd0;
            jesd_rx_gt_octets67_dbg <= 32'd0;
            jesd_gt_rxdisperr_seen_dbg <= 8'd0;
            jesd_gt_rxnotintable_seen_dbg <= 8'd0;
            jesd_gt_rxcharisk_seen_dbg <= 8'd0;
            jesd_gt_rxblock_sync_seen_dbg <= 8'd0;
            jesd_gt_rxcommadet_seen_dbg <= 8'd0;
            jesd_gt_rxdisperr_post_patch_seen_dbg <= 8'd0;
            jesd_gt_rxnotintable_post_patch_seen_dbg <= 8'd0;
            jesd_gt_rxcharisk_post_patch_seen_dbg <= 8'd0;
            jesd_gt_rxblock_sync_post_patch_seen_dbg <= 8'd0;
            jesd_gt_rxcommadet_post_patch_seen_dbg <= 8'd0;
            adc_rx_rearm_inhibit <= 1'b0;
            adc_rx_rearm_good_latched <= 1'b0;
            adc_rx_rearm_limit_latched <= 1'b0;
            adc_rx_rearm_reason_dbg <= ADC_RX_REARM_REASON_NONE;
            adc_rx_rearm_count <= 8'd0;
            adc_rx_rearm_wait_count <= 32'd0;
            adc_rx_rearm_drop_count <= 32'd0;
            adc_rx_rearm_reset_count <= 32'd0;
            adc_rx_rearm_good_count <= 32'd0;
            adc_rx_rearm_state <= ADC_RX_REARM_ST_IDLE;
            adc_rx_link_reinit_count <= 8'd0;
            adc_rx_link_reinit_done_latched <= 1'b0;
            adc_rx_link_reinit_fail_latched <= 1'b0;
            adc_rx_link_reinit_timeout_latched <= 1'b0;
            adc_rx_core_reinit_pending <= 1'b0;
            adc_rx_core_reinit_count <= 8'd0;
            adc_rx_core_reinit_done_latched <= 1'b0;
            adc_rx_gt_reset_req <= 1'b0;
            adc_rx_gt_reset_count <= 8'd0;
            adc_rx_gt_reset_done_latched <= 1'b0;
            adc_rx_gt_reset_timeout_latched <= 1'b0;
            adc_init_patch_dbg_q <= 32'd0;
            adc_sync_loop_dbg_q <= 32'd0;
            adc_rx_rearm_dbg_q <= 32'd0;
        end else if (hmc_done) begin
            hmc_ok_latched     <= hmc_ok;
            hmc_fail_latched   <= hmc_fail;
            hmc_status_latched <= hmc_status_dbg;
        end else if (dac_done) begin
            dac_ok_latched     <= dac_init_ok;
            dac_fail_latched   <= dac_init_fail;
            dac_status_latched <= dac_init_status_dbg;
            dac_sanity_latched <= dac_init_sanity_dbg;
            dac_debug_latched  <= dac_init_debug_dbg;
        end else if (adc_done) begin
            adc_ok_latched     <= adc_init_ok;
            adc_fail_latched   <= adc_init_fail;
            adc_status_latched <= adc_init_status_dbg;
        end

        case (state)
            ST_BOOT: begin
                resetb         <= 1'b0;
                txen_0         <= 1'b0;
                txen_1         <= 1'b0;
                adc_pdwn       <= 1'b1;
                adc_sync_drive <= 1'b0;
                jesd_release   <= 1'b0;
                if (boot_count == BOOT_WAIT_TICKS - 1) begin
                    boot_count <= 32'd0;
                    state      <= ST_START_HMC;
                end else begin
                    boot_count <= boot_count + 1'b1;
                end
            end

            ST_START_HMC: begin
                start_hmc <= 1'b1;
                state     <= ST_WAIT_HMC;
            end

            ST_WAIT_HMC: begin
                if (hmc_done && hmc_ok) begin
                    resetb     <= 1'b1;
                    hold_count <= 32'd0;
                    state      <= ST_HOLD_DAC;
                end
            end

            ST_HOLD_DAC: begin
                if (hold_count == HOLD_WAIT_TICKS - 1) begin
                    hold_count <= 32'd0;
                    state      <= ST_START_DAC;
                end else begin
                    hold_count <= hold_count + 1'b1;
                end
            end

            ST_START_DAC: begin
                start_dac <= 1'b1;
                state     <= ST_WAIT_DAC;
            end

            ST_WAIT_DAC: begin
                if (dac_done && dac_init_ok) begin
                    txen_0 <= 1'b1;
                    txen_1 <= 1'b1;
                    state  <= ST_START_JESD;
                end
            end

            ST_START_JESD: begin
                start_jesd0 <= 1'b1;
                start_jesd1 <= 1'b1;
                state       <= ST_WAIT_JESD;
            end

            ST_WAIT_JESD: begin
                if (jesd_retry_reset_count != 32'd0) begin
                    jesd_release <= 1'b0;
                    jesd_release_stable_count <= 32'd0;
                    jesd_pll_missing_count <= 32'd0;
                    if (jesd_retry_reset_count < JESD_RETRY_RESET_TICKS) begin
                        jesd_retry_reset_count <= jesd_retry_reset_count + 1'b1;
                    end else begin
                        jesd_retry_reset_count <= 32'd0;
                    end
                end else if (jesd_release) begin
                    if (jesd_links_ready || jesd_pll_ready_dbg) begin
                        jesd_pll_missing_count <= 32'd0;
                    end else if (jesd_pll_missing_count < JESD_RETRY_MISSING_TICKS) begin
                        jesd_pll_missing_count <= jesd_pll_missing_count + 1'b1;
                    end else begin
                        jesd_release <= 1'b0;
                        jesd_release_stable_count <= 32'd0;
                        jesd_pll_missing_count <= 32'd0;
                        jesd_retry_reset_count <= 32'd1;
                        jesd_retry_count <= jesd_retry_count + 1'b1;
                    end
                end else if (jesd_release_stable_count >= JESD_RELEASE_STABLE_TICKS) begin
                    jesd_release <= 1'b1;
                end
                if (adc_start_gate_ready) begin
                    hold_count <= 32'd0;
                    if (adc_diag_bypass_ready &&
                        (jesd_links_ready_stable_count < JESD_READY_STABLE_TICKS)) begin
                        adc_diag_bypass_taken <= 1'b1;
                    end
                    if (ENABLE_AD6688_INIT != 0) begin
                        adc_pdwn <= 1'b0;
                        state    <= ST_HOLD_ADC;
                    end else begin
                        adc_pdwn <= 1'b1;
                        state    <= ST_RUN;
                    end
                end
            end

            ST_HOLD_ADC: begin
                if (hold_count == ADC_HOLD_WAIT_TICKS - 1) begin
                    hold_count <= 32'd0;
                    state      <= ST_START_ADC;
                end else begin
                    hold_count <= hold_count + 1'b1;
                end
            end

            ST_START_ADC: begin
                start_adc <= 1'b1;
                if (adc_busy) begin
                    hold_count <= 32'd0;
                    state      <= ST_WAIT_ADC;
                end else if (hold_count >= (ADC_START_TIMEOUT_TICKS - 1)) begin
                    start_adc          <= 1'b0;
                    hold_count         <= 32'd0;
                    adc_fail_latched   <= 1'b1;
                    adc_status_latched <= 16'hf001;
                    state              <= ST_ADC_FAIL;
                end else begin
                    hold_count <= hold_count + 1'b1;
                end
            end

            ST_WAIT_ADC: begin
                if (adc_done && adc_init_ok) begin
                    hold_count <= 32'd0;
                    state      <= ST_START_RX;
                end else if (adc_done && adc_init_fail) begin
                    hold_count <= 32'd0;
                    state      <= ST_ADC_FAIL;
                end else if (hold_count >= (ADC_INIT_TIMEOUT_TICKS - 1)) begin
                    hold_count         <= 32'd0;
                    adc_fail_latched   <= 1'b1;
                    adc_status_latched <= 16'hf002;
                    state              <= ST_ADC_FAIL;
                end else begin
                    hold_count <= hold_count + 1'b1;
                end
            end

            ST_START_RX: begin
                start_jesd_rx <= 1'b1;
                state         <= ST_WAIT_RX;
            end

            ST_WAIT_RX: begin
                adc_sync_drive <= 1'b0;
                if (jesd_rx_done) begin
                    jesd_rx_cfg_done_seen <= 1'b1;
                    hold_count <= 32'd0;
                    state <= ST_RX_ALIGN_WAIT;
                end
            end

            ST_RX_ALIGN_WAIT: begin
                adc_sync_drive <= 1'b0;
                if (adc_runtime_patch_done) begin
                    adc_runtime_patch_done_latched <= 1'b1;
                    adc_runtime_patch_fail_latched <= adc_runtime_patch_fail;
                    hold_count <= 32'd0;
                    state <= ST_RUN;
                end else if (adc_runtime_patch_requested) begin
                    if (hold_count >= (ADC_RUNTIME_PATCH_TIMEOUT_TICKS - 1)) begin
                        adc_runtime_patch_fail_latched <= 1'b1;
                        hold_count <= 32'd0;
                        state <= ST_RUN;
                    end else begin
                        hold_count <= hold_count + 1'b1;
                    end
                end else if (!jesd_rx_release_ready_sys) begin
                    hold_count <= 32'd0;
                end else if (hold_count >= (ADC_CGS_ALIGN_WAIT_TICKS - 1)) begin
                    hold_count <= 32'd0;
                    adc_runtime_patch_requested <= 1'b1;
                    adc_runtime_patch_start <= 1'b1;
                end else begin
                    hold_count <= hold_count + 1'b1;
                end
            end

            ST_RUN: begin
                adc_sync_drive <= 1'b0;
                if (!ADC_RX_REARM_ENABLE_BIT ||
                    !adc_runtime_patch_done_latched ||
                    adc_runtime_patch_fail_latched) begin
                    adc_rx_rearm_inhibit <= 1'b0;
                    adc_rx_rearm_wait_count <= 32'd0;
                    adc_rx_rearm_drop_count <= 32'd0;
                    adc_rx_rearm_reset_count <= 32'd0;
                    adc_rx_rearm_good_count <= 32'd0;
                    adc_rx_rearm_state <= ADC_RX_REARM_ST_IDLE;
                    adc_rx_core_reinit_pending <= 1'b0;
                    adc_rx_gt_reset_req <= 1'b0;
                end else if (adc_rx_rearm_limit_latched) begin
                    adc_rx_rearm_inhibit <= 1'b0;
                    adc_rx_rearm_wait_count <= 32'd0;
                    adc_rx_rearm_drop_count <= 32'd0;
                    adc_rx_rearm_reset_count <= 32'd0;
                    adc_rx_rearm_good_count <= 32'd0;
                    adc_rx_rearm_state <= ADC_RX_REARM_ST_IDLE;
                    adc_rx_core_reinit_pending <= 1'b0;
                    adc_rx_gt_reset_req <= 1'b0;
                    if (!jesd_rx_cfg_done_seen && !jesd_rx_busy) begin
                        jesd_rx_cfg_done_seen <= 1'b1;
                    end
                end else if (adc_rx_rearm_state == ADC_RX_REARM_ST_RX_RESET) begin
                    adc_rx_rearm_wait_count <= 32'd0;
                    adc_rx_rearm_drop_count <= 32'd0;
                    adc_rx_rearm_good_count <= 32'd0;
                    adc_rx_gt_reset_req <= 1'b0;
                    if (adc_rx_rearm_reset_count >=
                        (ADC_RX_REARM_RESET_TICKS - 1)) begin
                        if (!jesd_rx_busy) begin
                            start_jesd_rx <= 1'b1;
                            adc_rx_rearm_reset_count <= 32'd0;
                            adc_rx_rearm_state <=
                                ADC_RX_REARM_ST_CORE_REINIT;
                        end
                    end else begin
                        adc_rx_rearm_reset_count <=
                            adc_rx_rearm_reset_count + 1'b1;
                    end
                end else if (adc_rx_rearm_state ==
                             ADC_RX_REARM_ST_LINK_RESET) begin
                    adc_rx_rearm_wait_count <= 32'd0;
                    adc_rx_rearm_drop_count <= 32'd0;
                    adc_rx_rearm_good_count <= 32'd0;
                    adc_rx_gt_reset_req <= 1'b0;
                    if (adc_rx_rearm_reset_count >=
                        (ADC_RX_REARM_RESET_TICKS - 1)) begin
                        adc_rx_rearm_reset_count <= 32'd0;
                        adc_runtime_link_reinit_start <= 1'b1;
                        adc_rx_link_reinit_count <=
                            adc_rx_link_reinit_count + 1'b1;
                        adc_rx_rearm_state <= ADC_RX_REARM_ST_LINK_WAIT;
                    end else begin
                        adc_rx_rearm_reset_count <=
                            adc_rx_rearm_reset_count + 1'b1;
                    end
                end else if (adc_rx_rearm_state ==
                             ADC_RX_REARM_ST_LINK_WAIT) begin
                    adc_rx_rearm_wait_count <= 32'd0;
                    adc_rx_rearm_drop_count <= 32'd0;
                    adc_rx_rearm_good_count <= 32'd0;
                    adc_rx_gt_reset_req <= 1'b0;
                    if (adc_runtime_link_reinit_done) begin
                        adc_rx_link_reinit_done_latched <= 1'b1;
                        adc_rx_link_reinit_fail_latched <=
                            adc_runtime_link_reinit_fail;
                        adc_rx_rearm_reset_count <= 32'd0;
                        if (adc_runtime_link_reinit_fail) begin
                            adc_rx_rearm_limit_latched <= 1'b1;
                            adc_rx_rearm_reason_dbg <=
                                ADC_RX_REARM_REASON_LINK_FAIL;
                            adc_rx_core_reinit_pending <= 1'b0;
                            adc_rx_rearm_state <= ADC_RX_REARM_ST_IDLE;
                        end else begin
                            if (ADC_RX_GT_RESET_ENABLE_BIT) begin
                                adc_rx_rearm_state <=
                                    ADC_RX_REARM_ST_GT_RESET;
                            end else begin
                                adc_rx_rearm_state <=
                                    ADC_RX_REARM_ST_LINK_SETTLE;
                            end
                        end
                    end else if (adc_rx_rearm_reset_count >=
                                 (ADC_RX_LINK_REINIT_TIMEOUT_TICKS - 1)) begin
                        adc_rx_link_reinit_timeout_latched <= 1'b1;
                        adc_rx_rearm_limit_latched <= 1'b1;
                        adc_rx_rearm_reason_dbg <=
                            ADC_RX_REARM_REASON_LINK_TIMEOUT;
                        adc_rx_core_reinit_pending <= 1'b0;
                        adc_rx_rearm_state <= ADC_RX_REARM_ST_IDLE;
                    end else begin
                        adc_rx_rearm_reset_count <=
                            adc_rx_rearm_reset_count + 1'b1;
                    end
                end else if (adc_rx_rearm_state ==
                             ADC_RX_REARM_ST_GT_RESET) begin
                    adc_rx_rearm_wait_count <= 32'd0;
                    adc_rx_rearm_drop_count <= 32'd0;
                    adc_rx_rearm_good_count <= 32'd0;
                    adc_rx_gt_reset_req <= 1'b1;
                    if (adc_rx_rearm_reset_count >=
                        (ADC_RX_GT_RESET_TICKS - 1)) begin
                        adc_rx_gt_reset_req <= 1'b0;
                        adc_rx_rearm_reset_count <= 32'd0;
                        adc_rx_rearm_state <= ADC_RX_REARM_ST_GT_WAIT;
                    end else begin
                        adc_rx_rearm_reset_count <=
                            adc_rx_rearm_reset_count + 1'b1;
                    end
                end else if (adc_rx_rearm_state ==
                             ADC_RX_REARM_ST_GT_WAIT) begin
                    adc_rx_rearm_wait_count <= 32'd0;
                    adc_rx_rearm_drop_count <= 32'd0;
                    adc_rx_rearm_good_count <= 32'd0;
                    adc_rx_gt_reset_req <= 1'b0;
                    if (adc_rx_gt_reset_ready) begin
                        adc_rx_gt_reset_count <= adc_rx_gt_reset_count + 1'b1;
                        adc_rx_gt_reset_done_latched <= 1'b1;
                        adc_rx_rearm_reset_count <= 32'd0;
                        adc_rx_rearm_state <= ADC_RX_REARM_ST_LINK_SETTLE;
                    end else if (adc_rx_rearm_reset_count >=
                                 (ADC_RX_GT_WAIT_TIMEOUT_TICKS - 1)) begin
                        adc_rx_gt_reset_timeout_latched <= 1'b1;
                        adc_rx_rearm_limit_latched <= 1'b1;
                        adc_rx_rearm_reason_dbg <=
                            ADC_RX_REARM_REASON_GT_TIMEOUT;
                        adc_rx_core_reinit_pending <= 1'b0;
                        adc_rx_rearm_reset_count <= 32'd0;
                        adc_rx_rearm_state <= ADC_RX_REARM_ST_IDLE;
                    end else begin
                        adc_rx_rearm_reset_count <=
                            adc_rx_rearm_reset_count + 1'b1;
                    end
                end else if (adc_rx_rearm_state ==
                             ADC_RX_REARM_ST_LINK_SETTLE) begin
                    adc_rx_rearm_wait_count <= 32'd0;
                    adc_rx_rearm_drop_count <= 32'd0;
                    adc_rx_rearm_good_count <= 32'd0;
                    adc_rx_gt_reset_req <= 1'b0;
                    if (adc_rx_rearm_reset_count >=
                        (ADC_RX_LINK_REINIT_SETTLE_TICKS - 1)) begin
                        if (!jesd_rx_busy) begin
                            start_jesd_rx <= 1'b1;
                            adc_rx_rearm_reset_count <= 32'd0;
                            adc_rx_rearm_state <=
                                ADC_RX_REARM_ST_CORE_REINIT;
                        end
                    end else begin
                        adc_rx_rearm_reset_count <=
                            adc_rx_rearm_reset_count + 1'b1;
                    end
                end else if (adc_rx_rearm_state ==
                             ADC_RX_REARM_ST_CORE_REINIT) begin
                    adc_rx_rearm_wait_count <= 32'd0;
                    adc_rx_rearm_drop_count <= 32'd0;
                    adc_rx_rearm_good_count <= 32'd0;
                    adc_rx_gt_reset_req <= 1'b0;
                    if (jesd_rx_done) begin
                        jesd_rx_cfg_done_seen <= 1'b1;
                        adc_rx_core_reinit_pending <= 1'b0;
                        adc_rx_core_reinit_count <=
                            adc_rx_core_reinit_count + 1'b1;
                        adc_rx_core_reinit_done_latched <= 1'b1;
                        adc_rx_rearm_inhibit <= 1'b0;
                        adc_rx_rearm_reset_count <= 32'd0;
                        adc_rx_rearm_state <= ADC_RX_REARM_ST_IDLE;
                    end else if (adc_rx_rearm_reset_count >=
                                 (ADC_RX_CORE_REINIT_TIMEOUT_TICKS - 1)) begin
                        adc_rx_core_reinit_pending <= 1'b0;
                        adc_rx_rearm_limit_latched <= 1'b1;
                        adc_rx_rearm_reason_dbg <=
                            ADC_RX_REARM_REASON_CORE_TIMEOUT;
                        adc_rx_rearm_reset_count <= 32'd0;
                        adc_rx_rearm_state <= ADC_RX_REARM_ST_IDLE;
                    end else begin
                        adc_rx_rearm_reset_count <=
                            adc_rx_rearm_reset_count + 1'b1;
                    end
                end else if (adc_rx_rearm_good_now) begin
                    adc_rx_rearm_wait_count <= 32'd0;
                    adc_rx_rearm_drop_count <= 32'd0;
                    adc_rx_rearm_reset_count <= 32'd0;
                    if (adc_rx_rearm_good_count >=
                        (ADC_RX_REARM_GOOD_STABLE_TICKS - 1)) begin
                        adc_rx_rearm_good_latched <= 1'b1;
                        adc_rx_rearm_reason_dbg <= ADC_RX_REARM_REASON_NONE;
                    end else begin
                        adc_rx_rearm_good_count <=
                            adc_rx_rearm_good_count + 1'b1;
                    end
                end else if (adc_rx_rearm_monitor_ready) begin
                    adc_rx_rearm_good_count <= 32'd0;
                    adc_rx_rearm_reset_count <= 32'd0;
                    if (!adc_rx_rearm_good_latched) begin
                        adc_rx_rearm_drop_count <= 32'd0;
                        if (adc_rx_rearm_wait_count >=
                            (ADC_RX_REARM_LOCK_TIMEOUT_TICKS - 1)) begin
                            if (!ADC_RX_AUTO_REINIT_ENABLE_BIT) begin
                                adc_rx_rearm_limit_latched <= 1'b1;
                                adc_rx_rearm_reason_dbg <=
                                    ADC_RX_REARM_REASON_LOCK_TIMEOUT;
                                adc_rx_rearm_wait_count <= 32'd0;
                                adc_rx_rearm_state <= ADC_RX_REARM_ST_IDLE;
                            end else if (adc_rx_rearm_count < ADC_RX_REARM_MAX_COUNT) begin
                                adc_rx_rearm_inhibit <= 1'b1;
                                adc_rx_rearm_good_latched <= 1'b0;
                                jesd_rx_cfg_done_seen <= 1'b0;
                                adc_rx_core_reinit_pending <= 1'b1;
                                adc_rx_core_reinit_done_latched <= 1'b0;
                                adc_rx_gt_reset_req <= 1'b0;
                                adc_rx_gt_reset_done_latched <= 1'b0;
                                adc_rx_gt_reset_timeout_latched <= 1'b0;
                                adc_rx_rearm_count <= adc_rx_rearm_count + 1'b1;
                                adc_rx_rearm_reason_dbg <=
                                    ADC_RX_REARM_REASON_LOCK_TIMEOUT;
                                adc_rx_rearm_wait_count <= 32'd0;
                                if (ADC_RX_LINK_REINIT_ENABLE_BIT &&
                                    (adc_rx_rearm_count >=
                                     ADC_RX_REARM_LINK_REINIT_THRESHOLD)) begin
                                    adc_rx_rearm_state <=
                                        ADC_RX_REARM_ST_LINK_RESET;
                                end else begin
                                    adc_rx_rearm_state <=
                                        ADC_RX_REARM_ST_RX_RESET;
                                end
                            end else begin
                                adc_rx_rearm_limit_latched <= 1'b1;
                                adc_rx_rearm_reason_dbg <=
                                    ADC_RX_REARM_REASON_RETRY_LIMIT;
                            end
                        end else begin
                            adc_rx_rearm_wait_count <=
                                adc_rx_rearm_wait_count + 1'b1;
                        end
                    end else begin
                        adc_rx_rearm_wait_count <= 32'd0;
                        if (adc_rx_rearm_drop_count >=
                            (ADC_RX_REARM_DROP_TIMEOUT_TICKS - 1)) begin
                            if (!ADC_RX_AUTO_REINIT_ENABLE_BIT) begin
                                adc_rx_rearm_limit_latched <= 1'b1;
                                adc_rx_rearm_reason_dbg <=
                                    ADC_RX_REARM_REASON_RUN_DROP;
                                adc_rx_rearm_drop_count <= 32'd0;
                                adc_rx_rearm_state <= ADC_RX_REARM_ST_IDLE;
                            end else if (adc_rx_rearm_count < ADC_RX_REARM_MAX_COUNT) begin
                                adc_rx_rearm_inhibit <= 1'b1;
                                adc_rx_rearm_good_latched <= 1'b0;
                                jesd_rx_cfg_done_seen <= 1'b0;
                                adc_rx_core_reinit_pending <= 1'b1;
                                adc_rx_core_reinit_done_latched <= 1'b0;
                                adc_rx_gt_reset_req <= 1'b0;
                                adc_rx_gt_reset_done_latched <= 1'b0;
                                adc_rx_gt_reset_timeout_latched <= 1'b0;
                                adc_rx_rearm_count <= adc_rx_rearm_count + 1'b1;
                                adc_rx_rearm_reason_dbg <=
                                    ADC_RX_REARM_REASON_RUN_DROP;
                                adc_rx_rearm_drop_count <= 32'd0;
                                if (ADC_RX_LINK_REINIT_ENABLE_BIT &&
                                    (adc_rx_rearm_count >=
                                     ADC_RX_REARM_LINK_REINIT_THRESHOLD)) begin
                                    adc_rx_rearm_state <=
                                        ADC_RX_REARM_ST_LINK_RESET;
                                end else begin
                                    adc_rx_rearm_state <=
                                        ADC_RX_REARM_ST_RX_RESET;
                                end
                            end else begin
                                adc_rx_rearm_limit_latched <= 1'b1;
                                adc_rx_rearm_reason_dbg <=
                                    ADC_RX_REARM_REASON_RETRY_LIMIT;
                            end
                        end else begin
                            adc_rx_rearm_drop_count <=
                                adc_rx_rearm_drop_count + 1'b1;
                        end
                    end
                end else begin
                    adc_rx_rearm_wait_count <= 32'd0;
                    adc_rx_rearm_drop_count <= 32'd0;
                    adc_rx_rearm_good_count <= 32'd0;
                    adc_rx_rearm_reset_count <= 32'd0;
                    adc_rx_rearm_state <= ADC_RX_REARM_ST_IDLE;
                    adc_rx_gt_reset_req <= 1'b0;
                end
            end

            ST_ADC_FAIL: begin
                adc_sync_drive <= 1'b0;
            end

            default: begin
                state <= ST_BOOT;
            end
        endcase
    end

endmodule
