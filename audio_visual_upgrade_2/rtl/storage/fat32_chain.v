`default_nettype none
//=============================================================================
// rtl/fat32_chain.v
//   第 2 层：FAT32 簇链查询
//     给定簇号 N，返回簇链中的下一个簇号。
//
//     FAT32 每个 FAT 项 4 字节，因此一个 512 字节 FAT 扇区容纳 128 个簇项：
//       FAT 扇区号 = fat_lba + (N >> 7)
//       扇区内偏移 = (N & 127) * 4
//       下一簇     = (该项 4 字节小端) & 0x0FFFFFFF
//
//     缓存策略（决策 A-17）：把整个 FAT 扇区缓存在片内。
//     一个 FAT 扇区可连续服务 128 个簇，避免"每读一个数据扇区就重读一次 FAT"
//     使吞吐减半。命中缓存时完全不访问 SD 卡。
//
//     本模块由 fat32_scan 与 fat32_read **时间复用**（由顶层编排状态保证互斥）。
//
//-----------------------------------------------------------------------------
// 2026-09-26 修正（v2）：命中路径不再"同拍组合取值"
//-----------------------------------------------------------------------------
// 现象（真卡实测，板上可复现、仿真不可见）：
//   - 命中缓存时读回的 FAT 项是错误的，且错误形态是"高 3 个字节被清 0"：
//       预期 0x0FFFFFFF(EOC) -> 实际 0x000000FF
//       预期 0x00000102(258) -> 实际 0x00000002
//     于是簇链走到 256 以上就拿到非法簇号：50MB 的 BIG.WAV 读到簇 255 后
//     报 E_CHAIN(0x53)，只读了 129 簇（= 簇 127..255）。
//   - 同一簇、同一地址连查 3 次，结果不一致（EOC / 0xFF / 0xFF），
//     而未命中路径（读扇区后隔几百拍再取值）永远正确。
//
// 原因：
//   原实现命中时在**接受请求的同一拍**用组合偏移取值
//       next_cluster <= {4'h0, fbuf[off_c+3..off_c][27:0]};
//   RTL 假设 fbuf 是"组合读"，但综合工具把该数组推断成了**带寄存器输出的
//   分布式 RAM**（见 check_Runs/phy_1/final_timing.rpt：
//       End Point : u_l_chain/ramread0_syn_5117.c[0]   DRAM (reg)
//       Begin Point: u_l_chain/wr_ptr_reg[2]_syn_18.clk
//       VIO hold slack = +0.014ns）
//   即读数据比地址晚一拍，命中路径当拍取到的是无效数据。仿真里数组是零延迟
//   理想模型，所以 ModelSim 永远看不到这个问题。
//
// 修法：命中路径改成和未命中路径**同一套读机制**——
//   先把偏移寄存（entry_off），等 HIT_SETTLE 拍让读数据稳定后再取 entry_mask。
//   地址稳定后任何读延迟都是安全的（未命中路径几百拍后才取值，一直是正确的，
//   就是最好的证明）。命中只发生在跨簇时，多等几拍对吞吐无实际影响。
//
// 验证：仿真无法判定此修正（模型理想），必须上板跑"索引组 2"（含 50MB
//   BIG.WAV）复验：期望 LR2/TR2 = E6B687D1、LB2/TB2 = 03200000。
//   原版留档：doc/fat32_chain_v1_orig.v.txt
//=============================================================================
module fat32_chain (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req,           // 单周期脉冲；仅 busy=0 时接受
    input  wire [31:0] cluster,
    output reg         busy,
    output reg         done,          // 1 拍脉冲
    output reg  [3:0]  err,           // 0=OK 1=FAT 扇区读失败
    output reg  [31:0] next_cluster,  // 已屏蔽高 4 位

    // 文件系统参数
    input  wire [31:0] fat_lba,
    input  wire [31:0] total_clusters,

    // 扇区读服务
    output reg         sec_req,
    output reg  [31:0] sec_lba,
    input  wire        sec_valid,
    input  wire [7:0]  sec_data,
    input  wire        sec_done,
    input  wire [3:0]  sec_err,
    output wire        sec_ready
);

    localparam [3:0] E_NONE = 4'd0,
                     E_FAT  = 4'd1;

    // 命中后等待读数据稳定的拍数（>=1 即可覆盖"寄存器输出"的读延迟；
    // 取 3 留余量。地址在这几拍内保持不变，任何读延迟都已稳定。）
    parameter [2:0] HIT_SETTLE = 3'd3;

    assign sec_ready = 1'b1;   // 缓存永远能接收

    //-------------------------------------------------------------------------
    // FAT 扇区缓存 = 块 RAM 原语（128 字 × 32 位 = 4 Kbit，单口 SP、读延迟 1 拍）
    //   为什么用原语：v2 的 `reg [7:0] fbuf [0:511]` 被 TD 推成**分布式 RAM（reg）**
    //   ⇒ 单实例 2063 LUT（产品树 41%）；换成 EG_LOGIC_BRAM 后只占 1 个 BRAM9K。
    //   映射（逐位等价）：byte 地址 b -> 字地址 b[8:2]、字内字节 b[1:0]（小端）
    //     读  word_r = {fbuf[o+3],fbuf[o+2],fbuf[o+1],fbuf[o]}  ==  BRAM[o[8:2]]
    //     写  fbuf[b] <= sec_data（b0,b1,b2,… 顺序）         ==  每 4 字节写
    //         dia = {sec_data, wr_word_r[31:8]} = {b3,b2,b1,b0}
    //   实例在文件末尾（本工程不允许先用后声明：声明在前、实例/赋值在末尾）。
    //-------------------------------------------------------------------------
    reg  [31:0] wr_word_r;         // 字节拼字寄存器（低→高右移入）
    reg  [8:0]  wr_cnt;            // 已收字节计数 0..511（原 wr_ptr 的语义）
    reg  [31:0] cache_lba;
    reg         cache_valid;

    reg [2:0]  state;
    reg [3:0]  err_r;
    reg [31:0] tgt_lba;
    reg [8:0]  entry_off;
    reg [2:0]  settle;

    localparam [2:0] C_IDLE = 3'd0,
                     C_REQ  = 3'd1,
                     C_HIT  = 3'd2,
                     C_FIN  = 3'd3;

    // 目标 FAT 扇区与扇区内偏移（必须在 always 块之前声明：本工程用
    // `default_nettype none`，不允许先用后声明）
    wire [31:0] tgt_c = fat_lba + {7'd0, cluster[31:7]};
    wire [8:0]  off_c = {cluster[6:0], 2'b00};              // (N & 127) * 4
    wire        hit_c = cache_valid && (cache_lba == tgt_c);

    // ---- 块 RAM 端口（声明必须在 always / 实例之前）----
    wire [6:0]  wr_word   = wr_cnt[8:2];      // 正在填充的字地址 0..127
    wire [1:0]  wr_phase  = wr_cnt[1:0];      // 字内字节相位 0..3
    wire        fbuf_fill = sec_valid && (state == C_REQ);
    wire        fbuf_we   = fbuf_fill && (wr_phase == 2'd3);  // 第 4 字节写一次
    wire [31:0] wr_word_n = {sec_data, wr_word_r[31:8]};      // = {b3,b2,b1,b0}
    // 端口复用：填充期间给字地址（写端口），其余时间给寄存后的读偏移。
    //   读延迟 1 拍（REGMODE_A=NOREG）：命中路径由 HIT_SETTLE=3 覆盖；
    //   未命中路径的取值在 sec_done 那一拍，而最后一个 sec_valid 至少早 32 拍
    //   （sd_block_read 的 R_CRC/R_TAIL/R_END）⇒ addra 早已稳定、读到完整字。
    //   ⇒ 填充与读取天然不同拍，单口无冲突。
    wire [6:0]  fbuf_addra = fbuf_fill ? wr_word : entry_off[8:2];
    wire [31:0] fbuf_doa;

    // 统一用**寄存后的** entry_off 取值（命中/未命中同一条通路）。
    // 注意：命中路径必须在接受请求后等 HIT_SETTLE 拍再取，
    //       不能用当拍的组合偏移——那是 v1 在真卡上读错数据的原因。
    wire [31:0] word_r     = fbuf_doa;        // 一次读 32 位（原为并行读 4 字节）
    wire [31:0] entry_mask = {4'h0, word_r[27:0]};

    // 字节计数：只有真正要填充（未命中）时才清 0，填充期间逐字节递增。
    // （原版在每次接受请求时都清 0；现在不让命中路径去动它，避免无谓翻转。）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_cnt <= 9'd0;
        else if (fbuf_fill) wr_cnt <= wr_cnt + 9'd1;
        else if (state == C_IDLE && req && !busy && !hit_c) wr_cnt <= 9'd0;
    end

    // 拼字寄存器：每个收到的字节右移入；第 4 字节时 dia 即完整的 {b3,b2,b1,b0}。
    // 复位只是为了仿真不留 X（前 3 个字节在写入前总会被覆盖）。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_word_r <= 32'd0;
        else if (fbuf_fill) wr_word_r <= wr_word_n;
    end

    //-------------------------------------------------------------------------
    // 主状态机
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= C_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            err          <= E_NONE;
            err_r        <= E_NONE;
            sec_req      <= 1'b0;
            sec_lba      <= 32'd0;
            next_cluster <= 32'd0;
            cache_lba    <= 32'd0;
            cache_valid  <= 1'b0;
            tgt_lba      <= 32'd0;
            entry_off    <= 9'd0;
            settle       <= 3'd0;
        end else begin
            done <= 1'b0;

            case (state)
            //-------------------------------------------------------------
            C_IDLE: begin
                if (req && !busy) begin
                    busy      <= 1'b1;
                    err_r     <= E_NONE;
                    entry_off <= off_c;          // 偏移先寄存（两种路径都一样）
                    if (hit_c) begin
                        // 命中：不访问 SD 卡，但要等读数据稳定
                        settle <= HIT_SETTLE;
                        state  <= C_HIT;
                    end else begin
                        tgt_lba <= tgt_c;
                        sec_req <= 1'b1;
                        sec_lba <= tgt_c;
                        state   <= C_REQ;
                    end
                end
            end
            //-------------------------------------------------------------
            C_HIT: begin
                if (settle == 3'd0) begin
                    next_cluster <= entry_mask;  // 地址已稳定，取值安全
                    state        <= C_FIN;
                end else begin
                    settle <= settle - 3'd1;
                end
            end
            //-------------------------------------------------------------
            C_REQ: begin
                sec_req <= 1'b0;
                if (sec_done) begin
                    if (sec_err != 4'd0) begin
                        err_r <= E_FAT;
                    end else begin
                        cache_lba    <= tgt_lba;
                        cache_valid  <= 1'b1;
                        next_cluster <= entry_mask;
                    end
                    state <= C_FIN;
                end
            end
            //-------------------------------------------------------------
            C_FIN: begin
                busy  <= 1'b0;
                done  <= 1'b1;
                err   <= err_r;
                state <= C_IDLE;
            end
            //-------------------------------------------------------------
            default: state <= C_IDLE;
            endcase
        end
    end

    // total_clusters 保留在接口中用于文档完整性；本模块只做取值，
    // 簇号合法性由调用方（fat32_scan / fat32_read）按 CHN-05 判定。

    //-------------------------------------------------------------------------
    // FAT 扇区缓存：EG_LOGIC_BRAM 128×32（4 Kbit = 1 个 BRAM9K）
    //   原语由 TD 宏库提供（arch/eagle_macro.v）；仿真侧用厂商行为模型
    //   sim/vendor/eg_logic_bram.v（取自 TD sim_release/eg4/）。
    //   MODE="SP" 单口、REGMODE_A="NOREG" 读延迟 1 拍、WRITEMODE_A="NORMAL"。
    //   B 口整体空置；rsta 接 0（本设计自己管初值，不依赖 BRAM 复位语义）。
    //-------------------------------------------------------------------------
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A (32),
        .DATA_WIDTH_B (32),
        .ADDR_WIDTH_A (7),
        .ADDR_WIDTH_B (7),
        .DATA_DEPTH_A (128),
        .DATA_DEPTH_B (128),
        .BYTE_ENABLE  (0),
        .BYTE_A       (1),
        .BYTE_B       (1),
        .MODE         ("SP"),
        .REGMODE_A    ("NOREG"),
        .REGMODE_B    ("NOREG"),
        .WRITEMODE_A  ("NORMAL"),
        .WRITEMODE_B  ("NORMAL"),
        .RESETMODE    ("SYNC"),
        .DEBUGGABLE   ("NO"),
        .PACKABLE     ("NO"),
        .FORCE_KEEP   ("OFF"),
        .INIT_FILE    ("NONE"),
        .FILL_ALL     ("NONE"),
        .IMPLEMENT    ("9K")
    ) u_fbuf (
        .dia   (wr_word_n),
        .addra (fbuf_addra),
        .cea   (1'b1),
        .ocea  (1'b1),
        .clka  (clk),
        .wea   (fbuf_we),
        .rsta  (1'b0),
        .bea   (1'b0),
        .dib   (32'd0),
        .addrb (7'd0),
        .ceb   (1'b0),
        .oceb  (1'b0),
        .clkb  (clk),
        .web   (1'b0),
        .rstb  (1'b0),
        .beb   (1'b0),
        .doa   (fbuf_doa),
        .dob   ()
    );

endmodule
`default_nettype wire
