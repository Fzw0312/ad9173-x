`timescale 1ns/1ps

module ad6688_lane_reorder (
    input  wire [255:0] physical_tdata,
    output wire [255:0] logical_tdata
);
    assign logical_tdata = 256'd0;
endmodule

module adc0_sample_packer #(
    parameter integer ADC_INDEX = 0,
    parameter integer COMPONENT_SELECT = 0
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         link_good,
    input  wire         jesd_valid,
    input  wire [255:0] jesd_data,
    output wire         sample_valid,
    output wire [63:0]  sample_data,
    output wire [31:0]  beat_count,
    output wire [15:0]  first_sample_dbg
);
    assign sample_valid = 1'b0;
    assign sample_data = 64'd0;
    assign beat_count = 32'd0;
    assign first_sample_dbg = 16'd0;
endmodule

module adc_capture_ddr64_model #(
    parameter integer ADDR_WIDTH = 11,
    parameter integer READ_LATENCY = 6,
    parameter integer READY_STALL_PERIOD = 0,
    parameter integer READY_STALL_CYCLES = 0
) (
    input  wire                  wr_clk,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [63:0]           wr_data,
    input  wire                  rd_clk,
    input  wire                  rd_rst,
    input  wire                  rd_req,
    output wire                  rd_ready,
    input  wire [ADDR_WIDTH+2:0] rd_byte_addr,
    output wire                  rd_valid,
    output wire [7:0]            rd_byte
);
    assign rd_ready = 1'b1;
    assign rd_valid = 1'b0;
    assign rd_byte = 8'd0;
endmodule

module adc_udp_capture_ctrl #(
    parameter integer CAPTURE_BEATS = 2048,
    parameter integer CAPTURE_ADDR_W = 11,
    parameter integer REPEAT_TICKS = 49_152_000,
    parameter integer LINK_GOOD_TICKS = 1_228_800,
    parameter integer SAMPLE_GAP_TICKS = 1
) (
    input  wire                      jclk,
    input  wire                      jrst,
    input  wire                      eth_clk,
    input  wire                      eth_rst,
    input  wire                      enable,
    input  wire                      eth_ready_async,
    input  wire                      link_good,
    input  wire                      sample_valid,
    output wire                      capture_active,
    output wire                      wait_pkt_done,
    output wire                      pkt_done_seen,
    output wire [CAPTURE_ADDR_W-1:0] wr_addr,
    output wire [31:0]               capture_id,
    output wire [31:0]               capture_count,
    output wire [31:0]               drop_count,
    output wire [31:0]               good_window_count,
    output wire [31:0]               capture_good_count,
    output wire [31:0]               repeat_count,
    input  wire                      pkt_busy,
    input  wire                      pkt_done,
    output wire                      pkt_start,
    output wire [31:0]               pkt_capture_id
);
    assign capture_active = 1'b0;
    assign wait_pkt_done = 1'b0;
    assign pkt_done_seen = 1'b0;
    assign wr_addr = {CAPTURE_ADDR_W{1'b0}};
    assign capture_id = 32'd0;
    assign capture_count = 32'd0;
    assign drop_count = 32'd0;
    assign good_window_count = 32'd0;
    assign capture_good_count = 32'd0;
    assign repeat_count = 32'd0;
    assign pkt_start = 1'b0;
    assign pkt_capture_id = 32'd0;
endmodule

module k5ad_udp_packetizer_ddr #(
    parameter integer CAPTURE_BEATS = 2048,
    parameter integer DATA_PAYLOAD_SAMPLES = 512,
    parameter [47:0]  SRC_MAC = 48'h02_00_00_00_5a_01,
    parameter [31:0]  SRC_IP = 32'hC0A8_010A,
    parameter [15:0]  SRC_PORT = 16'd6006,
    parameter [15:0]  DST_PORT = 16'd6006
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [31:0] capture_id,
    output wire        ram_rd_req,
    input  wire        ram_rd_ready,
    input  wire        ram_rd_valid,
    input  wire [7:0]  ram_rd_byte,
    output wire [13:0] ram_rd_byte_addr,
    output wire        busy,
    output wire        done,
    output wire [31:0] packet_count,
    output wire [7:0]  tx_data,
    output wire        tx_valid,
    output wire [31:0] prefetch_count
);
    assign ram_rd_req = 1'b0;
    assign ram_rd_byte_addr = 14'd0;
    assign busy = 1'b0;
    assign done = 1'b0;
    assign packet_count = 32'd0;
    assign tx_data = 8'd0;
    assign tx_valid = 1'b0;
    assign prefetch_count = 32'd0;
endmodule

module jesd204_rx_init #(
    parameter integer MS_TICKS = 100000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    output wire        busy,
    output wire        done,
    output wire [11:0] s_axi_awaddr,
    output wire        s_axi_awvalid,
    input  wire        s_axi_awready,
    output wire [31:0] s_axi_wdata,
    output wire [3:0]  s_axi_wstrb,
    output wire        s_axi_wvalid,
    input  wire        s_axi_wready,
    input  wire [1:0]  s_axi_bresp,
    input  wire        s_axi_bvalid,
    output wire        s_axi_bready
);
    assign busy = 1'b0;
    assign done = 1'b1;
    assign s_axi_awaddr = 12'd0;
    assign s_axi_awvalid = 1'b0;
    assign s_axi_wdata = 32'd0;
    assign s_axi_wstrb = 4'd0;
    assign s_axi_wvalid = 1'b0;
    assign s_axi_bready = 1'b0;
endmodule

module ad6688_init #(
    parameter integer CLK_DIV = 32,
    parameter integer MS_TICKS = 100000,
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
    output wire busy,
    output wire done,
    output wire ok,
    output wire fail,
    output wire [15:0] status_dbg,
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
    output wire runtime_patch_busy,
    output wire runtime_patch_done,
    output wire runtime_patch_fail,
    output wire runtime_link_reinit_busy,
    output wire runtime_link_reinit_done,
    output wire runtime_link_reinit_fail,
    output wire sclk,
    output wire cs_n,
    output wire sdio_o,
    output wire sdio_oe
);
    assign busy = 1'b0;
    assign done = 1'b1;
    assign ok = 1'b1;
    assign fail = 1'b0;
    assign status_dbg = 16'd0;
    assign debug_state = 5'd0;
    assign debug_retry_count = 4'd0;
    assign debug_wait_counter = 32'd0;
    assign debug_read_addr = 16'd0;
    assign debug_read_data = 8'd0;
    assign debug_read_busy = 1'b0;
    assign debug_read_done = 1'b0;
    assign debug_patch_word = 24'd0;
    assign debug_retry_clock_check = 1'b0;
    assign debug_clk_trace = 32'd0;
    assign debug_fail_detail = 32'd0;
    assign debug_jesd_ctrl = 32'd0;
    assign debug_jesd_param = 32'd0;
    assign debug_lane_map = 32'd0;
    assign debug_sysref = 32'd0;
    assign debug_serdes = 32'd0;
    assign debug_link_extra = 32'd0;
    assign debug_serdes_cfg = 32'd0;
    assign debug_serdes_emph = 32'd0;
    assign debug_jesd_param_ext = 32'd0;
    assign debug_checksum03 = 32'd0;
    assign debug_checksum47 = 32'd0;
    assign debug_lid03 = 32'd0;
    assign debug_lid47 = 32'd0;
    assign debug_runtime_patch = 32'd0;
    assign debug_runtime_link_reinit = 32'd0;
    assign runtime_patch_busy = 1'b0;
    assign runtime_patch_done = 1'b0;
    assign runtime_patch_fail = 1'b0;
    assign runtime_link_reinit_busy = 1'b0;
    assign runtime_link_reinit_done = 1'b0;
    assign runtime_link_reinit_fail = 1'b0;
    assign sclk = 1'b0;
    assign cs_n = 1'b1;
    assign sdio_o = 1'b0;
    assign sdio_oe = 1'b0;
endmodule

module jesd_rx_axi_probe #(
    parameter integer REPEAT_WAIT_CYCLES = 1000000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    output wire        running,
    output wire        done_seen,
    output wire        error_seen,
    output wire [31:0] status_dbg,
    output wire [31:0] rxerr_dbg,
    output wire [31:0] rxdebug_dbg,
    output wire [31:0] cfg_dbg,
    output wire [31:0] lanes_dbg,
    output wire [31:0] lane0_ilas0_dbg,
    output wire [31:0] lane0_ilas1_dbg,
    output wire [31:0] lane0_ilas2_dbg,
    output wire [31:0] lane0_ilas3_dbg,
    output wire [31:0] lane0_ilas4_dbg,
    output wire [31:0] lane0_ilas5_dbg,
    output wire [31:0] lane1_ilas3_dbg,
    output wire [31:0] lane2_ilas3_dbg,
    output wire [31:0] lane3_ilas0_dbg,
    output wire [31:0] lane3_ilas1_dbg,
    output wire [31:0] lane3_ilas2_dbg,
    output wire [31:0] lane3_ilas3_dbg,
    output wire [31:0] lane3_ilas4_dbg,
    output wire [31:0] lane3_ilas5_dbg,
    output wire [31:0] lane4_ilas3_dbg,
    output wire [31:0] lane5_ilas3_dbg,
    output wire [31:0] lane6_ilas3_dbg,
    output wire [31:0] lane7_ilas3_dbg,
    output wire [31:0] ilas3_lanes03_dbg,
    output wire [31:0] ilas3_lanes47_dbg,
    output wire [31:0] live_dbg,
    output wire [11:0] s_axi_araddr,
    output wire        s_axi_arvalid,
    input  wire        s_axi_arready,
    input  wire [31:0] s_axi_rdata,
    input  wire [1:0]  s_axi_rresp,
    input  wire        s_axi_rvalid,
    output wire        s_axi_rready
);
    assign running = 1'b0;
    assign done_seen = 1'b0;
    assign error_seen = 1'b0;
    assign status_dbg = 32'd0;
    assign rxerr_dbg = 32'd0;
    assign rxdebug_dbg = 32'd0;
    assign cfg_dbg = 32'd0;
    assign lanes_dbg = 32'd0;
    assign lane0_ilas0_dbg = 32'd0;
    assign lane0_ilas1_dbg = 32'd0;
    assign lane0_ilas2_dbg = 32'd0;
    assign lane0_ilas3_dbg = 32'd0;
    assign lane0_ilas4_dbg = 32'd0;
    assign lane0_ilas5_dbg = 32'd0;
    assign lane1_ilas3_dbg = 32'd0;
    assign lane2_ilas3_dbg = 32'd0;
    assign lane3_ilas0_dbg = 32'd0;
    assign lane3_ilas1_dbg = 32'd0;
    assign lane3_ilas2_dbg = 32'd0;
    assign lane3_ilas3_dbg = 32'd0;
    assign lane3_ilas4_dbg = 32'd0;
    assign lane3_ilas5_dbg = 32'd0;
    assign lane4_ilas3_dbg = 32'd0;
    assign lane5_ilas3_dbg = 32'd0;
    assign lane6_ilas3_dbg = 32'd0;
    assign lane7_ilas3_dbg = 32'd0;
    assign ilas3_lanes03_dbg = 32'd0;
    assign ilas3_lanes47_dbg = 32'd0;
    assign live_dbg = 32'd0;
    assign s_axi_araddr = 12'd0;
    assign s_axi_arvalid = 1'b0;
    assign s_axi_rready = 1'b0;
endmodule

module jesd204c_rx_link0 (
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    input  wire [11:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [11:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,
    input  wire        rx_core_clk,
    input  wire        rx_core_reset,
    input  wire        rx_sysref,
    output wire        irq,
    output wire [255:0] rx_tdata,
    output wire        rx_tvalid,
    output wire        rx_aresetn,
    output wire [3:0]  rx_sof,
    output wire [3:0]  rx_somf,
    output wire [31:0] rx_frm_err,
    output wire        rx_sync,
    output wire        encommaalign,
    output wire        rx_reset_gt,
    input  wire        rx_reset_done,
    input  wire [63:0] gt0_rxdata,
    input  wire [3:0]  gt0_rxcharisk,
    input  wire [3:0]  gt0_rxdisperr,
    input  wire [3:0]  gt0_rxnotintable,
    input  wire [1:0]  gt0_rxheader,
    input  wire        gt0_rxmisalign,
    input  wire        gt0_rxblock_sync,
    input  wire [63:0] gt1_rxdata,
    input  wire [3:0]  gt1_rxcharisk,
    input  wire [3:0]  gt1_rxdisperr,
    input  wire [3:0]  gt1_rxnotintable,
    input  wire [1:0]  gt1_rxheader,
    input  wire        gt1_rxmisalign,
    input  wire        gt1_rxblock_sync,
    input  wire [63:0] gt2_rxdata,
    input  wire [3:0]  gt2_rxcharisk,
    input  wire [3:0]  gt2_rxdisperr,
    input  wire [3:0]  gt2_rxnotintable,
    input  wire [1:0]  gt2_rxheader,
    input  wire        gt2_rxmisalign,
    input  wire        gt2_rxblock_sync,
    input  wire [63:0] gt3_rxdata,
    input  wire [3:0]  gt3_rxcharisk,
    input  wire [3:0]  gt3_rxdisperr,
    input  wire [3:0]  gt3_rxnotintable,
    input  wire [1:0]  gt3_rxheader,
    input  wire        gt3_rxmisalign,
    input  wire        gt3_rxblock_sync,
    input  wire [63:0] gt4_rxdata,
    input  wire [3:0]  gt4_rxcharisk,
    input  wire [3:0]  gt4_rxdisperr,
    input  wire [3:0]  gt4_rxnotintable,
    input  wire [1:0]  gt4_rxheader,
    input  wire        gt4_rxmisalign,
    input  wire        gt4_rxblock_sync,
    input  wire [63:0] gt5_rxdata,
    input  wire [3:0]  gt5_rxcharisk,
    input  wire [3:0]  gt5_rxdisperr,
    input  wire [3:0]  gt5_rxnotintable,
    input  wire [1:0]  gt5_rxheader,
    input  wire        gt5_rxmisalign,
    input  wire        gt5_rxblock_sync,
    input  wire [63:0] gt6_rxdata,
    input  wire [3:0]  gt6_rxcharisk,
    input  wire [3:0]  gt6_rxdisperr,
    input  wire [3:0]  gt6_rxnotintable,
    input  wire [1:0]  gt6_rxheader,
    input  wire        gt6_rxmisalign,
    input  wire        gt6_rxblock_sync,
    input  wire [63:0] gt7_rxdata,
    input  wire [3:0]  gt7_rxcharisk,
    input  wire [3:0]  gt7_rxdisperr,
    input  wire [3:0]  gt7_rxnotintable,
    input  wire [1:0]  gt7_rxheader,
    input  wire        gt7_rxmisalign,
    input  wire        gt7_rxblock_sync
);
    assign s_axi_awready = 1'b1;
    assign s_axi_wready = 1'b1;
    assign s_axi_bresp = 2'b00;
    assign s_axi_bvalid = s_axi_awvalid && s_axi_wvalid;
    assign s_axi_arready = 1'b1;
    assign s_axi_rdata = 32'd0;
    assign s_axi_rresp = 2'b00;
    assign s_axi_rvalid = s_axi_arvalid;
    assign irq = 1'b0;
    assign rx_tdata = 256'd0;
    assign rx_tvalid = 1'b0;
    assign rx_aresetn = 1'b1;
    assign rx_sof = 4'd0;
    assign rx_somf = 4'd0;
    assign rx_frm_err = 32'd0;
    assign rx_sync = 1'b0;
    assign encommaalign = 1'b0;
    assign rx_reset_gt = 1'b0;
endmodule

module ku5p_bringup_ila (
    input wire clk,
    input wire [31:0] probe0,
    input wire [31:0] probe1,
    input wire [31:0] probe2,
    input wire [31:0] probe3,
    input wire [31:0] probe4,
    input wire [31:0] probe5,
    input wire [31:0] probe6,
    input wire [31:0] probe7,
    input wire [31:0] probe8,
    input wire [31:0] probe9,
    input wire [31:0] probe10,
    input wire [31:0] probe11,
    input wire [31:0] probe12,
    input wire [31:0] probe13,
    input wire [31:0] probe14,
    input wire [31:0] probe15,
    input wire [31:0] probe16,
    input wire [31:0] probe17,
    input wire [31:0] probe18,
    input wire [31:0] probe19,
    input wire [31:0] probe20,
    input wire [31:0] probe21,
    input wire [31:0] probe22,
    input wire [31:0] probe23,
    input wire [31:0] probe24,
    input wire [31:0] probe25,
    input wire [31:0] probe26,
    input wire [31:0] probe27,
    input wire [31:0] probe28,
    input wire [31:0] probe29,
    input wire [31:0] probe30,
    input wire [31:0] probe31,
    input wire [31:0] probe32,
    input wire [31:0] probe33,
    input wire [31:0] probe34,
    input wire [31:0] probe35,
    input wire [31:0] probe36,
    input wire [31:0] probe37,
    input wire [31:0] probe38,
    input wire [31:0] probe39,
    input wire [31:0] probe40,
    input wire [31:0] probe41,
    input wire [31:0] probe42,
    input wire [31:0] probe43,
    input wire [31:0] probe44,
    input wire [31:0] probe45,
    input wire [31:0] probe46,
    input wire [31:0] probe47,
    input wire [31:0] probe48,
    input wire [31:0] probe49,
    input wire [31:0] probe50,
    input wire [31:0] probe51,
    input wire [31:0] probe52,
    input wire [31:0] probe53,
    input wire [31:0] probe54,
    input wire [31:0] probe55,
    input wire [31:0] probe56,
    input wire [31:0] probe57,
    input wire [31:0] probe58,
    input wire [31:0] probe59,
    input wire [31:0] probe60,
    input wire [31:0] probe61,
    input wire [31:0] probe62,
    input wire [31:0] probe63,
    input wire [31:0] probe64,
    input wire [31:0] probe65,
    input wire [31:0] probe66,
    input wire [31:0] probe67,
    input wire [31:0] probe68,
    input wire [31:0] probe69,
    input wire [31:0] probe70,
    input wire [31:0] probe71,
    input wire [31:0] probe72,
    input wire [31:0] probe73,
    input wire [31:0] probe74,
    input wire [31:0] probe75,
    input wire [31:0] probe76,
    input wire [31:0] probe77,
    input wire [31:0] probe78,
    input wire [31:0] probe79,
    input wire [31:0] probe80,
    input wire [31:0] probe81,
    input wire [31:0] probe82,
    input wire [31:0] probe83,
    input wire [31:0] probe84,
    input wire [31:0] probe85,
    input wire [31:0] probe86,
    input wire [31:0] probe87,
    input wire [31:0] probe88,
    input wire [31:0] probe89,
    input wire [31:0] probe90,
    input wire [31:0] probe91,
    input wire [31:0] probe92,
    input wire [31:0] probe93,
    input wire [31:0] probe94,
    input wire [31:0] probe95,
    input wire [31:0] probe96,
    input wire [31:0] probe97,
    input wire [31:0] probe98,
    input wire [31:0] probe99,
    input wire [31:0] probe100,
    input wire [31:0] probe101,
    input wire [31:0] probe102,
    input wire [31:0] probe103,
    input wire [31:0] probe104,
    input wire [31:0] probe105,
    input wire [31:0] probe106,
    input wire [31:0] probe107,
    input wire [31:0] probe108,
    input wire [31:0] probe109,
    input wire [31:0] probe110
);
endmodule
