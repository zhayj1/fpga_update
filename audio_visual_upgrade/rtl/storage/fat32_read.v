`default_nettype none
//=============================================================================
// rtl/fat32_read.v
//   第 2 层：文件流式读取
//     打开一个文件后，沿簇链把 file_size 个字节依次输出为单字节流。
//
//   要点：
//     1) 数据扇区 LBA = data_lba + ((簇号-2) << log2(SecPerClus)) + 簇内扇区号
//     2) 每读完一个簇的最后一个扇区且文件还没读完，就查一次 FAT 取下一簇
//     3) **严格按 file_size 截断**：末簇多出来的字节仍然从 SPI 读走（保证 CS 生命周期
//        完整、卡侧状态一致），但不输出给上层
//     4) 反压：sec_ready = ~out_v。上层 rd_ready=0 时输出槽被占满，
//        sec_ready 变低 -> sd_block_read 停止推进字节 -> SCK 停止翻转（时钟拉伸）
//
//   需求依据：F-06（顺簇链、簇号→LBA 换算）、F-08（单字节连续流）、
//             F-09（与上层 FIFO 速率匹配）、A-13（按 file_size 截断）
//=============================================================================
module fat32_read #(
    parameter integer CLK_HZ      = 50000000,
    parameter integer WATCHDOG_MS = 2000
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,          // 单周期脉冲；仅 busy=0 时接受
    input  wire [31:0] first_cluster,
    input  wire [31:0] file_size,
    output reg         busy,
    output reg         done,           // 1 拍脉冲
    output reg  [3:0]  err,            // 0=OK 1=数据扇区 2=FAT扇区 3=簇链异常 4=看门狗

    // 文件系统参数
    input  wire [31:0] data_lba,
    input  wire [3:0]  spc_shift,
    input  wire [31:0] total_clusters,

    // FAT 簇链查询服务
    output reg         chain_req,
    output reg  [31:0] chain_cluster,
    input  wire        chain_done,
    input  wire [3:0]  chain_err,
    input  wire [31:0] chain_next,

    // 扇区读服务
    output reg         sec_req,
    output reg  [31:0] sec_lba,
    input  wire        sec_valid,
    input  wire [7:0]  sec_data,
    input  wire        sec_done,
    input  wire [3:0]  sec_err,
    output wire        sec_ready,
    // ★ M1（双流仲裁用）：1 = 本流正在"等总线授权 / 有意停驻"。
    //   此时看门狗冻结：让出总线不算"没进展"，否则一条流被另一条流让出期间
    //   会被自己的 WATCHDOG_MS 误判成 E_WDOG(0x54)。
    //   单流用法（无仲裁）时接 1'b0 即可，行为与改动前完全一致。
    input  wire        sec_wait,

    // 字节流输出
    output wire        dvalid,
    output wire [7:0]  ddata,
    input  wire        dready
);

    localparam [3:0] E_NONE  = 4'd0,
                     E_DATA  = 4'd1,
                     E_FAT   = 4'd2,
                     E_CHAIN = 4'd3,
                     E_WDOG  = 4'd4,
                     E_CRC   = 4'd5;

    localparam [31:0] WDOG_CYCLES = (CLK_HZ / 1000) * WATCHDOG_MS;

    localparam [2:0] D_IDLE    = 3'd0,
                     D_REQ_SEC = 3'd1,
                     D_SEC     = 3'd2,
                     D_CHAIN   = 3'd3,
                     D_CHAIN_W = 3'd4,
                     D_FIN     = 3'd5;

    reg [2:0]  state;
    reg [3:0]  err_r;
    reg [31:0] cur_clus;
    reg [31:0] remaining;
    reg [6:0]  sec_idx;
    reg [31:0] wdog;

    // 输出滑板（单级）
    reg        out_v;
    reg [7:0]  out_d;

    assign dvalid = out_v;
    assign ddata  = out_d;
    // 输出槽空才允许 SD 字节推进 —— 这就是整条反压链的起点
    assign sec_ready = ~out_v;

    function [6:0] spc_shift_to_mask;
        input [3:0] s;
        begin
            spc_shift_to_mask = (7'd1 << s) - 7'd1;
        end
    endfunction

    wire [31:0] clus_off  = (cur_clus - 32'd2) << spc_shift;
    wire [31:0] sec_lba_c = data_lba + clus_off + {25'd0, sec_idx};
    wire        sec_last  = (sec_idx == spc_shift_to_mask(spc_shift));

    wire chn_eoc   = (chain_next >= 32'h0FFFFFF8);
    wire chn_bad   = (chain_next == 32'h0FFFFFF7);
    wire chn_low   = (chain_next < 32'd2);
    wire chn_over  = (chain_next >= (total_clusters + 32'd2));
    wire chn_bad_v = chn_bad | chn_low | chn_over;

    wire take_byte = sec_valid && (state == D_SEC) && (remaining != 32'd0);

    //-------------------------------------------------------------------------
    // 主状态机 + 输出滑板（同一时序块，避免 remaining 多驱动）
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= D_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            err           <= E_NONE;
            err_r         <= E_NONE;
            cur_clus      <= 32'd0;
            remaining     <= 32'd0;
            sec_idx       <= 7'd0;
            wdog          <= 32'd0;
            sec_req       <= 1'b0;
            sec_lba       <= 32'd0;
            chain_req     <= 1'b0;
            chain_cluster <= 32'd0;
            out_v         <= 1'b0;
            out_d         <= 8'd0;
        end else begin
            done <= 1'b0;

            // ---- 看门狗（进展型）----
            //   每完成一个数据扇区、或每完成一次簇链查询就复位一次，因此它约束的是
            //   "多久没有任何进展"，而不是整个文件的总时间：
            //     · 50MB 文件（约 102400 个扇区，每个约 167µs）能正常读完；
            //     · 真正的卡死（例如簇链查询一直不返回）仍会在 WATCHDOG_MS 内报 E_WDOG。
            //   上层取数停顿不归这里管：那由 sd_block_read 的 SECTOR_TIMEOUT_MS
            //   单扇区超时负责（取数停顿超过 250ms 会以 sec_err=4 报出）。
            if (state == D_IDLE || state == D_FIN)       wdog <= 32'd0;
            else if ((state == D_SEC)     && sec_done)   wdog <= 32'd0;
            else if ((state == D_CHAIN_W) && chain_done) wdog <= 32'd0;
            else if (sec_wait)                           wdog <= wdog;      // ★ M1：等总线/停驻期间冻结
            else if (wdog < WDOG_CYCLES)                 wdog <= wdog + 32'd1;

            if ((state != D_IDLE) && (state != D_FIN) && (wdog >= WDOG_CYCLES)) begin
                err_r     <= E_WDOG;
                sec_req   <= 1'b0;
                chain_req <= 1'b0;
                state     <= D_FIN;
            end else begin
                case (state)
                //---------------------------------------------------------
                D_IDLE: begin
                    if (start && !busy) begin
                        busy      <= 1'b1;
                        err_r     <= E_NONE;
                        cur_clus  <= first_cluster;
                        remaining <= file_size;
                        sec_idx   <= 7'd0;
                        wdog      <= 32'd0;
                        out_v     <= 1'b0;
                        if (file_size == 32'd0) state <= D_FIN;   // 空文件：0 字节，直接结束
                        else                    state <= D_REQ_SEC;
                    end
                end
                //---------------------------------------------------------
                D_REQ_SEC: begin
                    sec_req <= 1'b1;
                    sec_lba <= sec_lba_c;
                    state   <= D_SEC;
                end
                //---------------------------------------------------------
                // 数据扇区字节流：输出与丢弃都在输出滑板里完成，这里只等扇区结束
                D_SEC: begin
                    sec_req <= 1'b0;
                    if (sec_done) begin
                        if (sec_err != 4'd0) begin
                            // 透传扇区层错误：3=CRC16 校验失败，4=超时，其余归为一般数据扇区错误
                            if      (sec_err == 4'd3) err_r <= E_CRC;
                            else if (sec_err == 4'd4) err_r <= E_WDOG;
                            else                      err_r <= E_DATA;
                            state <= D_FIN;
                        end else if (remaining == 32'd0) begin
                            state <= D_FIN;                 // 文件已读完（末簇多余字节已丢弃）
                        end else if (sec_last) begin
                            state <= D_CHAIN;
                        end else begin
                            sec_idx <= sec_idx + 7'd1;
                            state   <= D_REQ_SEC;
                        end
                    end
                end
                //---------------------------------------------------------
                D_CHAIN: begin
                    chain_req     <= 1'b1;
                    chain_cluster <= cur_clus;
                    state         <= D_CHAIN_W;
                end
                //---------------------------------------------------------
                D_CHAIN_W: begin
                    chain_req <= 1'b0;
                    if (chain_done) begin
                        if (chain_err != 4'd0) begin
                            err_r <= E_FAT;
                            state <= D_FIN;
                        end else if (chn_eoc || chn_bad_v) begin
                            err_r <= E_CHAIN;               // 文件被截断或簇链损坏
                            state <= D_FIN;
                        end else begin
                            cur_clus <= chain_next;
                            sec_idx  <= 7'd0;
                            state    <= D_REQ_SEC;
                        end
                    end
                end
                //---------------------------------------------------------
                // 等输出滑板排空后再收尾，保证最后一个字节不丢
                D_FIN: begin
                    sec_req   <= 1'b0;
                    chain_req <= 1'b0;
                    if (!out_v) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        err   <= err_r;
                        state <= D_IDLE;
                    end
                end
                //---------------------------------------------------------
                default: begin
                    err_r <= E_WDOG;
                    state <= D_FIN;
                end
                endcase
            end

            // ---- 输出滑板（优先级高于 case 里的 remaining 装载） ----
            if (out_v) begin
                if (dready) out_v <= 1'b0;
            end else if (take_byte) begin
                out_v     <= 1'b1;
                out_d     <= sec_data;
                remaining <= remaining - 32'd1;
            end
        end
    end

endmodule
`default_nettype wire
