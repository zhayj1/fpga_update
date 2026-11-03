`default_nettype none
//============================================================================
// rtl/gfx/lyric_row.v —— 歌词"取字 + 排版 + 高亮"行渲染引擎（P3/S4-2a）
//
// 干什么（**一条扫描行**）：
//   把某一行歌词的第 `grow` 条字形行取出来，**拍平成一整行 2 位色码**（0 透明 / 1 未唱灰 /
//   2 已唱金 ✓），从 x=0 起**左对齐**写进行缓冲（≤40 字 = 640px ✓）。居中不在这里做 ✗。
//
// ★ 三个"零成本"的支点（都是先算清账再写的 ✓）：
//   ① **汉字 32px / 半角 16px ⇒ 都对齐到整字（1 字 = 16px = 16 色码 × 2bit = 32bit）** ✓
//      ⇒ 每字占地**正好 1 或 2 个 32 位字** ✓ ⇒ 写口只有"整字写"✓ **零字节使能、零移位器** ✓
//      （前提：居中偏移也量化到 16px ✓ —— 见 ②）
//   ② **居中放到像素域做**：本模块只输出 `nw`（本行占几个字 ✓），居中 = `(40-nw)>>1` ✓
//      由 `layer_lyric` 在**像素地址上减掉** ✓ ⇒ 引擎不必"先量宽度再排字"（那要两遍 ✗）
//      ★ 代价：居中量化到 16px（≤8px 偏差 ✓ 肉眼不可辨 ✓）换掉了一个桶形移位器 ✓
//   ③ **高亮在取数域判完**：每字取回自己的样本数，`samples ≤ played` ⇒ 金 / 否则灰 ✓
//      ⇒ 像素域**只读 2 位**、连一个比较器都没有 ✓（每字每行只比 1 次 ≈109k 次/s ✓ 免费）
//
// 【地址与字节序 ★ 已逐字对回 `sim/golden/S01_lrc_tab.mem`（2026-10-05 ✓）】
//   字记录 = 2 字：`word0 = {rsv, flags, code_hi, code_lo}`（**码是大端字节序** ✓）
//     ⇒ ★ `code = {px_data[7:0], px_data[15:8]}`（**要字节交换** ✗ 不是 `px_data[15:0]`）
//       其中 `qu = code[15:8]`、`wei = code[7:0]` ✓
//     · 实测 `word136 = 0x00004700` ⇒ `px_data[7:0]=0x00=hi`、`[15:8]=0x47=lo` ⇒ code = 0x0047 = 'G'
//       （**`qu = 0` ⇒ 半角判据** ✓）—— 第一版写成 `px_data[15:0]` 会得到 0x4700 ✗，被 PC golden 抓出 ✓
//     · 实测 `word150 = 0x0001B7D7` ⇒ code = 0xD7B7 = 追（qu=D7 / wei=B7 ✓ GB2312 ✓）
//   `word1` 低 24 位 = 该字样本数 ✓（**小端整数** ✓ 不换字节；实测 `word151 = 0x00005370` = 21360
//     ⇒ **逐字时间戳存在** ✓；而 line0 的 'GALA…' 12 字全是 18960 ⇒ 行级继承 ✓ 两种都见过 ✓）
//   汉字字形：`FONT + (((qu-0xA1)*94 + (wei-0xA1)) << 5) + grow`（128B/字 = 32 字/字 ✓ `design:783` ✓）
//   半角字形：`ASC  + ((code[7:0]-0x20) << 4) + (grow>>1)`，取 `grow[0] ? [31:16] : [15:0]` ✓
//     （64B/半角字 = 16 字 ✓ 每行 2B ⇒ 两个字一行、按 `grow[0]` 选高低半 ✓）
//   位序：**MSB 在左**（`design:784` ✓）⇒ 像素 p 的位 = `data[31-p]`（汉字）/ `g16[15-p]`（半角）✓
//
// 【色码打包】4 像素 = 1 字节（每像素 2 位 ✓，字节内**左像素在高位** ✓）：
//   `exp4(n) = Σ (n[i] ? 2'b01 << 2i : 0)`（n[3] = 最左像素 ✓）
//   颜色只有 1（灰）/ 2（金）两种取值 ⇒ `sung` 时整体**左移 1 位**即可 ✓ 零乘法器 ✓
//
// 【读法 ★★ p3-lean 步1 已改：从"记录 2 字 + 字形行 1 字"改成"两条**对齐的 4 字组**"】
//   **读定律**（受控实测，见 `doc/evidence/p3_lean_px_floor.md`）：
//     读突发必须 **(a) 长度 ≥ 4 字** 且 **(b) 起始地址 4 字组对齐**；违反任一 ⇒ 数据错，
//     错字数 = `len<4 ? len : (len/4)×(addr mod 4)`（**ctl 与 px 两口同律** ✓）。
//   ⇒ **字记录**：读**含该记录的对齐 4 字组**（一组正好覆盖 **2 条**记录 ✓），按 `rec_off` 挑 2 字 ✓
//      **字形行**：读**含该行的对齐 4 字组**（= 连续 4 行字模 ✓），按 `goff` 挑 1 字 ✓
//      （基址都天然 4 字对齐 ⇒ 偏移只来自 `grow` 与记录号奇偶 ✓）
//   代价：每字 2 笔读、每笔 4 字 ⇒ 19 字 = **38 笔 / 152 字每扫描行**
//     ≈ 152×4 B×480×60 = **17.5 MB/s**（对照显示通路自己 19.6 MB/s ✓ 仍非瓶颈 ✓）
//   ★ **收口一律等 `px_done`**（与已上板的 `fetch_line` 同款 ✓）：若"数到目标字就离开读状态"，
//     本笔剩余的字会流到下一笔、被当成下一条记录 ✗ —— 这是步 1 识别出的隐患 ✓
//   串行状态机 ⇒ **零行缓存、零字记录缓存** ✓
//
// 体检：`cnt=0` ⇒ 空行（`nw=0` ✓ 不算错 ✓）；`cnt>19` ⇒ `err=0x66` ✓；码非法 ⇒ `err=0x66` ✓；
//       读不出来/被截短 ⇒ `err=0x04` ✓（**绝不卡死** ✓）
//============================================================================
module lyric_row #(
    parameter [20:0] LRC_BASE  = 21'h17F040,
    parameter [20:0] FONT_BASE = 21'h13EC00,
    parameter [20:0] ASC_BASE  = 21'h17EA40,
    parameter integer CHAR_OFF = 136,        // 字记录区起始字 ✓
    parameter integer MAX_CH   = 19,         // ★ 单行硬上限（**口径 3/10：19 字** ✓
                                             //   `design:753` 原写 20 ✗ 已被口径改掉：
                                             //   20×32=640px = 满屏 0 边距 ✗ ⇒ >19 就不画 ✓）
    parameter integer CLK_HZ   = 100000000,
    parameter integer WD_MS    = 4
)(
    input  wire        clk_sdr,
    input  wire        rst_sdr_n,
    input  wire        start,                // 脉冲：渲染一行 ✓（同一行每条扫描行各一次 ✓）
    input  wire [5:0]  buf_base,             // 行缓冲基址（乒乓：0 / 40 ✓）
    input  wire [15:0] fc,                   // 本行首字记录号 ✓
    input  wire [15:0] cnt,                  // 本行字数 ✓
    input  wire [4:0]  grow,                 // 字形行号 0..31 ✓
    input  wire [23:0] played,               // 已播样本数 ✓

    output reg         busy,
    output reg         done,                 // 单拍 ✓（输出已稳定 ✓）
    output reg  [7:0]  err,                  // 0x00 / 0x66 素材坏 / 0x04 读超时
    output reg  [5:0]  nw,                   // 本行占的字数（1 字 = 16px ✓ 给居中用 ✓）

    // ---- 行缓冲写口（clk_sdr ✓；`layer_lyric` 接外部双时钟 BRAM 的写口 ✓）----
    output reg         wr_en,
    output reg  [6:0]  wr_addr,              // buf_base + 字偏移 ✓
    output reg  [31:0] wr_data,

    // ---- SDRAM 读客户端（与 `fetch_line` 同形 ✓）----
    output reg         px_req,
    output reg  [20:0] px_addr,
    output reg  [15:0] px_len,
    input  wire        px_ack,
    input  wire        px_done,
    input  wire [31:0] px_data,
    input  wire        px_valid
);
    localparam integer WD_MAX = (CLK_HZ / 1000) * WD_MS;

    localparam [2:0] S_IDLE = 3'd0,
                     S_CRQ  = 3'd1,   // 发字记录读（2 字 ✓）
                     S_CRD  = 3'd2,   // 收 code / samples ✓
                     S_GRQ  = 3'd3,   // 发字形行读（1 字 ✓）
                     S_GRD  = 3'd4,   // 收字形行 ⇒ 展开写"第一个字"（像素 0..15 ✓）
                     S_GW2  = 3'd5,   // 汉字还要写"第二个字"（像素 16..31 ✓）
                     S_FIN  = 3'd6;

    reg  [2:0]  st, st_d;
    reg  [31:0] wd;
    reg  [4:0]  ci;                  // 本行第几个字 ✓
    reg  [5:0]  xw;                  // 已排到的字偏移 0..40 ✓
    reg  [15:0] code;                // 当前字的码 ✓
    reg         sung;                // 当前字是否已唱 ✓
    reg         half;                // 是否半角 ✓
    reg  [1:0]  rx;                  // ★ p3-lean 步1：本笔已收字数 0..3（读定律：固定读 4 字 ✓）
    reg  [7:0]  err_t;
    reg  [15:0] cnt_l;
    reg  [31:0] g32;                 // 汉字整条字形行（第二个字要用 ✓）
    // ★★ p3-lean 步1：读定律要求"**长度 ≥4 字** 且 **起始地址 4 字组对齐**"（见
    //   `doc/evidence/p3_lean_px_floor.md`）⇒ 记录读与字形行读都改成"读**含目标字的对齐 4 字组**"，
    //   再按组内偏移就地挑字。`rec_off`/`goff` = 目标字在组内的偏移 ✓
    //   （字模/记录基址都天然 4 字对齐 ⇒ 偏移只来自 `grow` 与记录号奇偶 ✓）
    reg  [1:0]  rec_off;             // 记录 word0 在 4 字组内的偏移（0 或 2 ✓）
    reg  [1:0]  goff;                // 字形行在 4 字组内的偏移（0..3 ✓）
    reg         seen;                // 目标字已收到 ✓（没收齐就到 done ⇒ 0x04 截短 ✓）

    wire        last_ch = ({11'd0, ci} + 16'd1 >= cnt_l) || (ci + 5'd1 >= MAX_CH[4:0]);
    wire        wd_hit  = (st != S_IDLE) && (st != S_FIN) && (wd == WD_MAX[31:0]);

    //--------------------------------------------------------------------
    // 地址算术（组合 ✓ 零乘法器 ✓）
    //--------------------------------------------------------------------
    wire [7:0]  qu   = code[15:8];
    wire [7:0]  q    = qu - 8'hA1;                    // 区号 0..86 ✓
    wire [7:0]  w    = code[7:0] - 8'hA1;             // 位号 ✓
    // q*94 = q*128 - q*32 - q*2; two carry chains instead of four.
    wire [15:0] q94  = ({8'd0,q} << 7) - ({8'd0,q} << 5) - ({8'd0,q} << 1);
    wire [15:0] gi   = q94 + {8'd0, w};               // 字形序号 0..8177 ✓
    wire [20:0] fadr = FONT_BASE + ({5'd0, gi} << 5) + {16'd0, grow};   // 32 字/字 ✓
    wire [7:0]  asq  = code[7:0] - 8'h20;             // 半角序号 0..95 ✓
    // ★★ 更正（我先前误判过这一行，已撤回 ✗）：`aadr`/`fadr` 是 **字（word）地址** ✓ 不是字节地址 ✓
    //   卡上 `ASC.HZK` 每字 **64 字节 = 16 个字** ⇒ `asq << 4`（16 字/字）**本来就是对的** ✓
    //   （我一度改成 `<<6` ⇒ 单元台 LR-01 立刻变红 ⇒ **单元台正确抓住了我** ✓ 已还原 ✓）
    //   行内：每字 2 行/32bit 字 ⇒ 字号 `grow>>1`、半选 `grow[0]` ✓ 与权威 golden 逐字节一致 ✓
    wire [20:0] aadr = ASC_BASE + ({8'd0, asq} << 4) + {17'd0, grow[4:1]}; // 16 字/字 ✓
    wire        is_half = (qu == 8'h00);
    wire        code_ok = is_half ? ((code[7:0] >= 8'h20) && (code[7:0] <= 8'h7F))
                                  : (qu >= 8'hA1);
    // ★ p3-lean 步1：两处取数的"目标字地址"（组合 ✓ 稳定于各自读状态 ✓）
    wire [20:0] rec_wa = LRC_BASE + CHAR_OFF[20:0] + ({1'b0, (fc + {11'd0, ci})} << 1);
    wire [20:0] gly_wa = is_half ? aadr : fadr;
    // 本拍要展开的 16 个像素（**像素 0 在最高位** ✓）
    // ★★ 字节序还原（**由 PC golden 抓出的真错 ✗→✓**）：槽里字形行是**按字节顺序**存的
    //    （`b0 b1 b2 b3`，`b0` 在小端字的低 8 位 ✓ —— `font_load` 是逐字节原样拷 ✓）
    //    而"像素 p 在 bit(31-p)"的语义值必须是 `{b0,b1,b2,b3}` = **整字字节反转** ✓
    //    不做这一步 ⇒ 一行像素会**按字节镜像**（8px 一块左右颠倒 ✗），且高/低 16 像素会互换 ✗
    wire [31:0] row_be = {px_data[7:0], px_data[15:8], px_data[23:16], px_data[31:24]};
    wire [15:0] g_w0 = is_half ? (grow[0] ? row_be[15:0] : row_be[31:16])
                               : row_be[31:16];        // 汉字 = 像素 0..15 ✓
    wire [15:0] g_w1 = g32[15:0];                       // 汉字 = 像素 16..31（已还原 ✓）

    //--------------------------------------------------------------------
    // 展开函数：16 像素 → 1 个 32 位色码字（4 像素/字节、左像素在高位 ✓、金 = 色码 2 ✓）
    //--------------------------------------------------------------------
    function [7:0] exp4;
        input [3:0] n;
        begin
            exp4 = 8'h00;
            if (n[3]) exp4[7:6] = 2'b01;
            if (n[2]) exp4[5:4] = 2'b01;
            if (n[1]) exp4[3:2] = 2'b01;
            if (n[0]) exp4[1:0] = 2'b01;
        end
    endfunction

    function [31:0] expw;
        input [15:0] g;
        input        sg;
        reg   [7:0]  a, b, c, d;
        begin
            a = exp4(g[15:12]);
            b = exp4(g[11:8]);
            c = exp4(g[7:4]);
            d = exp4(g[3:0]);
            if (sg) expw = {a[6:0],1'b0, b[6:0],1'b0, c[6:0],1'b0, d[6:0],1'b0};
            else    expw = {a, b, c, d};
        end
    endfunction

    always @(posedge clk_sdr) begin
        if (!rst_sdr_n) begin
            st <= S_IDLE; st_d <= S_IDLE;
            busy <= 1'b0; done <= 1'b0; err <= 8'h00; nw <= 6'd0;
            wr_en <= 1'b0; wr_addr <= 7'd0; wr_data <= 32'd0;
            px_req <= 1'b0; px_addr <= 21'd0; px_len <= 16'd4;
            wd <= 32'd0; ci <= 5'd0; xw <= 6'd0; code <= 16'd0; sung <= 1'b0;
            half <= 1'b0; rx <= 2'd0; seen <= 1'b0; err_t <= 8'h00; cnt_l <= 16'd0; g32 <= 32'd0;
        end else begin
            st_d  <= st;
            done  <= 1'b0;
            wr_en <= 1'b0;
            px_req <= 1'b0;

            // ★ 2026-10-05（代理 TB 抓出，实为本模块既有缺陷）：wd 原先在 S_IDLE 也一直自增到饱和
            //   ⇒ 空闲超过 WD_MS 之后的第一条渲染会在 S_CRQ 当拍被判 wd_hit（假超时），
            //     表现为 err=0x04 / nw=0 ⇒ 整行不画（上板即偶发空行）。加 (st == S_IDLE) 清零。
            if ((st == S_IDLE) || (st != st_d) || px_valid) wd <= 32'd0;
            else if (wd != WD_MAX[31:0]) wd <= wd + 32'd1;

            case (st)
            //----------------------------------------------------------------
            S_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    busy  <= 1'b1;
                    ci    <= 5'd0;
                    xw    <= 6'd0;
                    rx    <= 2'd0;
                    seen  <= 1'b0;
                    err_t <= 8'h00;
                    cnt_l <= cnt;
                    st    <= S_CRQ;
                    if (cnt > MAX_CH[15:0]) begin
                        err_t <= 8'h66;                   // 超硬上限 ⇒ 素材坏 ✓
                        st    <= S_FIN;
                    end else if (cnt == 16'd0) begin
                        st    <= S_FIN;                   // 空行 ⇒ nw=0 ✓（不算错 ✓）
                    end
                end
            end
            //----------------------------------------------------------------
            // 读第 ci 个字的记录（2 字 ✓）；★ 只在 `px_ack` 那拍转状态（否则首个数据字会丢 ✗）
            // ★★ `fc` 是"本行首字记录号" ⇒ 地址必须是 `2*(fc+ci)` ✗ 不能只有 `ci`
            //    （第一版漏了 `fc` ⇒ `fc=0` 的行碰巧全过、`fc=25` 的行立刻渲染成第 0 行 ✗，
            //      正是 PC golden 的 LR-04 抓出来的 ✓）
            S_CRQ: begin
                busy     <= 1'b1;
                px_req   <= 1'b1;
                // ★ p3-lean 步1：读**含该记录的对齐 4 字组**、长度固定 4 ✓（读定律 ✓）
                px_addr  <= rec_wa & ~21'd3;
                px_len   <= 16'd4;
                rec_off  <= rec_wa[1:0];        // 0 或 2 ⇒ 一组覆盖两条记录 ✓
                if (px_ack) begin px_req <= 1'b0; rx <= 2'd0; seen <= 1'b0; st <= S_CRD; end
                if (wd_hit) begin err_t <= 8'h04; st <= S_FIN; end
            end
            //----------------------------------------------------------------
            S_CRD: begin
                busy <= 1'b1;
                if (px_valid) begin
                    if (rx == rec_off)
                        code <= {px_data[7:0], px_data[15:8]};   // ★ 码要字节交换 ✓（见文件头 ✓）
                    else if (rx == (rec_off + 2'd1)) begin
                        sung <= (px_data[23:0] <= played);       // ★ 逐字高亮：全程唯一一次比较 ✓
                        seen <= 1'b1;
                    end
                    rx <= rx + 2'd1;
                end
                // ★★ 与已上板的 `fetch_line` 同款：**用 `px_done` 收口**，不"数到目标字就走" ✗ ——
                //    否则本笔剩余的 2~3 个字会流到下一笔，被当成下一条记录的字 ✗（p3-lean 步1 识别的隐患）
                if (px_done) begin
                    if (seen) begin rx <= 2'd0; st <= S_GRQ; end
                    else      begin err_t <= 8'h04; st <= S_FIN; end   // 截短 ✓
                end
                if (wd_hit) begin err_t <= 8'h04; st <= S_FIN; end
            end
            //----------------------------------------------------------------
            S_GRQ: begin
                busy <= 1'b1;
                if (!code_ok) begin
                    err_t <= 8'h66;                       // 码非法 ⇒ 收口（已渲染的保留 ✓）
                    st    <= S_FIN;
                end else begin
                    px_req  <= 1'b1;
                    px_addr <= gly_wa & ~21'd3;      // ★ 读含该字形行的对齐 4 字组 ✓
                    px_len  <= 16'd4;                // ★ 固定 4 字 ✓（读定律 ✓）
                    goff    <= gly_wa[1:0];          // 汉字 = grow%4；半角 = (grow>>1)%4 ✓
                    half    <= is_half;
                    if (px_ack) begin px_req <= 1'b0; rx <= 2'd0; seen <= 1'b0; st <= S_GRD; end
                end
                if (wd_hit) begin err_t <= 8'h04; st <= S_FIN; end
            end
            //----------------------------------------------------------------
            // 展开写"第一个字"（像素 0..15 ✓，对着本拍 `px_data` 组合展开 ✓ 不用锁存值 ✗）
            S_GRD: begin
                busy <= 1'b1;
                if (px_valid) begin
                    if (rx == goff) begin                     // ★ 只有目标字那一拍才展开 ✓
                        g32     <= row_be;                    // ★ 已做字节反转 ✓（S_GW2 直接用 ✓）
                        wr_en   <= 1'b1;
                        wr_addr <= {1'b0, buf_base} + {1'b0, xw};
                        wr_data <= expw(g_w0, sung);
                        xw      <= xw + 6'd1;
                        seen    <= 1'b1;
                    end
                    rx <= rx + 2'd1;
                end
                // ★ 同 S_CRD：**等 `px_done` 收口**，剩余的字在本状态吞掉 ✓
                if (px_done) begin
                    if (!seen) begin err_t <= 8'h04; st <= S_FIN; end
                    else if (half) begin
                        if (last_ch) st <= S_FIN; else begin ci <= ci + 5'd1; st <= S_CRQ; end
                    end else begin
                        st <= S_GW2;                          // 汉字：还得写像素 16..31 ✓
                    end
                end
                if (wd_hit)  begin err_t <= 8'h04; st <= S_FIN; end
            end
            //----------------------------------------------------------------
            S_GW2: begin
                busy    <= 1'b1;
                wr_en   <= 1'b1;
                wr_addr <= {1'b0, buf_base} + {1'b0, xw};   // xw 已在 S_GRD 加过 1 ✓
                wr_data <= expw(g_w1, sung);                // 用锁存的 `g32[15:0]` ✓
                xw      <= xw + 6'd1;
                if (last_ch) st <= S_FIN; else begin ci <= ci + 5'd1; st <= S_CRQ; end
            end
            //----------------------------------------------------------------
            S_FIN: begin
                busy   <= 1'b0;
                done   <= 1'b1;
                err    <= err_t;
                nw     <= (err_t == 8'h00) ? xw : 6'd0;     // 坏素材 ⇒ 不显示（不黑屏 ✓）
                px_req <= 1'b0;
                st     <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
