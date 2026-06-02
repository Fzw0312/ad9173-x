module axi_lite_init_engine #(
    parameter integer TABLE_AW = 8,
    parameter integer MS_TICKS = 100000
) (
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 start,
    output reg                  busy,
    output reg                  done,
    output reg  [TABLE_AW-1:0]  table_addr,
    input  wire [63:0]          table_cmd,
    output reg                  axi_start,
    output reg  [11:0]          axi_addr,
    output reg  [31:0]          axi_wdata,
    input  wire                 axi_busy,
    input  wire                 axi_done
);

    localparam [7:0] OP_WRITE   = 8'h01;
    localparam [7:0] OP_WAIT_MS = 8'h02;
    localparam [7:0] OP_END     = 8'hff;

    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_FETCH = 3'd1;
    localparam [2:0] ST_KICK  = 3'd2;
    localparam [2:0] ST_AXI   = 3'd3;
    localparam [2:0] ST_WAIT  = 3'd4;

    reg [2:0]  state;
    reg [31:0] wait_tick_counter;
    reg [15:0] wait_ms_remaining;

    always @(posedge clk) begin
        if (rst) begin
            state        <= ST_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            table_addr   <= {TABLE_AW{1'b0}};
            axi_start    <= 1'b0;
            axi_addr     <= 12'd0;
            axi_wdata    <= 32'd0;
            wait_tick_counter <= 32'd0;
            wait_ms_remaining <= 16'd0;
        end else begin
            done      <= 1'b0;
            axi_start <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy       <= 1'b0;
                    table_addr <= {TABLE_AW{1'b0}};
                    if (start) begin
                        busy  <= 1'b1;
                        state <= ST_FETCH;
                    end
                end

                ST_FETCH: begin
                    case (table_cmd[63:56])
                        OP_WRITE: begin
                            axi_addr  <= table_cmd[55:44];
                            axi_wdata <= table_cmd[43:12];
                            state     <= ST_KICK;
                        end

                        OP_WAIT_MS: begin
                            wait_tick_counter <= 32'd0;
                            wait_ms_remaining <= table_cmd[15:0];
                            state             <= ST_WAIT;
                        end

                        OP_END: begin
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            state <= ST_IDLE;
                        end

                        default: begin
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            state <= ST_IDLE;
                        end
                    endcase
                end

                ST_KICK: begin
                    if (!axi_busy) begin
                        axi_start <= 1'b1;
                        state     <= ST_AXI;
                    end
                end

                ST_AXI: begin
                    if (axi_done) begin
                        table_addr <= table_addr + 1'b1;
                        state      <= ST_FETCH;
                    end
                end

                ST_WAIT: begin
                    if (wait_ms_remaining == 16'd0) begin
                        table_addr <= table_addr + 1'b1;
                        state      <= ST_FETCH;
                    end else if (wait_tick_counter >= (MS_TICKS - 1)) begin
                        wait_tick_counter <= 32'd0;
                        if (wait_ms_remaining == 16'd1) begin
                            wait_ms_remaining <= 16'd0;
                            table_addr        <= table_addr + 1'b1;
                            state             <= ST_FETCH;
                        end else begin
                            wait_ms_remaining <= wait_ms_remaining - 1'b1;
                        end
                    end else begin
                        wait_tick_counter <= wait_tick_counter + 1'b1;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
