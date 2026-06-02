`timescale 1ns/1ps

// Short-window ADC capture controller for the PL-only K5AD UDP path.
//
// jclk side:
//   - waits for a stable JESD/ADC link-good window,
//   - captures CAPTURE_BEATS 64-bit sample beats into an external RAM,
//   - aborts the window if link_good drops during capture.
//
// eth_clk side:
//   - receives the capture-ready toggle,
//   - starts the UDP packetizer only when it is idle,
//   - returns a done toggle after the packetizer completes.
module adc_udp_capture_ctrl #(
    parameter integer CAPTURE_BEATS = 2048,
    parameter integer CAPTURE_ADDR_W = 11,
    parameter integer REPEAT_TICKS = 49_152_000,
    parameter integer LINK_GOOD_TICKS = 1_228_800,
    parameter integer SAMPLE_GAP_TICKS = 1
) (
    input  wire                          jclk,
    input  wire                          jrst,
    input  wire                          eth_clk,
    input  wire                          eth_rst,
    input  wire                          enable,
    input  wire                          eth_ready_async,
    input  wire                          link_good,
    input  wire                          sample_valid,
    output reg                           capture_active,
    output reg                           wait_pkt_done,
    output reg                           pkt_done_seen,
    output reg  [CAPTURE_ADDR_W-1:0]     wr_addr,
    output reg  [31:0]                   capture_id,
    output reg  [31:0]                   capture_count,
    output reg  [31:0]                   drop_count,
    output reg  [31:0]                   good_window_count,
    output reg  [31:0]                   capture_good_count,
    output reg  [31:0]                   repeat_count,
    input  wire                          pkt_busy,
    input  wire                          pkt_done,
    output reg                           pkt_start,
    output reg  [31:0]                   pkt_capture_id
);

    localparam [CAPTURE_ADDR_W-1:0] LAST_WR_ADDR = CAPTURE_BEATS - 1;
    localparam integer SAMPLE_GAP_LIMIT =
        (SAMPLE_GAP_TICKS < 1) ? 1 : SAMPLE_GAP_TICKS;

    reg send_toggle_jclk;
    reg capture_arm_jclk;
    (* ASYNC_REG = "TRUE" *) reg [1:0] eth_ready_meta_jclk;
    (* ASYNC_REG = "TRUE" *) reg [2:0] send_toggle_meta_eth;
    (* ASYNC_REG = "TRUE" *) reg [2:0] pkt_done_toggle_meta_jclk;
    reg pkt_done_toggle_eth;
    reg pkt_done_q_eth;
    reg start_pending_eth;
    reg start_armed_eth;
    reg [31:0] next_capture_id_eth;
    reg [15:0] sample_gap_count;

    wire ctrl_reset_jclk = jrst || !enable || !eth_ready_meta_jclk[1];
    wire ctrl_reset_eth = eth_rst || !enable;
    wire start_pulse_eth =
        send_toggle_meta_eth[2] ^ send_toggle_meta_eth[1];
    wire done_pulse_jclk =
        pkt_done_toggle_meta_jclk[2] ^ pkt_done_toggle_meta_jclk[1];

    always @(posedge jclk) begin
        if (jrst) begin
            eth_ready_meta_jclk <= 2'b00;
        end else begin
            eth_ready_meta_jclk <= {
                eth_ready_meta_jclk[0],
                eth_ready_async
            };
        end
    end

    always @(posedge eth_clk) begin
        if (ctrl_reset_eth) begin
            send_toggle_meta_eth <= 3'd0;
            pkt_start            <= 1'b0;
            pkt_done_toggle_eth  <= 1'b0;
            pkt_done_q_eth       <= 1'b0;
            start_pending_eth    <= 1'b0;
            start_armed_eth      <= 1'b0;
            pkt_capture_id       <= 32'd0;
            next_capture_id_eth  <= 32'd0;
        end else begin
            send_toggle_meta_eth <= {
                send_toggle_meta_eth[1:0],
                send_toggle_jclk
            };
            pkt_start <= 1'b0;

            if (start_pulse_eth) begin
                start_pending_eth   <= 1'b1;
                next_capture_id_eth <= capture_id;
            end

            if (start_armed_eth) begin
                pkt_start       <= 1'b1;
                start_armed_eth <= 1'b0;
            end else if (start_pending_eth && !pkt_busy) begin
                pkt_capture_id    <= next_capture_id_eth;
                start_pending_eth <= 1'b0;
                start_armed_eth   <= 1'b1;
            end

            pkt_done_q_eth <= pkt_done;
            if (pkt_done && !pkt_done_q_eth) begin
                pkt_done_toggle_eth <= ~pkt_done_toggle_eth;
            end
        end
    end

    always @(posedge jclk) begin
        if (ctrl_reset_jclk) begin
            pkt_done_toggle_meta_jclk <= 3'd0;
            capture_arm_jclk          <= 1'b0;
            capture_active            <= 1'b0;
            wait_pkt_done             <= 1'b0;
            send_toggle_jclk          <= 1'b0;
            pkt_done_seen             <= 1'b0;
            capture_good_count        <= 32'd0;
            repeat_count              <= 32'd0;
            sample_gap_count          <= 16'd0;
            wr_addr                   <= {CAPTURE_ADDR_W{1'b0}};
            capture_id                <= 32'd0;
            capture_count             <= 32'd0;
            drop_count                <= 32'd0;
            good_window_count         <= 32'd0;
        end else begin
            pkt_done_toggle_meta_jclk <= {
                pkt_done_toggle_meta_jclk[1:0],
                pkt_done_toggle_eth
            };

            pkt_done_seen <= 1'b0;
            if (done_pulse_jclk) begin
                pkt_done_seen <= 1'b1;
                wait_pkt_done <= 1'b0;
            end

            if (link_good) begin
                if (capture_good_count < LINK_GOOD_TICKS) begin
                    capture_good_count <= capture_good_count + 1'b1;
                end
                if (good_window_count != 32'hffffffff) begin
                    good_window_count <= good_window_count + 1'b1;
                end

                if (repeat_count < REPEAT_TICKS) begin
                    repeat_count <= repeat_count + 1'b1;
                end

                if (capture_active && !sample_valid) begin
                    if (sample_gap_count >= (SAMPLE_GAP_LIMIT - 1)) begin
                        capture_arm_jclk <= 1'b0;
                        capture_active   <= 1'b0;
                        sample_gap_count <= 16'd0;
                        wr_addr          <= {CAPTURE_ADDR_W{1'b0}};
                        drop_count       <= drop_count + 1'b1;
                    end else begin
                        sample_gap_count <= sample_gap_count + 1'b1;
                    end
                end else if (capture_arm_jclk && sample_valid) begin
                    capture_arm_jclk <= 1'b0;
                    capture_active <= 1'b1;
                    sample_gap_count <= 16'd0;
                    wr_addr <= {CAPTURE_ADDR_W{1'b0}};
                end else if (capture_active && sample_valid) begin
                    sample_gap_count <= 16'd0;
                    if (wr_addr == LAST_WR_ADDR) begin
                        capture_active <= 1'b0;
                        wait_pkt_done  <= 1'b1;
                        send_toggle_jclk <= ~send_toggle_jclk;
                        capture_count <= capture_count + 1'b1;
                        repeat_count <= 32'd0;
                    end else begin
                        wr_addr <= wr_addr + 1'b1;
                    end
                end else if (!wait_pkt_done &&
                             !capture_active &&
                             !capture_arm_jclk &&
                             (capture_good_count >= LINK_GOOD_TICKS) &&
                             (repeat_count >= REPEAT_TICKS)) begin
                    capture_arm_jclk <= 1'b1;
                    sample_gap_count <= 16'd0;
                    wr_addr <= {CAPTURE_ADDR_W{1'b0}};
                    capture_id <= capture_id + 1'b1;
                end
            end else begin
                capture_good_count <= 32'd0;
                good_window_count  <= 32'd0;
                repeat_count       <= 32'd0;
                if (capture_active || capture_arm_jclk) begin
                    capture_arm_jclk <= 1'b0;
                    capture_active <= 1'b0;
                    sample_gap_count <= 16'd0;
                    wr_addr <= {CAPTURE_ADDR_W{1'b0}};
                    drop_count <= drop_count + 1'b1;
                end
            end
        end
    end

endmodule
