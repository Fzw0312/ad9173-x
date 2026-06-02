module spi_read_master_4wire #(
    parameter integer CLK_DIV = 32,
    parameter integer UPDATE_MOSI_ON_LOW = 0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [15:0] addr,
    input  wire        miso,
    output reg         busy,
    output reg         done,
    output reg  [7:0]  rx_data,
    output reg         sclk,
    output reg         cs_n,
    output reg         mosi
);

    localparam [2:0] ST_IDLE      = 3'd0;
    localparam [2:0] ST_HDR_LOW   = 3'd1;
    localparam [2:0] ST_HDR_HIGH  = 3'd2;
    localparam [2:0] ST_DATA_LOW    = 3'd3;
    localparam [2:0] ST_DATA_SAMPLE = 3'd4;
    localparam [2:0] ST_DATA_HIGH   = 3'd5;
    localparam [2:0] ST_STOP        = 3'd6;

    reg [2:0]  state;
    reg [15:0] shift_reg;
    reg [4:0]  bit_count;
    reg [15:0] div_count;

    wire tick = (div_count == 16'd0);

    always @(posedge clk) begin
        if (rst) begin
            state     <= ST_IDLE;
            shift_reg <= 16'd0;
            bit_count <= 5'd0;
            div_count <= 16'd0;
            busy      <= 1'b0;
            done      <= 1'b0;
            rx_data   <= 8'd0;
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
                    shift_reg <= {1'b1, addr[14:0]};
                    bit_count <= 5'd15;
                    rx_data   <= 8'd0;
                    mosi      <= 1'b1;
                    cs_n      <= 1'b0;
                    busy      <= 1'b1;
                    state     <= ST_HDR_LOW;
                end
            end else begin
                if (tick) begin
                    div_count <= CLK_DIV - 1;
                end else begin
                    div_count <= div_count - 1'b1;
                end

                case (state)
                    ST_HDR_LOW: begin
                        sclk <= 1'b0;
                        if (UPDATE_MOSI_ON_LOW != 0) begin
                            mosi <= shift_reg[bit_count];
                        end
                        if (tick) begin
                            state <= ST_HDR_HIGH;
                        end
                    end

                    ST_HDR_HIGH: begin
                        sclk <= 1'b1;
                        if (tick) begin
                            if (bit_count == 5'd0) begin
                                bit_count <= 5'd7;
                                state     <= ST_DATA_LOW;
                            end else begin
                                bit_count <= bit_count - 1'b1;
                                if (UPDATE_MOSI_ON_LOW == 0) begin
                                    shift_reg <= {shift_reg[14:0], 1'b0};
                                    mosi      <= shift_reg[14];
                                end
                                state     <= ST_HDR_LOW;
                            end
                        end
                    end

                    ST_DATA_LOW: begin
                        sclk <= 1'b0;
                        if (tick) begin
                            state <= ST_DATA_SAMPLE;
                        end
                    end

                    ST_DATA_SAMPLE: begin
                        sclk    <= 1'b0;
                        rx_data <= {rx_data[6:0], miso};
                        state   <= ST_DATA_HIGH;
                    end

                    ST_DATA_HIGH: begin
                        sclk <= 1'b1;
                        if (tick) begin
                            if (bit_count == 5'd0) begin
                                state <= ST_STOP;
                            end else begin
                                bit_count <= bit_count - 1'b1;
                                state     <= ST_DATA_LOW;
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
