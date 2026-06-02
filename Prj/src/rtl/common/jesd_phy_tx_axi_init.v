`timescale 1ns/1ps

module jesd_phy_tx_axi_init #(
    parameter integer USE_QPLL0 = 1,
    parameter integer RESET_WAIT_CYCLES = 10000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    output reg         busy,
    output reg         done_seen,
    output wire [11:0] s_axi_awaddr,
    output wire        s_axi_awvalid,
    input  wire        s_axi_awready,
    output wire [31:0] s_axi_wdata,
    output wire        s_axi_wvalid,
    input  wire        s_axi_wready,
    input  wire [1:0]  s_axi_bresp,
    input  wire        s_axi_bvalid,
    output wire        s_axi_bready
);

    localparam [11:0] ADDR_COMMON_SEL    = 12'h020;
    localparam [11:0] ADDR_GT_SEL        = 12'h024;
    localparam [11:0] ADDR_QPLL0_PD      = 12'h304;
    localparam [11:0] ADDR_QPLL1_PD      = 12'h308;
    localparam [11:0] ADDR_CPLLPD        = 12'h408;
    localparam [11:0] ADDR_TXPLLCLKSEL   = 12'h40c;
    localparam [11:0] ADDR_RXPLLCLKSEL   = 12'h410;
    localparam [11:0] ADDR_TX_SYS_RESET  = 12'h420;

    localparam [7:0] ST_IDLE             = 8'd0;
    localparam [7:0] ST_WAIT_WRITE       = 8'd1;
    localparam [7:0] ST_COMMON_DONE      = 8'd2;
    localparam [7:0] ST_QPLL0_DONE       = 8'd3;
    localparam [7:0] ST_QPLL1_DONE       = 8'd4;
    localparam [7:0] ST_LANE_SEL_ON_DONE = 8'd5;
    localparam [7:0] ST_TXPLL_DONE       = 8'd6;
    localparam [7:0] ST_RXPLL_DONE       = 8'd7;
    localparam [7:0] ST_CPLL_ON_DONE     = 8'd8;
    localparam [7:0] ST_TXRST_ON_DONE    = 8'd9;
    localparam [7:0] ST_WAIT_RESET_ON    = 8'd10;
    localparam [7:0] ST_LANE_SEL_OFF_DONE = 8'd11;
    localparam [7:0] ST_CPLL_OFF_DONE    = 8'd12;
    localparam [7:0] ST_TXRST_OFF_DONE   = 8'd13;

    reg [7:0]  state;
    reg [7:0]  next_state;
    reg [1:0]  lane_idx;
    reg [31:0] reset_wait;
    reg        axi_start;
    reg [11:0] axi_addr;
    reg [31:0] axi_wdata;
    wire       axi_busy;
    wire       axi_done;
    wire [3:0] axi_wstrb_unused;

    task start_write;
        input [11:0] addr;
        input [31:0] data;
        input [7:0]  after_state;
        begin
            axi_addr   <= addr;
            axi_wdata  <= data;
            axi_start  <= 1'b1;
            next_state <= after_state;
            state      <= ST_WAIT_WRITE;
        end
    endtask

    axi_lite_write_master #(
        .ADDR_W(12)
    ) u_master (
        .clk          (clk),
        .rst          (rst),
        .start        (axi_start),
        .addr         (axi_addr),
        .wdata        (axi_wdata),
        .busy         (axi_busy),
        .done         (axi_done),
        .m_axi_awaddr (s_axi_awaddr),
        .m_axi_awvalid(s_axi_awvalid),
        .m_axi_awready(s_axi_awready),
        .m_axi_wdata  (s_axi_wdata),
        .m_axi_wstrb  (axi_wstrb_unused),
        .m_axi_wvalid (s_axi_wvalid),
        .m_axi_wready (s_axi_wready),
        .m_axi_bresp  (s_axi_bresp),
        .m_axi_bvalid (s_axi_bvalid),
        .m_axi_bready (s_axi_bready)
    );

    always @(posedge clk) begin
        if (rst) begin
            state      <= ST_IDLE;
            next_state <= ST_IDLE;
            busy       <= 1'b0;
            done_seen  <= 1'b0;
            lane_idx   <= 2'd0;
            reset_wait <= 32'd0;
            axi_start  <= 1'b0;
            axi_addr   <= 12'd0;
            axi_wdata  <= 32'd0;
        end else begin
            axi_start <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (enable && !done_seen) begin
                        busy     <= 1'b1;
                        lane_idx <= 2'd0;
                        start_write(ADDR_COMMON_SEL, 32'd0, ST_COMMON_DONE);
                    end
                end

                ST_WAIT_WRITE: begin
                    if (axi_done) begin
                        state <= next_state;
                    end
                end

                ST_COMMON_DONE: begin
                    start_write(ADDR_QPLL0_PD,
                                (USE_QPLL0 != 0) ? 32'd0 : 32'd1,
                                ST_QPLL0_DONE);
                end

                ST_QPLL0_DONE: begin
                    start_write(ADDR_QPLL1_PD, 32'd1, ST_QPLL1_DONE);
                end

                ST_QPLL1_DONE: begin
                    start_write(ADDR_GT_SEL, {30'd0, lane_idx},
                                ST_LANE_SEL_ON_DONE);
                end

                ST_LANE_SEL_ON_DONE: begin
                    start_write(ADDR_TXPLLCLKSEL,
                                (USE_QPLL0 != 0) ? 32'd3 : 32'd0,
                                ST_TXPLL_DONE);
                end

                ST_TXPLL_DONE: begin
                    start_write(ADDR_RXPLLCLKSEL,
                                (USE_QPLL0 != 0) ? 32'd3 : 32'd0,
                                ST_RXPLL_DONE);
                end

                ST_RXPLL_DONE: begin
                    start_write(ADDR_CPLLPD, 32'd1, ST_CPLL_ON_DONE);
                end

                ST_CPLL_ON_DONE: begin
                    if (lane_idx == 2'd3) begin
                        start_write(ADDR_TX_SYS_RESET, 32'd1,
                                    ST_TXRST_ON_DONE);
                    end else begin
                        lane_idx <= lane_idx + 1'b1;
                        start_write(ADDR_GT_SEL, {30'd0, lane_idx + 1'b1},
                                    ST_LANE_SEL_ON_DONE);
                    end
                end

                ST_TXRST_ON_DONE: begin
                    reset_wait <= RESET_WAIT_CYCLES;
                    state      <= ST_WAIT_RESET_ON;
                end

                ST_WAIT_RESET_ON: begin
                    if (reset_wait == 32'd0) begin
                        lane_idx <= 2'd0;
                        start_write(ADDR_GT_SEL, 32'd0,
                                    ST_LANE_SEL_OFF_DONE);
                    end else begin
                        reset_wait <= reset_wait - 1'b1;
                    end
                end

                ST_LANE_SEL_OFF_DONE: begin
                    start_write(ADDR_CPLLPD,
                                (USE_QPLL0 != 0) ? 32'd1 : 32'd0,
                                ST_CPLL_OFF_DONE);
                end

                ST_CPLL_OFF_DONE: begin
                    if (lane_idx == 2'd3) begin
                        start_write(ADDR_TX_SYS_RESET, 32'd0,
                                    ST_TXRST_OFF_DONE);
                    end else begin
                        lane_idx <= lane_idx + 1'b1;
                        start_write(ADDR_GT_SEL, {30'd0, lane_idx + 1'b1},
                                    ST_LANE_SEL_OFF_DONE);
                    end
                end

                ST_TXRST_OFF_DONE: begin
                    busy      <= 1'b0;
                    done_seen <= 1'b1;
                    state     <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
