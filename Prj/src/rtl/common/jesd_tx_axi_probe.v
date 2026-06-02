module jesd_tx_axi_probe #(
    parameter integer REPEAT_WAIT_CYCLES = 1000000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    output reg         running,
    output reg         done_seen,
    output reg         error_seen,
    output reg  [31:0] status_dbg,
    output reg  [31:0] reset_lanes_dbg,
    output reg  [31:0] cfg_dbg,
    output reg  [31:0] ila1_dbg,
    output reg  [31:0] ila2_dbg,
    output reg  [31:0] laneids_dbg,
    output wire [31:0] live_dbg,

    output reg  [11:0] s_axi_araddr,
    output reg         s_axi_arvalid,
    input  wire        s_axi_arready,
    input  wire [31:0] s_axi_rdata,
    input  wire [1:0]  s_axi_rresp,
    input  wire        s_axi_rvalid,
    output reg         s_axi_rready
);

    localparam [2:0] ST_IDLE      = 3'd0;
    localparam [2:0] ST_READ_ADDR = 3'd1;
    localparam [2:0] ST_READ_DATA = 3'd2;
    localparam [2:0] ST_REPEAT    = 3'd3;

    localparam [3:0] IDX_RESET   = 4'd0;
    localparam [3:0] IDX_CFG     = 4'd1;
    localparam [3:0] IDX_LANES   = 4'd2;
    localparam [3:0] IDX_STATUS  = 4'd3;
    localparam [3:0] IDX_ILA1    = 4'd4;
    localparam [3:0] IDX_ILA2    = 4'd5;
    localparam [3:0] IDX_LANE0   = 4'd6;
    localparam [3:0] IDX_LANE1   = 4'd7;
    localparam [3:0] IDX_LANE2   = 4'd8;
    localparam [3:0] IDX_LANE3   = 4'd9;

    reg [2:0]  state;
    reg [3:0]  read_idx;
    reg [31:0] repeat_wait;
    reg [31:0] reset_dbg;
    reg [31:0] lanes_dbg;
    reg [11:0] last_addr_dbg;
    reg [1:0]  last_rresp_dbg;

    assign live_dbg = {
        3'd0,
        done_seen,
        error_seen,
        running,
        last_rresp_dbg,
        state,
        read_idx,
        last_addr_dbg
    };

    always @(*) begin
        case (read_idx)
            IDX_RESET:  s_axi_araddr = 12'h020;
            IDX_CFG:    s_axi_araddr = 12'h03c;
            IDX_LANES:  s_axi_araddr = 12'h040;
            IDX_STATUS: s_axi_araddr = 12'h060;
            IDX_ILA1:   s_axi_araddr = 12'h074;
            IDX_ILA2:   s_axi_araddr = 12'h078;
            IDX_LANE0:  s_axi_araddr = 12'h404;
            IDX_LANE1:  s_axi_araddr = 12'h484;
            IDX_LANE2:  s_axi_araddr = 12'h504;
            default:    s_axi_araddr = 12'h584;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state          <= ST_IDLE;
            read_idx       <= IDX_RESET;
            repeat_wait    <= 32'd0;
            running        <= 1'b0;
            done_seen      <= 1'b0;
            error_seen     <= 1'b0;
            status_dbg     <= 32'd0;
            reset_lanes_dbg <= 32'd0;
            cfg_dbg        <= 32'd0;
            ila1_dbg       <= 32'd0;
            ila2_dbg       <= 32'd0;
            laneids_dbg    <= 32'd0;
            reset_dbg      <= 32'd0;
            lanes_dbg      <= 32'd0;
            last_addr_dbg  <= 12'd0;
            last_rresp_dbg <= 2'b00;
            s_axi_arvalid  <= 1'b0;
            s_axi_rready   <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    running       <= 1'b0;
                    s_axi_arvalid <= 1'b0;
                    s_axi_rready  <= 1'b0;
                    if (enable) begin
                        running       <= 1'b1;
                        read_idx      <= IDX_RESET;
                        last_addr_dbg <= 12'h020;
                        s_axi_arvalid <= 1'b1;
                        state         <= ST_READ_ADDR;
                    end
                end

                ST_READ_ADDR: begin
                    running <= 1'b1;
                    if (s_axi_arvalid && s_axi_arready) begin
                        s_axi_arvalid <= 1'b0;
                        s_axi_rready  <= 1'b1;
                        state         <= ST_READ_DATA;
                    end
                end

                ST_READ_DATA: begin
                    running <= 1'b1;
                    if (s_axi_rvalid) begin
                        s_axi_rready   <= 1'b0;
                        last_rresp_dbg <= s_axi_rresp;
                        if (s_axi_rresp != 2'b00) begin
                            error_seen <= 1'b1;
                        end

                        case (read_idx)
                            IDX_RESET: begin
                                reset_dbg <= s_axi_rdata;
                                reset_lanes_dbg[15:0] <= s_axi_rdata[15:0];
                            end
                            IDX_CFG: begin
                                cfg_dbg <= s_axi_rdata;
                            end
                            IDX_LANES: begin
                                lanes_dbg <= s_axi_rdata;
                                reset_lanes_dbg[31:16] <= s_axi_rdata[15:0];
                            end
                            IDX_STATUS: begin
                                status_dbg <= s_axi_rdata;
                            end
                            IDX_ILA1: begin
                                ila1_dbg <= s_axi_rdata;
                            end
                            IDX_ILA2: begin
                                ila2_dbg <= s_axi_rdata;
                            end
                            IDX_LANE0: begin
                                laneids_dbg[7:0] <= s_axi_rdata[7:0];
                            end
                            IDX_LANE1: begin
                                laneids_dbg[15:8] <= s_axi_rdata[7:0];
                            end
                            IDX_LANE2: begin
                                laneids_dbg[23:16] <= s_axi_rdata[7:0];
                            end
                            default: begin
                                laneids_dbg[31:24] <= s_axi_rdata[7:0];
                            end
                        endcase

                        if (read_idx == IDX_LANE3) begin
                            done_seen   <= 1'b1;
                            repeat_wait <= REPEAT_WAIT_CYCLES;
                            state       <= ST_REPEAT;
                        end else begin
                            read_idx      <= read_idx + 1'b1;
                            last_addr_dbg <= next_addr(read_idx + 1'b1);
                            s_axi_arvalid <= 1'b1;
                            state         <= ST_READ_ADDR;
                        end
                    end
                end

                ST_REPEAT: begin
                    running <= 1'b0;
                    if (!enable) begin
                        state <= ST_IDLE;
                    end else if (repeat_wait == 32'd0) begin
                        running       <= 1'b1;
                        read_idx      <= IDX_RESET;
                        last_addr_dbg <= 12'h020;
                        s_axi_arvalid <= 1'b1;
                        state         <= ST_READ_ADDR;
                    end else begin
                        repeat_wait <= repeat_wait - 1'b1;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    function [11:0] next_addr;
        input [3:0] idx;
        begin
            case (idx)
                IDX_RESET:  next_addr = 12'h020;
                IDX_CFG:    next_addr = 12'h03c;
                IDX_LANES:  next_addr = 12'h040;
                IDX_STATUS: next_addr = 12'h060;
                IDX_ILA1:   next_addr = 12'h074;
                IDX_ILA2:   next_addr = 12'h078;
                IDX_LANE0:  next_addr = 12'h404;
                IDX_LANE1:  next_addr = 12'h484;
                IDX_LANE2:  next_addr = 12'h504;
                default:    next_addr = 12'h584;
            endcase
        end
    endfunction
endmodule
