// AD9173 初始化寄存器表。
//
// 这个文件只描述 AD9173 上电后需要写入的 SPI 寄存器序列，实际 SPI
// 执行动作在 ad9173_init.v 中完成。这里的配置覆盖：
// - AD9173 复位、SPI 模式和启动状态
// - DAC PLL / DLL / SERDES 上电和锁定
// - main datapath 12x 插值、main NCO 初值
// - JESD204 deframer、lane crossbar、同步释放
//
// 当前工程的 AD9173 工作时钟规划：
// - HMC7044 ch6 输出 DAC_CLKIN = 491.52 MHz，送入 AD9173 CLKIN+/-。
// - AD9173 使用片内 DAC PLL，不旁路 PLL。
// - DAC PLL 参数：
//     0x793[1:0] = 0，M_DIVIDER = 1，PFD = 491.52 MHz / 1。
//     0x799[5:0] = 3，N_DIVIDER = 3。
//     0x094[1:0] = 0，PLL VCO 不再做 /2 或 /3 输出分频。
//   按数据手册公式：
//     fDAC = 8 * N_DIVIDER * fREF / M_DIVIDER / output_div
//          = 8 * 3 * 491.52 MHz / 1 / 1
//          = 11.79648 GHz。
// - FPGA 侧 JESD core clock = 245.76 MHz，每拍每个 converter 送 4 个
//   16-bit 样点槽，所以 AD9173 看到的 payload 采样率是 983.04 MSPS。
// - main datapath 做 12x 插值：983.04 MSPS * 12 = 11.79648 GSPS，
//   与 DAC PLL 生成的 fDAC 对齐。
//
// 当前 PL 到 AD9173 的 JESD payload 使用 16-bit two's-complement sample
// slot。工程没有在 FPGA 侧把样点裁成 14 bit；如果需要 14-bit 有效码，
// 应在上游生成时左对齐到 [15:2]，并清零低 2 bit。
module ad9173_init_table (
    input  wire [7:0] addr,
    output reg  [31:0] cmd
);

    localparam [7:0] OP_WRITE   = 8'h01;
    localparam [7:0] OP_WAIT_MS = 8'h02;
    localparam [7:0] OP_END     = 8'hff;

    always @(*) begin
        case (addr)
            // 软件复位并切到后续初始化需要的 SPI 访问模式。
            8'd0:  cmd = {OP_WRITE, 16'h0000, 8'h81};
            8'd1:  cmd = {OP_WRITE, 16'h0000, 8'h24};
            8'd2:  cmd = {OP_WRITE, 16'h0090, 8'h03};
            8'd3:  cmd = {OP_WRITE, 16'h0203, 8'h03};
            8'd4:  cmd = {OP_WRITE, 16'h0091, 8'h00};
            8'd5:  cmd = {OP_WRITE, 16'h0206, 8'h01};
            8'd6:  cmd = {OP_WRITE, 16'h0705, 8'h01};
            8'd7:  cmd = {OP_WAIT_MS, 16'h0000, 8'd10};
            8'd8:  cmd = {OP_WRITE, 16'h0090, 8'h00};
            8'd9:  cmd = {OP_WRITE, 16'h0095, 8'h00};
            // DAC PLL / 时钟树相关配置。HMC7044 的 491.52 MHz DAC_CLKIN
            // 会送入 AD9173，由这里的寄存器配置 AD9173 内部时钟链路。
            //
            // 0x0796/0x07A0/0x0797/0x0798/0x07A2 是 AD9173 推荐的
            // DAC PLL required write，用于 PLL 环路/VCO 校准相关内部控制。
            // 0x0794[5:0] 是 DACPLL_CP，这里写 0x08，设置 PLL charge pump。
            8'd10: cmd = {OP_WRITE, 16'h0790, 8'h00};
            8'd11: cmd = {OP_WRITE, 16'h0791, 8'h00};
            8'd12: cmd = {OP_WRITE, 16'h0796, 8'he5};
            8'd13: cmd = {OP_WRITE, 16'h07a0, 8'hbc};
            8'd14: cmd = {OP_WRITE, 16'h0794, 8'h08};
            8'd15: cmd = {OP_WRITE, 16'h0797, 8'h10};
            8'd16: cmd = {OP_WRITE, 16'h0797, 8'h20};
            8'd17: cmd = {OP_WRITE, 16'h0798, 8'h10};
            8'd18: cmd = {OP_WRITE, 16'h07a2, 8'h7f};
            8'd19: cmd = {OP_WAIT_MS, 16'h0000, 8'd200};
            // 0x0799 = 0xC3：
            //   [5:0] N_DIVIDER = 3，用于 DAC PLL 倍频公式中的 N；
            //   [7:6] ADC_CLK_DIVIDER 编码 = 3，即 ADC/CLKOUT 输出分频 /4。
            //   该字段不参与 fDAC 计算，只影响观测 ADC clock driver 路径。
            // 0x0793 = 0x18：
            //   [7:2] 保持推荐默认 0x06；
            //   [1:0] M_DIVIDER-1 = 0，即 M_DIVIDER = 1。
            // 因此 PLL VCO/fDAC = 8 * 3 * 491.52 MHz / 1 = 11.79648 GHz。
            8'd20: cmd = {OP_WRITE, 16'h0799, 8'hc3};
            8'd21: cmd = {OP_WRITE, 16'h0793, 8'h18};
            // 0x0094 = 0：不启用 PLL VCO /2 或 /3 输出分频，DAC clock
            // 直接等于 11.79648 GHz PLL VCO。
            // 0x0095 = 0：不 bypass 片内 PLL，使用上面的 PLL 倍频结果。
            8'd22: cmd = {OP_WRITE, 16'h0094, 8'h00};
            // 0x0792 先置位再清零，用于释放/触发 DAC PLL VCO divider
            // 和校准相关复位，随后等待 PLL 重新稳定。
            8'd23: cmd = {OP_WRITE, 16'h0792, 8'h02};
            8'd24: cmd = {OP_WRITE, 16'h0792, 8'h00};
            8'd25: cmd = {OP_WAIT_MS, 16'h0000, 8'd200};
            // DAC DLL / clock receiver 相关启动序列。当前 fDAC > 4.5 GHz，
            // 按 AD9173 推荐流程使用 0x00C1=0x68/0x69 进入 DLL search/lock。
            8'd26: cmd = {OP_WRITE, 16'h00c0, 8'h00};
            8'd27: cmd = {OP_WRITE, 16'h00db, 8'h00};
            8'd28: cmd = {OP_WRITE, 16'h00db, 8'h01};
            8'd29: cmd = {OP_WRITE, 16'h00db, 8'h00};
            8'd30: cmd = {OP_WRITE, 16'h00c1, 8'h68};
            8'd31: cmd = {OP_WRITE, 16'h00c1, 8'h69};
            8'd32: cmd = {OP_WRITE, 16'h00c7, 8'h01};
            8'd33: cmd = {OP_WRITE, 16'h0050, 8'h2a};
            8'd34: cmd = {OP_WRITE, 16'h0061, 8'h68};
            8'd35: cmd = {OP_WRITE, 16'h0051, 8'h82};
            8'd36: cmd = {OP_WRITE, 16'h0051, 8'h83};
            8'd37: cmd = {OP_WRITE, 16'h0081, 8'h03};
            // main datapath、interpolation 和 JESD deframer 相关配置。
            // 这里决定 JESD 样点进入 AD9173 后如何进入 DAC 数据通路。
            // 当前工程不在 FPGA 侧改变 DAC 物理采样时钟；频率规划由
            // JESD payload 样点率 983.04 MSPS、main datapath 12x 插值、
            // 以及可选 main NCO 搬移共同决定。
            8'd38: cmd = {OP_WRITE, 16'h0100, 8'h00};
            8'd39: cmd = {OP_WRITE, 16'h0110, 8'h28};
            8'd40: cmd = {OP_WRITE, 16'h0111, 8'hc1};
            8'd41: cmd = {OP_WRITE, 16'h0084, 8'h40};
            8'd42: cmd = {OP_WRITE, 16'h0312, 8'h00};
            8'd43: cmd = {OP_WRITE, 16'h0300, 8'h0b};
            8'd44: cmd = {OP_WRITE, 16'h0475, 8'h09};
            8'd45: cmd = {OP_WRITE, 16'h0453, 8'h03};
            8'd46: cmd = {OP_WRITE, 16'h0458, 8'h2f};
            8'd47: cmd = {OP_WRITE, 16'h0475, 8'h01};
            8'd48: cmd = {OP_WRITE, 16'h0300, 8'h0f};
            8'd49: cmd = {OP_WRITE, 16'h0475, 8'h09};
            8'd50: cmd = {OP_WRITE, 16'h0453, 8'h03};
            8'd51: cmd = {OP_WRITE, 16'h0458, 8'h2f};
            8'd52: cmd = {OP_WRITE, 16'h0475, 8'h01};
            8'd53: cmd = {OP_WRITE, 16'h0008, 8'hff};
            // main datapath 使用 12x 插值。按 AD9173 数据手册要求，
            // 12x 模式下保留 main NCO 使能，但 FTW 写 0 表示不搬频。
            // 普通 JESD/RAM 输出时，频率主要由 FPGA payload 样点决定。
            8'd54: cmd = {OP_WRITE, 16'h0112, 8'h08};
            8'd55: cmd = {OP_WRITE, 16'h0113, 8'h00};
            8'd56: cmd = {OP_WRITE, 16'h0114, 8'h00};
            8'd57: cmd = {OP_WRITE, 16'h0115, 8'h00};
            8'd58: cmd = {OP_WRITE, 16'h0116, 8'h00};
            8'd59: cmd = {OP_WRITE, 16'h0117, 8'h00};
            8'd60: cmd = {OP_WRITE, 16'h0118, 8'h00};
            8'd61: cmd = {OP_WRITE, 16'h0119, 8'h00};
            8'd62: cmd = {OP_WRITE, 16'h011c, 8'h00};
            8'd63: cmd = {OP_WRITE, 16'h011d, 8'h00};
            8'd64: cmd = {OP_WRITE, 16'h0113, 8'h01};
            8'd65: cmd = {OP_WRITE, 16'h014b, 8'h00};
            // JESD deframer 参数。这里与 FPGA 侧 JESD IP 配置对应：
            // 两条 link，每条 4 lane，总共 8 lane，payload 为 16-bit 样点槽。
            8'd66: cmd = {OP_WRITE, 16'h0240, 8'haa};
            8'd67: cmd = {OP_WRITE, 16'h0241, 8'haa};
            8'd68: cmd = {OP_WRITE, 16'h0242, 8'h55};
            8'd69: cmd = {OP_WRITE, 16'h0243, 8'h55};
            8'd70: cmd = {OP_WRITE, 16'h0244, 8'h1f};
            8'd71: cmd = {OP_WRITE, 16'h0245, 8'h1f};
            8'd72: cmd = {OP_WRITE, 16'h0246, 8'h1f};
            8'd73: cmd = {OP_WRITE, 16'h0247, 8'h1f};
            8'd74: cmd = {OP_WRITE, 16'h0248, 8'h1f};
            8'd75: cmd = {OP_WRITE, 16'h0249, 8'h1f};
            8'd76: cmd = {OP_WRITE, 16'h024a, 8'h1f};
            8'd77: cmd = {OP_WRITE, 16'h024b, 8'h1f};
            8'd78: cmd = {OP_WRITE, 16'h0201, 8'h00};
            8'd79: cmd = {OP_WRITE, 16'h0203, 8'h00};
            8'd80: cmd = {OP_WRITE, 16'h0253, 8'h01};
            8'd81: cmd = {OP_WRITE, 16'h0254, 8'h01};
            8'd82: cmd = {OP_WRITE, 16'h0210, 8'h16};
            8'd83: cmd = {OP_WRITE, 16'h0216, 8'h05};
            8'd84: cmd = {OP_WRITE, 16'h0212, 8'hff};
            8'd85: cmd = {OP_WRITE, 16'h0212, 8'h00};
            8'd86: cmd = {OP_WRITE, 16'h0210, 8'h87};
            8'd87: cmd = {OP_WRITE, 16'h0216, 8'h11};
            8'd88: cmd = {OP_WRITE, 16'h0213, 8'h01};
            8'd89: cmd = {OP_WRITE, 16'h0213, 8'h00};
            8'd90: cmd = {OP_WRITE, 16'h0200, 8'h00};
            8'd91: cmd = {OP_WAIT_MS, 16'h0000, 8'd150};
            8'd92: cmd = {OP_WRITE, 16'h0210, 8'h86};
            8'd93: cmd = {OP_WRITE, 16'h0216, 8'h40};
            8'd94: cmd = {OP_WRITE, 16'h0213, 8'h01};
            8'd95: cmd = {OP_WRITE, 16'h0213, 8'h00};
            8'd96: cmd = {OP_WRITE, 16'h0210, 8'h86};
            8'd97: cmd = {OP_WRITE, 16'h0216, 8'h00};
            8'd98: cmd = {OP_WRITE, 16'h0213, 8'h01};
            8'd99: cmd = {OP_WRITE, 16'h0213, 8'h00};
            8'd100: cmd = {OP_WRITE, 16'h0210, 8'h87};
            8'd101: cmd = {OP_WRITE, 16'h0216, 8'h01};
            8'd102: cmd = {OP_WRITE, 16'h0213, 8'h01};
            8'd103: cmd = {OP_WRITE, 16'h0213, 8'h00};
            8'd104: cmd = {OP_WRITE, 16'h0280, 8'h05};
            8'd105: cmd = {OP_WRITE, 16'h0280, 8'h01};
            8'd106: cmd = {OP_WRITE, 16'h005a, 8'hff};
            // KU5P 板级 lane 映射：
            //   Link0 逻辑 lane 0..3 -> SERDIN0..3
            //   Link1 逻辑 lane 4..7 -> quad227 的物理顺序
            //   SERDIN5, SERDIN7, SERDIN6, SERDIN4
            // 下面 0x0308..0x030B 把物理连线顺序映射回逻辑 lane 顺序。
            8'd107: cmd = {OP_WRITE, 16'h0308, 8'h08};
            8'd108: cmd = {OP_WRITE, 16'h0309, 8'h1a};
            8'd109: cmd = {OP_WRITE, 16'h030a, 8'h3d};
            8'd110: cmd = {OP_WRITE, 16'h030b, 8'h26};
            8'd111: cmd = {OP_WRITE, 16'h0306, 8'h0c};
            8'd112: cmd = {OP_WRITE, 16'h0307, 8'h0c};
            8'd113: cmd = {OP_WRITE, 16'h0304, 8'h00};
            8'd114: cmd = {OP_WRITE, 16'h0305, 8'h01};
            8'd115: cmd = {OP_WRITE, 16'h003b, 8'hf1};
            8'd116: cmd = {OP_WRITE, 16'h003a, 8'h02};
            8'd117: cmd = {OP_WRITE, 16'h0300, 8'h0b};
            8'd118: cmd = {OP_WRITE, 16'h0085, 8'h13};
            8'd119: cmd = {OP_WRITE, 16'h01de, 8'h03};
            8'd120: cmd = {OP_WRITE, 16'h0008, 8'hc0};
            8'd121: cmd = {OP_WRITE, 16'h0596, 8'h0c};
            // Link0/Link1 lanes are clean with normal logical polarity.
            // Crossbar sweep kept the identity Link0 order and showed
            // polarity 0x00 as the full-pass candidate.
            8'd122: cmd = {OP_WRITE, 16'h0334, 8'h00};
            // Re-release both QBD deframers after the final lane crossbar
            // and polarity writes so ILAS is captured with the KU5P mapping.
            8'd123: cmd = {OP_WRITE, 16'h0300, 8'h0b};
            8'd124: cmd = {OP_WRITE, 16'h0475, 8'h09};
            8'd125: cmd = {OP_WRITE, 16'h0453, 8'h03};
            8'd126: cmd = {OP_WRITE, 16'h0458, 8'h2f};
            8'd127: cmd = {OP_WRITE, 16'h0475, 8'h01};
            8'd128: cmd = {OP_WAIT_MS, 16'h0000, 8'd1};
            8'd129: cmd = {OP_WRITE, 16'h0300, 8'h0f};
            8'd130: cmd = {OP_WRITE, 16'h0475, 8'h09};
            8'd131: cmd = {OP_WRITE, 16'h0453, 8'h03};
            8'd132: cmd = {OP_WRITE, 16'h0458, 8'h2f};
            8'd133: cmd = {OP_WRITE, 16'h0475, 8'h01};
            8'd134: cmd = {OP_WAIT_MS, 16'h0000, 8'd5};
            8'd135: cmd = {OP_WRITE, 16'h0300, 8'h0b};
            8'd136: cmd = {OP_END, 16'h0000, 8'h00};
            default: cmd = {OP_END, 16'h0000, 8'h00};
        endcase
    end

endmodule
