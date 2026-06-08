// AD9173 初始化与运行时配置模块。
//
// 上电时，本模块通过 SPI 执行 ad9173_init_table.v，完成 AD9173 的
// PLL、JESD deframer、插值、lane 映射等基础配置；初始化后会回读
// 芯片 ID、boot、PLL、DLL、SERDES 等状态，确认 DAC 已经进入可运行状态。
//
// 运行时，VIO/UDP 会通过 runtime_apply_toggle 触发本模块重新写
// AD9173 的 main NCO、channel NCO 和幅度寄存器。JESD/RAM 样点本身
// 不在这里生成，而是在 pattern_gen_256.v/tx_mapper.v 中生成和打包。
module ad9173_init #(
    parameter integer CLK_DIV  = 32,
    parameter integer MS_TICKS = 100000
) (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire sdo,
    input  wire sdio_i,
    input  wire runtime_nco_only,
    input  wire [15:0] runtime_ch0_amp,
    input  wire [47:0] runtime_ch0_ftw,
    input  wire [47:0] runtime_main0_ftw,
    input  wire [15:0] runtime_ch1_amp,
    input  wire [47:0] runtime_ch1_ftw,
    input  wire runtime_apply_toggle,
    output reg  busy,
    output reg  done,
    output reg  ok,
    output reg  fail,
    output reg  [31:0] status_dbg,
    output reg  [31:0] sanity_dbg,
    output wire [31:0] debug_dbg,
    output wire [31:0] runtime_dbg,
    output wire sclk,
    output wire cs_n,
    output wire sdio_o,
    output wire sdio_oe
);

    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_RUN_TABLE   = 4'd1;
    localparam [3:0] ST_READ_START  = 4'd2;
    localparam [3:0] ST_READ_WAIT   = 4'd3;
    localparam [3:0] ST_RETRY_WAIT  = 4'd4;
    localparam [3:0] ST_DONE        = 4'd5;
    localparam [3:0] ST_FAIL        = 4'd6;
    localparam [3:0] ST_WRITE_START = 4'd7;
    localparam [3:0] ST_WRITE_WAIT  = 4'd8;
    localparam [3:0] ST_DEBUG_START = 4'd9;
    localparam [3:0] ST_DEBUG_WAIT  = 4'd10;
    localparam [3:0] ST_PRE_RESET_START = 4'd11;
    localparam [3:0] ST_PRE_RESET_WAIT  = 4'd12;
    localparam [3:0] ST_PRE_4WIRE_START = 4'd13;
    localparam [3:0] ST_PRE_4WIRE_WAIT  = 4'd14;

    localparam [3:0] CHECK_ID_TYPE      = 4'd0;
    localparam [3:0] CHECK_ID_L         = 4'd1;
    localparam [3:0] CHECK_ID_H         = 4'd2;
    localparam [3:0] CHECK_SCR_WR_5A    = 4'd3;
    localparam [3:0] CHECK_SCR_RD_5A    = 4'd4;
    localparam [3:0] CHECK_SCR_WR_A5    = 4'd5;
    localparam [3:0] CHECK_SCR_RD_A5    = 4'd6;
    localparam [3:0] CHECK_BOOT         = 4'd7;
    localparam [3:0] CHECK_PLL          = 4'd8;
    localparam [3:0] CHECK_DLL          = 4'd9;
    localparam [3:0] CHECK_SERDES       = 4'd10;

    localparam [3:0] MAX_RETRY = 4'd10;
    localparam [31:0] DEBUG_GAP_TICKS = 32'd1000;
    // channel NCO 约 300 MHz 的 FTW 阈值。RF 高频输出时，如果超过
    // 这个范围或者 GUI/VIO 显式给了 main NCO FTW，就改用 main NCO 搬频。
    localparam [47:0] CH_NCO_300MHZ_FTW   = 48'h341552F1CC2F;

    wire [7:0]  table_addr;
    wire [31:0] table_cmd;
    wire        table_spi_start;
    wire [23:0] spi_word;
    wire        table_spi_busy;
    wire        table_spi_done;
    wire        spi_write_start;
    wire [23:0] spi_write_word;
    wire        spi_write_busy;
    wire        spi_write_done;
    wire        table_busy;
    wire        table_done;
    wire        read_busy;
    wire        read_done;
    wire [7:0]  read_data;
    wire        read4_busy;
    wire        read4_done;
    wire [7:0]  read4_data;
    wire        read3_busy;
    wire        read3_done;
    wire [7:0]  read3_data;
    wire        runtime_ch0_use_main_nco;
    wire [47:0] runtime_nco_main0_ftw;
    wire [47:0] runtime_jesd_main0_ftw;
    wire [47:0] runtime_main1_ftw;
    wire [47:0] runtime_ch0_channel_ftw;
    wire        write_sclk;
    wire        write_cs_n;
    wire        write_sdio;
    wire        read_sclk;
    wire        read_cs_n;
    wire        read_sdio;
    wire        read3_sclk;
    wire        read3_cs_n;
    wire        read3_sdio_o;
    wire        read3_sdio_oe;

    reg         table_start;
    reg         read_start;
    reg         direct_write_start;
    reg [23:0]  direct_write_word;
    reg         runtime_write_start;
    reg [23:0]  runtime_write_word;
    reg         runtime_apply_meta;
    reg         runtime_apply_sync;
    reg         runtime_apply_sync_d1;
    reg         runtime_apply_pending;
    reg         runtime_update_active;
    reg         runtime_update_nco_only;
    reg         init_done_latched;
    reg [5:0]   runtime_update_index;
    reg [3:0]   state;
    reg [3:0]   check_sel;
    reg [3:0]   retry_count;
    reg [15:0]  check_addr;
    reg [7:0]   check_mask;
    reg [7:0]   check_value;
    reg [31:0]  wait_counter;
    reg [3:0]   wait_next_state;
    reg         precheck_mode;
    reg         debug_phase_read;
    reg         precheck_3wire_done;
    reg         read_use_3wire;

    assign table_spi_busy  = spi_write_busy;
    assign table_spi_done  = spi_write_done;
    assign spi_write_start = runtime_write_start | table_spi_start | direct_write_start;
    assign spi_write_word  = runtime_write_start ? runtime_write_word :
                             (table_spi_start ? spi_word : direct_write_word);
    assign read_busy = read_use_3wire ? read3_busy : read4_busy;
    assign read_done = read_use_3wire ? read3_done : read4_done;
    assign read_data = read_use_3wire ? read3_data : read4_data;
    assign runtime_ch0_use_main_nco =
        (runtime_main0_ftw != 48'd0) || (runtime_ch0_ftw > CH_NCO_300MHZ_FTW);
    assign runtime_nco_main0_ftw =
        (runtime_main0_ftw != 48'd0) ? runtime_main0_ftw :
        (runtime_ch0_use_main_nco ? (({1'b0, runtime_ch0_ftw} + 49'd4) >> 3) : 48'd0);
    assign runtime_jesd_main0_ftw = runtime_nco_only ? 48'd0 : runtime_main0_ftw;
    assign runtime_main1_ftw = 48'd0;
    assign runtime_ch0_channel_ftw =
        runtime_ch0_use_main_nco ? 48'd0 : runtime_ch0_ftw;
    assign sclk = read_busy ? (read_use_3wire ? read3_sclk : read_sclk) : write_sclk;
    assign cs_n = read_busy ? (read_use_3wire ? read3_cs_n : read_cs_n) : write_cs_n;
    assign sdio_o = read_busy ? (read_use_3wire ? read3_sdio_o : read_sdio) : write_sdio;
    assign sdio_oe = read_busy ? (read_use_3wire ? read3_sdio_oe : 1'b1) : 1'b1;
    assign debug_dbg = {
        state,
        check_sel,
        retry_count,
        read_busy,
        read_done,
        spi_write_busy,
        spi_write_done,
        check_addr[7:0],
        read_data
    };
    assign runtime_dbg = {
        4'hA,
        runtime_update_active,
        runtime_apply_pending,
        runtime_update_nco_only,
        init_done_latched,
        runtime_update_index,
        runtime_apply_sync,
        runtime_apply_sync_d1,
        runtime_apply_toggle,
        start,
        table_busy,
        spi_write_busy,
        read_busy,
        state,
        runtime_write_start,
        spi_write_done,
        runtime_write_word[4:0]
    };

    ad9173_init_table u_table (
        .addr(table_addr),
        .cmd (table_cmd)
    );

    spi_init_engine #(
        .TABLE_AW(8),
        .MS_TICKS(MS_TICKS),
        .POST_WRITE_TICKS(MS_TICKS)
    ) u_engine (
        .clk      (clk),
        .rst      (rst),
        .start    (table_start),
        .busy     (table_busy),
        .done     (table_done),
        .table_addr(table_addr),
        .table_cmd(table_cmd),
        .spi_start(table_spi_start),
        .spi_word (spi_word),
        .spi_busy (table_spi_busy),
        .spi_done (table_spi_done)
    );

    spi_write_master #(
        .CLK_DIV(CLK_DIV),
        .UPDATE_MOSI_ON_LOW(1)
    ) u_spi (
        .clk    (clk),
        .rst    (rst),
        .start  (spi_write_start),
        .tx_word(spi_write_word),
        .busy   (spi_write_busy),
        .done   (spi_write_done),
        .sclk   (write_sclk),
        .cs_n   (write_cs_n),
        .mosi   (write_sdio)
    );

    spi_read_master_4wire #(
        .CLK_DIV(CLK_DIV),
        .UPDATE_MOSI_ON_LOW(1)
    ) u_read (
        .clk    (clk),
        .rst    (rst),
        .start  (read_start && !read_use_3wire),
        .addr   (check_addr),
        .miso   (sdo),
        .busy   (read4_busy),
        .done   (read4_done),
        .rx_data(read4_data),
        .sclk   (read_sclk),
        .cs_n   (read_cs_n),
        .mosi   (read_sdio)
    );

    spi_read_master_3wire #(
        .CLK_DIV(CLK_DIV)
    ) u_read3 (
        .clk    (clk),
        .rst    (rst),
        .start  (read_start && read_use_3wire),
        .addr   (check_addr),
        .sdio_i (sdio_i),
        .busy   (read3_busy),
        .done   (read3_done),
        .rx_data(read3_data),
        .sclk   (read3_sclk),
        .cs_n   (read3_cs_n),
        .sdio_o (read3_sdio_o),
        .sdio_oe(read3_sdio_oe)
    );

    always @(posedge clk) begin
        if (rst) begin
            table_start   <= 1'b0;
            read_start    <= 1'b0;
            busy          <= 1'b0;
            done          <= 1'b0;
            ok            <= 1'b0;
            fail          <= 1'b0;
            status_dbg    <= 32'd0;
            sanity_dbg    <= 32'd0;
            state         <= ST_IDLE;
            check_sel     <= CHECK_ID_TYPE;
            retry_count   <= 4'd0;
            check_addr    <= 16'h0003;
            check_mask    <= 8'hff;
            check_value   <= 8'h04;
            wait_counter  <= 32'd0;
            wait_next_state <= ST_READ_START;
            precheck_mode <= 1'b0;
            debug_phase_read <= 1'b0;
            precheck_3wire_done <= 1'b0;
            read_use_3wire <= 1'b0;
            direct_write_start <= 1'b0;
            direct_write_word  <= 24'd0;
            runtime_write_start <= 1'b0;
            runtime_write_word <= 24'd0;
            runtime_apply_meta <= 1'b0;
            runtime_apply_sync <= 1'b0;
            runtime_apply_sync_d1 <= 1'b0;
            runtime_apply_pending <= 1'b0;
            runtime_update_active <= 1'b0;
            runtime_update_nco_only <= 1'b0;
            init_done_latched <= 1'b0;
            runtime_update_index <= 6'd0;
        end else begin
            table_start        <= 1'b0;
            read_start         <= 1'b0;
            direct_write_start <= 1'b0;
            runtime_write_start <= 1'b0;
            done               <= 1'b0;
            runtime_apply_meta <= runtime_apply_toggle;
            runtime_apply_sync <= runtime_apply_meta;
            runtime_apply_sync_d1 <= runtime_apply_sync;
            if (runtime_apply_sync ^ runtime_apply_sync_d1) begin
                runtime_apply_pending <= 1'b1;
            end

            // 运行时更新路径：
            // runtime_nco_only=1 时，写 AD9173 片内 DDS/NCO 输出需要的
            // main NCO、channel NCO 和幅度寄存器；
            // runtime_nco_only=0 时，JESD/RAM 样点继续由 FPGA 输入，
            // 这里只更新 main NCO FTW，用于高频搬移。
            if (runtime_update_active) begin
                if (spi_write_done) begin
                    if ((runtime_update_nco_only && (runtime_update_index == 6'd58)) ||
                        (!runtime_update_nco_only && (runtime_update_index == 6'd13))) begin
                        runtime_update_active <= 1'b0;
                        runtime_update_index <= 6'd0;
                    end else begin
                        runtime_update_index <= runtime_update_index + 1'b1;
                    end
                end else if (!spi_write_busy && !table_busy && !read_busy) begin
                    if (runtime_update_nco_only) begin
                        // DDS 单音输出：按索引分多次 SPI 写入，依次配置
                        // main NCO、两路 channel NCO 和两路幅度。
                        case (runtime_update_index)
                            6'd0:  runtime_write_word <= {16'h0008, 8'hC0};
                            6'd1:  runtime_write_word <= {16'h003F, 8'h00};
                            6'd2:  runtime_write_word <= {16'h047D, 8'h00};
                            6'd3:  runtime_write_word <= {16'h058D, 8'h51};
                            6'd4:  runtime_write_word <= {16'h0596, 8'h0C};
                            6'd5:  runtime_write_word <= {16'h0110, 8'h24};
                            6'd6:  runtime_write_word <= {16'h0111, 8'h84};
                            6'd7:  runtime_write_word <= {16'h0112, 8'h08};
                            6'd8:  runtime_write_word <= {16'h0100, 8'h00};
                            6'd9:  runtime_write_word <= {16'h003B, 8'hF1};
                            6'd10: runtime_write_word <= {16'h003A, 8'h02};
                            6'd11: runtime_write_word <= {16'h0008, 8'h40};
                            6'd12: runtime_write_word <= {16'h0113, 8'h00};
                            6'd13: runtime_write_word <= {16'h0114, runtime_nco_main0_ftw[7:0]};
                            6'd14: runtime_write_word <= {16'h0115, runtime_nco_main0_ftw[15:8]};
                            6'd15: runtime_write_word <= {16'h0116, runtime_nco_main0_ftw[23:16]};
                            6'd16: runtime_write_word <= {16'h0117, runtime_nco_main0_ftw[31:24]};
                            6'd17: runtime_write_word <= {16'h0118, runtime_nco_main0_ftw[39:32]};
                            6'd18: runtime_write_word <= {16'h0119, runtime_nco_main0_ftw[47:40]};
                            6'd19: runtime_write_word <= {16'h011C, 8'h00};
                            6'd20: runtime_write_word <= {16'h011D, 8'h00};
                            6'd21: runtime_write_word <= {16'h0113, 8'h01};
                            6'd22: runtime_write_word <= {16'h0008, 8'h80};
                            6'd23: runtime_write_word <= {16'h0113, 8'h00};
                            6'd24: runtime_write_word <= {16'h0114, runtime_main1_ftw[7:0]};
                            6'd25: runtime_write_word <= {16'h0115, runtime_main1_ftw[15:8]};
                            6'd26: runtime_write_word <= {16'h0116, runtime_main1_ftw[23:16]};
                            6'd27: runtime_write_word <= {16'h0117, runtime_main1_ftw[31:24]};
                            6'd28: runtime_write_word <= {16'h0118, runtime_main1_ftw[39:32]};
                            6'd29: runtime_write_word <= {16'h0119, runtime_main1_ftw[47:40]};
                            6'd30: runtime_write_word <= {16'h011C, 8'h00};
                            6'd31: runtime_write_word <= {16'h011D, 8'h00};
                            6'd32: runtime_write_word <= {16'h0113, 8'h01};
                            6'd33: runtime_write_word <= {16'h0008, 8'h01};
                            6'd34: runtime_write_word <= {16'h0148, runtime_ch0_amp[7:0]};
                            6'd35: runtime_write_word <= {16'h0149, runtime_ch0_amp[15:8]};
                            6'd36: runtime_write_word <= {16'h0130, 8'h41};
                            6'd37: runtime_write_word <= {16'h0132, runtime_ch0_channel_ftw[7:0]};
                            6'd38: runtime_write_word <= {16'h0133, runtime_ch0_channel_ftw[15:8]};
                            6'd39: runtime_write_word <= {16'h0134, runtime_ch0_channel_ftw[23:16]};
                            6'd40: runtime_write_word <= {16'h0135, runtime_ch0_channel_ftw[31:24]};
                            6'd41: runtime_write_word <= {16'h0136, runtime_ch0_channel_ftw[39:32]};
                            6'd42: runtime_write_word <= {16'h0137, runtime_ch0_channel_ftw[47:40]};
                            6'd43: runtime_write_word <= {16'h0131, 8'h00};
                            6'd44: runtime_write_word <= {16'h0131, 8'h01};
                            6'd45: runtime_write_word <= {16'h0008, 8'h08};
                            6'd46: runtime_write_word <= {16'h0148, runtime_ch1_amp[7:0]};
                            6'd47: runtime_write_word <= {16'h0149, runtime_ch1_amp[15:8]};
                            6'd48: runtime_write_word <= {16'h0130, 8'h41};
                            6'd49: runtime_write_word <= {16'h0132, runtime_ch1_ftw[7:0]};
                            6'd50: runtime_write_word <= {16'h0133, runtime_ch1_ftw[15:8]};
                            6'd51: runtime_write_word <= {16'h0134, runtime_ch1_ftw[23:16]};
                            6'd52: runtime_write_word <= {16'h0135, runtime_ch1_ftw[31:24]};
                            6'd53: runtime_write_word <= {16'h0136, runtime_ch1_ftw[39:32]};
                            6'd54: runtime_write_word <= {16'h0137, runtime_ch1_ftw[47:40]};
                            6'd55: runtime_write_word <= {16'h0131, 8'h00};
                            6'd56: runtime_write_word <= {16'h0131, 8'h01};
                            6'd57: runtime_write_word <= {16'h0008, 8'hC0};
                            default: runtime_write_word <= {16'h0596, 8'h0C};
                        endcase
                    end else begin
                        // JESD/RAM 输出：payload 样点从 FPGA/JESD 进入 DAC，
                        // 这里只在需要时修改 main NCO 搬频寄存器。
                        case (runtime_update_index)
                            6'd0:  runtime_write_word <= {16'h0008, 8'hFF};
                            6'd1:  runtime_write_word <= {16'h0110, 8'h28};
                            6'd2:  runtime_write_word <= {16'h0111, 8'hC1};
                            6'd3:  runtime_write_word <= {16'h0112, 8'h08};
                            6'd4:  runtime_write_word <= {16'h0113, 8'h00};
                            6'd5:  runtime_write_word <= {16'h0114, runtime_jesd_main0_ftw[7:0]};
                            6'd6:  runtime_write_word <= {16'h0115, runtime_jesd_main0_ftw[15:8]};
                            6'd7:  runtime_write_word <= {16'h0116, runtime_jesd_main0_ftw[23:16]};
                            6'd8:  runtime_write_word <= {16'h0117, runtime_jesd_main0_ftw[31:24]};
                            6'd9:  runtime_write_word <= {16'h0118, runtime_jesd_main0_ftw[39:32]};
                            6'd10: runtime_write_word <= {16'h0119, runtime_jesd_main0_ftw[47:40]};
                            6'd11: runtime_write_word <= {16'h011C, 8'h00};
                            6'd12: runtime_write_word <= {16'h011D, 8'h00};
                            6'd13: runtime_write_word <= {16'h0113, 8'h01};
                            default: runtime_write_word <= {16'h0596, 8'h0C};
                        endcase
                    end
                    runtime_write_start <= 1'b1;
                end
            end else if (init_done_latched && runtime_apply_pending && (state == ST_IDLE) &&
                         !start && !table_busy && !spi_write_busy && !read_busy) begin
                runtime_update_active <= 1'b1;
                runtime_update_nco_only <= runtime_nco_only;
                runtime_update_index <= 6'd0;
                runtime_apply_pending <= 1'b0;
            end else begin
                case (state)
                ST_IDLE: begin
                    busy       <= 1'b0;
                    fail       <= 1'b0;
                    status_dbg <= 32'd0;
                    sanity_dbg <= 32'd0;
                    retry_count <= 4'd0;
                    check_sel   <= CHECK_ID_TYPE;
                    if (start) begin
                        busy              <= 1'b1;
                        precheck_mode     <= 1'b1;
                        precheck_3wire_done <= 1'b0;
                        read_use_3wire    <= 1'b1;
                        direct_write_word <= {16'h0000, 8'h81};
                        state             <= ST_PRE_RESET_START;
                    end
                end

                ST_RUN_TABLE: begin
                    // 执行 ad9173_init_table.v 中的完整初始化寄存器表。
                    if (table_done) begin
                        check_sel   <= CHECK_BOOT;
                        check_addr  <= 16'h0705;
                        check_mask  <= 8'h02;
                        check_value <= 8'h02;
                        read_use_3wire <= 1'b1;
                        retry_count <= 4'd0;
                        state       <= ST_READ_START;
                    end
                end

                ST_PRE_RESET_START: begin
                    // 初始化前先做软件复位，保证 AD9173 SPI/内部状态干净。
                    if (!spi_write_busy && !table_busy) begin
                        direct_write_start <= 1'b1;
                        state              <= ST_PRE_RESET_WAIT;
                    end
                end

                ST_PRE_RESET_WAIT: begin
                    if (spi_write_done) begin
                        direct_write_word <= {16'h0000, 8'h24};
                        wait_counter      <= MS_TICKS;
                        wait_next_state   <= ST_PRE_4WIRE_START;
                        state             <= ST_RETRY_WAIT;
                    end
                end

                ST_PRE_4WIRE_START: begin
                    // 复位后切换到后续回读/调试使用的 SPI 访问方式。
                    if (!spi_write_busy && !table_busy) begin
                        direct_write_start <= 1'b1;
                        state              <= ST_PRE_4WIRE_WAIT;
                    end
                end

                ST_PRE_4WIRE_WAIT: begin
                    if (spi_write_done) begin
                        read_use_3wire <= !precheck_3wire_done;
                        check_sel       <= CHECK_ID_TYPE;
                        check_addr      <= 16'h0003;
                        check_mask      <= 8'hff;
                        check_value     <= 8'h04;
                        retry_count     <= 4'd0;
                        wait_counter    <= MS_TICKS;
                        wait_next_state <= ST_READ_START;
                        state           <= ST_RETRY_WAIT;
                    end
                end

                ST_READ_START: begin
                    // 回读芯片 ID、boot、PLL、DLL、SERDES 等关键状态。
                    // 这些状态都通过后，顶层才会继续释放 JESD 链路。
                    if (!read_busy) begin
                        read_start <= 1'b1;
                        state      <= ST_READ_WAIT;
                    end
                end

                ST_READ_WAIT: begin
                    if (read_done) begin
                        case (check_sel)
                            CHECK_ID_TYPE:   sanity_dbg[7:0]   <= read_data;
                            CHECK_ID_L:      sanity_dbg[15:8]  <= read_data;
                            CHECK_ID_H:      sanity_dbg[23:16] <= read_data;
                            CHECK_SCR_RD_A5: sanity_dbg[31:24] <= read_data;
                            CHECK_BOOT:   status_dbg[7:0]   <= read_data;
                            CHECK_PLL:    status_dbg[15:8]  <= read_data;
                            CHECK_DLL:    status_dbg[23:16] <= read_data;
                            CHECK_SERDES: status_dbg[31:24] <= read_data;
                            default:      status_dbg <= status_dbg;
                        endcase

                        if ((read_data != 8'hff) && ((read_data & check_mask) == check_value)) begin
                            retry_count <= 4'd0;
                            case (check_sel)
                                CHECK_ID_TYPE: begin
                                    check_sel         <= CHECK_SCR_WR_5A;
                                    check_addr        <= 16'h000a;
                                    check_mask  <= 8'hff;
                                    check_value       <= 8'h5a;
                                    direct_write_word <= {16'h000a, 8'h5a};
                                    state             <= ST_WRITE_START;
                                end

                                CHECK_SCR_RD_5A: begin
                                    check_sel         <= CHECK_SCR_WR_A5;
                                    check_addr        <= 16'h000a;
                                    check_value       <= 8'ha5;
                                    direct_write_word <= {16'h000a, 8'ha5};
                                    state             <= ST_WRITE_START;
                                end

                                CHECK_SCR_RD_A5: begin
                                    if (precheck_mode) begin
                                        precheck_mode <= 1'b0;
                                        table_start   <= 1'b1;
                                        state         <= ST_RUN_TABLE;
                                    end else begin
                                        check_sel   <= CHECK_BOOT;
                                        check_addr  <= 16'h0705;
                                        check_mask  <= 8'h02;
                                        check_value <= 8'h02;
                                        state       <= ST_READ_START;
                                    end
                                end

                                CHECK_BOOT: begin
                                    check_sel   <= CHECK_PLL;
                                    check_addr  <= 16'h07b5;
                                    check_mask  <= 8'h01;
                                    check_value <= 8'h01;
                                    state       <= ST_READ_START;
                                end

                                CHECK_PLL: begin
                                    check_sel   <= CHECK_DLL;
                                    check_addr  <= 16'h00c3;
                                    check_mask  <= 8'h01;
                                    check_value <= 8'h01;
                                    state       <= ST_READ_START;
                                end

                                CHECK_DLL: begin
                                    check_sel   <= CHECK_SERDES;
                                    check_addr  <= 16'h0281;
                                    check_mask  <= 8'h01;
                                    check_value <= 8'h01;
                                    state       <= ST_READ_START;
                                end

                                default: begin
                                    state <= ST_DONE;
                                end
                            endcase
                        end else if (retry_count == MAX_RETRY - 1'b1) begin
                            state <= ST_FAIL;
                        end else begin
                            retry_count  <= retry_count + 1'b1;
                            wait_counter <= MS_TICKS;
                            wait_next_state <= ST_READ_START;
                            state        <= ST_RETRY_WAIT;
                        end
                    end
                end

                ST_RETRY_WAIT: begin
                    if (wait_counter == 32'd0) begin
                        state <= wait_next_state;
                    end else begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end

                ST_WRITE_START: begin
                    if (!spi_write_busy && !table_busy) begin
                        direct_write_start <= 1'b1;
                        state              <= ST_WRITE_WAIT;
                    end
                end

                ST_WRITE_WAIT: begin
                    if (spi_write_done) begin
                        case (check_sel)
                            CHECK_SCR_WR_5A: begin
                                check_sel   <= CHECK_SCR_RD_5A;
                                check_addr  <= 16'h000a;
                                check_mask  <= 8'hff;
                                check_value <= 8'h5a;
                                wait_counter <= MS_TICKS;
                                wait_next_state <= ST_READ_START;
                                state       <= ST_RETRY_WAIT;
                            end

                            CHECK_SCR_WR_A5: begin
                                check_sel   <= CHECK_SCR_RD_A5;
                                check_addr  <= 16'h000a;
                                check_mask  <= 8'hff;
                                check_value <= 8'ha5;
                                wait_counter <= MS_TICKS;
                                wait_next_state <= ST_READ_START;
                                state       <= ST_RETRY_WAIT;
                            end

                            default: begin
                                state <= ST_FAIL;
                            end
                        endcase
                    end
                end

                ST_DONE: begin
                    busy <= 1'b0;
                    ok   <= 1'b1;
                    done <= 1'b1;
                    init_done_latched <= 1'b1;
                    state <= ST_IDLE;
                end

                ST_FAIL: begin
                    busy       <= 1'b1;
                    fail       <= 1'b1;
                    done       <= 1'b1;
                    check_sel  <= CHECK_ID_TYPE;
                    check_addr <= 16'h0003;
                    read_use_3wire   <= 1'b1;
                    debug_phase_read <= 1'b1;
                    state      <= ST_DEBUG_START;
                end

                // After a hard SPI sanity failure, alternate 4-wire enable
                // writes with chip-type reads so the scope can see both sides.
                ST_DEBUG_START: begin
                    busy <= 1'b1;
                    fail <= 1'b1;
                    if (!debug_phase_read && !spi_write_busy && !table_busy) begin
                        direct_write_word  <= {16'h0000, 8'h3c};
                        direct_write_start <= 1'b1;
                        state              <= ST_DEBUG_WAIT;
                    end else if (debug_phase_read && !read_busy) begin
                        read_start <= 1'b1;
                        state      <= ST_DEBUG_WAIT;
                    end
                end

                ST_DEBUG_WAIT: begin
                    busy <= 1'b1;
                    fail <= 1'b1;
                    if (!debug_phase_read && spi_write_done) begin
                        debug_phase_read <= 1'b1;
                        wait_counter     <= DEBUG_GAP_TICKS;
                        wait_next_state  <= ST_DEBUG_START;
                        state            <= ST_RETRY_WAIT;
                    end else if (debug_phase_read && read_done) begin
                        sanity_dbg[7:0] <= read_data;
                        debug_phase_read <= read_use_3wire ? 1'b1 : 1'b0;
                        wait_counter     <= DEBUG_GAP_TICKS;
                        wait_next_state  <= ST_DEBUG_START;
                        state            <= ST_RETRY_WAIT;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
                endcase
            end
        end
    end

endmodule
