`timescale 1ns / 1ps

module adi_spi_master #(
    parameter integer CLK_DIV = 8,
    parameter integer SPI_TIMEOUT_CYCLES = 32'd1000000,
    parameter integer SCLK_IDLE_HIGH = 1
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        read_en,
    input  wire        three_wire,
    input  wire        read_capture_falling,
    input  wire [14:0] addr,
    input  wire [7:0]  wdata,
    input  wire        sdio_i,
    input  wire        sdo_i,
    output reg         busy,
    output reg         done,
    output reg         cs_n,
    output reg         sclk,
    output reg         sdio_oe,
    output reg  [7:0]  rdata,
    output reg         rdata_valid,
    output reg         sdio_o
);

    localparam [0:0] ST_IDLE = 1'b0;
    localparam [0:0] ST_XFER = 1'b1;
    localparam integer LOW_PHASE_SAMPLE_TICK = (CLK_DIV > 1) ? ((CLK_DIV / 2) - 1) : 0;

    wire        read_data_i = three_wire ? sdio_i : sdo_i;
    wire [23:0] tx_word     = {read_en, addr, read_en ? 8'h00 : wdata};

    reg        state;
    reg [31:0] div_cnt;
    reg [31:0] timeout_cnt;
    reg [5:0]  bit_count;
    reg [23:0] tx_shift;
    reg [23:0] rx_shift;
    reg        read_active;
    reg        three_wire_active;
    reg        read_capture_falling_active;
    reg        low_phase_sample_pending;
    reg        prime_falling_half;
    reg        turnaround_release_pending;

    wire       falling_read_mode = read_active && read_capture_falling_active;

    always @(posedge clk) begin
        if (rst) begin
            state                       <= ST_IDLE;
            div_cnt                     <= 32'd0;
            timeout_cnt                 <= 32'd0;
            bit_count                   <= 6'd0;
            tx_shift                    <= 24'd0;
            rx_shift                    <= 24'd0;
            read_active                 <= 1'b0;
            three_wire_active           <= 1'b0;
            read_capture_falling_active <= 1'b0;
            low_phase_sample_pending    <= 1'b0;
            prime_falling_half          <= 1'b0;
            turnaround_release_pending  <= 1'b0;
            busy                        <= 1'b0;
            done                        <= 1'b0;
            cs_n                        <= 1'b1;
            sclk                        <= (SCLK_IDLE_HIGH != 0);
            sdio_oe                     <= 1'b0;
            rdata                       <= 8'h00;
            rdata_valid                 <= 1'b0;
            sdio_o                      <= 1'b0;
        end else begin
            done        <= 1'b0;
            rdata_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy                       <= 1'b0;
                    cs_n                       <= 1'b1;
                    sclk                       <= (SCLK_IDLE_HIGH != 0);
                    sdio_oe                    <= 1'b0;
                    div_cnt                    <= 32'd0;
                    timeout_cnt                <= 32'd0;
                    bit_count                  <= 6'd0;
                    turnaround_release_pending <= 1'b0;
                    low_phase_sample_pending   <= 1'b0;

                    if (start) begin
                        state                       <= ST_XFER;
                        busy                        <= 1'b1;
                        cs_n                        <= 1'b0;
                        sclk                        <= (SCLK_IDLE_HIGH != 0);
                        div_cnt                     <= 32'd0;
                        timeout_cnt                 <= 32'd0;
                        bit_count                   <= 6'd24;
                        tx_shift                    <= tx_word;
                        rx_shift                    <= 24'd0;
                        read_active                 <= read_en;
                        three_wire_active           <= three_wire;
                        read_capture_falling_active <= read_capture_falling;
                        low_phase_sample_pending    <= 1'b0;
                        prime_falling_half          <= (SCLK_IDLE_HIGH != 0);
                        turnaround_release_pending  <= 1'b0;
                        sdio_o                      <= tx_word[23];
                        sdio_oe                     <= 1'b1;
                    end
                end

                ST_XFER: begin
                    if (timeout_cnt >= (SPI_TIMEOUT_CYCLES - 1)) begin
                        state                       <= ST_IDLE;
                        busy                        <= 1'b0;
                        done                        <= 1'b1;
                        cs_n                        <= 1'b1;
                        sclk                        <= (SCLK_IDLE_HIGH != 0);
                        sdio_o                      <= 1'b0;
                        sdio_oe                     <= 1'b0;
                        read_active                 <= 1'b0;
                        three_wire_active           <= 1'b0;
                        read_capture_falling_active <= 1'b0;
                        low_phase_sample_pending    <= 1'b0;
                        prime_falling_half          <= 1'b0;
                        turnaround_release_pending  <= 1'b0;
                    end else begin
                        timeout_cnt <= timeout_cnt + 32'd1;

                        if (falling_read_mode && low_phase_sample_pending &&
                            !sclk && (div_cnt == LOW_PHASE_SAMPLE_TICK)) begin
                            low_phase_sample_pending <= 1'b0;
                            rx_shift                 <= {rx_shift[22:0], read_data_i};
                            bit_count                <= bit_count - 6'd1;

                            if (bit_count == 6'd1) begin
                                rdata <= {rx_shift[6:0], read_data_i};
                            end
                        end

                        if (read_active && three_wire_active &&
                            turnaround_release_pending && sclk) begin
                            sdio_o                     <= 1'b0;
                            sdio_oe                    <= 1'b0;
                            turnaround_release_pending <= 1'b0;
                        end

                        if (div_cnt >= (CLK_DIV - 1)) begin
                            div_cnt <= 32'd0;

                            if (!sclk) begin
                                sclk <= 1'b1;

                                if (falling_read_mode) begin
                                    if (bit_count == 6'd0) begin
                                        state                       <= ST_IDLE;
                                        busy                        <= 1'b0;
                                        done                        <= 1'b1;
                                        cs_n                        <= 1'b1;
                                        sdio_o                      <= 1'b0;
                                        sdio_oe                     <= 1'b0;
                                        rdata_valid                 <= read_active;
                                        read_active                 <= 1'b0;
                                        three_wire_active           <= 1'b0;
                                        read_capture_falling_active <= 1'b0;
                                        low_phase_sample_pending    <= 1'b0;
                                        prime_falling_half          <= 1'b0;
                                        turnaround_release_pending  <= 1'b0;
                                    end else if (!(read_active && (bit_count <= 6'd8))) begin
                                        if (bit_count > 0) begin
                                            bit_count <= bit_count - 6'd1;
                                        end

                                        if (read_active && three_wire_active && (bit_count == 6'd9)) begin
                                            turnaround_release_pending <= 1'b1;
                                        end
                                    end
                                end else begin
                                    rx_shift <= {rx_shift[22:0], read_data_i};

                                    if (bit_count > 0) begin
                                        bit_count <= bit_count - 6'd1;
                                    end

                                    if (read_active && three_wire_active && (bit_count == 6'd9)) begin
                                        turnaround_release_pending <= 1'b1;
                                    end

                                    if (read_active && (bit_count == 6'd1)) begin
                                        rdata <= {rx_shift[6:0], read_data_i};
                                    end
                                end
                            end else begin
                                sclk <= 1'b0;

                                if (!falling_read_mode && (bit_count == 6'd0)) begin
                                    state                       <= ST_IDLE;
                                    busy                        <= 1'b0;
                                    done                        <= 1'b1;
                                    cs_n                        <= 1'b1;
                                    sdio_o                      <= 1'b0;
                                    sdio_oe                     <= 1'b0;
                                    rdata_valid                 <= read_active;
                                    read_active                 <= 1'b0;
                                    three_wire_active           <= 1'b0;
                                    read_capture_falling_active <= 1'b0;
                                    low_phase_sample_pending    <= 1'b0;
                                    prime_falling_half          <= 1'b0;
                                    turnaround_release_pending  <= 1'b0;
                                end else if (prime_falling_half) begin
                                    prime_falling_half <= 1'b0;
                                end else begin
                                    if (read_capture_falling_active && read_active &&
                                        (bit_count <= 6'd8) && (bit_count > 6'd0)) begin
                                        low_phase_sample_pending <= 1'b1;
                                    end

                                    if (read_active && three_wire_active && (bit_count <= 6'd8)) begin
                                        sdio_o  <= 1'b0;
                                        sdio_oe <= 1'b0;
                                    end else begin
                                        sdio_o  <= tx_shift[22];
                                        sdio_oe <= 1'b1;
                                    end
                                    tx_shift <= {tx_shift[22:0], 1'b0};
                                end
                            end
                        end else begin
                            div_cnt <= div_cnt + 32'd1;
                        end
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
