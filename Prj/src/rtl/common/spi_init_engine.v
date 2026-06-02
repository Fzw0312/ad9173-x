module spi_init_engine #(
    parameter integer TABLE_AW = 8,
    parameter integer MS_TICKS = 100000,
    parameter integer POST_WRITE_TICKS = 0
) (
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 start,
    output reg                  busy,
    output reg                  done,
    output reg  [TABLE_AW-1:0]  table_addr,
    input  wire [31:0]          table_cmd,
    output reg                  spi_start,
    output reg  [23:0]          spi_word,
    input  wire                 spi_busy,
    input  wire                 spi_done
) ;

    localparam [7:0] OP_WRITE   = 8'h01;
    localparam [7:0] OP_WAIT_MS = 8'h02;
    localparam [7:0] OP_END     = 8'hff;

    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_FETCH = 3'd1;
    localparam [2:0] ST_KICK  = 3'd2;
    localparam [2:0] ST_SPI   = 3'd3;
    localparam [2:0] ST_WAIT  = 3'd4;
    localparam [2:0] ST_POST  = 3'd5;

    reg [2:0]  state;
    reg [31:0] wait_counter;
    reg [31:0] wait_tick_counter;
    reg [7:0]  wait_ms_remaining;

    always @(posedge clk) begin
        if (rst) begin
            state       <= ST_IDLE;
            busy        <= 1'b0;
            done        <= 1'b0;
            table_addr  <= {TABLE_AW{1'b0}};
            spi_start   <= 1'b0;
            spi_word    <= 24'd0;
            wait_counter <= 32'd0;
            wait_tick_counter <= 32'd0;
            wait_ms_remaining <= 8'd0;
        end else begin
            done      <= 1'b0;
            spi_start <= 1'b0;

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
                    case (table_cmd[31:24])
                        OP_WRITE: begin
                            spi_word <= {table_cmd[23:8], table_cmd[7:0]};
                            state    <= ST_KICK;
                        end

                        OP_WAIT_MS: begin
                            wait_tick_counter <= 32'd0;
                            wait_ms_remaining <= table_cmd[7:0];
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
                    if (!spi_busy) begin
                        spi_start <= 1'b1;
                        state     <= ST_SPI;
                    end
                end

                ST_SPI: begin
                    if (spi_done) begin
                        if (POST_WRITE_TICKS == 0) begin
                            table_addr <= table_addr + 1'b1;
                            state      <= ST_FETCH;
                        end else begin
                            wait_counter <= POST_WRITE_TICKS;
                            state        <= ST_POST;
                        end
                    end
                end

                ST_WAIT: begin
                    if (wait_ms_remaining == 8'd0) begin
                        table_addr <= table_addr + 1'b1;
                        state      <= ST_FETCH;
                    end else if (wait_tick_counter >= (MS_TICKS - 1)) begin
                        wait_tick_counter <= 32'd0;
                        if (wait_ms_remaining == 8'd1) begin
                            wait_ms_remaining <= 8'd0;
                            table_addr        <= table_addr + 1'b1;
                            state             <= ST_FETCH;
                        end else begin
                            wait_ms_remaining <= wait_ms_remaining - 1'b1;
                        end
                    end else begin
                        wait_tick_counter <= wait_tick_counter + 1'b1;
                    end
                end

                ST_POST: begin
                    if (wait_counter == 32'd0) begin
                        table_addr <= table_addr + 1'b1;
                        state      <= ST_FETCH;
                    end else begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
