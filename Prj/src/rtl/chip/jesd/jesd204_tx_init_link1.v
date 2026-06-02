module jesd204_tx_init_link1 #(
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

    wire [7:0]  table_addr;
    wire [63:0] table_cmd;
    wire        axi_start;
    wire [11:0] axi_addr;
    wire [31:0] axi_wdata;
    wire        axi_busy;
    wire        axi_done;

    jesd204_tx_init_table_link1 u_table (
        .addr(table_addr),
        .cmd (table_cmd)
    );

    axi_lite_init_engine #(
        .TABLE_AW(8),
        .MS_TICKS(MS_TICKS)
    ) u_engine (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .busy      (busy),
        .done      (done),
        .table_addr(table_addr),
        .table_cmd (table_cmd),
        .axi_start (axi_start),
        .axi_addr  (axi_addr),
        .axi_wdata (axi_wdata),
        .axi_busy  (axi_busy),
        .axi_done  (axi_done)
    );

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
        .m_axi_wstrb  (s_axi_wstrb),
        .m_axi_wvalid (s_axi_wvalid),
        .m_axi_wready (s_axi_wready),
        .m_axi_bresp  (s_axi_bresp),
        .m_axi_bvalid (s_axi_bvalid),
        .m_axi_bready (s_axi_bready)
    );

endmodule
