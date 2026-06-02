module axi_lite_write_master #(
    parameter integer ADDR_W = 12
) (
    input  wire                clk,
    input  wire                rst,
    input  wire                start,
    input  wire [ADDR_W-1:0]   addr,
    input  wire [31:0]         wdata,
    output reg                 busy,
    output reg                 done,
    output reg  [ADDR_W-1:0]   m_axi_awaddr,
    output reg                 m_axi_awvalid,
    input  wire                m_axi_awready,
    output reg  [31:0]         m_axi_wdata,
    output wire [3:0]          m_axi_wstrb,
    output reg                 m_axi_wvalid,
    input  wire                m_axi_wready,
    input  wire [1:0]          m_axi_bresp,
    input  wire                m_axi_bvalid,
    output reg                 m_axi_bready
);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_REQ  = 2'd1;
    localparam [1:0] ST_RESP = 2'd2;

    reg [1:0] state;
    reg       aw_done;
    reg       w_done;

    assign m_axi_wstrb = 4'hf;

    always @(posedge clk) begin
        if (rst) begin
            state         <= ST_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            aw_done       <= 1'b0;
            w_done        <= 1'b0;
            m_axi_awaddr  <= {ADDR_W{1'b0}};
            m_axi_awvalid <= 1'b0;
            m_axi_wdata   <= 32'd0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy         <= 1'b0;
                    aw_done      <= 1'b0;
                    w_done       <= 1'b0;
                    m_axi_bready <= 1'b0;
                    if (start) begin
                        busy          <= 1'b1;
                        m_axi_awaddr  <= addr;
                        m_axi_wdata   <= wdata;
                        m_axi_awvalid <= 1'b1;
                        m_axi_wvalid  <= 1'b1;
                        state         <= ST_REQ;
                    end
                end

                ST_REQ: begin
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
                        state        <= ST_RESP;
                    end
                end

                ST_RESP: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
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
