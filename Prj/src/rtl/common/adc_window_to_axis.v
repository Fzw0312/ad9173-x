// Fixed-window ADC capture to AXI-Stream.
//
// The input has no backpressure because JESD RX produces continuous samples.
// If m_axis_tready is deasserted during a capture, this module drops that
// sample beat, increments overflow_count, and keeps the capture length in
// sample-beat units. For the DDR implementation, place an async FIFO between
// this module and the AXI/MIG clock domain or replace the output with a wider
// FIFO-facing stream.
module adc_window_to_axis #(
    parameter integer DATA_WIDTH = 64
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  arm,
    input  wire [31:0]           capture_beats,
    input  wire                  sample_valid,
    input  wire [DATA_WIDTH-1:0] sample_data,
    output reg                   m_axis_tvalid,
    input  wire                  m_axis_tready,
    output reg  [DATA_WIDTH-1:0] m_axis_tdata,
    output wire [DATA_WIDTH/8-1:0] m_axis_tkeep,
    output reg                   m_axis_tlast,
    output reg                   busy,
    output reg                   done,
    output reg                   overflow,
    output reg  [31:0]           captured_beats,
    output reg  [31:0]           overflow_count,
    output reg  [31:0]           dropped_when_idle_count
);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_RUN  = 2'd1;
    localparam [1:0] ST_HOLD = 2'd2;

    reg [1:0] state;
    reg       arm_q;
    wire      arm_rise = arm && !arm_q;
    wire      final_beat = (captured_beats + 1'b1) >= capture_beats;

    assign m_axis_tkeep = {DATA_WIDTH/8{1'b1}};

    always @(posedge clk) begin
        if (rst) begin
            state                   <= ST_IDLE;
            arm_q                   <= 1'b0;
            m_axis_tvalid           <= 1'b0;
            m_axis_tdata            <= {DATA_WIDTH{1'b0}};
            m_axis_tlast            <= 1'b0;
            busy                    <= 1'b0;
            done                    <= 1'b0;
            overflow                <= 1'b0;
            captured_beats          <= 32'd0;
            overflow_count          <= 32'd0;
            dropped_when_idle_count <= 32'd0;
        end else begin
            arm_q <= arm;
            done  <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy          <= 1'b0;
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                    if (sample_valid) begin
                        dropped_when_idle_count <= dropped_when_idle_count + 1'b1;
                    end
                    if (arm_rise && (capture_beats != 32'd0)) begin
                        busy           <= 1'b1;
                        overflow       <= 1'b0;
                        captured_beats <= 32'd0;
                        state          <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    busy <= 1'b1;
                    if (m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast  <= 1'b0;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        state         <= ST_IDLE;
                        if (sample_valid) begin
                            overflow       <= 1'b1;
                            overflow_count <= overflow_count + 1'b1;
                        end
                    end else begin
                        if (m_axis_tvalid && m_axis_tready) begin
                            m_axis_tvalid <= 1'b0;
                            m_axis_tlast  <= 1'b0;
                        end

                        if (sample_valid) begin
                            if (m_axis_tvalid && !m_axis_tready) begin
                                overflow       <= 1'b1;
                                overflow_count <= overflow_count + 1'b1;
                            end else begin
                                m_axis_tvalid  <= 1'b1;
                                m_axis_tdata   <= sample_data;
                                m_axis_tlast   <= final_beat;
                                captured_beats <= captured_beats + 1'b1;
                                if (final_beat) begin
                                    state <= ST_HOLD;
                                end
                            end
                        end
                    end
                end

                ST_HOLD: begin
                    busy <= 1'b1;
                    if (sample_valid) begin
                        overflow       <= 1'b1;
                        overflow_count <= overflow_count + 1'b1;
                    end
                    if (m_axis_tvalid && m_axis_tready) begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast  <= 1'b0;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        state         <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
