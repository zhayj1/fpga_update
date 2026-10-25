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
// 【上色（`design:749-750` ✓）】色码 0=透明 ✓；当前行：2=已唱粉紫 / 1=未唱浅紫 ✓；
//   预备行（nxt/n3）：与当前行未唱部分同色（不管是 1 还是 2）
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
module layer_text #(
    parameter integer H_ACT_DLY = 144,
    parameter integer V_ACT_DLY = 35,       // ★ 场首 → 首个有效行（`vln` 含消隐 ⇒ 必须减 ✓）
    parameter integer V_ACT_LIN = 480,      // 一帧有效行数 ✓
    parameter integer WIN_Y0    = 322,      // 窗口上沿（**屏幕坐标** ✓）
    parameter integer WIN_H     = 76,       // 窗口高 = 2 × PITCH ✓
    parameter integer ROW_Y0    = 328,      // 当前行常态顶边（屏幕坐标 ✓）
    parameter integer PITCH     = 38,       // 行距 ✓
    parameter integer NW_MAX    = 40,       // 行缓冲字数（= 640px ✓）
    parameter integer GL_H      = 32,       // 字高 ✓
    parameter integer AW        = 8,        // 统一文字行缓冲：歌词 80 + 歌名 96 + 歌手 16 字
    parameter [23:0]  C_SUNG    = 24'hFF5FCB,   // (255,95,203) ✓
    parameter [23:0]  C_UNSUNG  = 24'hE8E4FF,   // (232,228,255) ✓
    parameter [23:0]  C_NEXT    = 24'hE8E4FF,   // same as C_UNSUNG
    // ★★ L1M 并层：歌名/歌手（跑马灯）—— 参数与口径照旧 `layer_title.v` **冻结值** ✓
    //   （旧版在 `exp/lrc-linefetch` 分支上 ✓：BOX_X=32 / BOX_W=160 / TTL_Y0=408 / SGR_Y0=442
    //     / GL_H=32 / SPP=1200（40px/s @48k）/ HOLD_N=24000（停 0.5s）/ C_TTL 白 / C_SGR 浅蓝灰 ✓）
    parameter integer BOX_X     = 32,       // 文本框左沿（屏幕坐标 ✓）
    parameter integer BOX_W     = 160,      // 文本框宽（5 字 ✓；文字宽 ≤ 此值 ⇒ **静止**不滚 ✓）
    parameter integer TTL_Y0    = 408,      // 歌名框顶 ✓
    parameter integer SGR_Y0    = 442,      // 歌手框顶 ✓
    parameter integer MAX_CH_T  = 24,       // 歌名/歌手单条硬上限（本曲歌名 22 字 ✓）
    parameter integer MAX_CH_L  = 19,       // ★ 歌词单条硬上限 = **素材契约** ✓（用户 2026-10-07 裁定 ✓）：
                                            //   ≤19 字/行 ✓；20 字 ⇒ 按坏素材 `err 0x66`、该行不出 ✓
                                            //   —— **规定行为** ✗ 不是缺陷 ✓；换歌时按 ≤19 字/行 备素材 ✓
    parameter integer SPP       = 1200,     // 跑马灯：每像素的样本数（40 px/s @48kHz ✓）
    parameter integer HOLD_N    = 24000,    // 每圈起始停留样本数（0.5 s ✓）
    parameter [23:0]  C_TTL     = 24'hFFFFFF,   // 歌名（白 ✓）
    parameter [23:0]  C_SGR     = 24'hBCC4D2,   // 歌手（浅蓝灰 ✓）
    // ★★ 行缓冲**三段**布局（**仍是一枚 128 字 BRAM** ⇒ +0 枚 BRAM ✓）：
    //   0..39  歌词 A 块（乒乓①）／40..79 歌词 B 块（乒乓②）／**80..127 歌名+歌手**
    //   ⇒ 歌名与歌手**永不共存**（408 与 442 两带在扫描行上不重叠 ✓）⇒ 共用这 48 字 ✓
    //   ⇒ MAX_CH_T=24 汉字 = 24×2 = **48 字** ✓ 正好装下（本曲歌名 22 字 = 44 字 ✓ 余 4 ✓）
    parameter [6:0]   TTL_BASE  = 7'd80,
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
    input  wire        en,              // 层使能（歌词 ✓）
    input  wire        en_ttl,          // ★ 歌名/歌手使能（独立可关 ✓；两带在扫描行上不重叠 ✓）
    output wire [23:0] dout,
    output wire        dout_vld,
    output reg  [31:0] gap_cnt,         // 有字却没就绪（**必须 0** ✓）
    output reg  [31:0] on_cnt,          // 本层出墨的像素数（观测 ✓）
    output wire [11:0] ttl_off,         // ★ 歌名带跑马灯当前偏移（px ✓ 板上自证用 ✓）

    // ---------------- 时间轴（clk_sdr 慢值 ✓）----------------
    input  wire        clk_sdr,
    input  wire        rst_sdr_n,
    input  wire [23:0] played,
    input  wire [15:0] cur_fc, nxt_fc, n3_fc, cur_cnt, nxt_cnt, n3_cnt,
    input  wire        cur_vld, nxt_vld, n3_vld,
    input  wire [5:0]  off_px,
    input  wire        desc_tgl,        // 每次 `lyric_pick.done` 翻转 ✓
    // ★★ L1M 并层：歌名/歌手（`lyric_pick` **本来就在输出**这六根 ✓ 零改动 ✓）
    input  wire        samp_stb,        // 48kHz 样本节拍（单拍 ✓ 跑马灯时基 ✓）
    input  wire [15:0] ttl_fc, ttl_cnt, sgr_fc, sgr_cnt,
    input  wire        ttl_vld, sgr_vld,

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
    // ★★ L1M：歌名/歌手两个带（屏幕坐标 ✓；与歌词窗口不重叠 ✓）
    localparam [15:0] BX   = BOX_X[15:0];               // 32 ✓
    localparam [15:0] BW   = BOX_W[15:0];               // 160 ✓
    localparam [15:0] TY0  = TTL_Y0[15:0];              // 408 ✓
    localparam [15:0] SY0  = SGR_Y0[15:0];              // 442 ✓
    localparam [15:0] GLH2 = GL_H[15:0];                // 32 ✓
    localparam [15:0] SPPW = SPP[15:0];                 // 1200 ✓
    localparam [14:0] HOLDW= HOLD_N[14:0];              // 24000 ✓（跑马灯每圈起始停留 ✓）
    // ★★ L1M-瘦身：文本框几何的 **11 位**形式（§D4 与读路径都要用 ⇒ 必须早于两者声明 ✓）
    localparam [10:0] BX11 = BOX_X[10:0];               // 32 ✓
    localparam [10:0] BW11 = BOX_W[10:0];               // 160 ✓
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

    //=========================================================================
    // ★★ L1M 并层：歌名/歌手（**分时共用同一个 `lyric_row`** ✓ 省下一整套取字引擎 ✓）
    //   为什么能分时：歌词窗口 y∈[322,398) 与 歌名框 [408,440)、歌手框 [442,474)
    //     **在扫描行上互不重叠** ✓ ⇒ 每一条扫描行只需要发起**一次**取字 ✓ ⇒ 单实例足够 ✓
    //     而且**不需要仲裁**（不会饿死 ✓）—— 只需"按当前扫描行选前端" ✓✓
    //   行缓冲：歌词仍是那枚 128 字 BRAM 的两段（0..39 / 40..79 ✓ **L1G 的乒乓原样不动** ✓）；
    //     歌名/歌手用**另一枚 64 字小 BRAM** ✓（+1 枚 9K，余 8 枚 ⇒ 不影响 ✓）
    //     ★ 为什么不塞进同一枚：`lyric_row.buf_base` 是 **6 位** ✗，而歌词已占 0..79，
    //       歌名只能落在 80..127 ⇒ base=80 超 6 位 ✗（上次把它加宽到 7 位时写口全坏、被单元台抓住 ✗）。
    //   `lyric_row.v` **一行不改** ✓ ⇒ 它的 golden/单元台继续有效 ✓
    //=========================================================================
    reg  [15:0] s_tfc, s_tcnt, s_sfc, s_scnt;   // 歌名/歌手描述符快照（每帧 ✓）
    reg         s_tv, s_sv;
    reg         c_ttl;                          // sdr：本次渲染是不是"歌名/歌手"带
    reg         c_is_t;                         // sdr：是歌名（1）还是歌手（0）
    reg         r_ttl;                          // pix：本行请求的是不是"歌名/歌手"带
    reg         r_is_t;                         // pix：请求的是歌名（1）还是歌手（0）
    // ★★ L1M-c 乒乓：歌名/歌手**各自两块**（照 L1G 歌词侧同一套法 ✓ `bk = vln[0]` 选读块 ✓）
    //   病因：单块时"每扫描行重取"直接覆写**正在显示**的那一块 ✗ ⇒ 同一行里新旧混杂 ⇒ 笔画锯齿 ✓
    reg  [5:0]  b_nt0, b_nt1;                   // sdr：歌名 块0/块1 字数
    reg  [5:0]  b_ns0, b_ns1;                   // sdr：歌手 块0/块1 字数
    reg  [5:0]  nt0_s1, nt0_s2, nt1_s1, nt1_s2; // pix：2FF（每块一条 ✓）
    reg  [5:0]  ns0_s1, ns0_s2, ns1_s1, ns1_s2;
    reg  [10:0] off_t, off_s;                   // 跑马灯偏移（px ✓）
    reg  [11:0] w_t, w_s;                       // 该条文字宽（px = nw×16 ✓）
    reg  [10:0] off_t_p1, off_t_p2, off_s_p1, off_s_p2;
    reg  [11:0] w_t_p1, w_t_p2, w_s_p1, w_s_p2;
    // ★★ L1M-b：**跑马灯归零的触发条件** —— 只在"这一条文字换了"时归零 ✗
    //   旧版每次渲染完（`dn_d[1]`）都 `off_t <= 0` ✗ ⇒ 一帧 16.7ms < 走 1px 要的
    //   1200 样本 = 25ms ⇒ 偏移被每帧清零 ⇒ **永远停在 0** ✗（板上实测：歌名不滚 ✓）
    //   ⇒ 改判据：`c_fc`（本条首字）与上一条不同 = 换歌/换文本 ⇒ 才归零 ✓
    reg  [15:0] fc_t_p, fc_s_p;                 // 上一条文字的首字（换文本检测 ✓）
    reg  [10:0] div;                            // 0..SPP-1（每 px 样本分频 ✓）
    reg  [14:0] hold;                           // 0..HOLD_N-1（每圈起始停留 ✓）
    wire [31:0] mem_dob;

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

    //---- ★★ L1M：歌名/歌手带（**请求侧也用 `vln+2`** ✓ 见 §C 的 L1G 说明 ✓）----
    //   ★ 为什么必须同步改口径：旧 `layer_title.v` 用的是 `vln+1` + 全局 `buf_ok` ✗
    //     ⇒ 直接照搬会**原样重现"行头被啃"** ✗✗（板上查了两轮的那个病 ✓）
    //   ★ 两带与歌词窗口在 `yr` 上也不重叠 ✓ ⇒ `r_*` 三组互斥 ⇒ 一次取字 ✓
    wire        rt_ok  = en_ttl && frame_seen && s_tv && in_row(yr, TY0);
    wire        rs_ok  = en_ttl && frame_seen && s_sv && in_row(yr, SY0);
    wire        want_ttl = rt_ok || rs_ok;                     // 本行要取"歌名/歌手"（组合 ✓）
    wire [15:0] r_fc_t  = rt_ok ? s_tfc : s_sfc;
    wire [15:0] r_cnt_t = rt_ok ? s_tcnt : s_scnt;
    wire [4:0]  r_gr_t  = rt_ok ? (yr[4:0] - TY0[4:0]) : (yr[4:0] - SY0[4:0]);
    //   ★ 逐带硬上限（`lyric_row` 的 `MAX_CH` 是**参数**、对两带是同一个 ⇒ 必须在此各自把关 ✓）
    //     歌词 ≤ MAX_CH_L（19 ✓ ⇒ ≤38 字，落在 0..39 / 40..79 ✓）
    //     歌名/歌手 ≤ MAX_CH_T（24 ✓ ⇒ ≤48 字，落在 64 字小 BRAM ✓）
    wire        r_ttl_ch_ok = (r_cnt_t <= MAX_CH_T[15:0]);
    wire        r_lyr_ch_ok = (r_cnt_s <= MAX_CH_L[15:0]);
    wire        r_any_all   = (r_any && r_lyr_ch_ok) || (want_ttl && r_ttl_ch_ok);
    wire        r_ttl_all   = want_ttl && r_ttl_ch_ok;

    // 保底：`V_ACT_LIN` 在像素域也用得上（窗口不得越过帧底 ✓ 参考 `layer_bg` KI-01 ✓）
    wire        in_vact = (yc < VLIN);

    //=========================================================================
    // D3. ★★ L1M：歌名/歌手两带（显示侧 `yc` ✓）
    //   ★ 与歌词窗口 `[WY0,WY1)=[322,398)` **在扫描行上不重叠** ✓
    //     （歌名 408..439、歌手 442..473 ✓）⇒ 每行只需**一次**取字 ⇒ 单实例足够 ✓
    //   ★ `s_tv`/`s_sv` 必须进来 ✗（否则"没有歌名"会被当成 underrun ⇒ gap 白涨 ✗
    //     —— 旧版 TM-04 就抓到过：`ttl_vld=0` 时 gap 记了 64 行×640 ✗）
    //=========================================================================
    wire        in_t  = en_ttl && frame_seen && s_tv && in_row(yc, TY0);
    wire        in_s  = en_ttl && frame_seen && s_sv && in_row(yc, SY0);

    //=========================================================================
    // D4. ★★ L1M：跑马灯几何（clk_pix 组合读 ✓；状态在 sdr 域推进 ✓）
    //   口径照旧 `layer_title.v` **冻结值** ✓：
    //     周期 `per = W + BOX_W`（W = 本条文字宽 px = nw×16 ✓）；`W > BOX_W` 才滚动 ✓
    //     滚动时 `off` 每 `SPP` 个样本 +1 px；绕一圈回来再停 `HOLD_N` 个样本 ✓
    //     ⇒ 尾出/头进同一刻 ✓（全框皆空只有 `off = W` 这一个值 = 25ms ✓ 肉眼不可辨 ✓）
    //=========================================================================
    // 宽度来自 6 位 row_nw*16，周期使用 12 位；偏移保持原来的 11 位。
    // off+1 >= W+BOX_W 等价于 off >= W+(BOX_W-1)。把常量运算放在
    // 宽度侧，移除偏移反馈路径上“加一再比较”的串联进位链，不增加寄存器。
    localparam [11:0] BW_LAST = {1'b0, BW11} - 12'd1;
    wire [11:0] last_t = w_t + BW_LAST;
    wire [11:0] last_s = w_s + BW_LAST;
    wire [11:0] per_t_pix = {1'b0, w_t_p2} + {1'b0, BW11};
    wire [11:0] per_s_pix = {1'b0, w_s_p2} + {1'b0, BW11};
    wire        mov_t = ({1'b0, w_t} > {1'b0, BW11});    // >5 字 ⇒ 滚动 ✓（各自判 ✓）
    wire        mov_s = ({1'b0, w_s} > {1'b0, BW11});
    wire        wrp_t = mov_t && ({1'b0, off_t} >= last_t);
    wire        wrp_s = mov_s && ({1'b0, off_s} >= last_s);
    // 显示侧选带（组合 ✓；`per_sel`/`off_sel` 被上面两段共用 ⇒ 放这里 ✓）
    wire [10:0] off_sel = in_t ? off_t_p2 : off_s_p2;
    wire [11:0] per_sel = in_t ? per_t_pix : per_s_pix;

    //=========================================================================
    // D2. 行缓冲读（clk_pix ✓ 1 拍延迟 ⇒ 地址**提前一拍**给 ✓ 数据与 `xcnt` 对齐 ✓）
    //     修 ✗③：`de` 为空那拍给 `f(xcnt)`（= f(0) ✓），`de` 有效才给 `f(xcnt+1)` ✓
    //=========================================================================
    wire [15:0] xa   = de ? (xcnt + 16'd1) : xcnt;
    //--------------------------------------------------------------------
    // ★★ L1G 歌词侧：显示"字数/地址"按 **bank** 选（`bk = vln[0]` ✓）
    //--------------------------------------------------------------------
    wire        bk    = vln[0];
    wire [5:0]  s_nwL = bk ? nw1_s2 : nw0_s2;                    // 该块**自己**的字数 ✓
    wire [5:0]  x0_wL = (NMAX - s_nwL) >> 1;                     // 居中（字为单位 ✓）
    wire [5:0]  raL   = (xa >> 4) - x0_wL;                       // 低 6 位 = 缓冲字号 ✓
    wire [1:0]  codeL = mem_dob[31 - {xcnt[3:0], 1'b0} -: 2];   // 字内 16 像素、像素 0 在 bit31 ✓
    wire        jokL  = (xcnt[9:4] >= x0_wL) && ((xcnt[9:4] - x0_wL) < s_nwL);
    wire        xinL  = de && any_a && in_vact && (s_nwL != 6'd0) && jokL;
    //--------------------------------------------------------------------
    // ★★ L1M 歌名/歌手侧：框内 + 跑马灯偏移（口径照旧 `layer_title.v` **冻结** ✓）
    //   `u = x − BOX_X`、`src = (u + off) mod (W + BOX_W)`；`src < W` 才出字 ✓
    //   ★★ 字内位序必须用 **`src[3:0]`** ✗ 不能用 `xcnt[3:0]` ✗（`off` 不是 16 的倍数 ✓）
    //   ★★ L1M-瘦身：整条算术**降到 11 位** ✗（原来 16 位 ✗ 白烧 LUT、还拉长关键路径 ⇒
    //      实测曾把 Hold 从 +11ps 拖到 **-20ps** ✗）。框 ≤160px、周期 ≤512px ⇒ 11 位够 ✓
    //--------------------------------------------------------------------
    wire [10:0] u11  = xcnt[10:0] - BX11;                     // 显示侧 u ✓
    wire [10:0] ua11 = xa[10:0]   - BX11;                     // 地址侧 u ✓
    wire [10:0] sa   = ((ua11 < BW11) ? ua11 : 11'd0) + off_sel;   // 地址侧 src ✓
    wire [10:0] sd_  = ((u11  < BW11) ? u11  : 11'd0) + off_sel;   // 显示侧 src ✓
    wire [10:0] per11= per_sel[10:0];                         // ≤ 512 ✓
    wire [10:0] sa_w = (sa  >= per11) ? (sa  - per11) : sa;   // 一次减法够 ✓
    wire [10:0] s_w  = (sd_ >= per11) ? (sd_ - per11) : sd_;
    wire [5:0]  raT   = sa_w[9:4];                            // 缓冲字号 = src>>4 ✓
    wire [5:0]  s_nwT = bk ? nt1_s2 : nt0_s2;                 // ★ L1M-c：歌名**按块**取 ✓
    wire [5:0]  s_nwS = bk ? ns1_s2 : ns0_s2;                 // ★ L1M-c：歌手**按块**取 ✓
    wire [5:0]  s_nw2 = in_t ? s_nwT : s_nwS;                 // 显示侧选带 ✓
    wire [10:0] w10T  = {s_nw2, 4'b0};                        // 本条文字宽（px ✓ ≤768 ⇒ 11 位够 ✓）
    wire        any_ttl = in_t || in_s;                       // ★ 必须在用之前声明 ✓
    wire [1:0]  codeT = mem_dob[31 - {s_w[3:0], 1'b0} -: 2]; // ★ 用 src[3:0] ✓
    //   ★ `w10T == 0` 时 `s_w < w10T` 恒假 ⇒ **不需要**再单独判"有没有字" ✓（瘦身：去掉重复判断 ✓）
    wire        xinT  = de && any_ttl && in_vact && (u11 < BW11) && (s_w < w10T);
    //--------------------------------------------------------------------
    // 合并（两带与歌词窗口**在扫描行上不重叠** ✓ ⇒ 本行只会选到一个 ✓）
    //--------------------------------------------------------------------
    wire [1:0]  code    = any_ttl ? codeT  : codeL;
    wire [5:0]  s_nw    = any_ttl ? s_nw2  : s_nwL;
    wire        xin     = any_ttl ? xinT   : xinL;

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
            // ★★ L1M：歌名/歌手侧（快照 + 请求标记 + 字数 2FF ✓）
            s_tfc <= 16'd0; s_tcnt <= 16'd0; s_sfc <= 16'd0; s_scnt <= 16'd0;
            s_tv <= 1'b0; s_sv <= 1'b0; r_ttl <= 1'b0;
            nt0_s1 <= 6'd0; nt0_s2 <= 6'd0; nt1_s1 <= 6'd0; nt1_s2 <= 6'd0;
            ns0_s1 <= 6'd0; ns0_s2 <= 6'd0; ns1_s1 <= 6'd0; ns1_s2 <= 6'd0;
            off_t_p1 <= 11'd0; off_t_p2 <= 11'd0;
            off_s_p1 <= 11'd0; off_s_p2 <= 11'd0;
            w_t_p1 <= 12'd0; w_t_p2 <= 12'd0;
            w_s_p1 <= 12'd0; w_s_p2 <= 12'd0;
            r_is_t <= 1'b1;                   // ★ L1M：上电默认"歌名"（偏移归零前不显示 ✓）
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
            nt0_s1 <= b_nt0;  nt0_s2 <= nt0_s1;      // ★ L1M-c：歌名两块各自 2FF ✓
            nt1_s1 <= b_nt1;  nt1_s2 <= nt1_s1;
            ns0_s1 <= b_ns0;  ns0_s2 <= ns0_s1;      // ★ L1M-c：歌手两块各自 2FF ✓
            ns1_s1 <= b_ns1;  ns1_s2 <= ns1_s1;
            off_t_p1 <= off_t; off_t_p2 <= off_t_p1;
            off_s_p1 <= off_s; off_s_p2 <= off_s_p1;
            w_t_p1 <= w_t; w_t_p2 <= w_t_p1;
            w_s_p1 <= w_s; w_s_p2 <= w_s_p1;

            // ---- 每帧：锁描述符快照 ✓（`off_px` 一帧内不变 ⇒ 不撕裂 ✓）----
            if (dt_f) begin
                s_fc0 <= cur_fc; s_cnt0 <= cur_cnt; s_v0 <= cur_vld;
                s_fc1 <= nxt_fc; s_cnt1 <= nxt_cnt; s_v1 <= nxt_vld;
                s_fc2 <= n3_fc;  s_cnt2 <= n3_cnt;  s_v2 <= n3_vld;
                // ★★ L1M：歌名/歌手来自 LRC 表头字 5/6（`lyric_pick` 已在输出 ✓ 零改动 ✓）
                s_tfc <= ttl_fc; s_tcnt <= ttl_cnt; s_tv <= ttl_vld;
                s_sfc <= sgr_fc; s_scnt <= sgr_cnt; s_sv <= sgr_vld;
                s_off <= off_px;
                s_en  <= 1'b1;                  // 见过一次描述符才允许出字（上电不出字 ✓）
            end

            // ---- 行首：发起请求 ✓（没字就不请求、保持透明 ✓）----
            if (hs_f) begin
                if (r_any_all) begin
                    // ★★ L1M：三带合一 —— 本行要取"歌词"还是"歌名/歌手"由带决定 ✓
                    //   （三带在扫描行上互不重叠 ⇒ 至多一个为真 ✓ 无需仲裁 ✓）
                    r_ttl  <= r_ttl_all;
                    r_is_t <= rt_ok;                  // ★ L1M：歌名 vs 歌手（互斥 ⇒ 直接取 ✓）
                    r_fc   <= r_ttl_all ? r_fc_t  : r_fc_s;
                    r_cnt  <= r_ttl_all ? r_cnt_t : r_cnt_s;
                    r_grow <= r_ttl_all ? r_gr_t  : rgrow;
                    // ★★ L1G：目标 = **行 L+1** 那块。此拍 `vln` 未自增（= V）⇒ `(V+2)[0] = vln[0]` ✓
                    //   （歌名/歌手有自己的小 BRAM ⇒ bank 对它无意义，恒 0 ✓）
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

            // ---- 兜底计数：带内有字、**这块却一个字都没有**（冷启动/坏素材 ✓ 稳态应恒 0 ✓）----
            //   ★ L1G：判据从"某次渲染完成没"改成"**这块有没有字**" ⇒ 结构上不再有"行头被啃" ✓
            //   ★ L1M：歌名/歌手带同样纳入（否则那一带的空白无人计 ✓）
            //   ★★ L1M-c：`s_nwT`/`s_nwS` 现在是**按块**取的 ✓ ⇒ 这个计数**能看见"读到的是还没写完的那一块"** ✓
            //     （单块时它看不见 ✗ —— 这正是这次锯齿轮次能溜上板的原因 ✓）
            if (de && in_vact && ((any_a && (s_nwL == 6'd0)) || ((in_t || in_s) && (s_nw2 == 6'd0))))
                gap_cnt <= gap_cnt + 32'd1;
        end
    end

    //=========================================================================
    // F. 上色
    //   · 歌词带：色码 0=透明 ✓；当前行 2=粉紫/1=浅紫 ✓；预备行同未唱浅紫 ✓
    //   · 歌名/歌手带：**整条一个颜色** ✓（歌名白 / 歌手浅蓝灰 ✓；本层只判"是不是墨" ✓）
    //=========================================================================
    assign dout     = any_ttl ? (in_t ? C_TTL : C_SGR)
                              : ((code == 2'd2) ? (sel == 2'd0 ? C_SUNG : C_NEXT)
                                                : (sel == 2'd0 ? C_UNSUNG : C_NEXT));
    assign dout_vld = xin && (code != 2'd0);
    assign ttl_off  = {1'b0, off_t};            // ★ L1M-b：跑马灯偏移上报（板上自证 ✓）

    //=========================================================================
    // G. 渲染引擎 + 行缓冲（写口 clk_sdr ✓ 读口 clk_pix ✓）
    //=========================================================================
    wire        row_we;
    wire [6:0]  row_waddr;
    wire [31:0] row_wdata;
    wire [5:0]  ok_nw = (row_err == 8'h00) ? row_nw : 6'd0;   // ★ L1M-c：坏素材 ⇒ 0（不黑屏 ✓）

    lyric_row #(
        .LRC_BASE (LRC_BASE), .FONT_BASE (FONT_BASE), .ASC_BASE (ASC_BASE),
        .MAX_CH   (MAX_CH_T),                 // ★ 取两带较大者（24 ✓）⇒ 逐带上限由 §D 自把关 ✓
        .CLK_HZ   (CLK_HZ)
    ) u_row (
        .clk_sdr (clk_sdr), .rst_sdr_n (rst_sdr_n),
        // 各带内部仍用原有相对地址；物理区域在 RAM 端口处统一偏移。
        .start (row_start),
        .buf_base (c_ttl ? (c_is_t ? (c_bank ? 6'd48 : 6'd0)
                                   : (c_bank ? 6'd8  : 6'd0))
                         : (c_bank ? 6'd40 : 6'd0)),
        .fc (c_fc), .cnt (c_cnt),
        // ★ 歌名/歌手**不高亮** ⇒ `played=0` ⇒ 色码只可能是 1 ⇒ 本层只判"是不是墨" ✓
        .grow (c_grow), .played (c_ttl ? 24'd0 : played),
        .busy (row_busy), .done (row_done), .err (row_err), .nw (row_nw),
        .wr_en (row_we), .wr_addr (row_waddr), .wr_data (row_wdata),
        .px_req (px_req), .px_addr (px_addr), .px_len (px_len),
        .px_ack (px_ack), .px_done (px_done), .px_data (px_data), .px_valid (px_valid)
    );

    // 0..79 歌词，80..175 歌名，176..191 歌手；每带仍有独立乒乓区。
    wire [AW-1:0] text_wr_addr = c_ttl ? (c_is_t ? (8'd80 + {1'b0, row_waddr})
                                                   : (8'd176 + {1'b0, row_waddr}))
                                             : {{(AW-7){1'b0}}, row_waddr};
    wire [AW-1:0] text_rd_addr = any_ttl ?
        (in_t ? (8'd80 + (bk ? 8'd48 : 8'd0) + {2'b00, raT})
              : (8'd176 + (bk ? 8'd8 : 8'd0) + {2'b00, raT}))
        : ((bk ? 8'd40 : 8'd0) + {2'b00, raL});

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
        .dia (row_wdata), .addra (text_wr_addr), .cea (1'b1), .ocea (1'b0),
        .clka (clk_sdr), .wea (row_we), .rsta (1'b0), .bea (1'b0),
        .dib (32'd0), .addrb (text_rd_addr), .ceb (1'b1), .oceb (1'b1),
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
            c_ttl <= 1'b0; c_is_t <= 1'b0;
            b_nt0 <= 6'd0; b_nt1 <= 6'd0; b_ns0 <= 6'd0; b_ns1 <= 6'd0;   // ★ L1M-c
            div <= 11'd0; hold <= 15'd0; off_t <= 11'd0; off_s <= 11'd0;
            w_t <= 12'd0; w_s <= 12'd0;
            fc_t_p <= 16'd0; fc_s_p <= 16'd0;
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
                c_ttl  <= r_ttl;                   // ★ L1M：本次是"歌名/歌手"带吗 ✓
                c_is_t <= r_is_t;                  // ★ L1M：是歌名（1）还是歌手（0）✓
                row_start <= 1'b1;
            end
            if (row_done) begin
                done_tgl <= ~done_tgl;
                err_s    <= row_err;
            end
            // ★★ L1G：写完 ⇒ 记**该块**的字数（`row_done` 后 2 拍读 `row_nw`/`row_err` ✓）
            //   坏素材 ⇒ 记 0 ⇒ 那层不出字（不黑屏 ✓）
            if (dn_d[1]) begin
                // ★★ L1M-c：字数按 **带 × 块** 记 ✓（读侧按 `bk` 选 ✓ —— 与歌词侧同一套 ✓）
                if (c_ttl) begin
                    if (c_is_t) begin
                        if (c_bank) b_nt1 <= ok_nw; else b_nt0 <= ok_nw;
                    end else begin
                        if (c_bank) b_ns1 <= ok_nw; else b_ns0 <= ok_nw;
                    end
                end else if (c_bank) b_nw1 <= ok_nw;
                else                 b_nw0 <= ok_nw;
                // ★ L1M：歌名/歌手**新的一条**渲染完 ⇒ 记宽度（各条独立 ✓）
                //   ★★ L1M-b 修正：**偏移只在"换了一条文字"时归零** ✗ ——
                //   本块**每行/每帧都执行**（见头注 ①②），若在这里无条件 `off_t<=0` ✗，
                //   而走 1px 需 1200 样本（25ms）> 一帧（16.7ms）⇒ 偏移永远走不动 ✗
                //   （板上实测：歌名静止、只看得见头 5 个字 ✓ 就是这个原因 ✓）
                //   判据改用 `c_fc`（本条首字）：同一首歌每帧都一样 ⇒ 不归零 ✓；
                //   换歌/换文本时 `ttl_fc` 变 ⇒ `c_fc` 变 ⇒ 归零重跑 ✓（绕圈归零由 `wrp_*` 负责 ✓）
                if (c_ttl) begin
                    if (c_is_t) begin
                        w_t <= {row_nw, 4'b0};
                        if (c_fc != fc_t_p) off_t <= 11'd0;
                        fc_t_p <= c_fc;
                    end else begin
                        w_s <= {row_nw, 4'b0};
                        if (c_fc != fc_s_p) off_s <= 11'd0;
                        fc_s_p <= c_fc;
                    end
                end
            end
            // ★★ L1M：跑马灯（**样本域**计数 ⇒ 与声音同步、时长精确 ✓）
            //   口径照旧 `layer_title.v` 冻结值：每 `SPP` 个样本走 1px ✓；绕一圈回来停 `HOLD_N` ✓
            else if (samp_stb) begin
                if (hold != 15'd0) hold <= hold - 15'd1;
                else if (div != (SPPW[10:0] - 11'd1)) div <= div + 11'd1;
                else begin
                    div <= 11'd0;
                    off_t <= mov_t ? (wrp_t ? 11'd0 : (off_t + 11'd1)) : 11'd0;
                    off_s <= mov_s ? (wrp_s ? 11'd0 : (off_s + 11'd1)) : 11'd0;
                    if (wrp_t || wrp_s) hold <= HOLDW;   // 绕回来再停 ✓
                end
            end
        end
    end
endmodule

`default_nettype wire
