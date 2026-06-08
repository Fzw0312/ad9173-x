// Xilinx JESD204C TX link1 初始化表。
//
// link1 连接 AD9173 的 SERDIN4..7，承载 DAC2/DAC3 的 payload。
// 参数必须与 link0、AD9173 deframer 和 HMC7044 输出时钟保持一致：
// GT refclk/core clock 为 245.76 MHz，线速为 9.8304 Gbps，每个
// DAC converter 每拍 4 个 16-bit 样点槽。
//
// 板上 quad227 的物理 lane 顺序与逻辑顺序不同，最终顺序由
// ad9173_init_table.v 中的 AD9173 crossbar 寄存器配合修正。
module jesd204_tx_init_table_link1 (
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
            // logical lane4..7 绑定到第二组 JESD TX 物理 lane。
            8'd4:  cmd = {OP_WRITE,   12'h404, 32'h00030004, 12'd0};
            8'd5:  cmd = {OP_WRITE,   12'h484, 32'h00030005, 12'd0};
            8'd6:  cmd = {OP_WRITE,   12'h504, 32'h00030006, 12'd0};
            8'd7:  cmd = {OP_WRITE,   12'h584, 32'h00030007, 12'd0};
            // 拉起/释放 JESD IP 内部 reset，让配置生效并启动链路。
            8'd8:  cmd = {OP_WRITE,   12'h020, 32'h00000001, 12'd0};
            8'd9:  cmd = {OP_WAIT_MS, 40'd0,   16'd1};
            8'd10: cmd = {OP_WRITE,   12'h020, 32'h00000000, 12'd0};
            8'd11: cmd = {OP_WAIT_MS, 40'd0,   16'd1};
            default: cmd = {OP_END, 56'd0};
        endcase
    end

endmodule
