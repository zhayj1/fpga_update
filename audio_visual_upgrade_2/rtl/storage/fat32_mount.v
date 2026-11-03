`default_nettype none
//=============================================================================
// rtl/fat32_mount.v
//   第 2 层：文件系统挂载
//     1) 读 LBA0，按 SD 规范之外的标准 FAT 结构判定它是 MBR 还是引导扇区：
//        - 偏移 0x52 起为 "FAT32"  -> 无分区(Superfloppy)，分区起始 LBA = 0
//        - 否则按 MBR 分区表（4 项，每项 16 字节，偏移 446/462/478/494）找
//          类型 0x0B/0x0C（FAT32 CHS/LBA），取其 "相对扇区号"(偏移 +8，4 字节小端)
//     2) 读分区引导扇区，解析 FAT32 BPB，产出派生参数：
//          FAT_LBA     = part_lba + RsvdSecCnt
//          Data_LBA    = FAT_LBA  + NumFATs * FATSz32
//          total_clusters = (TotSec32 - RsvdSecCnt - NumFATs*FATSz32) >> log2(SecPerClus)
//     3) 只使用第 1 个 FAT 副本（只读，不需要读镜像副本）
//
//   只捕获 BPB/MBR 需要的固定偏移字节，不保存整个扇区。
//   挂载后的簇数换算最多用 7 拍单步移位，避免 32 位可变移位器。
//
//   需求依据：需求 F-04（兼容 MBR 与 Superfloppy）、F-06（隐藏 LBA/簇/FAT）
//=============================================================================
module fat32_mount #(
    parameter integer CLK_HZ = 50000000
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,          // 单周期脉冲；仅 busy=0 时接受
    output reg         busy,
    output reg         done,           // 1 拍脉冲
    output reg  [3:0]  err,            // 0=OK，见下 E_* 编码

    // 派生文件系统参数（挂载成功后保持稳定）
    output reg  [31:0] part_lba,
    output reg  [31:0] fat_lba,
    output reg  [31:0] data_lba,
    output reg  [3:0]  spc_shift,
    output reg  [31:0] root_cluster,
    output reg  [31:0] total_clusters,

    // 扇区读服务
    output reg         sec_req,
    output reg  [31:0] sec_lba,
    input  wire        sec_valid,
    input  wire [7:0]  sec_data,
    input  wire        sec_done,
    input  wire [3:0]  sec_err,
    output wire        sec_ready
);

    //-------------------------------------------------------------------------
    // 错误编码（低 4 位，顶层映射为 0x3x）
    //-------------------------------------------------------------------------
    localparam [3:0] E_NONE      = 4'd0,
                     E_LBA0      = 4'd1,
                     E_SIG       = 4'd2,
                     E_NO_PART   = 4'd3,
                     E_PART_RD   = 4'd4,
                     E_BPS       = 4'd5,
                     E_SPC       = 4'd6,
                     E_FATSZ     = 4'd7,
                     E_ROOTCLUS  = 4'd8,
                     E_TYPE      = 4'd9,
                     E_NUMFAT    = 4'd10,
                     E_RSVD      = 4'd11;

    // 挂载只需要接收，永远能收
    assign sec_ready = 1'b1;

    //-------------------------------------------------------------------------
    // 状态
    //-------------------------------------------------------------------------
    localparam [3:0] M_IDLE  = 4'd0,
                     M_RD0   = 4'd1,
                     M_CHK0  = 4'd2,
                     M_MBR   = 4'd3,
                     M_RD1   = 4'd4,
                     M_CHK1  = 4'd5,
                     M_PARSE = 4'd6,
                     M_FIN   = 4'd7,
                     M_SPACE = 4'd8,
                     M_SHIFT = 4'd9,
                     M_ROOT  = 4'd10,
                     M_COMMIT= 4'd11;

    reg [3:0]  state;
    reg [3:0]  err_r;
    reg [9:0]  wr_ptr;
    reg [31:0] part_lba_r;
    // Mount is a one-shot control task. Reuse work_count for subtraction and
    // cluster conversion instead of chaining every operation into one clock.
    reg [31:0] used_sec_r, work_count;
    reg [2:0] shift_left;

    //-------------------------------------------------------------------------
    // 扇区里**真正用到的字节**：按偏移捕获（不再整扇区入触发器）
    //   ★ 2026-10-01 改：原为 `reg [7:0] sbuf [0:511]` —— 整个 512 字节扇区都进触发器
    //     （TD 综合出 4096 个 FF），字段读取变成一棵巨大的 mux 树，成为布线后 50MHz 域
    //     最差路径（`sbuf` → `data_lba` 的 CE：15 级逻辑、64% 互连、-0.376ns）。
    //     本模块只用到下面 46 个固定偏移（已全量核对、无动态下标）⇒ 改为按偏移捕获：
    //       · 行为完全等价：未写入前同样是 X；换扇区（sec_req）时同样保留上一扇区的值；
    //       · 省掉 ~4000 个 FF + 消掉 mux 树 ⇒ 既修时序又缓解拥塞。
    //-------------------------------------------------------------------------
    reg [7:0] b011, b012, b013, b014, b015, b016;
    reg [7:0] b032, b033, b034, b035, b036, b037, b038, b039;
    reg [7:0] b044, b045, b046, b047;
    reg [7:0] b082, b083, b084, b085, b086;
    reg [7:0] b450;
    reg [7:0] b454, b455, b456, b457;
    reg [7:0] b466;
    reg [7:0] b470, b471, b472, b473;
    reg [7:0] b482;
    reg [7:0] b486, b487, b488, b489;
    reg [7:0] b498;
    reg [7:0] b502, b503, b504, b505;
    reg [7:0] b510, b511;

    always @(posedge clk) begin
        if (sec_valid) begin
            case (wr_ptr[8:0])
              9'd11:  b011 <= sec_data;
              9'd12:  b012 <= sec_data;
              9'd13:  b013 <= sec_data;
              9'd14:  b014 <= sec_data;
              9'd15:  b015 <= sec_data;
              9'd16:  b016 <= sec_data;
              9'd32:  b032 <= sec_data;
              9'd33:  b033 <= sec_data;
              9'd34:  b034 <= sec_data;
              9'd35:  b035 <= sec_data;
              9'd36:  b036 <= sec_data;
              9'd37:  b037 <= sec_data;
              9'd38:  b038 <= sec_data;
              9'd39:  b039 <= sec_data;
              9'd44:  b044 <= sec_data;
              9'd45:  b045 <= sec_data;
              9'd46:  b046 <= sec_data;
              9'd47:  b047 <= sec_data;
              9'd82:  b082 <= sec_data;
              9'd83:  b083 <= sec_data;
              9'd84:  b084 <= sec_data;
              9'd85:  b085 <= sec_data;
              9'd86:  b086 <= sec_data;
              9'd450: b450 <= sec_data;
              9'd454: b454 <= sec_data;
              9'd455: b455 <= sec_data;
              9'd456: b456 <= sec_data;
              9'd457: b457 <= sec_data;
              9'd466: b466 <= sec_data;
              9'd470: b470 <= sec_data;
              9'd471: b471 <= sec_data;
              9'd472: b472 <= sec_data;
              9'd473: b473 <= sec_data;
              9'd482: b482 <= sec_data;
              9'd486: b486 <= sec_data;
              9'd487: b487 <= sec_data;
              9'd488: b488 <= sec_data;
              9'd489: b489 <= sec_data;
              9'd498: b498 <= sec_data;
              9'd502: b502 <= sec_data;
              9'd503: b503 <= sec_data;
              9'd504: b504 <= sec_data;
              9'd505: b505 <= sec_data;
              9'd510: b510 <= sec_data;
              9'd511: b511 <= sec_data;
              default: ;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_ptr <= 10'd0;
        else if (sec_valid) wr_ptr <= (wr_ptr == 10'd511) ? 10'd0 : (wr_ptr + 10'd1);
        else if (sec_req)   wr_ptr <= 10'd0;
    end

    //-------------------------------------------------------------------------
    // BPB 字段（小端）
    //-------------------------------------------------------------------------
    wire [15:0] f_bps      = {b012, b011};
    wire [7:0]  f_spc      = b013;
    wire [15:0] f_rsvd     = {b015, b014};
    wire [7:0]  f_nfat     = b016;
    wire [31:0] f_totsec   = {b035, b034, b033, b032};
    wire [31:0] f_fatsz    = {b039, b038, b037, b036};
    wire [31:0] f_rootclus = {b047, b046, b045, b044};

    wire f_sig   = (b510 == 8'h55) && (b511 == 8'hAA);
    wire f_fat32 = (b082 == 8'h46) && (b083 == 8'h41) &&
                   (b084 == 8'h54) && (b085 == 8'h33) &&
                   (b086 == 8'h32);                      // "FAT32"

    //-------------------------------------------------------------------------
    // MBR 分区表扫描（类型 0x0B / 0x0C）
    //-------------------------------------------------------------------------
    function is_fat32_type;
        input [7:0] t;
        begin
            is_fat32_type = (t == 8'h0B) || (t == 8'h0C);
        end
    endfunction

    wire p0_ok = is_fat32_type(b450);
    wire p1_ok = is_fat32_type(b466);
    wire p2_ok = is_fat32_type(b482);
    wire p3_ok = is_fat32_type(b498);
    wire any_ok = p0_ok | p1_ok | p2_ok | p3_ok;

    wire [31:0] sel_lba = p0_ok ? {b457, b456, b455, b454} :
                          p1_ok ? {b473, b472, b471, b470} :
                          p2_ok ? {b489, b488, b487, b486} :
                                  {b505, b504, b503, b502};

    //-------------------------------------------------------------------------
    // SecPerClus 校验与 log2
    //-------------------------------------------------------------------------
    wire spc_ok = (f_spc == 8'd1)   || (f_spc == 8'd2)   || (f_spc == 8'd4)  ||
                  (f_spc == 8'd8)   || (f_spc == 8'd16)  || (f_spc == 8'd32) ||
                  (f_spc == 8'd64)  || (f_spc == 8'd128);

    function [3:0] log2_of;
        input [7:0] v;
        begin
            case (v)
                8'd1:   log2_of = 4'd0;
                8'd2:   log2_of = 4'd1;
                8'd4:   log2_of = 4'd2;
                8'd8:   log2_of = 4'd3;
                8'd16:  log2_of = 4'd4;
                8'd32:  log2_of = 4'd5;
                8'd64:  log2_of = 4'd6;
                8'd128: log2_of = 4'd7;
                default: log2_of = 4'd0;
            endcase
        end
    endfunction

    //-------------------------------------------------------------------------
    // 派生参数（组合；NumFATs 只允许 1/2，用移位代替乘法）
    //-------------------------------------------------------------------------
    wire [31:0] nfat_fatsz = (f_nfat == 8'd1) ? f_fatsz : {f_fatsz[30:0], 1'b0};
    wire [31:0] rsvd_x     = {16'd0, f_rsvd};
    wire [31:0] used_sec   = rsvd_x + nfat_fatsz;

    wire overflow_p  = (part_lba_r[31:16] != 16'd0) && (f_rsvd != 16'd0);
    wire underflow_p = (f_totsec < used_sec_r);
    wire rootclus_ok = (f_rootclus >= 32'd2) &&
                       (f_rootclus < (work_count + 32'd2));

    //-------------------------------------------------------------------------
    // 主状态机
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= M_IDLE;
            err_r          <= E_NONE;
            sec_req        <= 1'b0;
            sec_lba        <= 32'd0;
            busy           <= 1'b0;
            done           <= 1'b0;
            err            <= E_NONE;
            part_lba       <= 32'd0;
            fat_lba        <= 32'd0;
            data_lba       <= 32'd0;
            spc_shift      <= 4'd0;
            root_cluster   <= 32'd0;
            total_clusters <= 32'd0;
            part_lba_r     <= 32'd0;
            used_sec_r     <= 32'd0;
            work_count     <= 32'd0;
            shift_left     <= 3'd0;
        end else begin
            done <= 1'b0;

            case (state)
            //-------------------------------------------------------------
            M_IDLE: begin
                if (start && !busy) begin
                    busy     <= 1'b1;
                    err_r    <= E_NONE;
                    sec_req  <= 1'b1;
                    sec_lba  <= 32'd0;
                    state    <= M_RD0;
                end
            end
            //-------------------------------------------------------------
            M_RD0: begin
                sec_req <= 1'b0;
                if (sec_done) begin
                    if (sec_err != 4'd0) begin
                        err_r <= E_LBA0;
                        state <= M_FIN;
                    end else begin
                        state <= M_CHK0;
                    end
                end
            end
            //-------------------------------------------------------------
            M_CHK0: begin
                if (!f_sig) begin
                    err_r <= E_SIG;
                    state <= M_FIN;
                end else if (f_fat32) begin
                    // Superfloppy：LBA0 本身就是 FAT32 引导扇区
                    part_lba_r <= 32'd0;
                    state      <= M_PARSE;
                end else begin
                    state <= M_MBR;
                end
            end
            //-------------------------------------------------------------
            M_MBR: begin
                if (!any_ok) begin
                    err_r <= E_NO_PART;
                    state <= M_FIN;
                end else begin
                    part_lba_r <= sel_lba;
                    sec_req    <= 1'b1;
                    sec_lba    <= sel_lba;
                    state      <= M_RD1;
                end
            end
            //-------------------------------------------------------------
            M_RD1: begin
                sec_req <= 1'b0;
                if (sec_done) begin
                    if (sec_err != 4'd0) begin
                        err_r <= E_PART_RD;
                        state <= M_FIN;
                    end else begin
                        state <= M_CHK1;
                    end
                end
            end
            //-------------------------------------------------------------
            M_CHK1: begin
                if (!f_sig || !f_fat32) begin
                    err_r <= E_TYPE;
                    state <= M_FIN;
                end else begin
                    state <= M_PARSE;
                end
            end
            //-------------------------------------------------------------
            // Validate raw fields first; preserve the original error priority.
            M_PARSE: begin
                if (f_bps != 16'd512) begin
                    err_r <= E_BPS;
                    state <= M_FIN;
                end else if (!spc_ok) begin
                    err_r <= E_SPC;
                    state <= M_FIN;
                end else if (f_rsvd == 16'd0 || overflow_p) begin
                    err_r <= E_RSVD;
                    state <= M_FIN;
                end else if (!(f_nfat == 8'd1 || f_nfat == 8'd2)) begin
                    err_r <= E_NUMFAT;
                    state <= M_FIN;
                end else if (f_fatsz == 32'd0) begin
                    err_r <= E_FATSZ;
                    state <= M_FIN;
                end else begin
                    used_sec_r <= used_sec;
                    state <= M_SPACE;
                end
            end
            M_SPACE: begin
                if (underflow_p) begin
                    err_r <= E_FATSZ;
                    state <= M_FIN;
                end else begin
                    work_count <= f_totsec - used_sec_r;
                    shift_left <= log2_of(f_spc);
                    state <= M_SHIFT;
                end
            end
            M_SHIFT: begin
                if (shift_left == 3'd0) begin
                    state <= M_ROOT;
                end else begin
                    work_count <= {1'b0, work_count[31:1]};
                    shift_left <= shift_left - 3'd1;
                end
            end
            M_ROOT: begin
                if (work_count == 32'd0) begin
                    err_r <= E_FATSZ;
                    state <= M_FIN;
                end else if (!rootclus_ok) begin
                    err_r <= E_ROOTCLUS;
                    state <= M_FIN;
                end else begin
                    state <= M_COMMIT;
                end
            end
            M_COMMIT: begin
                    // Publish together only after all checks succeed. Failures
                    // retain the last successfully mounted output parameters.
                    part_lba       <= part_lba_r;
                    fat_lba        <= part_lba_r + rsvd_x;
                    data_lba       <= part_lba_r + used_sec_r;
                    spc_shift      <= log2_of(f_spc);
                    root_cluster   <= f_rootclus;
                    total_clusters <= work_count;
                    state          <= M_FIN;
            end
            //-------------------------------------------------------------
            M_FIN: begin
                busy  <= 1'b0;
                done  <= 1'b1;
                err   <= err_r;
                state <= M_IDLE;
            end
            //-------------------------------------------------------------
            default: begin
                err_r <= E_SIG;
                state <= M_FIN;
            end
            endcase
        end
    end

endmodule
`default_nettype wire
