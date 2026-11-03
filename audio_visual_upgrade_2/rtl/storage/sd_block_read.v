`default_nettype none
//=============================================================================
// rtl/sd_block_read.v
//   CMD17 单块读引擎：读一个 512 字节扇区，并把它变成带反压的字节流。
//
//   协议依据：SD_Spec_Part1_Physical_Layer_v2.00_2006
//     §7.2.1  CMD17 = READ_SINGLE_BLOCK，命令字 0x51，参数为块地址(LBA)
//     §7.2    SPI 命令帧 6 字节 = 命令字 + 4 字节参数 + CRC7 + 结束位
//     数据块：R1 之后经可变延迟发起始令牌 0xFE，随后 512 字节数据 + 2 字节 CRC16
//
//   反压：本引擎**一个字节一个字节**地驱动 sd_spi_byte。
//     当 dready=0 时不再启动下一个字节，SCK 停在低电平（SPI 允许的时钟拉伸），
//     卡会保持当前数据块等待时钟恢复，因此不会丢字节。
//     SPI 模式 0（CPOL=0, CPHA=0）由 sd_spi_byte 保证。
//=============================================================================
module sd_block_read #(
    parameter integer CLK_HZ            = 50000000,  // 输入时钟频率
    parameter integer DATA_SCK_HZ       = 12500000,  // 数据阶段 SCK 目标频率
    //   ★ 2026-09-26 板上实测：25MHz 采样裕量不足（详见 storage_top.v 同名参数说明）；
    //     这里只改**默认值**（实际值由 sd_phy 传入），避免单独用本模块时又踩同一个坑。
    parameter integer SECTOR_TIMEOUT_MS = 250,       // 单扇区读取超时（含令牌等待与反压）
    parameter         CHECK_CRC16       = 1'b0       // 1: 校验扇区 CRC16；0: 只接收不校验
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,        // 单周期脉冲；仅 busy=0 时被接受
    input  wire [31:0] lba,          // 与 start 同拍有效（SDHC 下即为块地址）
    output reg         busy,
    output reg         done,         // 1 拍脉冲：512 字节全部交付完毕
    output reg  [3:0]  err,          // 0=OK 1=R1非法/无响应 2=令牌超时 3=CRC16错 4=整体超时
    output wire        dvalid,       // 数据字节有效，保持到 dready
    output wire [7:0]  ddata,
    input  wire        dready,       // 0 时暂停 SCK
    output reg  [15:0] crc_rx,       // 卡发来的 CRC16（调试）
    output reg  [15:0] crc_calc,     // 本地计算的 CRC16-CCITT（调试）
    output reg         cs_n,
    output wire        sck,
    output wire        mosi,
    input  wire        miso
);

    //-------------------------------------------------------------------------
    // 参数换算：向上取整保证实际 SCK <= 目标频率
    //-------------------------------------------------------------------------
    localparam integer HALF_PERIOD     = (CLK_HZ + (2 * DATA_SCK_HZ) - 1) / (2 * DATA_SCK_HZ);
    localparam [31:0]  TIMEOUT_CYCLES  = (CLK_HZ / 1000) * SECTOR_TIMEOUT_MS;

    //-------------------------------------------------------------------------
    // 状态编码
    //-------------------------------------------------------------------------
    localparam [2:0] R_IDLE  = 3'd0,
                     R_CMD   = 3'd1,
                     R_R1    = 3'd2,
                     R_TOKEN = 3'd3,
                     R_DATA  = 3'd4,
                     R_CRC   = 3'd5,
                     R_TAIL  = 3'd6,
                     R_END   = 3'd7;

    localparam [3:0] E_NONE    = 4'd0,
                     E_R1      = 4'd1,
                     E_TOKEN   = 4'd2,
                     E_CRC     = 4'd3,
                     E_TIMEOUT = 4'd4;

    //-------------------------------------------------------------------------
    // CRC7（命令帧）与 CRC16（数据块）
    //-------------------------------------------------------------------------
    function [6:0] crc7_step;
        input [6:0] crc_in;
        input [7:0] data_in;
        integer i;
        reg [6:0] c;
        reg       msb;
        begin
            c = crc_in;
            for (i = 7; i >= 0; i = i - 1) begin
                msb = c[6];
                c   = {c[5:0], 1'b0};
                if (msb ^ data_in[i]) c = c ^ 7'h09;
            end
            crc7_step = c;
        end
    endfunction

    function [7:0] cmd_crc;
        input [39:0] h;              // 命令字 + 4 字节参数
        reg [6:0] c;
        begin
            c = crc7_step(7'd0, h[39:32]);
            c = crc7_step(c,    h[31:24]);
            c = crc7_step(c,    h[23:16]);
            c = crc7_step(c,    h[15:8]);
            c = crc7_step(c,    h[7:0]);
            cmd_crc = {c, 1'b1};     // CRC7 + 结束位
        end
    endfunction

    function [15:0] crc16_step;
        input [15:0] c_in;
        input [7:0]  d_in;
        integer i;
        reg [15:0] c;
        reg        msb;
        begin
            c = c_in;
            for (i = 7; i >= 0; i = i - 1) begin
                msb = c[15] ^ d_in[i];
                c   = {c[14:0], 1'b0};
                if (msb) c = c ^ 16'h1021;
            end
            crc16_step = c;
        end
    endfunction

    // 命令帧（组合）
    wire [39:0] cmd_head  = {8'h51, lba};          // CMD17 + LBA
    wire [47:0] cmd_frame = {cmd_head, cmd_crc(cmd_head)};

    //-------------------------------------------------------------------------
    // 状态
    //-------------------------------------------------------------------------
    reg [2:0]  state;
    reg [47:0] tx_shift;
    reg [2:0]  cmd_idx;
    reg [8:0]  data_idx;
    reg [3:0]  r1_try;
    reg        crc_idx;
    reg [31:0] timer;
    reg [3:0]  err_r;

    // 输出流水（2 级滑板：pend + out）
    //   dvalid/ddata 直接由 out_v/out_d 组合输出：这两个寄存器本身已打拍，
    //   valid 与 data 天然同拍同步；再加一级寄存器会造成同一字节重复交付。
    reg        pend_v;
    reg [7:0]  pend_d;
    reg        out_v;
    reg [7:0]  out_d;

    assign dvalid = out_v;
    assign ddata  = out_d;

    //-------------------------------------------------------------------------
    // 字节收发引擎
    //-------------------------------------------------------------------------
    wire       be_busy, be_done;
    wire [7:0] be_rx;
    reg        be_req;

    wire be_start = be_req & ~be_busy & ~be_done;

    wire be_want = (state == R_CMD)  | (state == R_R1) | (state == R_TOKEN) |
                   (state == R_CRC)  | (state == R_TAIL) |
                   ((state == R_DATA) & ~pend_v);

    wire [7:0] be_tx = (state == R_CMD) ? tx_shift[47:40] : 8'hFF;

    sd_spi_byte u_byte (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (be_start),
        .tx_data     (be_tx),
        .half_period (HALF_PERIOD[15:0]),
        .busy        (be_busy),
        .done        (be_done),
        .rx_data     (be_rx),
        .sck         (sck),
        .mosi        (mosi),
        .miso        (miso)
    );

    //-------------------------------------------------------------------------
    // 主状态机
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= R_IDLE;
            tx_shift  <= 48'd0;
            cmd_idx   <= 3'd0;
            data_idx  <= 9'd0;
            r1_try    <= 4'd0;
            crc_idx   <= 1'b0;
            timer     <= 32'd0;
            err_r     <= E_NONE;
            pend_v    <= 1'b0;
            pend_d    <= 8'd0;
            out_v     <= 1'b0;
            out_d     <= 8'd0;
            be_req    <= 1'b0;
            cs_n      <= 1'b1;
            busy      <= 1'b0;
            done      <= 1'b0;
            err       <= E_NONE;
            crc_rx    <= 16'd0;
            crc_calc  <= 16'd0;
        end else begin
            done <= 1'b0;

            // ---- 字节引擎请求控制 ----
            if (be_start) be_req <= 1'b0;
            else if (be_want & ~be_busy & ~be_done) be_req <= 1'b1;

            // ---- 输出流水（最后写者胜出） ----
            if (pend_v && (out_v ? dready : 1'b1)) begin
                out_d  <= pend_d;
                out_v  <= 1'b1;
                pend_v <= 1'b0;
            end else if (out_v && dready) begin
                out_v <= 1'b0;
            end

            // ---- 超时计数 ----
            if (state == R_IDLE || state == R_END) timer <= 32'd0;
            else if (timer < TIMEOUT_CYCLES)       timer <= timer + 32'd1;

            if (busy && (timer >= TIMEOUT_CYCLES) && (state != R_END)) begin
                err_r <= E_TIMEOUT;
                cs_n  <= 1'b1;
                state <= R_END;
            end else begin
                case (state)
                //---------------------------------------------------------
                R_IDLE: begin
                    if (start && !busy) begin
                        busy      <= 1'b1;
                        cs_n      <= 1'b0;
                        tx_shift  <= cmd_frame;
                        cmd_idx   <= 3'd0;
                        data_idx  <= 9'd0;
                        r1_try    <= 4'd0;
                        crc_idx   <= 1'b0;
                        err_r     <= E_NONE;
                        pend_v    <= 1'b0;
                        out_v     <= 1'b0;
                        crc_rx    <= 16'd0;
                        crc_calc  <= 16'd0;
                        timer     <= 32'd0;
                        state     <= R_CMD;
                    end
                end
                //---------------------------------------------------------
                // 发 6 字节命令帧
                R_CMD: begin
                    if (be_done) begin
                        tx_shift <= {tx_shift[39:0], 8'hFF};
                        if (cmd_idx == 3'd5) begin
                            state  <= R_R1;
                            r1_try <= 4'd0;
                        end else begin
                            cmd_idx <= cmd_idx + 3'd1;
                        end
                    end
                end
                //---------------------------------------------------------
                // 发 0xFF 找 R1（最多 16 字节）
                R_R1: begin
                    if (be_done) begin
                        if (be_rx[7] == 1'b0) begin
                            if (be_rx == 8'h00) begin
                                state <= R_TOKEN;
                            end else begin
                                err_r <= E_R1;
                                cs_n  <= 1'b1;
                                state <= R_END;
                            end
                        end else if (r1_try == 4'd15) begin
                            err_r <= E_R1;
                            cs_n  <= 1'b1;
                            state <= R_END;
                        end else begin
                            r1_try <= r1_try + 4'd1;
                        end
                    end
                end
                //---------------------------------------------------------
                // 发 0xFF 等数据起始令牌 0xFE（由 timer 保护）
                R_TOKEN: begin
                    if (be_done) begin
                        if (be_rx == 8'hFE) begin
                            state    <= R_DATA;
                            data_idx <= 9'd0;
                            crc_calc <= 16'd0;
                        end
                    end
                end
                //---------------------------------------------------------
                // 512 字节数据（字节粒度反压）
                R_DATA: begin
                    if (be_done) begin
                        crc_calc <= crc16_step(crc_calc, be_rx);
                        pend_d   <= be_rx;
                        pend_v   <= 1'b1;
                        if (data_idx == 9'd511) begin
                            state   <= R_CRC;
                            crc_idx <= 1'b0;
                        end else begin
                            data_idx <= data_idx + 9'd1;
                        end
                    end
                end
                //---------------------------------------------------------
                // 2 字节 CRC16
                R_CRC: begin
                    if (be_done) begin
                        if (crc_idx == 1'b0) begin
                            crc_rx[15:8] <= be_rx;
                            crc_idx      <= 1'b1;
                        end else begin
                            crc_rx[7:0] <= be_rx;
                            state       <= R_TAIL;
                        end
                    end
                end
                //---------------------------------------------------------
                // 补 1 字节 0xFF（给卡 8 个时钟），随后拉高 CS
                R_TAIL: begin
                    if (be_done) begin
                        cs_n <= 1'b1;
                        if (CHECK_CRC16 && (crc_rx != crc_calc)) err_r <= E_CRC;
                        state <= R_END;
                    end
                end
                //---------------------------------------------------------
                // 等输出流水排空后收尾
                R_END: begin
                    cs_n <= 1'b1;
                    if (!out_v && !pend_v) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        err   <= err_r;
                        state <= R_IDLE;
                    end
                end
                //---------------------------------------------------------
                default: begin
                    err_r <= E_TIMEOUT;
                    cs_n  <= 1'b1;
                    state <= R_END;
                end
                endcase
            end
        end
    end

endmodule
`default_nettype wire
