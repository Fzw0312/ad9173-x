module axi_lite_rdwr_master #(
    parameter integer ADDR_W = 12
) (
    input  wire                clk,
    input  wire                rst,
    input  wire                start,
    input  wire                is_read,
    input  wire [ADDR_W-1:0]   addr,
    input  wire [31:0]         wdata,
    output reg                 busy,
    output reg                 done,
    output reg                 error,
    output reg  [31:0]         rdata,
    output reg  [1:0]          last_bresp,
    output reg  [1:0]          last_rresp,

    output reg  [ADDR_W-1:0]   m_axi_awaddr,
    output reg                 m_axi_awvalid,
    input  wire                m_axi_awready,
    output reg  [31:0]         m_axi_wdata,
    output reg                 m_axi_wvalid,
    input  wire                m_axi_wready,
    input  wire [1:0]          m_axi_bresp,
    input  wire                m_axi_bvalid,
    output reg                 m_axi_bready,
    output reg  [ADDR_W-1:0]   m_axi_araddr,
    output reg                 m_axi_arvalid,
    input  wire                m_axi_arready,
    input  wire [31:0]         m_axi_rdata,
    input  wire [1:0]          m_axi_rresp,
    input  wire                m_axi_rvalid,
    output reg                 m_axi_rready
);

    localparam [2:0] ST_IDLE       = 3'd0;
    localparam [2:0] ST_WRITE_REQ  = 3'd1;
    localparam [2:0] ST_WRITE_RESP = 3'd2;
    localparam [2:0] ST_READ_ADDR  = 3'd3;
    localparam [2:0] ST_READ_DATA  = 3'd4;

    reg [2:0] state;
    reg       aw_done;
    reg       w_done;

    always @(posedge clk) begin
        if (rst) begin
            state         <= ST_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            error         <= 1'b0;
            rdata         <= 32'd0;
            last_bresp    <= 2'b00;
            last_rresp    <= 2'b00;
            aw_done       <= 1'b0;
            w_done        <= 1'b0;
            m_axi_awaddr  <= {ADDR_W{1'b0}};
            m_axi_awvalid <= 1'b0;
            m_axi_wdata   <= 32'd0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            m_axi_araddr  <= {ADDR_W{1'b0}};
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy          <= 1'b0;
                    error         <= 1'b0;
                    aw_done       <= 1'b0;
                    w_done        <= 1'b0;
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_bready  <= 1'b0;
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;

                    if (start) begin
                        busy <= 1'b1;
                        if (is_read) begin
                            m_axi_araddr  <= addr;
                            m_axi_arvalid <= 1'b1;
                            state         <= ST_READ_ADDR;
                        end else begin
                            m_axi_awaddr  <= addr;
                            m_axi_wdata   <= wdata;
                            m_axi_awvalid <= 1'b1;
                            m_axi_wvalid  <= 1'b1;
                            state         <= ST_WRITE_REQ;
                        end
                    end
                end

                ST_WRITE_REQ: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        aw_done       <= 1'b1;
                    end

                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        w_done       <= 1'b1;
                    end

                    if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                        (w_done  || (m_axi_wvalid  && m_axi_wready))) begin
                        m_axi_bready <= 1'b1;
                        state        <= ST_WRITE_RESP;
                    end
                end

                ST_WRITE_RESP: begin
                    if (m_axi_bvalid) begin
                        last_bresp   <= m_axi_bresp;
                        error        <= (m_axi_bresp != 2'b00);
                        m_axi_bready <= 1'b0;
                        busy         <= 1'b0;
                        done         <= 1'b1;
                        state        <= ST_IDLE;
                    end
                end

                ST_READ_ADDR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= ST_READ_DATA;
                    end
                end

                ST_READ_DATA: begin
                    if (m_axi_rvalid) begin
                        rdata        <= m_axi_rdata;
                        last_rresp   <= m_axi_rresp;
                        error        <= (m_axi_rresp != 2'b00);
                        m_axi_rready <= 1'b0;
                        busy         <= 1'b0;
                        done         <= 1'b1;
                        state        <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
