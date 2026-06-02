module jesd_rx_axi_probe #(
    parameter integer REPEAT_WAIT_CYCLES = 1000000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    output reg         running,
    output reg         done_seen,
    output reg         error_seen,
    output reg  [31:0] status_dbg,
    output reg  [31:0] rxerr_dbg,
    output reg  [31:0] rxdebug_dbg,
    output reg  [31:0] cfg_dbg,
    output reg  [31:0] lanes_dbg,
    output reg  [31:0] lane0_ilas0_dbg,
    output reg  [31:0] lane0_ilas1_dbg,
    output reg  [31:0] lane0_ilas2_dbg,
    output reg  [31:0] lane0_ilas3_dbg,
    output reg  [31:0] lane0_ilas4_dbg,
    output reg  [31:0] lane0_ilas5_dbg,
    output reg  [31:0] lane1_ilas3_dbg,
    output reg  [31:0] lane2_ilas3_dbg,
    output reg  [31:0] lane3_ilas0_dbg,
    output reg  [31:0] lane3_ilas1_dbg,
    output reg  [31:0] lane3_ilas2_dbg,
    output reg  [31:0] lane3_ilas3_dbg,
    output reg  [31:0] lane3_ilas4_dbg,
    output reg  [31:0] lane3_ilas5_dbg,
    output reg  [31:0] lane4_ilas3_dbg,
    output reg  [31:0] lane5_ilas3_dbg,
    output reg  [31:0] lane6_ilas3_dbg,
    output reg  [31:0] lane7_ilas3_dbg,
    output reg  [31:0] ilas3_lanes03_dbg,
    output reg  [31:0] ilas3_lanes47_dbg,
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

    localparam [4:0] IDX_RESET    = 5'd0;
    localparam [4:0] IDX_CFG      = 5'd1;
    localparam [4:0] IDX_LANES    = 5'd2;
    localparam [4:0] IDX_STATUS   = 5'd3;
    localparam [4:0] IDX_RXERR    = 5'd4;
    localparam [4:0] IDX_RXDEBUG  = 5'd5;
    localparam [4:0] IDX_LANE0_D0 = 5'd6;
    localparam [4:0] IDX_LANE0_D1 = 5'd7;
    localparam [4:0] IDX_LANE0_D2 = 5'd8;
    localparam [4:0] IDX_LANE0_D3 = 5'd9;
    localparam [4:0] IDX_LANE0_D4 = 5'd10;
    localparam [4:0] IDX_LANE0_D5 = 5'd11;
    localparam [4:0] IDX_LANE1_D3 = 5'd12;
    localparam [4:0] IDX_LANE2_D3 = 5'd13;
    localparam [4:0] IDX_LANE3_D0 = 5'd14;
    localparam [4:0] IDX_LANE3_D1 = 5'd15;
    localparam [4:0] IDX_LANE3_D2 = 5'd16;
    localparam [4:0] IDX_LANE3_D3 = 5'd17;
    localparam [4:0] IDX_LANE3_D4 = 5'd18;
    localparam [4:0] IDX_LANE3_D5 = 5'd19;
    localparam [4:0] IDX_LANE4_D3 = 5'd20;
    localparam [4:0] IDX_LANE5_D3 = 5'd21;
    localparam [4:0] IDX_LANE6_D3 = 5'd22;
    localparam [4:0] IDX_LANE7_D3 = 5'd23;

    reg [2:0]  state;
    reg [4:0]  read_idx;
    reg [31:0] repeat_wait;
    reg [31:0] reset_dbg;
    reg [11:0] last_addr_dbg;
    reg [1:0]  last_rresp_dbg;

    assign live_dbg = {
        7'd0,
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
            IDX_RESET:   s_axi_araddr = 12'h020;
            IDX_CFG:     s_axi_araddr = 12'h03c;
            IDX_LANES:   s_axi_araddr = 12'h040;
            IDX_STATUS:  s_axi_araddr = 12'h060;
            IDX_RXERR:   s_axi_araddr = 12'h058;
            IDX_RXDEBUG: s_axi_araddr = 12'h05c;
            IDX_LANE0_D0: s_axi_araddr = 12'h430;
            IDX_LANE0_D1: s_axi_araddr = 12'h434;
            IDX_LANE0_D2: s_axi_araddr = 12'h438;
            IDX_LANE0_D3: s_axi_araddr = 12'h43c;
            IDX_LANE0_D4: s_axi_araddr = 12'h440;
            IDX_LANE0_D5: s_axi_araddr = 12'h444;
            IDX_LANE1_D3: s_axi_araddr = 12'h4bc;
            IDX_LANE2_D3: s_axi_araddr = 12'h53c;
            IDX_LANE3_D0: s_axi_araddr = 12'h5b0;
            IDX_LANE3_D1: s_axi_araddr = 12'h5b4;
            IDX_LANE3_D2: s_axi_araddr = 12'h5b8;
            IDX_LANE3_D3: s_axi_araddr = 12'h5bc;
            IDX_LANE3_D4: s_axi_araddr = 12'h5c0;
            IDX_LANE3_D5: s_axi_araddr = 12'h5c4;
            IDX_LANE4_D3: s_axi_araddr = 12'h63c;
            IDX_LANE5_D3: s_axi_araddr = 12'h6bc;
            IDX_LANE6_D3: s_axi_araddr = 12'h73c;
            default:     s_axi_araddr = 12'h7bc;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state             <= ST_IDLE;
            read_idx          <= IDX_RESET;
            repeat_wait       <= 32'd0;
            running           <= 1'b0;
            done_seen         <= 1'b0;
            error_seen        <= 1'b0;
            status_dbg        <= 32'd0;
            rxerr_dbg         <= 32'd0;
            rxdebug_dbg       <= 32'd0;
            cfg_dbg           <= 32'd0;
            lanes_dbg         <= 32'd0;
            lane0_ilas0_dbg   <= 32'd0;
            lane0_ilas1_dbg   <= 32'd0;
            lane0_ilas2_dbg   <= 32'd0;
            lane0_ilas3_dbg   <= 32'd0;
            lane0_ilas4_dbg   <= 32'd0;
            lane0_ilas5_dbg   <= 32'd0;
            lane1_ilas3_dbg   <= 32'd0;
            lane2_ilas3_dbg   <= 32'd0;
            lane3_ilas0_dbg   <= 32'd0;
            lane3_ilas1_dbg   <= 32'd0;
            lane3_ilas2_dbg   <= 32'd0;
            lane3_ilas3_dbg   <= 32'd0;
            lane3_ilas4_dbg   <= 32'd0;
            lane3_ilas5_dbg   <= 32'd0;
            lane4_ilas3_dbg   <= 32'd0;
            lane5_ilas3_dbg   <= 32'd0;
            lane6_ilas3_dbg   <= 32'd0;
            lane7_ilas3_dbg   <= 32'd0;
            ilas3_lanes03_dbg <= 32'd0;
            ilas3_lanes47_dbg <= 32'd0;
            reset_dbg         <= 32'd0;
            last_addr_dbg     <= 12'd0;
            last_rresp_dbg    <= 2'b00;
            s_axi_arvalid     <= 1'b0;
            s_axi_rready      <= 1'b0;
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
                            end
                            IDX_CFG: begin
                                cfg_dbg <= s_axi_rdata;
                            end
                            IDX_LANES: begin
                                lanes_dbg <= s_axi_rdata;
                            end
                            IDX_STATUS: begin
                                status_dbg <= s_axi_rdata;
                            end
                            IDX_RXERR: begin
                                rxerr_dbg <= s_axi_rdata;
                            end
                            IDX_RXDEBUG: begin
                                rxdebug_dbg <= s_axi_rdata;
                            end
                            IDX_LANE0_D0: begin
                                lane0_ilas0_dbg <= s_axi_rdata;
                            end
                            IDX_LANE0_D1: begin
                                lane0_ilas1_dbg <= s_axi_rdata;
                            end
                            IDX_LANE0_D2: begin
                                lane0_ilas2_dbg <= s_axi_rdata;
                            end
                            IDX_LANE0_D3: begin
                                lane0_ilas3_dbg <= s_axi_rdata;
                                ilas3_lanes03_dbg[7:0] <= pack_ilas3(s_axi_rdata);
                            end
                            IDX_LANE0_D4: begin
                                lane0_ilas4_dbg <= s_axi_rdata;
                            end
                            IDX_LANE0_D5: begin
                                lane0_ilas5_dbg <= s_axi_rdata;
                            end
                            IDX_LANE1_D3: begin
                                lane1_ilas3_dbg <= s_axi_rdata;
                                ilas3_lanes03_dbg[15:8] <= pack_ilas3(s_axi_rdata);
                            end
                            IDX_LANE2_D3: begin
                                lane2_ilas3_dbg <= s_axi_rdata;
                                ilas3_lanes03_dbg[23:16] <= pack_ilas3(s_axi_rdata);
                            end
                            IDX_LANE3_D0: begin
                                lane3_ilas0_dbg <= s_axi_rdata;
                            end
                            IDX_LANE3_D1: begin
                                lane3_ilas1_dbg <= s_axi_rdata;
                            end
                            IDX_LANE3_D2: begin
                                lane3_ilas2_dbg <= s_axi_rdata;
                            end
                            IDX_LANE3_D3: begin
                                lane3_ilas3_dbg <= s_axi_rdata;
                                ilas3_lanes03_dbg[31:24] <= pack_ilas3(s_axi_rdata);
                            end
                            IDX_LANE3_D4: begin
                                lane3_ilas4_dbg <= s_axi_rdata;
                            end
                            IDX_LANE3_D5: begin
                                lane3_ilas5_dbg <= s_axi_rdata;
                            end
                            IDX_LANE4_D3: begin
                                lane4_ilas3_dbg <= s_axi_rdata;
                                ilas3_lanes47_dbg[7:0] <= pack_ilas3(s_axi_rdata);
                            end
                            IDX_LANE5_D3: begin
                                lane5_ilas3_dbg <= s_axi_rdata;
                                ilas3_lanes47_dbg[15:8] <= pack_ilas3(s_axi_rdata);
                            end
                            IDX_LANE6_D3: begin
                                lane6_ilas3_dbg <= s_axi_rdata;
                                ilas3_lanes47_dbg[23:16] <= pack_ilas3(s_axi_rdata);
                            end
                            default: begin
                                lane7_ilas3_dbg <= s_axi_rdata;
                                ilas3_lanes47_dbg[31:24] <= pack_ilas3(s_axi_rdata);
                            end
                        endcase

                        if (read_idx == IDX_LANE7_D3) begin
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
        input [4:0] idx;
        begin
            case (idx)
                IDX_RESET:   next_addr = 12'h020;
                IDX_CFG:     next_addr = 12'h03c;
                IDX_LANES:   next_addr = 12'h040;
                IDX_STATUS:  next_addr = 12'h060;
                IDX_RXERR:   next_addr = 12'h058;
                IDX_RXDEBUG: next_addr = 12'h05c;
                IDX_LANE0_D0: next_addr = 12'h430;
                IDX_LANE0_D1: next_addr = 12'h434;
                IDX_LANE0_D2: next_addr = 12'h438;
                IDX_LANE0_D3: next_addr = 12'h43c;
                IDX_LANE0_D4: next_addr = 12'h440;
                IDX_LANE0_D5: next_addr = 12'h444;
                IDX_LANE1_D3: next_addr = 12'h4bc;
                IDX_LANE2_D3: next_addr = 12'h53c;
                IDX_LANE3_D0: next_addr = 12'h5b0;
                IDX_LANE3_D1: next_addr = 12'h5b4;
                IDX_LANE3_D2: next_addr = 12'h5b8;
                IDX_LANE3_D3: next_addr = 12'h5bc;
                IDX_LANE3_D4: next_addr = 12'h5c0;
                IDX_LANE3_D5: next_addr = 12'h5c4;
                IDX_LANE4_D3: next_addr = 12'h63c;
                IDX_LANE5_D3: next_addr = 12'h6bc;
                IDX_LANE6_D3: next_addr = 12'h73c;
                default:     next_addr = 12'h7bc;
            endcase
        end
    endfunction

    function [7:0] pack_ilas3;
        input [31:0] data;
        begin
            pack_ilas3 = {data[26:24], data[20:16]};
        end
    endfunction

endmodule
