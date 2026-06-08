// JESD payload 样点映射模块。
//
// 输入 data_in 来自 pattern_gen_256.v，格式为：
//   DAC0: data_in[255:192]，4 个 16-bit 样点
//   DAC1: data_in[191:128]，4 个 16-bit 样点
//   DAC2: data_in[127:64] ，4 个 16-bit 样点
//   DAC3: data_in[63:0]   ，4 个 16-bit 样点
//
// 输出 data_out0/data_out1 分别送到两组 Xilinx JESD204C TX IP。
// 本模块只做字节重排，不改变样点数值、不做 14-bit/16-bit 裁剪。
// 当前链路按 16-bit two's-complement sample slot 送入 AD9173。
module tx_mapper (
    input  wire [255:0] data_in,
    output wire         data_in_ready,
    output wire [127:0] data_out0,
    output wire [127:0] data_out1,
    output wire [15:0]  dac0_sample0_ila,
    output wire [15:0]  dac1_sample0_ila,
    output wire [15:0]  dac2_sample0_ila,
    output wire [15:0]  dac3_sample0_ila
);
    wire [15:0] dac0_sample0;
    wire [15:0] dac0_sample1;
    wire [15:0] dac0_sample2;
    wire [15:0] dac0_sample3;
    wire [15:0] dac1_sample0;
    wire [15:0] dac1_sample1;
    wire [15:0] dac1_sample2;
    wire [15:0] dac1_sample3;
    wire [15:0] dac2_sample0;
    wire [15:0] dac2_sample1;
    wire [15:0] dac2_sample2;
    wire [15:0] dac2_sample3;
    wire [15:0] dac3_sample0;
    wire [15:0] dac3_sample1;
    wire [15:0] dac3_sample2;
    wire [15:0] dac3_sample3;
    wire [31:0] lane0_i;
    wire [31:0] lane1_i;
    wire [31:0] lane2_i;
    wire [31:0] lane3_i;
    wire [31:0] lane4_i;
    wire [31:0] lane5_i;
    wire [31:0] lane6_i;
    wire [31:0] lane7_i;

    assign data_in_ready    = 1'b1;
    assign dac0_sample0_ila = dac0_sample0;
    assign dac1_sample0_ila = dac1_sample0;
    assign dac2_sample0_ila = dac2_sample0;
    assign dac3_sample0_ila = dac3_sample0;

    // 从 256-bit 总线中取出每个 DAC converter 的 4 个连续样点。
    assign dac0_sample0 = data_in[207:192];
    assign dac0_sample1 = data_in[223:208];
    assign dac0_sample2 = data_in[239:224];
    assign dac0_sample3 = data_in[255:240];
    assign dac1_sample0 = data_in[143:128];
    assign dac1_sample1 = data_in[159:144];
    assign dac1_sample2 = data_in[175:160];
    assign dac1_sample3 = data_in[191:176];
    assign dac2_sample0 = data_in[79:64];
    assign dac2_sample1 = data_in[95:80];
    assign dac2_sample2 = data_in[111:96];
    assign dac2_sample3 = data_in[127:112];
    assign dac3_sample0 = data_in[15:0];
    assign dac3_sample1 = data_in[31:16];
    assign dac3_sample2 = data_in[47:32];
    assign dac3_sample3 = data_in[63:48];

    // JESD lane 打包方式：
    // 每个 DAC converter 使用两条 byte lane，一条放 4 个样点的高 8 bit，
    // 另一条放 4 个样点的低 8 bit。这样一个 16-bit 样点槽完整保留。
    // 如果上游使用 14-bit 有效数据，应保证低 2 bit 已经按要求处理。
    assign lane0_i = {dac0_sample3[15:8], dac0_sample2[15:8], dac0_sample1[15:8], dac0_sample0[15:8]};
    assign lane1_i = {dac0_sample3[7:0],  dac0_sample2[7:0],  dac0_sample1[7:0],  dac0_sample0[7:0]};
    assign lane2_i = {dac1_sample3[15:8], dac1_sample2[15:8], dac1_sample1[15:8], dac1_sample0[15:8]};
    assign lane3_i = {dac1_sample3[7:0],  dac1_sample2[7:0],  dac1_sample1[7:0],  dac1_sample0[7:0]};
    assign lane4_i = {dac2_sample3[15:8], dac2_sample2[15:8], dac2_sample1[15:8], dac2_sample0[15:8]};
    assign lane5_i = {dac2_sample3[7:0],  dac2_sample2[7:0],  dac2_sample1[7:0],  dac2_sample0[7:0]};
    assign lane6_i = {dac3_sample3[15:8], dac3_sample2[15:8], dac3_sample1[15:8], dac3_sample0[15:8]};
    assign lane7_i = {dac3_sample3[7:0],  dac3_sample2[7:0],  dac3_sample1[7:0],  dac3_sample0[7:0]};

    // link0 承载 DAC0/DAC1，link1 承载 DAC2/DAC3。
    assign data_out0 = {lane3_i, lane2_i, lane1_i, lane0_i};
    assign data_out1 = {lane7_i, lane6_i, lane5_i, lane4_i};

endmodule
