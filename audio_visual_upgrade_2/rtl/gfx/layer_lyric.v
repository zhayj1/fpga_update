`default_nettype none
//============================================================================
// rtl/gfx/layer_lyric.v —— 歌词图层（P3/S4-2b）：描述符 → 行渲染 → 像素上色
//
// 组成：内含 `lyric_row`（取字排平 ✓ S4-2a 已验 11/11 ✓）+
//       双时钟行缓冲（写 `clk_sdr` / 读 `clk_pix` ✓ 与 `fetch_line` 同一招 ✓）+ 窗口裁切 + 居中
//
// 【几何】窗口 `y ∈ [322, 398)`（高 76 = 2×PITCH ✓ `design:738` ✓）；
//   三行顶边 = `328 + k*38 − off_px`（k=0/1/2 ✓）；★ 32 < 38 ⇒ **每条扫描行至多一行有字** ✓
//   ⇒ 像素域只需"三选一"，不需要混叠/优先级 ✓
//   `design:747`：窗口只有 **2 行高** ⇒ 常态看不见第三行 ✓，滚动时旧行进上沿、第三行从下沿进 ✓
//
// 【为什么行缓冲只要 1 块、不要乒乓】渲染在**行首**（`hs` 下降沿）发起 ⇒ 到 `de` 有
//   `H_ACT_DLY`=144 个像素拍 = **576 个 clk_sdr** ✓，而一行 12~19 字只要 ~60 拍 ⇒
//   **`de` 之前必然写完** ✓（写/读在时间上天然错开 ⇒ 单缓冲就够 ✓ 省一块 BRAM ✓）。
//   ⇒ 不用乒乓，但要用 `buf_ok` 兜底：`hs` 清 0、渲染 `done` 置 1；没就绪就整行透明 ✓
//      （★ 单缓冲下"没就绪"时 BRAM 里是**上一行的旧字** ⇒ 必须用 `buf_ok` 挡住 ✗ 不能靠数据 ✓）
//
// 【居中】`x0 = (40 − nw) >> 1`（字为单位 ✓ 量化到 16px ⇒ ≤8px 偏差 ✓）
//   读地址 `= (x>>4) − x0` ✓ 天然字节对齐 ⇒ **零桶形移位器** ✓（见 `lyric_row` 头注释 ✓）
//
// 【上色（`design:749-750` ✓）】色码 0=透明 ✓；当前行：2=已唱金 / 1=未唱中灰 ✓；
//   预备行（nxt/n3）：**整行暗灰**（不管是 1 还是 2 ✓）—— 引擎不必知道自己是第几行 ✓
//
// 【跨域】三类信号，全部按本工程既有口径处理：
//   ① 每帧一次的**描述符快照**：`desc_tgl`（来自 `lyric_pick.done` ✓）+ 2FF 边沿捕获 ✓
//   ② 每行一次的**渲染请求**：`req_tgl` + 2FF 边沿捕获（请求总线在整行内稳定 ⇒ 安全 ✓）
//   ③ 每行一次的**完成通知**：`done_tgl` + 2FF 边沿捕获 ⇒ 同时锁 `nw`/`err` ✓
//   `off_px` 也随 ① 快照 ⇒ **一帧之内不变** ⇒ 不会帧内跳行（不撕裂 ✓）
//
//============================================================================
// ★★ 2026-10-06 写 TB 前复查，自己抓出**三处真错**（都已修 ✓，TB 逐像素对账兜底 ✓）：
//
//  ✗① **行号忘了减 `V_ACT_DLY`**：`layer_bg` 的口径是"`vln` 从 `vs` 起算、含场消隐 35 行"，
//     有效行号 `ycnt = vln − V_ACT_DLY`（`layer_bg.v:110` ✓）。本模块第一版直接拿 `vln` 去比
//     `328` ⇒ 整个歌词窗口**上移 35 行**（画到 y=287..363 ✗ 压在封面下沿 ✗）。
//     （`V_ACT_DLY` 参数当时"声明了却没人用" —— 正是这条漏掉的痕迹 ✓）
//  ✗② **行首发请求用了上一行的行号**：`hs_f` 那一拍 `vln` **还没自增**（NBA ⇒ 组合读到的是旧值 ✗），
//     所以 `any_a/sel/grow` 反映的是**刚结束的那一行** ⇒ 每行都渲染上一行的字形行 ✗：
//     字形整体错开 1 像素行，且每块字形行 0（`grow=0`）**永远不渲染**（换成 `grow` 回绕成 31 ✗）。
//     ⇒ 请求侧必须用 `vln+1`（= **即将开始的那一行** ✓）；显示侧仍用 `vln` ✓（两套几何，只多几个比较器 ✓）
//  ✗③ **BRAM 读地址没"预置"**：`REGMODE_B="NOREG"` ⇒ 地址进、数据**下一拍**出（`fetch_line.v:100` ✓）。
//     本模块用 `ra = f(xcnt+1)` 提前一拍给地址 ⇒ 要求**给地址那一拍的 `xcnt` 已经等于该像素** ✓。
//     但 `de` 为空时 `xcnt` 被清 0，`f(0+1)=f(1)` 被锁进 BRAM ⇒ **每行头 16 个像素读错字** ✗
//     （整行右移 1 个字 = 16px，看起来像"居中算错" ✗）。⇒ 给地址时用 `de ? xcnt+1 : xcnt` ✓
//        （de 下降沿那一拍给出 `f(0)`，正好接上下一行的第一个 `de` 像素 ✓）
//
// 另修：`(ROW_Y0+PITCH)[15:0]` 是**对表达式做位选**，Verilog-2001 不允许 ✗ ⇒ 改 `localparam` ✓
//============================================================================
module layer_lyric #(
    parameter integer H_ACT_DLY = 144,
    parameter integer V_ACT_DLY = 35,       // ★ 场首 → 首个有效行（`vln` 含消隐 ⇒ 必须减 ✓）
    parameter integer V_ACT_LIN = 480,      // 一帧有效行数 ✓
    parameter integer WIN_Y0    = 322,      // 窗口上沿（**屏幕坐标** ✓）
    parameter integer WIN_H     = 76,       // 窗口高 = 2 × PITCH ✓
    parameter integer ROW_Y0    = 328,      // 当前行常态顶边（屏幕坐标 ✓）
    parameter integer PITCH     = 38,       // 行距 ✓
    parameter integer NW_MAX    = 40,       // 行缓冲字数（= 640px ✓）
    parameter integer GL_H      = 32,       // 字高 ✓
    parameter integer AW        = 7,        // 行缓冲地址位宽（128 字 ✓）
    parameter [23:0]  C_SUNG    = 24'hFFD678,   // (255,214,120) ✓
    parameter [23:0]  C_UNSUNG  = 24'h8A92A0,   // (138,146,160) ✓
    parameter [23:0]  C_NEXT    = 24'h929BAA,   // (146,155,170) ✓
    parameter [20:0]  LRC_BASE  = 21'h17F040,
    parameter [20:0]  FONT_BASE = 21'h13EC00,
    parameter [20:0]  ASC_BASE  = 21'h17EA40,
    parameter integer CLK_HZ    = 100000000
)(
    // ---------------- 像素域（25MHz）----------------
    input  wire        clk_pix,
    input  wire        rst_pix_n,
    input  wire        hs,              // 行同步（低有效 ✓）
    input  wire        vs,              // 场同步（低有效 ✓）
    input  wire        de,              // 像素有效 ✓
    input  wire        en,              // 层使能 ✓
    output wire [23:0] dout,
    output wire        dout_vld,
    output reg  [31:0] gap_cnt,         // 有字却没就绪（**必须 0** ✓）
    output reg  [31:0] on_cnt,          // 本层出墨的像素数（观测 ✓）

    // ---------------- 时间轴（clk_sdr 慢值 ✓）----------------
    input  wire        clk_sdr,
    input  wire        rst_sdr_n,
    input  wire [23:0] played,
    input  wire [15:0] cur_fc, nxt_fc, n3_fc, cur_cnt, nxt_cnt, n3_cnt,
    input  wire        cur_vld, nxt_vld, n3_vld,
    input  wire [5:0]  off_px,
    input  wire        desc_tgl,        // 每次 `lyric_pick.done` 翻转 ✓

    // ---------------- SDRAM / px 客户端（透传 `lyric_row` ✓）----------------
    output wire        px_req,
    output wire [20:0] px_addr,
    output wire [15:0] px_len,
    input  wire        px_ack,
    input  wire        px_done,
    input  wire [31:0] px_data,
    input  wire        px_valid
);
    //=========================================================================
    // 0. 编译期常量（★ 见头注：不能对表达式做位选 ✓）
    //=========================================================================
    localparam [15:0] ROW0 = ROW_Y0[15:0];              // 328 ✓
    localparam [15:0] ROW1 = (ROW_Y0 + PITCH);          // 366 ✓
    localparam [15:0] ROW2 = (ROW_Y0 + 2 * PITCH);      // 404 ✓
    localparam [15:0] WY0  = WIN_Y0[15:0];              // 322 ✓
    localparam [15:0] WY1  = (WIN_Y0 + WIN_H);          // 398 ✓
    localparam [15:0] GLH  = GL_H[15:0];                // 32 ✓
    localparam [15:0] VDLY = V_ACT_DLY[15:0];           // 35 ✓
    localparam [15:0] VLIN = V_ACT_LIN[15:0];           // 480 ✓
    localparam [5:0]  NMAX = NW_MAX[5:0];               // 40 ✓

    // 某一行号 `v` 是否落在 `top` 起的字形块内 ✓（只用一个比较器对，两处复用 ✓）
    function in_row;
        input [15:0] v;
        input [15:0] top;
        begin
            in_row = (v >= top) && (v < (top + GLH));
        end
    endfunction

    //=========================================================================
    // A. 光栅计时（与 `layer_bg` 同口径 ✓：行号按**行首**计数 ✗ 不能数 de 边沿 ✓）
    //=========================================================================
    reg  [1:0]  hs_d, vs_d, de_d;
    wire        hs_f = hs_d[0] & ~hs;
    wire        vs_f = vs_d[0] & ~vs;

    reg  [15:0] vln;                    // 帧首起算的行数（含场消隐 ✓）
    reg  [15:0] xcnt;                   // 行内 de 像素序号 ✓
    reg         frame_seen;

    //=========================================================================
    // B. 每帧一次的描述符快照（2FF 边沿捕获 ✓）
    //=========================================================================
    reg  [1:0]  dt_d;
    wire        dt_f = dt_d[0] ^ dt_d[1];

    reg  [15:0] s_fc0, s_cnt0, s_fc1, s_cnt1, s_fc2, s_cnt2;
    reg         s_v0, s_v1, s_v2;
    reg  [5:0]  s_off;
    reg         s_en;

    //=========================================================================
    // C. 每行一次的渲染请求 / 完成（toggle + 2FF ✓）
    //=========================================================================
    reg         req_tgl, done_tgl;
    //=========================================================================
    // ★★ L1G：**行缓冲乒乓 + 彻底去掉就绪门**
    //   依据（两处实测，不再靠推断）：
    //     ① 板上 `LYR GAP` 巨大（7.7M 起、≈385k/秒）⇒ 门确实在吞行首像素 ✓
    //     ② 本工程受控台（`tb_layer_lyric_pp`）B1：`hs_f` 那拍 `vln` 未自增（= V）⇒
    //        `yr = V+1−VDLY` = **行 L 自己** ⇒ 引擎在行 L 期间才渲染行 L，消隐 576 拍不够 ⇒ 行首空白 ✓
    //        B2：把渲染拖到 576 之后（dly=70 ⇒ ≈1,370 拍）⇒ `gap` 涨 21 倍、出墨掉九成 ✓
    //   ⇒ 修法（**三条必须一起配平** ✗ 少一条就是我 L1E/L1F 的错）：
    //     ① 两块缓冲，基址 **0 / 40**（都在 `lyric_row` 原 **6 位**端口内 ⇒ 那个模块一字不改 ✓）
    //     ② `yr = vln+2`：引擎在**行 L 期间**渲染**行 L+1** ⇒ 有整整一行 3,200 拍去写完 ✓
    //     ③ ★ `r_bank` 极性：那拍 `vln` = V ⇒ 目标是行 L+1 ⇒ 该写 `(V+2)[0]` = **`vln[0]`**
    //        （**不是** `~vln[0]` —— L1E/L1F 正是错在这一位，表现为 `nw` 恒 0 + 灰蓝点 ✓）
    //   显示读 `vln[0]`、引擎写 `vln[0]` 的目标行 ⇒ **两者永不重合** ⇒ 门可去掉 ✓
    //   ★ `nw` **不在开写时清 0**：宁可短暂显示"上一行的旧字"（完整），也不要空白 ✓
    //     （这正是板上教训：空白比陈旧难看 ✓；且渲染超过一行时也只是多留一行旧字 ✓）
    //=========================================================================
    reg         r_bank, c_bank;
    reg  [5:0]  b_nw0, b_nw1;
    reg  [5:0]  nw0_s1, nw0_s2, nw1_s1, nw1_s2;   // 每块字数的 2FF（跨到像素域 ✓）
    reg  [1:0]  dn_d;                              // `row_done` 延 2 拍：那时 `nw`/`err` 才稳定 ✓
    reg  [7:0]  err_s;
    reg  [1:0]  rd_d;
    wire        rd_f = rd_d[0] ^ rd_d[1];
    reg  [1:0]  rt_d;
    wire        rt_f = rt_d[0] ^ rt_d[1];

    reg  [15:0] r_fc, r_cnt;
    reg  [4:0]  r_grow;
    reg         row_start;

    // ★ `nw` 跨域 2FF（**必须 6 位**，见 §H 注释 ✓；Verilog-2001 要求先声明后使用 ⇒ 提前声明 ✓）
    reg  [5:0]  nw_s1, nw_s2;

    // sdr 侧捕获的请求参数 ✓
    reg  [15:0] c_fc, c_cnt;
    reg  [4:0]  c_grow;
    wire        row_busy, row_done;
    wire [7:0]  row_err;
    wire [5:0]  row_nw;

    //=========================================================================
    // D. 几何：三行顶边（只随 `s_off` 变 ✓）+ 显示侧/请求侧两套判定 ✓
    //=========================================================================
    wire [15:0] y0 = ROW0 - {10'd0, s_off};
    wire [15:0] y1 = ROW1 - {10'd0, s_off};
    wire [15:0] y2 = ROW2 - {10'd0, s_off};

    //---- 显示侧：当前扫描行（`vln` ✓）----
    wire [15:0] yc    = vln - VDLY;                      // ★ 有效行号（修 ✗① ✓）
    wire        win_c = en && frame_seen && (yc >= WY0) && (yc < WY1);   // `en` 也挡住取数 ✓
    wire        a0    = s_en && s_v0 && in_row(yc, y0);
    wire        a1    = s_en && s_v1 && in_row(yc, y1);
    wire        a2    = s_en && s_v2 && in_row(yc, y2);
    wire        any_a = win_c && (a0 || a1 || a2);
    wire [1:0]  sel   = a0 ? 2'd0 : (a1 ? 2'd1 : 2'd2);
    wire [4:0]  grow  = a0 ? (yc[4:0] - y0[4:0])
                          : (a1 ? (yc[4:0] - y1[4:0]) : (yc[4:0] - y2[4:0]));

    //---- 请求侧：行首那一拍要"**再下一行**"（★ L1G：`vln+2` ✓ —— 见 §C 的说明 ✓）----
    //   那拍 `vln` 未自增 = V ⇒ `yr = V+2−VDLY` = 行 L+1 的行 ⇒ 引擎在行 L 期间渲染行 L+1 ✓
    wire [15:0] yr    = (vln + 16'd2) - VDLY;
    wire        win_r = en && frame_seen && (yr >= WY0) && (yr < WY1);
    wire        r0    = s_en && s_v0 && in_row(yr, y0);
    wire        r1    = s_en && s_v1 && in_row(yr, y1);
    wire        r2    = s_en && s_v2 && in_row(yr, y2);
    wire        r_any = win_r && (r0 || r1 || r2);
    wire [1:0]  rsel  = r0 ? 2'd0 : (r1 ? 2'd1 : 2'd2);
    wire [4:0]  rgrow = r0 ? (yr[4:0] - y0[4:0])
                           : (r1 ? (yr[4:0] - y1[4:0]) : (yr[4:0] - y2[4:0]));
    wire [15:0] r_fc_s  = (rsel == 2'd0) ? s_fc0 : ((rsel == 2'd1) ? s_fc1 : s_fc2);
    wire [15:0] r_cnt_s = (rsel == 2'd0) ? s_cnt0 : ((rsel == 2'd1) ? s_cnt1 : s_cnt2);

    // 保底：`V_ACT_LIN` 在像素域也用得上（窗口不得越过帧底 ✓ 参考 `layer_bg` KI-01 ✓）
    wire        in_vact = (yc < VLIN);

    //=========================================================================
    // D2. 行缓冲读（clk_pix ✓ 1 拍延迟 ⇒ 地址**提前一拍**给 ✓ 数据与 `xcnt` 对齐 ✓）
    //     修 ✗③：`de` 为空那拍给 `f(xcnt)`（= f(0) ✓），`de` 有效才给 `f(xcnt+1)` ✓
    //=========================================================================
    wire [15:0] xa   = de ? (xcnt + 16'd1) : xcnt;
    // ★★ L1G：显示侧"字数/地址"按 **bank** 选（`bk = vln[0]` = 正在显示那一行属于哪块 ✓）
    wire        bk    = vln[0];
    wire [5:0]  s_nw  = bk ? nw1_s2 : nw0_s2;            // ★ 该块**自己**的字数 ✓
    wire [5:0]  x0_w = (NMAX - s_nw) >> 1;                        // 居中（字为单位 ✓）
    wire [5:0]  ra   = (xa >> 4) - x0_w;                          // 低 6 位 = 缓冲字号 ✓
    wire [31:0] mem_dob;
    wire [1:0]  code = mem_dob[31 - {xcnt[3:0], 1'b0} -: 2];      // 字内 16 像素、像素 0 在 bit31 ✓
    wire        jok  = (xcnt[9:4] >= x0_w) && ((xcnt[9:4] - x0_w) < s_nw);
    //   ★ 门只剩"**这块有没有字**"（`s_nw != 0`）：冷启动/空行不出墨 ✓，**不再等渲染** ✓
    wire        xin  = de && any_a && in_vact && (s_nw != 6'd0) && jok;

    //=========================================================================
    // E. 像素域顺序块
    //=========================================================================
    always @(posedge clk_pix) begin
        if (!rst_pix_n) begin
            hs_d <= 2'd0; vs_d <= 2'd0; de_d <= 2'd0;
            vln <= 16'd0; xcnt <= 16'd0; frame_seen <= 1'b0;
            dt_d <= 2'd0; rd_d <= 2'd0;
            s_fc0 <= 16'd0; s_cnt0 <= 16'd0; s_fc1 <= 16'd0; s_cnt1 <= 16'd0;
            s_fc2 <= 16'd0; s_cnt2 <= 16'd0;
            s_v0 <= 1'b0; s_v1 <= 1'b0; s_v2 <= 1'b0; s_off <= 6'd0; s_en <= 1'b0;
            req_tgl <= 1'b0; r_bank <= 1'b1;
            nw0_s1 <= 6'd0; nw0_s2 <= 6'd0; nw1_s1 <= 6'd0; nw1_s2 <= 6'd0;
            r_fc <= 16'd0; r_cnt <= 16'd0; r_grow <= 5'd0;
            gap_cnt <= 32'd0; on_cnt <= 32'd0;
        end else begin
            hs_d <= {hs_d[0], hs};
            vs_d <= {vs_d[0], vs};
            de_d <= {de_d[0], de};
            dt_d <= {dt_d[0], desc_tgl};
            rd_d <= {rd_d[0], done_tgl};
            // ★★ L1G：两块字数的 2FF（sdr 域慢变电平 ⇒ 教科书安全 ✓ 且避开同块读写风险 ✓）
            nw0_s1 <= b_nw0;  nw0_s2 <= nw0_s1;
            nw1_s1 <= b_nw1;  nw1_s2 <= nw1_s1;

            // ---- 每帧：锁描述符快照 ✓（`off_px` 一帧内不变 ⇒ 不撕裂 ✓）----
            if (dt_f) begin
                s_fc0 <= cur_fc; s_cnt0 <= cur_cnt; s_v0 <= cur_vld;
                s_fc1 <= nxt_fc; s_cnt1 <= nxt_cnt; s_v1 <= nxt_vld;
                s_fc2 <= n3_fc;  s_cnt2 <= n3_cnt;  s_v2 <= n3_vld;
                s_off <= off_px;
                s_en  <= 1'b1;                  // 见过一次描述符才允许出字（上电不出字 ✓）
            end

            // ---- 行首：发起请求 ✓（没字就不请求、保持透明 ✓）----
            if (hs_f) begin
                if (r_any) begin
                    r_fc   <= r_fc_s;
                    r_cnt  <= r_cnt_s;
                    r_grow <= rgrow;
                    // ★★ L1G：目标 = **行 L+1** 那块。此拍 `vln` 未自增（= V）⇒ `(V+2)[0] = vln[0]` ✓
                    r_bank <= vln[0];
                    req_tgl <= ~req_tgl;
                end
            end
            if (vs_f) begin
                vln <= 16'd0;
                frame_seen <= 1'b1;
            end else if (hs_f) begin
                vln <= vln + 16'd1;
            end

            // ---- ★ L1G：`buf_ok`/`s_nw` 的"渲染完成"锁存已**搬去 sdr 域按 bank 记** ✓ ----
            //   （在像素域做全局锁存就是病根 ✗：它把"某次渲染完成"当成了"本行就绪" ✗）
            //   `rd_d`/`rd_f` 保留（观测用 ✓ 不参与判定 ✓）

            // ---- 行内像素序号 ✓ ----
            if (de) xcnt <= xcnt + 16'd1;
            else    xcnt <= 16'd0;

            if (dout_vld) on_cnt <= on_cnt + 32'd1;

            // ---- 兜底计数：窗口内有字、**这块却一个字都没有**（冷启动/坏素材 ✓ 稳态应恒 0 ✓）----
            //   ★ L1G：判据从"某次渲染完成没"改成"**这块有没有字**" ⇒ 结构上不再有"行头被啃" ✓
            if (de && any_a && in_vact && (s_nw == 6'd0)) gap_cnt <= gap_cnt + 32'd1;
        end
    end

    //=========================================================================
    // F. 上色（色码 0=透明 ✓；当前行 2=金/1=中灰 ✓；预备行整行暗灰 ✓）
    //=========================================================================
    assign dout     = (code == 2'd2) ? (sel == 2'd0 ? C_SUNG : C_NEXT)
                                     : (sel == 2'd0 ? C_UNSUNG : C_NEXT);
    assign dout_vld = xin && (code != 2'd0) && en;

    //=========================================================================
    // G. 渲染引擎 + 行缓冲（写口 clk_sdr ✓ 读口 clk_pix ✓）
    //=========================================================================
    wire        row_we;
    wire [6:0]  row_waddr;
    wire [31:0] row_wdata;

    lyric_row #(
        .LRC_BASE (LRC_BASE), .FONT_BASE (FONT_BASE), .ASC_BASE (ASC_BASE),
        .CLK_HZ   (CLK_HZ)
    ) u_row (
        .clk_sdr (clk_sdr), .rst_sdr_n (rst_sdr_n),
        .start (row_start), .buf_base (c_bank ? 6'd40 : 6'd0), .fc (c_fc), .cnt (c_cnt),
        .grow (c_grow), .played (played),
        .busy (row_busy), .done (row_done), .err (row_err), .nw (row_nw),
        .wr_en (row_we), .wr_addr (row_waddr), .wr_data (row_wdata),
        .px_req (px_req), .px_addr (px_addr), .px_len (px_len),
        .px_ack (px_ack), .px_done (px_done), .px_data (px_data), .px_valid (px_valid)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A (32), .DATA_WIDTH_B (32),
        .ADDR_WIDTH_A (AW), .ADDR_WIDTH_B (AW),
        .DATA_DEPTH_A (1 << AW), .DATA_DEPTH_B (1 << AW),
        .BYTE_ENABLE (0), .BYTE_A (1), .BYTE_B (1),
        .MODE ("DP"), .REGMODE_A ("NOREG"), .REGMODE_B ("NOREG"),
        .WRITEMODE_A ("NORMAL"), .WRITEMODE_B ("NORMAL"),
        .RESETMODE ("SYNC"), .DEBUGGABLE ("NO"), .PACKABLE ("NO"),
        .FORCE_KEEP ("OFF"), .INIT_FILE ("NONE"), .FILL_ALL ("NONE"),
        .IMPLEMENT ("9K")
    ) u_buf (
        .dia (row_wdata), .addra (row_waddr), .cea (1'b1), .ocea (1'b0),
        .clka (clk_sdr), .wea (row_we), .rsta (1'b0), .bea (1'b0),
        // ★★ L1G：读地址按 bank 偏置 —— **必须显式 7 位** ✗
        //   原先写 `(bk ? 6'd40 : 6'd0) + ra`：Verilog 里 `a+b` 的宽度 = max(操作数宽度)
        //   = **6 位** ⇒ `40+39=79` 会**溢出回绕** ✗（读到的不是要的那块/那个字 ⇒ 数据 X）
        .dib (32'd0), .addrb ((bk ? 7'd40 : 7'd0) + {1'b0, ra}), .ceb (1'b1), .oceb (1'b1),
        .clkb (clk_pix), .web (1'b0), .rstb (1'b0), .beb (1'b0),
        .doa (), .dob (mem_dob)
    );

    //=========================================================================
    // H. sdr 域：请求捕获 + 完成通知 + `nw`/`err` 跨域
    //    ★ `nw` 是 **6 位总线** ⇒ 2FF 必须也按 6 位打（第一版写成 `reg [1:0] ns_d`
    //      再接 `{ns_d[0], row_nw}` ⇒ 只剩 `row_nw[1:0]` ✗：`nw=17(0b010001)` 的 bit1=0
    //      ⇒ `s_nw` 恒 0 ⇒ **整层一个像素都不出** ✗。TB 的 LY-01 逐像素对账一把抓住 ✓）
    //=========================================================================
    always @(posedge clk_sdr) begin
        if (!rst_sdr_n) begin
            rt_d <= 2'd0; done_tgl <= 1'b0; row_start <= 1'b0;
            c_fc <= 16'd0; c_cnt <= 16'd0; c_grow <= 5'd0; c_bank <= 1'b0;
            nw_s1 <= 6'd0; nw_s2 <= 6'd0; err_s <= 8'h00;
            b_nw0 <= 6'd0; b_nw1 <= 6'd0; dn_d <= 2'd0;
        end else begin
            rt_d  <= {rt_d[0], req_tgl};
            nw_s1 <= row_nw;                      // ★ 6 位 2FF（同步跨域 ✓）
            nw_s2 <= nw_s1;
            row_start <= 1'b0;
            dn_d  <= {dn_d[0], row_done};          // ★ L1G：延 2 拍（`nw`/`err` 那时才稳定 ✓）
            if (rt_f) begin                       // ★ 请求总线在整行内稳定 ⇒ 直接捕获 ✓
                c_fc   <= r_fc;
                c_cnt  <= r_cnt;
                c_grow <= r_grow;
                c_bank <= r_bank;                  // ★ L1G：本次渲染写哪块 ✓（开写**不清** `b_nw` ✓）
                row_start <= 1'b1;
            end
            if (row_done) begin
                done_tgl <= ~done_tgl;
                err_s    <= row_err;
            end
            // ★★ L1G：写完 ⇒ 记**该块**的字数（`row_done` 后 2 拍读 `row_nw`/`row_err` ✓）
            //   坏素材 ⇒ 记 0 ⇒ 那层不出字（不黑屏 ✓）
            if (dn_d[1]) begin
                if (c_bank) b_nw1 <= (row_err == 8'h00) ? row_nw : 6'd0;
                else        b_nw0 <= (row_err == 8'h00) ? row_nw : 6'd0;
            end
        end
    end
endmodule

`default_nettype wire
