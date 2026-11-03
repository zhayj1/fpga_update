`default_nettype none
//=============================================================================
// rtl/fat32_scan.v
//   第 2 层：根目录扫描 -> 文件表
//
//   FAT32 的根目录不是固定区域，而是一条普通簇链（起始簇号来自 BPB 的 RootClus）。
//   本模块：
//     1) 沿根目录簇链逐簇、逐扇区读取
//     2) 每个扇区按 32 字节切成 16 个目录项
//     3) 过滤掉  LFN(attr=0x0F) / 子目录(attr.4) / 卷标(attr.3) / 已删除(首字节0xE5)
//        遇到首字节 0x00 立即结束扫描
//     4) 对普通文件项抽取 8.3 名(11 字节)、文件大小、首簇，并按扩展名打类型标签
//
//   目录项字段偏移（FAT32 标准 32 字节目录项）：
//     [0..10]  8.3 短名（空格填充，无小数点）
//     [11]     属性
//     [20..21] 首簇高 16 位（小端）
//     [26..27] 首簇低 16 位（小端）
//     [28..31] 文件大小（小端，32 位）
//
//   需求依据：F-05（扫描根目录、识别 BMP/WAV/LRC、支持碎片）、F-15（FILE_MAX）
//=============================================================================
module fat32_scan #(
    parameter integer FILE_MAX   = 240,
    parameter integer CLK_HZ     = 50000000,
    parameter integer WATCHDOG_MS = 2000
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,          // 单周期脉冲；仅 busy=0 时接受
    output reg         busy,
    output reg         done,           // 1 拍脉冲
    output reg  [3:0]  err,            // 0=OK 1=目录扇区读失败 2=簇链异常 3=看门狗超时
    output reg  [8:0]  file_total,

    // 文件系统参数
    input  wire [31:0] data_lba,
    input  wire [3:0]  spc_shift,
    input  wire [31:0] root_cluster,
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

    // 文件表写端口
    output reg         ft_we,
    output reg  [8:0]  ft_index,
    output reg  [87:0] ft_name,
    output reg  [1:0]  ft_type,
    output reg  [31:0] ft_size,
    output reg  [31:0] ft_cluster
);

    localparam [3:0] E_NONE = 4'd0,
                     E_SEC  = 4'd1,
                     E_CHN  = 4'd2,
                     E_WDOG = 4'd3;

    localparam [8:0] FMAX = FILE_MAX[8:0];
    localparam [31:0] WDOG_CYCLES = (CLK_HZ / 1000) * WATCHDOG_MS;

    assign sec_ready = 1'b1;

    //-------------------------------------------------------------------------
    // 状态
    //-------------------------------------------------------------------------
    localparam [3:0] S_IDLE    = 4'd0,
                     S_REQ_SEC = 4'd1,
                     S_SEC     = 4'd2,
                     S_CHAIN   = 4'd3,
                     S_CHAIN_W = 4'd4,
                     S_FIN     = 4'd5,
                     S_SHIFT   = 4'd6,
                     S_BASE    = 4'd7,
                     S_OFFSET  = 4'd8,
                     S_SEND    = 4'd9;

    reg [3:0]  state;
    reg [3:0]  shift_left;
    reg [3:0]  err_r;
    reg [31:0] cur_clus;
    reg [6:0]  sec_idx;
    reg [5:0]  bpos;
    reg [8:0]  ft_cnt;
    reg        stop_scan;
    reg [31:0] wdog;

    //-------------------------------------------------------------------------
    // 只保存需要的目录字段；时间戳等未使用字节不进入寄存器。
    // 第 31 字节在提交当拍直接作为文件大小的高字节，保持 ft_we 时序。
    //-------------------------------------------------------------------------
    reg [87:0] entry_name;
    reg [7:0] entry_attr;
    reg [31:0] entry_cluster;
    reg [23:0] entry_size_low;

    wire        ent_complete = sec_valid && (bpos == 6'd31);

    wire [7:0]  e_b0   = entry_name[87:80];
    wire [7:0]  e_attr = entry_attr;
    wire [87:0] e_name = entry_name;
    wire [31:0] e_size = {sec_data, entry_size_low};
    wire [31:0] e_clus = entry_cluster;

    wire e_end = (e_b0 == 8'h00);
    wire e_del = (e_b0 == 8'hE5);
    wire e_lfn = (e_attr == 8'h0F);
    wire e_dir = e_attr[4];
    wire e_vol = e_attr[3];
    wire e_file = !e_end && !e_del && !e_lfn && !e_dir && !e_vol;

    // 扩展名大小写不敏感比较（清除 bit5）
    wire [23:0] ext_u = entry_name[23:0] & 24'hDFDFDF;
    wire e_is_bmp = (ext_u == 24'h424D50);   // "BMP"
    wire e_is_wav = (ext_u == 24'h574156);   // "WAV"
    wire e_is_lrc = (ext_u == 24'h4C5243);   // "LRC"
    wire [1:0]  e_type = e_is_bmp ? 2'd0 : e_is_wav ? 2'd1 : e_is_lrc ? 2'd2 : 2'd3;

    wire        ft_room = (ft_cnt < FMAX);
    wire        ft_do   = ent_complete && !stop_scan && e_file && ft_room;

    //-------------------------------------------------------------------------
    // 地址换算
    //-------------------------------------------------------------------------
    // sec_lba is private scratch until S_SEND raises sec_req. Reuse one
    // full-width adder and single-bit shifts; no variable barrel shifter.
    // The request is delayed by spc_shift+4 clocks; its address, directory
    // stream, error handling and progress watchdog otherwise keep their contract.
    wire [31:0] address_a = (state == S_REQ_SEC) ? cur_clus : sec_lba;
    wire [31:0] address_b = (state == S_REQ_SEC) ? 32'hfffffffe :
                            (state == S_BASE) ? data_lba : {25'd0, sec_idx};
    wire [31:0] address_sum = address_a + address_b;

    // SecPerClus-1 = (1 << spc_shift) - 1
    function [6:0] spc_shift_to_mask;
        input [3:0] s;
        begin
            spc_shift_to_mask = (7'd1 << s) - 7'd1;
        end
    endfunction

    // 簇链下一簇合法性判定（CHN-05）
    wire chn_eoc   = (chain_next >= 32'h0FFFFFF8);
    wire chn_bad   = (chain_next == 32'h0FFFFFF7);
    wire chn_low   = (chain_next < 32'd2);
    wire chn_over  = (chain_next >= (total_clusters + 32'd2));
    wire chn_bad_v = chn_bad | chn_low | chn_over;

    wire sec_last  = (sec_idx == spc_shift_to_mask(spc_shift));

    //-------------------------------------------------------------------------
    // 目录项写入（1 拍脉冲 + 同拍数据）
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ft_we      <= 1'b0;
            ft_index   <= 9'd0;
            ft_name    <= 88'd0;
            ft_type    <= 2'd0;
            ft_size    <= 32'd0;
            ft_cluster <= 32'd0;
        end else begin
            ft_we <= 1'b0;
            if (ft_do) begin
                ft_we      <= 1'b1;
                ft_index   <= ft_cnt;
                ft_name    <= e_name;
                ft_type    <= e_type;
                ft_size    <= e_size;
                ft_cluster <= e_clus;
            end
        end
    end

    //-------------------------------------------------------------------------
    // 主状态机
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            shift_left    <= 4'd0;
            busy          <= 1'b0;
            done          <= 1'b0;
            err           <= E_NONE;
            err_r         <= E_NONE;
            cur_clus      <= 32'd0;
            sec_idx       <= 7'd0;
            bpos          <= 6'd0;
            ft_cnt        <= 9'd0;
            stop_scan     <= 1'b0;
            wdog          <= 32'd0;
            entry_name    <= 88'd0;
            entry_attr    <= 8'd0;
            entry_cluster <= 32'd0;
            entry_size_low <= 24'd0;
            sec_req       <= 1'b0;
            sec_lba       <= 32'd0;
            chain_req     <= 1'b0;
            chain_cluster <= 32'd0;
            file_total    <= 9'd0;
        end else begin
            done <= 1'b0;

            // ---- 看门狗（进展型）----
            //   与 fat32_read 同一套语义：每完成一个目录扇区或一次簇链查询就复位，
            //   约束"多久没有进展"而不是目录扫描的总时间（大目录也不会误报）。
            if (state == S_IDLE || state == S_FIN)         wdog <= 32'd0;
            else if ((state == S_SEC)     && sec_done)     wdog <= 32'd0;
            else if ((state == S_CHAIN_W) && chain_done)   wdog <= 32'd0;
            else if (wdog < WDOG_CYCLES)                   wdog <= wdog + 32'd1;

            if ((state != S_IDLE) && (state != S_FIN) && (wdog >= WDOG_CYCLES)) begin
                err_r <= E_WDOG;
                state <= S_FIN;
                sec_req   <= 1'b0;
                chain_req <= 1'b0;
            end else begin
                case (state)
                //---------------------------------------------------------
                S_IDLE: begin
                    if (start && !busy) begin
                        busy          <= 1'b1;
                        err_r         <= E_NONE;
                        cur_clus      <= root_cluster;
                        sec_idx       <= 7'd0;
                        bpos          <= 6'd0;
                        ft_cnt        <= 9'd0;
                        stop_scan     <= 1'b0;
                        entry_name    <= 88'd0;
                        entry_attr    <= 8'd0;
                        entry_cluster <= 32'd0;
                        entry_size_low <= 24'd0;
                        wdog          <= 32'd0;
                        state         <= S_REQ_SEC;
                    end
                end
                //---------------------------------------------------------
                S_REQ_SEC: begin
                    sec_lba <= address_sum;
                    shift_left <= spc_shift;
                    state <= S_SHIFT;
                end
                S_SHIFT: begin
                    if (shift_left != 4'd0) begin
                        sec_lba <= {sec_lba[30:0], 1'b0};
                        shift_left <= shift_left - 4'd1;
                    end else state <= S_BASE;
                end
                S_BASE: begin
                    sec_lba <= address_sum;
                    state <= S_OFFSET;
                end
                S_OFFSET: begin
                    sec_lba <= address_sum;
                    state <= S_SEND;
                end
                S_SEND: begin
                    sec_req <= 1'b1;
                    state   <= S_SEC;
                end
                //---------------------------------------------------------
                S_SEC: begin
                    sec_req <= 1'b0;

                    // 捕获固定字段；所有偏移仍只随 sec_valid 推进。
                    if (sec_valid) begin
                        if (bpos <= 6'd10)
                            entry_name <= {entry_name[79:0], sec_data};
                        case (bpos)
                            6'd11: entry_attr <= sec_data;
                            6'd20: entry_cluster[23:16] <= sec_data;
                            6'd21: entry_cluster[31:24] <= sec_data;
                            6'd26: entry_cluster[7:0] <= sec_data;
                            6'd27: entry_cluster[15:8] <= sec_data;
                            6'd28: entry_size_low[7:0] <= sec_data;
                            6'd29: entry_size_low[15:8] <= sec_data;
                            6'd30: entry_size_low[23:16] <= sec_data;
                            default: ;
                        endcase
                        bpos   <= (bpos == 6'd31) ? 6'd0 : (bpos + 6'd1);
                    end

                    // 目录项结束（首字节 0x00）
                    if (ent_complete && !stop_scan && e_end) stop_scan <= 1'b1;

                    // 入表计数
                    if (ft_do) ft_cnt <= ft_cnt + 9'd1;

                    // 扇区收完：决定下一步
                    if (sec_done) begin
                        if (sec_err != 4'd0) begin
                            err_r <= E_SEC;
                            state <= S_FIN;
                        end else if (stop_scan || (ft_cnt >= FMAX)) begin
                            state <= S_FIN;
                        end else if (sec_last) begin
                            state <= S_CHAIN;
                        end else begin
                            sec_idx <= sec_idx + 7'd1;
                            state   <= S_REQ_SEC;
                        end
                    end
                end
                //---------------------------------------------------------
                S_CHAIN: begin
                    chain_req     <= 1'b1;
                    chain_cluster <= cur_clus;
                    state         <= S_CHAIN_W;
                end
                //---------------------------------------------------------
                S_CHAIN_W: begin
                    chain_req <= 1'b0;
                    if (chain_done) begin
                        if (chain_err != 4'd0) begin
                            err_r <= E_CHN;
                            state <= S_FIN;
                        end else if (chn_eoc) begin
                            state <= S_FIN;              // 正常结束
                        end else if (chn_bad_v) begin
                            err_r <= E_CHN;
                            state <= S_FIN;
                        end else begin
                            cur_clus <= chain_next;
                            sec_idx  <= 7'd0;
                            bpos     <= 6'd0;
                            state    <= S_REQ_SEC;
                        end
                    end
                end
                //---------------------------------------------------------
                S_FIN: begin
                    busy       <= 1'b0;
                    done       <= 1'b1;
                    err        <= err_r;
                    file_total <= ft_cnt;
                    sec_req    <= 1'b0;
                    chain_req  <= 1'b0;
                    state      <= S_IDLE;
                end
                //---------------------------------------------------------
                default: begin
                    err_r <= E_WDOG;
                    state <= S_FIN;
                end
                endcase
            end
        end
    end

endmodule
`default_nettype wire
