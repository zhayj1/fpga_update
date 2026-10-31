`default_nettype none
//============================================================================
// rtl/load/bmp_load.v —— BMP(BMP3/24bit 非压缩) → SDRAM 图像槽装载器（P1-①）
//
// 规格：doc/spec/bmp_load_behavior_spec.md（端口/判据/错误码/FSM 全在里面）
// 依据：doc/HANDOVER.md §11（契约 + 6 条不变量）、doc/design_music_player.md
//       §3.1（两条 ★ 注：字节打包 / 突发粒度）、§4.1（跨域一律异步 FIFO）、
//       §4.3（lo 反压契约）、§10.1（帧签名判据）
//
// 两个时钟域（**物理事实**，见 design §4.1 与 skeleton_core.v 现状）：
//   · clk     = 50MHz ：lo 字节流（storage_top）+ 控制/状态（与 load_sched 同域）
//   · clk_sdr = 150MHz：ld 写口（sdram_arb）
//   跨域用厂商 afifo_8i_32o_1024（rtl/ip/，逐字节不改）+ 2 组"稳定数据+翻转"握手。
//
// 数据通路（A 侧 → FIFO → B 侧）：
//   A：解析 54 字节 BMP3 头 → 按行吃像素 → BGR 字节序改写成 RGB → 行末补 8'h00 到 16B
//      → 逐字节推进 8bit/32bit 异步 FIFO（字内小端 ⇒ 取出即 design §3.1 的打包字）
//   B：从 FIFO 取 32bit 字 → 以**不跨行**的突发写进 sdram_arb 的 ld 口；
//      bottom-up 图逐行**递减**行基址（行序翻转在此完成），top-down 图递增。
//
// ★ 与 design §3.1 第二条 ★ 的关系（实现级偏差，理由见规格 §4）：
//   硬约束"突发不得跨行（地址单调 +1 且行序翻转要求递减）"**完整保留**；
//   只是把"每行一次突发 + 整行缓冲"改成"行内流式突发"⇒ 省掉 1920B 行缓冲
//   （否则需要一块跨 `clk`/`clk_sdr` 的双时钟 RAM，属综合推断风险）。
//   写入 SDRAM 的字节序列与逐行地址**与整行突发方案逐字节相同**。
//
// ★ 接口要点（照上游实测契约，勿改）：
//   1. sdram_arb 的 `ld_data` 是 **FWFT** ⇒ 直接接 FIFO 的 `dout`；
//      `ld_req` 必须在 `ld_ack` 的**下一拍**撤（不是等 `ld_done`），否则会被当成新请求重跑；
//   2. `ld_len` 必须 **≥1**：arb 在 len=0 时仍会发一次写使能 ⇒ 会多写一个字；
//   3. storage_top 的 `lo_rd_eof` 是 **单拍脉冲**（storage_top.v:657 每拍默认清零）
//      ⇒ 本模块用 `eof_seen` 锁存；`lo_rd_err` 是电平（下次 lo_accept 才清）；
//   4. lo 流必须**读干净到 eof/err** 才报 done：否则 storage_top 停在 T_READ，
//      下一次 lo_open 会被拒（err_code=0x63）。
//
// 未验证：TD 综合资源/时序、§8 的跨域约束是否落到位、真机上板（见规格 §9）。
//============================================================================
module bmp_load #(
    // 行缓冲/尺寸上限：MAX_W 同时决定 words_per_row 上限（640 ⇒ 1920B/行 ⇒ 480 字/行）
    parameter integer MAX_W  = 640,
    parameter integer MAX_H  = 480,
    // 看门狗：等待态连续多久无进展判超时（拍数 = CLK_HZ/1000*WD_MS）
    parameter integer CLK_HZ = 50000000,
    parameter integer WD_MS  = 2500,
    parameter integer EXTERNAL_BACKEND = 0,
    // Zero preserves the caller's wd_max for every phase. A mailbox-based
    // reader needs a separate, bounded wait for complete SD/FAT transactions.
    parameter integer STREAM_WD_MS = 0,
    // Normalize while consuming the source stream; no source row/frame RAM.
    parameter integer DOWNSCALE = 0,
    parameter integer SRC_MAX_W = 4096,
    parameter integer SRC_MAX_H = 4096,
    parameter integer BG_W = 640, parameter integer BG_H = 480,
    parameter integer COVER_W = 240, parameter integer COVER_H = 240,
    parameter integer MAX_FILE_BYTES = 67108864
)(
    // ---------------- 控制/状态（clk 域，与 storage_top / load_sched 同域）----------------
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,           // 脉冲：启动一次装载（busy 期间被忽略）
    input  wire        target_cover,    // DOWNSCALE: sampled with accepted start
    input  wire [7:0]  file_index,      // 文件表索引（start 前 ≥2 拍建立，保持到 done）
    input  wire [20:0] slot_base,       // 目标槽基址（32bit 字地址）
    output reg         busy,
    output reg         done,            // 单拍脉冲：本次装载结束（成功或失败）
    output reg  [7:0]  err,             // 错误码，done 那拍有效并保持到下次 start
    output reg  [15:0] img_w,
    output reg  [15:0] img_h,

    // ---------------- lo 读流（storage_top，clk 域）----------------
    output reg         lo_open,         // 单拍脉冲
    output reg  [7:0]  lo_open_index,
    input  wire        lo_open_busy,
    input  wire        lo_rd_valid,
    input  wire [7:0]  lo_rd_data,
    output wire        lo_rd_ready,     // ★ 组合译码（必须与"本拍真的吃字节"逐拍一致）
    output wire        lo_want,         // 本模块的取数需求（顶层须与 §4.2 音频水位策略相与）
    input  wire        lo_rd_eof,       // ★ 单拍脉冲
    input  wire        lo_rd_err,       // 电平
    input  wire [31:0] file_size,
    // ★★★ 2026-10-10：**运行期可切换的看门狗门限**（拍，`clk` 域）✓
    //   【为什么必须可切换，而不是把 `WD_MS` 一刀切放大】
    //     · `WD_MS=1`（1ms）是按**独占卡**标定的：那时卡侧字节连续 ✓
    //     · 卡与音频**共用**时，两次"吃到字节"之间可能有几十 ms 空档 ⇒ 1ms 必然误判 ✗
    //       （实测：并发装载 `err=04`、只写 3,826/7,680 ✗；连开机那几笔也被打断 ✗）
    //     · 但**一刀切放大到 200ms 会把开机弄坏** ✗（实测）：开机那笔装载若在 `A_WIDLE`
    //       等 `bidle_pend`，本来 **1ms** 就被看门狗救回 ✓，放大后要**等满 200ms** ✗ ⇒ 开机崩 ✓
    //   ⇒ 顶层按**上下文**给：开机 1ms ／ 并发（`cwp_active`）≈200ms ✓
    //   ★ 代价：一个 32 位比较器、**0 块 BRAM** ✓
    input  wire [31:0] wd_max,

    // ---------------- ld 写口（sdram_arb，clk_sdr 域）----------------
    input  wire        clk_sdr,
    input  wire        rst_sdr_n,
    output wire        ld_req,
    output wire [20:0] ld_addr,
    output wire [15:0] ld_len,
    output wire [31:0] ld_data,         // FWFT：直接接 FIFO 的 dout
    input  wire        ld_rd,
    input  wire        ld_ack,
    input  wire        ld_done,
    input wire fifo_full_ext, input wire backend_done_ext,
    input wire [18:0] slot_words,
    output wire fifo_flush_ext, output wire fifo_we_ext,
    output wire [7:0] fifo_di_ext,
    output wire cfg_valid_ext, output wire [20:0] cfg_first_ext,
    output wire [18:0] cfg_words_ext, output wire [15:0] cfg_wpr_ext,
    output wire cfg_down_ext,
    output wire finish_valid_ext, output wire [18:0] finish_words_ext
);

    //=========================================================================
    // 0. 参数派生
    //=========================================================================
    localparam integer WD_MAX = (CLK_HZ / 1000) * WD_MS;   // 看门狗上限（拍）
    // Only counters used after the complete header checks may use these
    // bounds. Keep header fields, geometry checks and error-path CFG full width.
    function integer count_width;
        input integer maximum;
        integer value;
        begin
            value=maximum; count_width=0;
            while(value>0) begin count_width=count_width+1; value=value/2; end
            if(count_width==0) count_width=1;
        end
    endfunction
    localparam integer SOURCE_W = DOWNSCALE ? SRC_MAX_W : MAX_W;
    localparam integer SOURCE_H = DOWNSCALE ? SRC_MAX_H : MAX_H;
    localparam integer ROW_BYTE_W = count_width(SOURCE_W * 3);
    localparam integer ROW_COUNT_W = count_width(SOURCE_H);
    localparam integer X_PHASE_W = count_width(SOURCE_W * 2);
    localparam integer Y_PHASE_W = count_width(SOURCE_H * 2);

    // A 侧状态（clk 域）
    localparam [3:0] A_IDLE  = 4'd0,
                     A_FRST  = 4'd1,    // FIFO 冲洗
                     A_OPENW = 4'd2,    // 等 storage 空闲
                     A_OPENP = 4'd3,    // 拉 lo_open 一拍
                     A_HDR   = 4'd4,    // 吃 54 字节头
                     A_HCHK  = 4'd5,    // 判据 + 派生量 + 发布 cfg
                     A_SKIP  = 4'd6,    // 跳过 bfOffBits-54
                     A_PIX   = 4'd7,    // 吃像素、改字节序、推 FIFO
                     A_PAD   = 4'd8,    // 丢 BMP 行补字节
                     A_ZPAD  = 4'd9,    // 推 8'h00 补到 16B
                     A_END   = 4'd10,   // 发布 a_words/a_end
                     A_DRAIN = 4'd11,   // 把 lo 流读干净到 eof/err
                     A_WIDLE = 4'd12,   // 等 B 侧 b_idle
                     A_FIN   = 4'd13;   // done

    // A_PIX 的像素相位
    localparam [1:0] PX_B = 2'd0, PX_G = 2'd1, PX_R = 2'd2, PX_PUSH = 2'd3;

    // B 侧状态（clk_sdr 域）


    //=========================================================================
    // 1. 跨域异步 FIFO（**BRAM 版**：8bit 写 / 32bit 读，1024 字节等效，FWFT）
    //    ★ 2026-10-03 由厂商 `afifo_8i_32o_1024` 换成自建 `afifo_8i_32o_bram`
    //      （工单 doc/workitem_fifo_bram.md，用户指令"不能占 LUT"）：
    //      厂商件内部 1KB 缓冲被综合成 **1117 LUT + 32 触发器**（`bram` 列 = 0 ✗），
    //      根因是 `MODE("SDP")` 的 8i/32o 非对称 RAM ⇒ 新件把**打包搬到写域触发器**
    //      （攒满 4 字节再写一次 RAM），RAM 变**对称 32→32 + MODE("DP") + 深度 256**
    //      ⇒ 落 BRAM ✓。★ 口径：实测 **2 块 9K**（EG4 的 9K 块是 512×18 ⇒ 32 位宽要 2 块并排 ✓，
    //      `#bram` 28→30 ✓），换来 FIFO 子树 **1258→150 LUT** ✓。
    //      **端口/参数名逐一对齐 ⇒ 本文件只改了这一行例化名 ✓**
    //      （连 TB 里的 `u_dut.u_fifo.rdusedw` 都不用改 ✓）。
    //    实测语义（未变）：
    //      · SHOW_AHEAD_EN=1 ⇒ `dout` 常驻 head 字（不拉 re 也能读）
    //      · `rdusedw` 以 **32bit 字**为单位且**保守**（写指针格雷码同步，滞后不超前）
    //      · `rst` 一拍即清空
    //    ⇒ 突发前判 `rdusedw >= len` 即可保证中途不取空；`re` 只在突发中拉高。
    //    ⚠ 不用 `wrusedw`（厂商件以 8bit 写单位计并对读指针做 >>2 量化；
    //      新件按"整字×4"计、容量 255 字 ⇒ 语义都不适合判满 ✓）。
    //    等价性证据：`tb/tb_afifo_bram.v` 与厂商件**背靠背逐拍对拍** 8/8 PASS ✓
    //      （`dout/rdusedw/empty/valid/aempty/full/afull` 全等，`eq_err=0` ✓）。
    //=========================================================================
    reg fifo_flush;
    wire fifo_full, fifo_we;
    wire [7:0] fifo_di;
    wire backend_done;
    reg cfg_valid_int, finish_valid_int, cfg_issued;
    reg  [3:0]  st;
    reg  [3:0]  st_d;                // 看门狗用：上一拍状态
    reg  [1:0]  px;
    reg  [7:0]  px_b, px_g, px_r;    // 本像素暂存（文件序 B,G,R）
    reg  [1:0]  pcnt;                // 推 FIFO 相位计数 0..2
    reg  [5:0]  frst_cnt;
    reg  [5:0]  hcnt;                // 头字节计数 0..53
    reg  [7:0]  magic_b0, magic_b1;
    reg  [31:0] bf_size_i, bf_off_i, bi_size_i, bi_width_i, bi_height_i;
    reg  [15:0] bi_planes_i, bi_bpp_i;
    reg  [31:0] bi_comp_i;
    reg  [31:0] skip_left;
    reg  [31:0] rd_bytes;            // 本次从 lo 吃掉的字节数
    reg  [20:0] wr_bytes;            // Only [20:2] is published in finish_words.
    reg  [ROW_BYTE_W-1:0] row_bytes, w3_r; // 0..MAX_W*3, after header validation
    reg  [1:0] pbleft, padb_r;       // BMP row padding 0..3 bytes
    reg  [3:0] zleft, padz_r;        // SDRAM row padding 0..15 bytes
    reg  [ROW_COUNT_W-1:0] row_cnt, h_r; // 0..MAX_H, after header validation
    reg cover_r;
    reg [X_PHASE_W-1:0] x_phase;
    reg [Y_PHASE_W-1:0] y_phase;
    wire [15:0] target_w = cover_r ? COVER_W : BG_W;
    wire [15:0] target_h = cover_r ? COVER_H : BG_H;
    wire [X_PHASE_W-1:0] x_step = {target_w,1'b0};
    wire [Y_PHASE_W-1:0] y_step = {target_h,1'b0};
    wire keep_row = !DOWNSCALE || (y_phase < y_step);
    wire keep_pixel = !DOWNSCALE || (x_phase < x_step);
    reg  [20:0] cfg_first;           // ↓ 发布给 B 侧（跨域，稳定数据）
    reg  [15:0] cfg_wpr;
    reg  [18:0] cfg_words;           // 本次图像总字数 = H*words_per_row（B 侧的收口基准）
    reg         cfg_bu;

    reg  [18:0] a_words;             // 本次推入 FIFO 的完整字数

    reg  [7:0]  err_hold;
    reg         eof_seen;            // ★ lo_rd_eof 单拍脉冲的锁存
    reg  [31:0] wd;                  // 看门狗计数
    reg         gave_up;
    reg  [1:0]  open_wait;           // ★★★ 2026-10-10：`A_OPENP` 里"打开后等 2 拍"的计数器 ✓
                                     //   （让共用读口的锁存值在**第一次使用之前**就绪 ✓ 见 `A_OPENP` 注释 ✓）
             // B→A 同步链

    reg         bidle_pend;          // 事件锁存（A 可能晚几拍才来消费它）

    assign fifo_flush_ext = fifo_flush;
    assign fifo_we_ext = fifo_we;
    assign fifo_di_ext = fifo_di;
    assign cfg_valid_ext = cfg_valid_int;
    assign cfg_first_ext = cfg_first;
    assign cfg_words_ext = cfg_words;
    assign cfg_wpr_ext = cfg_wpr;
    assign cfg_down_ext = cfg_bu;
    assign finish_valid_ext = finish_valid_int;
    assign finish_words_ext = a_words;
    generate if (EXTERNAL_BACKEND) begin : g_external
        assign fifo_full = fifo_full_ext;
        assign backend_done = backend_done_ext;
        assign ld_req = 1'b0;
        assign ld_addr = 21'd0;
        assign ld_len = 16'd0;
        assign ld_data = 32'd0;
    end else begin : g_standalone
        load_writeback u_writeback (
            .clk(clk), .rst_n(rst_n), .clk_sdr(clk_sdr), .rst_sdr_n(rst_sdr_n),
            .flush(fifo_flush), .byte_we(fifo_we), .byte_data(fifo_di), .full(fifo_full),
            .cfg_valid(cfg_valid_int), .cfg_first(cfg_first), .cfg_words({1'b0,cfg_words}),
            .cfg_wpr(cfg_wpr), .cfg_rows(1'b1), .cfg_down(cfg_bu),
            .finish_valid(finish_valid_int), .finish_words({1'b0,a_words}), .done(backend_done),
            .ld_req(ld_req), .ld_addr(ld_addr), .ld_len(ld_len), .ld_data(ld_data),
            .ld_take(ld_rd), .ld_ack(ld_ack), .ld_done(ld_done)
        );
    end endgenerate

    //-------------------------------------------------------------------------
    // 2.1 头字段派生量（组合，值来自已寄存的头字段）
    //     `span_w = H*words_per_row` 是本模块**唯一**的乘法。
    //
    // ★★ 2026-10-04（**S2 时序报告实测** ✗→✓）：这里原来"组合算出 ⇒ 当拍进判据/进 FSM"
    //   ⇒ clk0（50MHz，20ns 预算）上形成一条 **20.156ns / 13 级（ADDER=8 + MULT18）** 的路径 ✗，
    //    slack **−0.436ns**、且**一次占满 9 条违例端点里的 8 条** ✗
    //    （端点全是 `u_load/*`：`padz_r/w3_r/st_reg/px_reg/bidle_pend…` ✗）。
    //   这条路径在本工程历史上**长期贴在 0 附近**（编译笔记里记过 −0.665ns ✗）。
    //
    //   【修法：加一级流水**只切路径、不改逻辑** ✓】
    //     时序违例的本质不是"链太慢"✗，而是"**整条链必须在一个 20ns 里走完**"✗：
    //     在乘法**之前**寄存一拍 ⇒ 链被切成
    //       ① `bi_* → w3 → sts → wpr`（≈6 级 ✓）
    //       ② `寄存后的 wpr/hmag → MULT18 → add → 比较/st_en`（≈5 级 ✓）
    //     两段**各自**重新获得一个完整的 20ns ✓（总门延迟**一点没变** ✗，用一拍延迟换一次周期预算 ✓）。
    //
    //   【为什么这里是**功能透明**的 ✓（不是"试试看" ✗）】
    //     判据只在 `A_HCHK` 用一次 ✓，而 `A_HCHK` 是在**第 53 字节之后一拍**才进入的 ✓；
    //     最后一个被判的字段 `bi_comp_i`（字节 30..33 ✓）早在 `hcnt==33` 就写完 ✓
    //     —— 中间隔了 **20 拍** ⇒ 进 `A_HCHK` 时这些派生量的**组合值与寄存值必然相同** ✓✓
    //     ⇒ 判据结果、`cfg_*` 发布值、`w3_r/padb_r/padz_r/...` 全部逐字不变 ✓。
    //     （装载器按 SPI 字节流走 ✓，多一拍 20ns 相对字节间隔可忽略 ✓）
    //-------------------------------------------------------------------------
    wire [31:0] hmag_w = bi_height_i[31] ? (~bi_height_i + 32'd1) : bi_height_i;
    wire [31:0] w3_w   = {bi_width_i[30:0], 1'b0} + bi_width_i;         // *3
    wire [31:0] stb_w  = (w3_w + 32'd3)  & 32'hFFFFFFFC;                // BMP 行跨距（4B 对齐）
    wire [31:0] dest_w3 = DOWNSCALE ? (cover_r ? COVER_W*3 : BG_W*3) : w3_w;
    wire [31:0] sts_w  = (dest_w3 + 32'd15) & 32'hFFFFFFF0;              // destination stride
    wire [15:0] wpr_w  = sts_w[17:2];                                   // 行字数
    // Alignment differences are modular: even malformed 32-bit widths produce
    // the same 0..3 / 0..15 result as the former twelve-bit subtractors.
    wire [1:0] padb_w = 2'd0 - w3_w[1:0];
    wire [3:0] padz_w = 4'd0 - dest_w3[3:0];
    wire        bu_w   = (bi_height_i[31] == 1'b0);                     // 正高 ⇒ bottom-up
    // Select constant target spans so enabled normalization needs no multiplier.
    wire [31:0] span_w = DOWNSCALE ?
        (cover_r ? COVER_H*((COVER_W*3+15)/16)*4 : BG_H*((BG_W*3+15)/16)*4) :
        hmag_w * {16'd0, wpr_w};
    wire [21:0] enda_w = {1'b0, slot_base} + span_w[21:0];              // 槽尾（开区间）
    wire [20:0] first_w = bu_w ? (slot_base + span_w[20:0] - {5'd0, wpr_w}) : slot_base;

    // ---- ★ 流水级（上面那套派生量寄存一拍 ✓；判据与发布一律用 `*_s` ✓）----
    reg  [31:0] hmag_s, w3_s, span_s;
    reg  [15:0] wpr_s;
    reg  [1:0] padb_s;
    reg  [3:0] padz_s;
    reg  [21:0] enda_s;
    reg  [20:0] first_s;
    reg         bu_s;
    always @(posedge clk) begin
        hmag_s <= hmag_w;   w3_s   <= w3_w;    wpr_s  <= wpr_w;
        padb_s <= padb_w;   padz_s <= padz_w;  span_s <= span_w;
        enda_s <= enda_w;   first_s<= first_w; bu_s   <= bu_w;
    end

    //-------------------------------------------------------------------------
    // 2.2 头部判据（顺序固定，取第一个命中；见规格 §5）
    //-------------------------------------------------------------------------
    //     ★ 判据里的**派生量一律用流水后的 `*_s`** ✓（见 §2.1 的说明：进 A_HCHK 时
    //       组合值与寄存值必然相同 ⇒ 结果逐字不变 ✓；而路径从 20.156ns 切成两段 ✓）
    reg  [7:0] hchk_err;
    always @(*) begin
        hchk_err = 8'h00;
        if      ((magic_b0 != 8'h42) || (magic_b1 != 8'h4D)) hchk_err = 8'h01; // 'B','M'
        else if (bi_size_i != 32'd40)                        hchk_err = 8'h01; // 非 BMP3
        else if (bi_width_i[31] || (bi_width_i == 32'd0))    hchk_err = 8'h01;
        else if (bi_width_i > SOURCE_W)                      hchk_err = 8'h02;
        else if (bi_height_i == 32'd0)                       hchk_err = 8'h01;
        else if (hmag_s > SOURCE_H)                          hchk_err = 8'h06;
        else if (bi_planes_i != 16'd1)                       hchk_err = 8'h05;
        else if (bi_bpp_i    != 16'd24)                      hchk_err = 8'h05;
        else if (bi_comp_i   != 32'd0)                       hchk_err = 8'h05;
        else if (bf_off_i < 32'd54)                          hchk_err = 8'h01;
        else if (DOWNSCALE && file_size > MAX_FILE_BYTES)    hchk_err = 8'h09;
        else if (DOWNSCALE && (bi_width_i < {16'd0,target_w} ||
                                hmag_s < {16'd0,target_h})) hchk_err = 8'h08;
        else if (DOWNSCALE && (cover_r ? bi_width_i != hmag_s :
                                  w3_s != (hmag_s << 2)))   hchk_err = 8'h07;
        else if (enda_s > 22'd2097152)                       hchk_err = 8'h02; // 槽越界（2^21 字）
    end

    //-------------------------------------------------------------------------
    // 2.3 消费/等待分类 + 看门狗
    //-------------------------------------------------------------------------
    wire a_consume  = (st == A_HDR) | (st == A_SKIP) | (st == A_PIX) |
                      (st == A_PAD) | (st == A_DRAIN);
    // ★★ 2026-10-09（Step 0 实测暴露的**潜藏 bug**）：`a_wait` 原来**漏了 `A_OPENP`** ✗
    //   而 `A_OPENP` 正是"等 storage 应答"的那个状态 —— 讽刺的是**它自己的代码里就有
    //   `wd_hit` 的处理分支**（`err_hold <= 8'h04; ...`）✗，可 `a_wait` 不算它
    //   ⇒ **看门狗在那个状态永远不计数** ⇒ 卡被占住时**既不报错、也不结束**，
    //     `busy` 永久为 1 ✓（本次实测：探针发起 20 次、`done` 一次没来、末尾 `busy=1` ✓）
    //   ⇒ 口径改成"**只要不在空闲、也不在收尾，就算在等**" ✓
    //     （`A_IDLE` = 没干活；`A_FIN` = 已经出 done ⇒ 这两个不该被计数 ✓）
    wire a_wait     = (st != A_IDLE) && (st != A_FIN);
    wire accept_now = a_consume & lo_rd_valid & lo_rd_ready;

    // ★★ `lo_rd_ready` / `lo_want` 必须是**组合**译码，逐拍与"本模块真的会吃这个字节"一致。
    //   曾经的写法是在 always 里"该状态不赋 1"（寄存器保持），结果 A_PIX 的 3 拍推 FIFO 相位
    //   里 ready 仍为 1：字节源按 valid/ready 交付了一个字节（fat32_read 的 `if (dready) out_v<=0`
    //   就是这语义），而本模块当时并不取它 ⇒ **每像素丢 1 字节**，整幅图逐字节漂移
    //   （在纯色区看不出来，一进花纹区就大面积不符）。TB 的 BURST 追踪一击定位。
    wire px_push    = (st == A_PIX) && (px == PX_PUSH) && !fifo_full;
    wire zpad_push  = (st == A_ZPAD) && keep_row && (zleft != 4'd0) && !fifo_full;
    wire [7:0] px_byte = (pcnt == 2'd0) ? px_r : ((pcnt == 2'd1) ? px_g : px_b);

    //   ★ 同一类错误的第二个实例：`A_PAD` 在 `pbleft==0` 时**本拍不取字节**就直接去 A_ZPAD，
    //     但 ready 若仍为 1，字节源就会白白交付 1 个字节 ⇒ **每行丢 1 字节**（480 行 = 480B = 120 字）。
    //     所以 ready 的每一项都必须与"该状态真的会取字节"的条件逐字一致。
    assign lo_rd_ready = (st == A_HDR) | (st == A_SKIP) | (st == A_DRAIN) |
                         ((st == A_PIX) & (px != PX_PUSH)) |
                         ((st == A_PAD) & (pbleft != 2'd0));
    assign lo_want     = (st == A_HDR) | (st == A_SKIP) | (st == A_PIX) |
                         (st == A_PAD) | (st == A_DRAIN);

    // ★ FIFO 写口也做**组合**：`we`/`di` 与 FSM 的计数在同一拍生效，避免"寄存一拍后
    //   恰好 full_flag 变化 ⇒ FIFO 丢掉这次写而计数已经加过"的潜在丢字节（见 §8 风险）。
    assign fifo_we = px_push | zpad_push;
    assign fifo_di = px_push ? px_byte : 8'h00;

    wire [31:0] wd_limit = (STREAM_WD_MS > 0 && a_consume) ?
                          ((CLK_HZ / 1000) * STREAM_WD_MS) : wd_max;
    wire wd_hit     = a_wait & (wd >= wd_limit);
    // Start the backend deadline when stream draining actually ends. State
    // transitions within the read loop must never refresh its watchdog.
    wire wd_phase_end = (st == A_END) ||
                        ((st == A_DRAIN) && (lo_rd_err || eof_seen ||
                                             (wd_hit && STREAM_WD_MS == 0)));

    //=========================================================================
    // 3. A 侧时序（clk 域）
    //=========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            st <= A_IDLE; st_d <= A_IDLE;
            busy <= 1'b0; done <= 1'b0; err <= 8'h00; err_hold <= 8'h00;
            img_w <= 16'd0; img_h <= 16'd0;
            lo_open <= 1'b0; lo_open_index <= 8'd0;
            px <= PX_B; px_b <= 8'd0; px_g <= 8'd0; px_r <= 8'd0;
            pcnt <= 2'd0; frst_cnt <= 6'd0; hcnt <= 6'd0;
            magic_b0 <= 8'd0; magic_b1 <= 8'd0;
            bf_size_i <= 32'd0; bf_off_i <= 32'd0; bi_size_i <= 32'd0;
            bi_width_i <= 32'd0; bi_height_i <= 32'd0;
            bi_planes_i <= 16'd0; bi_bpp_i <= 16'd0; bi_comp_i <= 32'd0;
            skip_left <= 32'd0; rd_bytes <= 32'd0; wr_bytes <= 21'd0;
            row_bytes <= 0; pbleft <= 2'd0; zleft <= 4'd0; row_cnt <= 0;
            cover_r <= 1'b0; x_phase <= 0; y_phase <= 0;
            w3_r <= 0; h_r <= 0;
            padb_r <= 2'd0; padz_r <= 4'd0;
            cfg_first <= 21'd0; cfg_wpr <= 16'd0; cfg_words <= 19'd0;
            cfg_bu <= 1'b0;
            a_words <= 19'd0;
            eof_seen <= 1'b0; wd <= 32'd0; gave_up <= 1'b0;
            open_wait <= 2'd0;      // ★ 必须复位（否则初值 x ⇒ `!=2` 恒假 ⇒ 卡在 A_OPENP ✗）
            bidle_pend <= 1'b0;
            cfg_valid_int <= 1'b0; finish_valid_int <= 1'b0; cfg_issued <= 1'b0;
            fifo_flush <= 1'b0;
        end else begin
            st_d <= st;
            done       <= 1'b0;
            cfg_valid_int <= 1'b0; finish_valid_int <= 1'b0;
            lo_open    <= 1'b0;
            fifo_flush <= 1'b0;

            // ---- B→A：b_idle 同步 + 事件锁存（防漏：A 可能几拍后才到 A_WIDLE）----
            if (backend_done) bidle_pend <= 1'b1;
            else if (st == A_WIDLE && bidle_pend) bidle_pend <= 1'b0;

            // ---- lo_rd_eof 是单拍脉冲 ⇒ 必须锁存；start 时清 ----
            if (lo_rd_eof) eof_seen <= 1'b1;

            // ---- 看门狗：★★ 只有"**真的从卡上吃到字节**"才算进展 ✓
            //   【2026-10-09 Step 0 实测修正】原来还带 `| (st != st_d)`（状态推进也清零）✗ ——
            //   实测：卡被音频占住时，A 侧会在若干状态之间**循环打转**（采样看到 st 在 2/7/11 之间变）✗
            //   ⇒ 每次状态变化都把 `wd` 清零 ⇒ 计数器**永远到不了 `WD_MAX`** ⇒ **看门狗形同虚设** ✓
            //   ⇒ 口径改成只看"从卡上取到字节" ✓：状态打转**不再算进展** ✓
            //   ★ 合法路径上"长时间吃不到字节"的窗口都很短（`A_FRST` 6 拍、`A_HCHK` 1 拍、
            //     收尾等 B 侧排空 FIFO ≪ 1ms）⇒ **开机路径的 1ms 门限不受影响** ✓
            if (accept_now || wd_phase_end) wd <= 32'd0;
            else if (wd < wd_limit)         wd <= wd + 32'd1;

            case (st)
            //-----------------------------------------------------------------
            A_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    cover_r <= target_cover;
                    busy      <= 1'b1;
                    done      <= 1'b0;
                    err       <= 8'h00;
                    err_hold  <= 8'h00;
                    img_w     <= 16'd0;
                    img_h     <= 16'd0;
                    rd_bytes  <= 32'd0;
                    wr_bytes  <= 21'd0;
                    row_bytes <= 0;
                    row_cnt   <= 0;
                    hcnt      <= 6'd0;
                    px        <= PX_B;
                    pcnt      <= 2'd0;
                    skip_left <= 32'd0;
                    pbleft    <= 2'd0;
                    zleft     <= 4'd0;
                    eof_seen  <= 1'b0;
                    gave_up   <= 1'b0;
                    wd        <= 32'd0;
                    frst_cnt  <= 6'd16;
                    cfg_issued <= 1'b0;   // 重新对齐（上次装载的应答已消费）
                    bidle_pend<= 1'b0;
                    st        <= A_FRST;
                end
            end
            //-----------------------------------------------------------------
            // FIFO 冲洗：冲掉上次残留字节（含错误路径的不足一字尾巴）
            A_FRST: begin
                busy       <= 1'b1;
                fifo_flush <= 1'b1;
                if (frst_cnt != 6'd0) frst_cnt <= frst_cnt - 6'd1;
                else begin
                    fifo_flush <= 1'b0;
                    st <= A_OPENW;
                end
            end
            //-----------------------------------------------------------------
            // 等 storage 回到 T_READY（lo_open_busy=0）
            A_OPENW: begin
                busy <= 1'b1;
                if (wd_hit) begin
                    err_hold <= 8'h04;
                    st <= A_END;
                    gave_up <= 1'b1;
                end else if (!lo_open_busy) begin
                    lo_open_index <= file_index;
                    lo_open       <= 1'b1;
                    st            <= A_OPENP;
                end
            end
            //-----------------------------------------------------------------
            A_OPENP: begin
                busy <= 1'b1;                    // lo_open 已在上一拍寄存为 1，本拍回 0
                // ★★★ 2026-10-10：**打开后等 2 拍再进 `A_HDR`** ✓ —— 这是并发装载 bug 的正解 ✓
                //   【实测证据（`[FS ]` 判据，2026-10-10）】装载器进 `A_HDR`（**第一次用
                //     `file_size`**）那一拍，`file_size` 还停在**上一笔**的值 ✗：
                //       `进A_HDR: file_size=0     | lo_idx=1 真值=30774` ✗ ← 第一笔读到 0
                //       `进A_HDR: file_size=30774 | lo_idx=0 真值=15414` ✗ ← 晚一整笔
                //     ⇒ 第一笔 `rd_bytes(0) >= 0` **立即成立** ⇒ 判 EOF、**一个字都不写** ✗
                //   【为什么会晚】共用读口的**数据比地址晚一拍**（寄存输出 ✓），
                //     而装载器**在地址给出后的下一拍就要用** ✗ ⇒ **永远来不及** ✗✗
                //     ★ 这也解释了为什么我前面四种"挪锁存点"的修法**各对一半** ✗ ——
                //       它们都在挪**锁存点**，而没挪**装载器的等待** ✗
                //   【代价】一个 2 位计数器、**0 块 BRAM** ✓；对开机/并发**两条路同时成立** ✓
                if (open_wait != 2'd2) begin
                    open_wait <= open_wait + 2'd1;
                end else begin
                    open_wait <= 2'd0;
                    st        <= A_HDR;
                end
            end
            //-----------------------------------------------------------------
            // 吃 54 字节头（小端：先来的字节在低位）
            A_HDR: begin
                busy <= 1'b1;
                if (lo_rd_err) begin
                    err_hold <= 8'h04; st <= A_END; gave_up <= 1'b1;
                end else if (wd_hit) begin
                    err_hold <= 8'h04; st <= A_END; gave_up <= 1'b1;
                end else if (eof_seen || (rd_bytes >= file_size)) begin
                    err_hold <= 8'h03; st <= A_END; gave_up <= 1'b1;
                end else if (lo_rd_valid & lo_rd_ready) begin
                    case (hcnt)
                    8'd0:  magic_b0 <= lo_rd_data;
                    8'd1:  magic_b1 <= lo_rd_data;
                    8'd2,  8'd3,  8'd4,  8'd5:  bf_size_i   <= {lo_rd_data, bf_size_i[31:8]};
                    8'd10, 8'd11, 8'd12, 8'd13: bf_off_i    <= {lo_rd_data, bf_off_i[31:8]};
                    8'd14, 8'd15, 8'd16, 8'd17: bi_size_i   <= {lo_rd_data, bi_size_i[31:8]};
                    8'd18, 8'd19, 8'd20, 8'd21: bi_width_i  <= {lo_rd_data, bi_width_i[31:8]};
                    8'd22, 8'd23, 8'd24, 8'd25: bi_height_i <= {lo_rd_data, bi_height_i[31:8]};
                    8'd26, 8'd27:               bi_planes_i <= {lo_rd_data, bi_planes_i[15:8]};
                    8'd28, 8'd29:               bi_bpp_i    <= {lo_rd_data, bi_bpp_i[15:8]};
                    8'd30, 8'd31, 8'd32, 8'd33: bi_comp_i   <= {lo_rd_data, bi_comp_i[31:8]};
                    default: ;
                    endcase
                    rd_bytes <= rd_bytes + 32'd1;
                    if (hcnt == 6'd53) st <= A_HCHK;
                    else               hcnt <= hcnt + 6'd1;
                end
            end
            //-----------------------------------------------------------------
            // 判据 + 派生量 + 发布 cfg（**错误路径也发布**：B 必须先 armed 才能回应 a_end）
            A_HCHK: begin
                busy <= 1'b1;
                cfg_first <= first_s;
                cfg_wpr   <= wpr_s;
                cfg_words <= span_s[18:0];
                cfg_bu    <= bu_s;
                cfg_valid_int <= 1'b1; cfg_issued <= 1'b1;
                if (hchk_err != 8'h00 || ((EXTERNAL_BACKEND || DOWNSCALE) && span_s > {13'd0,slot_words})) begin
                    err_hold <= hchk_err != 8'h00 ? hchk_err : 8'h02;
                    st <= A_END;
                    gave_up <= 1'b1;
                end else begin
                    w3_r          <= w3_s[ROW_BYTE_W-1:0];
                    h_r           <= hmag_s[ROW_COUNT_W-1:0];
                    padb_r        <= padb_s;
                    padz_r        <= padz_s;
                    img_w         <= DOWNSCALE ? target_w : bi_width_i[15:0];
                    img_h         <= DOWNSCALE ? target_h : hmag_s[15:0];
                    x_phase       <= bi_width_i[X_PHASE_W-1:0];
                    // Complement the tie at an exact source-row boundary when
                    // reading bottom-up; both orientations sample the same y.
                    y_phase       <= hmag_s[Y_PHASE_W-1:0] - (bu_s ? 1'b1 : 1'b0);
                    skip_left     <= bf_off_i - 32'd54;
                    pbleft        <= padb_s;
                    zleft         <= padz_s;
                    row_bytes     <= 0;
                    row_cnt       <= 0;
                    px            <= PX_B;
                    pcnt          <= 2'd0;
                    if (bf_off_i > 32'd54) st <= A_SKIP;
                    else                   st <= A_PIX;
                end
            end
            //-----------------------------------------------------------------
            A_SKIP: begin
                busy <= 1'b1;
                if (lo_rd_err) begin
                    err_hold <= 8'h04; st <= A_END; gave_up <= 1'b1;
                end else if (wd_hit) begin
                    err_hold <= 8'h04; st <= A_END; gave_up <= 1'b1;
                end else if (eof_seen || (rd_bytes >= file_size)) begin
                    err_hold <= 8'h03; st <= A_END; gave_up <= 1'b1;
                end else if (lo_rd_valid & lo_rd_ready) begin
                    rd_bytes <= rd_bytes + 32'd1;
                    if (skip_left <= 32'd1) st <= A_PIX;
                    else                    skip_left <= skip_left - 32'd1;
                end
            end
            //-----------------------------------------------------------------
            // 吃像素：文件序 B,G,R ⇒ 推 FIFO 顺序 R,G,B（design §3.1 行内字节序）
            A_PIX: begin
                busy <= 1'b1;
                if (px == PX_PUSH) begin
                    // 推 3 个字节：先 R，再 G，最后 B（`fifo_we`/`fifo_di` 组合，见 2.3）
                    if (px_push) begin
                        wr_bytes  <= wr_bytes  + 21'd1;
                        if (pcnt == 2'd2) begin
                            pcnt <= 2'd0;
                            px   <= PX_B;
                            if (row_bytes == w3_r) st <= A_PAD;
                        end else begin
                            pcnt <= pcnt + 2'd1;
                        end
                    end
                end else if (lo_rd_err) begin
                    err_hold <= 8'h04; st <= A_END; gave_up <= 1'b1;
                end else if (wd_hit) begin
                    err_hold <= 8'h04; st <= A_END; gave_up <= 1'b1;
                end else if (eof_seen || (rd_bytes >= file_size)) begin
                    err_hold <= 8'h03; st <= A_END; gave_up <= 1'b1;
                end else if (lo_rd_valid & lo_rd_ready) begin
                    rd_bytes <= rd_bytes + 32'd1;
                    row_bytes <= row_bytes + 1'b1;
                    case (px)
                    PX_B: begin px_b <= lo_rd_data; px <= PX_G; end
                    PX_G: begin px_g <= lo_rd_data; px <= PX_R; end
                    default: begin
                        px_r <= lo_rd_data; pcnt <= 2'd0;
                        if (DOWNSCALE) begin
                            if (keep_pixel)
                                x_phase <= x_phase + (bi_width_i << 1) - x_step;
                            else x_phase <= x_phase - x_step;
                        end
                        if (keep_row && keep_pixel) px <= PX_PUSH;
                        else begin
                            px <= PX_B;
                            if ((row_bytes + 1'b1) == w3_r) st <= A_PAD;
                        end
                    end
                    endcase
                end
            end
            //-----------------------------------------------------------------
            // 丢 BMP 行补字节（0~3 个；绝不能进 SDRAM）
            A_PAD: begin
                busy <= 1'b1;
                if (pbleft == 2'd0) begin
                    st <= A_ZPAD;                                   // 不需要字节 ⇒ 不判 eof
                end else if (lo_rd_err) begin
                    err_hold <= 8'h04; st <= A_END; gave_up <= 1'b1;
                end else if (wd_hit) begin
                    err_hold <= 8'h04; st <= A_END; gave_up <= 1'b1;
                end else if (eof_seen || (rd_bytes >= file_size)) begin
                    err_hold <= 8'h03; st <= A_END; gave_up <= 1'b1;
                end else if (lo_rd_valid & lo_rd_ready) begin
                    rd_bytes <= rd_bytes + 32'd1;
                    pbleft   <= pbleft - 2'd1;
                end
            end
            //-----------------------------------------------------------------
            // 补 8'h00 到 16B 边界（0~12 个字节 ⇒ 0~3 个字）
            A_ZPAD: begin
                busy <= 1'b1;
                if (zleft == 4'd0 || !keep_row) begin
                    if ((row_cnt + 1'b1) >= h_r) begin
                        st <= A_END;                                 // 全部行完成
                    end else begin
                        row_cnt   <= row_cnt + 1'b1;
                        x_phase <= bi_width_i[X_PHASE_W-1:0];
                        if (DOWNSCALE) begin
                            if (keep_row) y_phase <= y_phase + (hmag_s << 1) - y_step;
                            else y_phase <= y_phase - y_step;
                        end
                        row_bytes <= 0;
                        pbleft    <= padb_r;
                        zleft     <= padz_r;
                        px        <= PX_B;
                        pcnt      <= 2'd0;
                        st        <= A_PIX;
                    end
                end else if (zpad_push) begin
                    wr_bytes  <= wr_bytes + 21'd1;
                    zleft     <= zleft - 4'd1;
                end
            end
            //-----------------------------------------------------------------
            // 发布"已推完整字数" + 翻转 a_end（数据与翻转同拍寄存 ⇒ 采样时已稳定）
            A_END: begin
                if (!cfg_issued) begin
                    cfg_first <= 21'd0; cfg_words <= 19'd0;
                    cfg_valid_int <= 1'b1; cfg_issued <= 1'b1;
                end
                busy     <= 1'b1;
                a_words  <= wr_bytes[20:2];
                finish_valid_int <= 1'b1;
                st       <= A_DRAIN;
            end
            //-----------------------------------------------------------------
            // 把 lo 流读干净（到 eof/err）⇒ storage_top 才能回 T_READY
            A_DRAIN: begin
                busy <= 1'b1;
                if (lo_rd_err || eof_seen) begin
                    st <= A_WIDLE;
                end else begin
                    if (wd_hit) begin
                        err_hold <= 8'h04;
                        gave_up <= 1'b1;
                        // Sector-mailbox readers own a file until EOF/error.
                        // Continue discarding bytes after the consumer deadline
                        // so a later open cannot strand a full mailbox. The SD
                        // and file services retain their physical watchdogs.
                        if (STREAM_WD_MS == 0) st <= A_WIDLE;
                    end
                    if (lo_rd_valid & lo_rd_ready) rd_bytes <= rd_bytes + 32'd1;
                end
            end
            //-----------------------------------------------------------------
            A_WIDLE: begin
                busy <= 1'b1;
                if (bidle_pend) begin
                    st <= A_FIN;
                end else if (wd_hit) begin
                    err_hold <= 8'h04;
                    st <= A_WIDLE;
                    gave_up <= 1'b1;
                end
            end
            //-----------------------------------------------------------------
            A_FIN: begin
                fifo_flush <= 1'b1;
                busy <= 1'b0;
                done <= 1'b1;
                err  <= err_hold;
                st   <= A_IDLE;
            end
            //-----------------------------------------------------------------
            default: st <= A_IDLE;
            endcase
        end
    end

    //=========================================================================
    // 5. B 侧时序（clk_sdr 域）：把 FIFO 里的 32bit 字按"不跨行突发"写进 ld 口
    //=========================================================================
    // 本次可突发长度：min(FIFO 可用字数, 本行剩余字数) —— 两者都 ≥1 ⇒ ld_len ≥1
endmodule
`default_nettype wire
