module spi_write_master #(
    parameter integer CLK_DIV = 32,
    parameter integer UPDATE_MOSI_ON_LOW = 0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [23:0] tx_word,
    output reg         busy,
    output reg         done,
    output reg         sclk,
    output reg         cs_n,
    output reg         mosi
);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_LOW  = 2'd1;
    localparam [1:0] ST_HIGH = 2'd2;
    localparam [1:0] ST_STOP = 2'd3;

    reg [1:0]  state;
    reg [23:0] shift_reg;
    reg [4:0]  bit_count;
    reg [15:0] div_count;

    wire tick = (div_count == 16'd0);

    always @(posedge clk) begin
        if (rst) begin
            state     <= ST_IDLE;
            shift_reg <= 24'd0;
            bit_count <= 5'd0;
            div_count <= 16'd0;
            busy      <= 1'b0;
            done      <= 1'b0;
            sclk      <= 1'b1;
            cs_n      <= 1'b1;
            mosi      <= 1'b0;
        end else begin
            done <= 1'b0;

            if (state == ST_IDLE) begin
                div_count <= CLK_DIV - 1;
                sclk      <= 1'b1;
                cs_n      <= 1'b1;
                busy      <= 1'b0;
                if (start) begin
                    shift_reg <= tx_word;
                    bit_count <= 5'd23;
                    mosi      <= tx_word[23];
                    cs_n      <= 1'b0;
                    busy      <= 1'b1;
                    state     <= ST_LOW;
                end
            end else begin
                if (tick) begin
                    div_count <= CLK_DIV - 1;
                end else begin
                    div_count <= div_count - 1'b1;
                end

                case (state)
                    ST_LOW: begin
                        sclk <= 1'b0;
                        if (UPDATE_MOSI_ON_LOW != 0) begin
                            mosi <= shift_reg[bit_count];
                        end
                        if (tick) begin
                            state <= ST_HIGH;
                        end
                    end

                    ST_HIGH: begin
                        sclk <= 1'b1;
                        if (tick) begin
                            if (bit_count == 5'd0) begin
                                state <= ST_STOP;
                            end else begin
                                bit_count <= bit_count - 1'b1;
                                if (UPDATE_MOSI_ON_LOW == 0) begin
                                    shift_reg <= {shift_reg[22:0], 1'b0};
                                    mosi      <= shift_reg[22];
                                end
                                state     <= ST_LOW;
                            end
                        end
                    end

                    ST_STOP: begin
                        sclk <= 1'b1;
                        cs_n <= 1'b1;
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end

                    default: begin
                        state <= ST_IDLE;
                    end
                endcase
            end
        end
    end

endmodule
