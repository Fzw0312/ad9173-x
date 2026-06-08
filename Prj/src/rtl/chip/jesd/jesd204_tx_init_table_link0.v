// Xilinx JESD204C TX link0 初始化表。
//
// link0 连接 AD9173 的 SERDIN0..3，承载 DAC0/DAC1 的 payload。
// JESD IP 的 GT refclk/core clock 均按 245.76 MHz 配置，线速为
// 9.8304 Gbps。每个 DAC converter 在 245.76 MHz core clock 下每拍
// 送 4 个 16-bit 样点槽，因此 payload 样点率为 983.04 MSPS。
//
// 这里只配置 Xilinx JESD204C TX IP 自身；AD9173 deframer 和 lane
// crossbar 的 SPI 配置在 ad9173_init_table.v 中完成。
module jesd204_tx_init_table_link0 (
    input  wire [7:0]  addr,
    output reg  [63:0] cmd
);

    localparam [7:0] OP_WRITE   = 8'h01;
    localparam [7:0] OP_WAIT_MS = 8'h02;
    localparam [7:0] OP_END     = 8'hff;

    always @(*) begin
        case (addr)
            // 使能 4 条 TX lane，并写入与 AD9173 deframer 匹配的 JESD 参数。
            8'd0:  cmd = {OP_WRITE,   12'h040, 32'h0000000f, 12'd0};
            8'd1:  cmd = {OP_WRITE,   12'h03c, 32'h03021f00, 12'd0};
            8'd2:  cmd = {OP_WRITE,   12'h074, 32'h000f0f01, 12'd0};
            8'd3:  cmd = {OP_WRITE,   12'h078, 32'h00010000, 12'd0};
            // logical lane0..3 绑定到 link0 的物理 lane0..3。
            8'd4:  cmd = {OP_WRITE,   12'h404, 32'h00030000, 12'd0};
            8'd5:  cmd = {OP_WRITE,   12'h484, 32'h00030001, 12'd0};
            8'd6:  cmd = {OP_WRITE,   12'h504, 32'h00030002, 12'd0};
            8'd7:  cmd = {OP_WRITE,   12'h584, 32'h00030003, 12'd0};
            // 拉起/释放 JESD IP 内部 reset，让配置生效并启动链路。
            8'd8:  cmd = {OP_WRITE,   12'h020, 32'h00000001, 12'd0};
            8'd9:  cmd = {OP_WAIT_MS, 40'd0,   16'd1};
            8'd10: cmd = {OP_WRITE,   12'h020, 32'h00000000, 12'd0};
            8'd11: cmd = {OP_WAIT_MS, 40'd0,   16'd1};
            default: cmd = {OP_END, 56'd0};
        endcase
    end

endmodule
