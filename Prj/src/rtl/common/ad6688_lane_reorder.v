`timescale 1ns/1ps

// AD6688 JESD RX lane mapping shim before applying the VCK190
// rx_mapper-compatible sample extraction.
//
// Board netlist evidence, 2026-05-27:
//   SERDOUT6 -> FMC DP0_M2C -> FPGA adc_rx[0]
//   SERDOUT7 -> FMC DP1_M2C -> FPGA adc_rx[1]
//   SERDOUT5 -> FMC DP2_M2C -> FPGA adc_rx[2]
//   SERDOUT4 -> FMC DP3_M2C -> FPGA adc_rx[3]
//   SERDOUT2 -> FMC DP4_M2C -> FPGA adc_rx[4]
//   SERDOUT0 -> FMC DP5_M2C -> FPGA adc_rx[5]
//   SERDOUT1 -> FMC DP6_M2C -> FPGA adc_rx[6]
//   SERDOUT3 -> FMC DP7_M2C -> FPGA adc_rx[7]
//
// AD6688 register values programmed by ad6688_init_table compensate that
// physical routing:
//   0x05B2 = 0x65: SERDOUT0 -> logical5, SERDOUT1 -> logical6
//   0x05B3 = 0x74: SERDOUT2 -> logical4, SERDOUT3 -> logical7
//   0x05B5 = 0x23: SERDOUT4 -> logical3, SERDOUT5 -> logical2
//   0x05B6 = 0x10: SERDOUT6 -> logical0, SERDOUT7 -> logical1
//
// Therefore the Xilinx JESD RX core already presents logical lane N at
// tdata[(32*N)+31:32*N].  The PL reorder stage is intentionally identity.
//
// The Xilinx JESD RX core presents lane N at tdata[(32*N)+31:32*N].
module ad6688_lane_reorder (
    input  wire [255:0] physical_tdata,
    output wire [255:0] logical_tdata
);

    assign logical_tdata = physical_tdata;

endmodule
