`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: pe43711_serial_ctrl
// Description:
//   Three-wire serial controller for the pSemi PE43711/PE43711A DSA.
//
//   The PE43711 serial word is 8 bits, LSB first. Bits D6..D0 select
//   attenuation in 0.25 dB steps, and D7 must be 0.
//////////////////////////////////////////////////////////////////////////////////
module pe43711_serial_ctrl #(
    parameter integer CLK_HALF_CYCLES = 16,
    parameter [6:0]   DEFAULT_ATTENUATION_CODE = 7'd127,
    parameter integer POWER_ON_APPLY = 1
) (
    input             clk,
    input             rst_n,
    input      [6:0]  attenuation_code,
    input             apply_toggle,

    output reg        pe_data,
    output reg        pe_clk,
    output reg        pe_le,

    output reg [6:0]  active_code,
    output reg [7:0]  apply_count,
    output reg        busy,
    output     [31:0] status_word
);

    localparam [2:0] ST_IDLE     = 3'd0;
    localparam [2:0] ST_SETUP    = 3'd1;
    localparam [2:0] ST_CLK_HIGH = 3'd2;
    localparam [2:0] ST_CLK_LOW  = 3'd3;
    localparam [2:0] ST_LE_SETUP = 3'd4;
    localparam [2:0] ST_LE_HIGH  = 3'd5;
    localparam [2:0] ST_LE_LOW   = 3'd6;

    reg [2:0] state;
    reg [7:0] shift_word;
    reg [6:0] pending_code;
    reg       apply_meta;
    reg       apply_sync;
    reg       apply_sync_d1;
    reg       apply_pending;
    reg       power_on_done;
    reg [3:0] bit_index;
    reg [15:0] half_count;

    wire apply_edge = apply_sync ^ apply_sync_d1;
    wire half_done = (half_count == (CLK_HALF_CYCLES - 1));
    wire power_on_apply_enabled = (POWER_ON_APPLY != 0);

    assign status_word = {
        apply_count,       // [31:24]
        active_code,       // [23:17]
        busy,              // [16]
        pending_code,      // [15:9]
        apply_pending,     // [8]
        power_on_done,     // [7]
        pe_le,             // [6]
        pe_clk,            // [5]
        pe_data,           // [4]
        power_on_apply_enabled, // [3]
        state              // [2:0]
    };

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            shift_word <= 8'd0;
            pending_code <= DEFAULT_ATTENUATION_CODE;
            apply_meta <= 1'b0;
            apply_sync <= 1'b0;
            apply_sync_d1 <= 1'b0;
            apply_pending <= power_on_apply_enabled;
            power_on_done <= ~power_on_apply_enabled;
            bit_index <= 4'd0;
            half_count <= 16'd0;
            pe_data <= 1'b0;
            pe_clk <= 1'b0;
            pe_le <= 1'b0;
            active_code <= DEFAULT_ATTENUATION_CODE;
            apply_count <= 8'd0;
            busy <= 1'b0;
        end else begin
            apply_meta <= apply_toggle;
            apply_sync <= apply_meta;
            apply_sync_d1 <= apply_sync;

            if (apply_edge) begin
                pending_code <= attenuation_code;
                apply_pending <= 1'b1;
            end

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    pe_clk <= 1'b0;
                    pe_le <= 1'b0;
                    half_count <= 16'd0;
                    bit_index <= 4'd0;
                    if (apply_pending) begin
                        shift_word <= {1'b0, pending_code};
                        pe_data <= pending_code[0];
                        apply_pending <= 1'b0;
                        busy <= 1'b1;
                        state <= ST_SETUP;
                    end
                end

                ST_SETUP: begin
                    busy <= 1'b1;
                    pe_clk <= 1'b0;
                    pe_le <= 1'b0;
                    pe_data <= shift_word[bit_index];
                    if (half_done) begin
                        half_count <= 16'd0;
                        state <= ST_CLK_HIGH;
                    end else begin
                        half_count <= half_count + 16'd1;
                    end
                end

                ST_CLK_HIGH: begin
                    pe_clk <= 1'b1;
                    if (half_done) begin
                        half_count <= 16'd0;
                        state <= ST_CLK_LOW;
                    end else begin
                        half_count <= half_count + 16'd1;
                    end
                end

                ST_CLK_LOW: begin
                    pe_clk <= 1'b0;
                    if (half_done) begin
                        half_count <= 16'd0;
                        if (bit_index == 4'd7) begin
                            state <= ST_LE_SETUP;
                        end else begin
                            bit_index <= bit_index + 4'd1;
                            state <= ST_SETUP;
                        end
                    end else begin
                        half_count <= half_count + 16'd1;
                    end
                end

                ST_LE_SETUP: begin
                    pe_data <= 1'b0;
                    pe_clk <= 1'b0;
                    pe_le <= 1'b0;
                    if (half_done) begin
                        half_count <= 16'd0;
                        state <= ST_LE_HIGH;
                    end else begin
                        half_count <= half_count + 16'd1;
                    end
                end

                ST_LE_HIGH: begin
                    pe_le <= 1'b1;
                    if (half_done) begin
                        half_count <= 16'd0;
                        state <= ST_LE_LOW;
                    end else begin
                        half_count <= half_count + 16'd1;
                    end
                end

                ST_LE_LOW: begin
                    pe_le <= 1'b0;
                    active_code <= shift_word[6:0];
                    apply_count <= apply_count + 8'd1;
                    power_on_done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
