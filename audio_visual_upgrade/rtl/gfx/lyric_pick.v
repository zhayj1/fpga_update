`default_nettype none
//============================================================================
// rtl/gfx/lyric_pick.v —— LRC 时间轴：选"当前/下一/再下一"行 + 滚行位移（P3/S4-1）
//
// 【为什么存在】逐字高亮要"这一拍该显示哪几行、滚到第几像素"这一个答案 ✓；
//   表在 SDRAM（`LRC_TAB` ✓），60 帧/秒要一次答案 ⇒ 本模块负责把"表"变成"三行"。
//
// 【★ 设计取舍：不缓存全表 —— 每帧**一次 136 字突发**，边收边比】
//   旧想法：先把 64 行时间戳读进片内 RAM（64×24 = **1,536 bit** ✓）再扫 64 拍选行 ✓。
//   现在的做法：**一次突发把"头 8 字 + 64 行槽 128 字"全读回来**（= 136 字 = 544 B ✓
//   正好落在**同一个 SDRAM 行**内：`0x17F040` 起 136 字 ⊂ 行 6128 的 1,569,792..1,570,047 ✓），
//   数据**流进来的过程中**就把行槽一个个比完 ✓ ⇒ **零存储**（省掉 1,536 bit ✓）
//   且比"读一次 + 每帧扫 64 拍"**更简单**（没有数组、没有扫描状态机、没有索引算术 ✓）。
//
//   代价（算过 ✓ 不是感觉）：每帧一次 136 字突发 ⇒ 60 × 136 = **8,160 字/s = 32.6 KB/s** ✓
//   （`design:186` 给图形通路的预算是 < 1 MB/s ✓ ⇒ 占 **3.3%** ✓；逐字取字形那一路约 365 KB/s ✓）
//   而"缓存全表"版本省下的是 1,536 bit 寄存器/LUTRAM —— 板上资源紧，这一头更贵 ✓。
//   ★ 另一个副作用是**更好**的：一帧只选一次行 ⇒ 换行**只发生在帧边界** ✓，
//     不会在一帧中间突然换行（撕裂 ✓），A7-1 要求"±1 帧"✓ 正好落在边界上 ✓。
//
// 【行语义】`design:733-755`（严格双行 + 从底滚入 ✓）：
//   `cur` = 时间戳 ≤ `played` 的**最后一行** ✓（`cur_vld=0` = 还没到第 0 行 ⇒ 不显示歌词 ✓）
//   `nxt` = cur 后面一行 ✓、`n3` = 再后面一行 ✓（滚行时三行同时可见 ⇒ 必须提前就绪 ✓）
//   ★ 三行都带完整行槽：`s`（时间戳样本数 ✓ 滚行相位用）+ `fc`（首个字记录号 ✓）+ `cnt`（字数 ✓）
//     ⇒ 渲染层**不需要**再读行表（只去读字记录 ✓）。
//
// 【滚行相位（0.3s / 38px ✓ workitem §1b-3/4）】
//   窗口内（`0 < nxt_s − played ≤ 14400` 样本 ✓ = 0.3s@48kHz ✓）按 48kHz 节拍 `samp_stb` 推进：
//     `acc += 38`；`acc ≥ 14400` ⇒ `off_px++`、`acc −= 14400` ✓
//   窗口判断在采样拍锁存，位移在下一 clk_sdr 拍提交；换行取消待提交的旧样本。
//   ⇒ 14400 拍正好走 38 px ✓（38 × 14400 / 14400 = 38 **精确** ✓ 无除法、无乘法器 ✓，
//     只用"加常数 + 比较 + 减常数" ✓）。
//   ★ 进入窗口的那一拍**预置** `acc = 38`、`off_px = 0` ⇒ 窗口最后一拍恰好 `off_px = 38` ✓
//     （若不预置会差 1 px ✗ —— 已按算式核过 ✓，TB `LP-09` 逐点对账 ✓）。
//   ★ 出窗口**不清零** `off_px` ✗：`played` 追平 `nxt_s` 时窗口就关了，但 `cur` 要等**下一帧**
//     才换 ⇒ 这中间若清 0，字会"啪"地掉回下面 38 px ✗（可见跳变 ✓）。
//     清零点改在 **`done` 且 `cur_idx` 变了**（= 真换行的那一帧 ✓）⇒ 滚动结束时停在 38 ✓
//     下一帧新行从 0 开始 ✓ 衔接连续 ✓。
//
// 【时钟】全在 `clk_sdr`（100MHz ✓）。三个输入都是"同域/慢值"：
//   · `played`：顶层在 **clk_sdr 数 48kHz 节拍边沿**得到的计数器 ✓（同域 ✓ 无跨域多比特风险 ✓）
//   · `tick`  ：帧起点脉冲（60Hz ✓）⇒ 每帧选一次 ✓
//   · `samp_stb`：48kHz 单拍脉冲 ✓（与 `played` 同源 ✓）
//
// 【读客户端】与 `fetch_line` 同形 ✓（req 电平 / ack 后立刻撤 req ✓ 铁律）。
//
// 体检（A11"素材坏 ⇒ 不黑屏" ✓）：magic ≠ `'LRC1'` ⇒ `err=0x65`、`tab_ok=0`、三行全 `vld=0` ✓；
//   `n_lines > 64` ⇒ 同上 ✓；读不出来（看门狗 `WD_MS`）⇒ `err=0x04` ✓ 且 `busy` 照常释放 ✓。
//============================================================================
module lyric_pick #(
    parameter [20:0] LRC_BASE  = 21'h17F040,   // `LRC_TAB` 槽（`plan:76` ✓）
    parameter integer SLOT_MAX = 64,            // 行槽固定 64（表结构 v2 ✓）
    parameter integer CLK_HZ   = 100000000,
    parameter integer WD_MS    = 4,             // 取表看门狗（100MHz 下 4ms ✓）
    parameter integer SC_SAMP  = 14400,         // 滚行窗口 = 0.3s @48kHz ✓
    parameter integer SC_PX    = 38,            // 滚行总位移 = PITCH ✓
    parameter integer CONTEXT = 0              // previous two / third future for five-row viewport
)(
    input  wire        clk_sdr,
    input  wire        rst_sdr_n,
    input  wire        tick,                    // 脉冲：帧起点（60Hz）⇒ 选一次行 ✓
    input  wire        samp_stb,                // 48000Hz 单拍脉冲（滚行累加 ✓）
    input  wire [23:0] played,                  // 已播样本数（clk_sdr 域 ✓ 48kHz 递增 ✓）

    output reg         busy,
    output reg         done,                    // 单拍：本次选行结束（成败都出 ✓）
    output reg  [7:0]  err,                     // 0x00 正常 ｜ 0x65 表坏 ｜ 0x04 读超时
    output reg         tab_ok,                  // 1 ⇒ 表可用（magic/行数都对 ✓）
    output reg  [15:0] n_lines,

    // ---- 三行（各带完整行槽 ✓；只在 `done` 那拍更新 ⇒ 引擎随便读都不会读到半截 ✓）----
    output reg  [15:0] cur_idx, nxt_idx, n3_idx,
    output reg  [23:0] cur_s,   nxt_s,   n3_s,      // 行时间戳（样本数 ✓）
    output reg  [15:0] cur_fc,  nxt_fc,  n3_fc,     // 首个字记录号 ✓
    output reg  [15:0] cur_cnt, nxt_cnt, n3_cnt,    // 本行字数 ✓
    output reg         cur_vld, nxt_vld, n3_vld,
    output reg [15:0]  prev2_fc, prev2_cnt, prev_fc, prev_cnt, n4_fc, n4_cnt,
    output reg         prev2_vld, prev_vld, n4_vld,

    // ★★ P3/S6-2：表头**字 5 / 6** 的歌名/歌手素材（`{cnt[31:16], fc[15:0]}` ✓）
    //   那 136 字突发**本来就覆盖字 0..135** ⇒ 顺手读回来，**零额外流量** ✓
    output reg  [15:0] ttl_fc, ttl_cnt, sgr_fc, sgr_cnt,
    output reg         ttl_vld, sgr_vld,

    // ---- 滚行相位 ----
    output reg  [5:0]  off_px,                  // 0..38（px ✓ 三行同时上移这么多 ✓）
    output reg         scroll_on,               // 1 ⇒ 正处于滚行窗口内 ✓

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
    localparam integer NW     = 8 + 2 * SLOT_MAX;      // 8 头 + 128 行槽 = 136 字 ✓
    localparam [31:0]  MAGIC  = 32'h3143524C;          // 'LRC1'（小端 ✓ 工具侧 `put32` ✓）
    localparam [15:0]  SLOT16 = SLOT_MAX;              // 行数上限（比较用向量 ✓ 不切 integer ✓）

    function integer clog2f;
        input integer value;
        integer v;
        begin
            clog2f = 0;
            for (v = value - 1; v > 0; v = v >> 1) clog2f = clog2f + 1;
        end
    endfunction
    // Narrow residue only when each step is at most one window. Preserve the
    // original 32-bit arithmetic for parameter sets with a larger increment.
    localparam integer ACC_W = (SC_PX > SC_SAMP) ? 32 : clog2f(SC_SAMP + SC_PX);
    localparam [ACC_W-1:0] WRAP_AT = SC_SAMP - SC_PX;

    localparam [2:0] S_IDLE = 3'd0,
                     S_REQ  = 3'd1,       // 发一次 136 字读请求 ✓
                     S_FILL = 3'd2,       // 边收边比（体检 + 选行 ✓）
                     S_FIN  = 3'd3;

    reg  [2:0]  st, st_d;
    reg  [31:0] wd;
    reg  [7:0]  wc;                    // 已收字数 0..135 ✓
    reg  [15:0] nl_t;                  // 表头里的行数（字 4 高半 ✓）
    reg  [23:0] pend_s;                // 偶数字（= 槽的 samples ✓）暂存，等下一个奇数字配对 ✓
    reg         pend_hit;              // 偶数字拍预比较，奇数字拍只使用结果
    localparam integer FC_W=CONTEXT ? 9 : 16, CNT_W=CONTEXT ? 5 : 16;
    localparam integer SLOT_W=24+FC_W+CNT_W;
    reg [SLOT_W-1:0] sl_c,sl_n,sl_3;
    reg  [15:0] wi_c;                  // cur 行号 ✓
    reg  [1:0]  want;                  // 命中后还要收几个"后续行"（2 ⇒ 收 nxt、1 ⇒ 收 n3 ✓）
    reg         c_v, n_v, n3_v;        // 本次扫描的中间有效位 ✓
    // Only bounded first/count fields are needed for history, not timestamps.
    reg [8:0] p2_fc, p_fc, f4_fc;
    reg [4:0] p2_cnt, p_cnt, f4_cnt;
    reg p2_v, p_v, f4_v;
    reg         bad;                   // 表坏（magic 或行数 ✓）
    reg         wd_e;                  // 读超时 / 突发被截短 ✓
    reg  [ACC_W-1:0] acc;              // 只需容纳窗口阈值及单次增量
    reg  [23:0] win_start;             // 下一行滚动窗口的饱和起点
    reg         in_prev;               // 上一拍是否在窗口内（上升沿预置 ✓）
    // Sample decisions commit one clk_sdr later. A real line change cancels
    // both the pending decision and a coincident sample, keeping reset priority.
    reg         scroll_stb, scroll_nxt, scroll_win;
    reg  [15:0] ttl_fc_r, ttl_cnt_r, sgr_fc_r, sgr_cnt_r;   // 字 5 / 6 暂存（提交那拍才对外 ✓）
    reg         ttl_vld_r, sgr_vld_r;

    wire        wd_hit  = (st != S_IDLE) && (st != S_FIN) && (wd == WD_MAX[31:0]);
    wire        ok_w    = ~bad & ~wd_e;                 // 本次结果可用 ✓
    wire [6:0]  sidx7   = wc[7:1] - 7'd4;               // 本字对应的槽号 = (wc-8)>>1 ✓（0..63 ✓）
    wire [5:0]  sidx    = sidx7[5:0];
    wire [SLOT_W-1:0] slot_in = {pend_s, px_data[FC_W-1:0], px_data[16 +: CNT_W]};
    wire slot_valid=px_data[31:16]!=0 && px_data[31:16]<=19 &&
                    ({1'b0,px_data[15:0]}+{1'b0,px_data[31:16]}<=17'd488);
    //   工具侧槽 = [samples 4B][first_char 2B][count 2B] ⇒ 偶数字 = samples、
    //   奇数字低半 = first_char ✓ 高半 = count ✓（表结构 v2 ✓ 已对 golden 核过 ✓）
    wire        in_win  = nxt_vld && (nxt_s > played) && (played >= win_start);
    wire        acc_wrap = (SC_PX <= SC_SAMP) ? (acc >= WRAP_AT)
                         : ((acc + SC_PX[ACC_W-1:0]) >= SC_SAMP[ACC_W-1:0]);
    wire [ACC_W-1:0] wrapped_acc = (SC_PX <= SC_SAMP) ? (acc - WRAP_AT)
                                : (acc + SC_PX[ACC_W-1:0] - SC_SAMP[ACC_W-1:0]);

    integer k;

    always @(posedge clk_sdr) begin
        if (!rst_sdr_n) begin
            st <= S_IDLE; st_d <= S_IDLE;
            busy <= 1'b0; done <= 1'b0; err <= 8'h00; tab_ok <= 1'b0; n_lines <= 16'd0;
            cur_idx <= 16'd0; nxt_idx <= 16'd0; n3_idx <= 16'd0;
            cur_s <= 24'd0; nxt_s <= 24'd0; n3_s <= 24'd0;
            cur_fc <= 16'd0; nxt_fc <= 16'd0; n3_fc <= 16'd0;
            cur_cnt <= 16'd0; nxt_cnt <= 16'd0; n3_cnt <= 16'd0;
            cur_vld <= 1'b0; nxt_vld <= 1'b0; n3_vld <= 1'b0;
            prev2_fc<=0; prev2_cnt<=0; prev_fc<=0; prev_cnt<=0; n4_fc<=0; n4_cnt<=0;
            prev2_vld<=0; prev_vld<=0; n4_vld<=0;
            p2_fc<=0; p2_cnt<=0; p_fc<=0; p_cnt<=0; f4_fc<=0; f4_cnt<=0;
            p2_v<=0; p_v<=0; f4_v<=0;
            ttl_fc <= 16'd0; ttl_cnt <= 16'd0; ttl_vld <= 1'b0;
            sgr_fc <= 16'd0; sgr_cnt <= 16'd0; sgr_vld <= 1'b0;
            ttl_fc_r <= 16'd0; ttl_cnt_r <= 16'd0; ttl_vld_r <= 1'b0;
            sgr_fc_r <= 16'd0; sgr_cnt_r <= 16'd0; sgr_vld_r <= 1'b0;
            off_px <= 6'd0; scroll_on <= 1'b0; acc <= {ACC_W{1'b0}}; in_prev <= 1'b0;
            win_start <= 24'd0;
            scroll_stb <= 1'b0; scroll_nxt <= 1'b0; scroll_win <= 1'b0;
            px_req <= 1'b0; px_addr <= 21'd0; px_len <= 16'd0;
            wd <= 32'd0; wc <= 8'd0; nl_t <= 16'd0; pend_s <= 24'd0; pend_hit <= 1'b0;
            sl_c <= 56'd0; sl_n <= 56'd0; sl_3 <= 56'd0; wi_c <= 16'd0;
            want <= 2'd0; c_v <= 1'b0; n_v <= 1'b0; n3_v <= 1'b0;
            bad <= 1'b0; wd_e <= 1'b0;
        end else begin
            st_d <= st;
            done <= 1'b0;
            px_req <= 1'b0;                       // 默认撤 ✓（ack 那拍撤 ✓）
            scroll_stb <= samp_stb;
            if (samp_stb) begin
                scroll_nxt <= nxt_vld;
                scroll_win <= in_win;
            end

            // 看门狗：状态推进或收到数据就清零 ✓
            // ★★ 2026-10-05（**整机仿真实测抓出**）：`wd` 在 S_IDLE 也自增到**饱和** ✗
            //   ⇒ 一旦空闲超过看门狗窗口（整机 `pick_tick` 每帧才来一次 = 16.7ms ≫ WD_MS=4ms ✗），
            //     进入 S_REQ 的**第一拍** `wd` 仍读到饱和值、而 `st` 已不是 S_IDLE
            //     ⇒ `wd_hit` **假命中** ⇒ 立刻跳 S_FIN、`err=0x04`、请求只挂了一拍 ✗
            //   症状（实测）：`wc=0 st=S_IDLE wd_e=1`，但 `ctl` 口确实回了整 136 字 ✗、
            //     `tab_ok` 永远为 0 ⇒ 文本层整层透明 ✗
            //   ⇒ 与 `lyric_row.v:180` 那处**同一修法**：**空闲就清零** ✓
            if ((st == S_IDLE) || (st != st_d) || px_valid) wd <= 32'd0;
            else if (wd != WD_MAX[31:0]) wd <= wd + 32'd1;

            //----------------------------------------------------------------
            // ★ 滚行累加器（本 always 块是 `off_px`/`acc`/`scroll_on` 的**唯一写者** ✓；
            //   S_FIN 里的清零写在**后面** ⇒ 同拍冲突时"换行清零"优先 ✓ 确定性 ✓）
            //----------------------------------------------------------------
            if (scroll_stb) begin
                if (!scroll_nxt) begin            // 没有下一行 ⇒ 永远不滚 ✓ 顺手清干净
                    scroll_on <= 1'b0; off_px <= 6'd0; acc <= {ACC_W{1'b0}}; in_prev <= 1'b0;
                end else if (scroll_win) begin
                    scroll_on <= 1'b1;
                    if (!in_prev) begin           // ★ 刚进窗口：预置一拍 ⇒ 末拍恰好 38 ✓
                        acc     <= SC_PX[ACC_W-1:0];
                        off_px  <= 6'd0;
                        in_prev <= 1'b1;
                    end else if (acc_wrap) begin
                        acc <= wrapped_acc;
                        if (off_px < SC_PX[5:0]) off_px <= off_px + 6'd1;
                    end else begin
                        acc <= acc + SC_PX[ACC_W-1:0];
                    end
                end else begin
                    scroll_on <= 1'b0;            // ★ 出窗口只停不动 ✗ 不清零（见文件头 ✓）
                    in_prev   <= 1'b0;
                end
            end

            case (st)
            //----------------------------------------------------------------
            S_IDLE: begin
                busy <= 1'b0;
                if (tick) begin
                    busy   <= 1'b1;
                    wc     <= 8'd0;
                    want   <= 2'd0;
                    c_v    <= 1'b0; n_v <= 1'b0; n3_v <= 1'b0;
                    bad    <= 1'b0; wd_e <= 1'b0;
                    pend_s <= 24'd0;
                    pend_hit <= 1'b0;
                    sl_c   <= 56'd0; sl_n <= 56'd0; sl_3 <= 56'd0; wi_c <= 16'd0;
                    p2_fc<=0; p2_cnt<=0; p_fc<=0; p_cnt<=0; f4_fc<=0; f4_cnt<=0;
                    p2_v<=0; p_v<=0; f4_v<=0;
                    err    <= 8'h00;
                    st     <= S_REQ;
                end
            end
            //----------------------------------------------------------------
            // 一次突发：`LRC_BASE` 起 `NW` 字（头 8 + 64 行槽 ×2 ✓）
            S_REQ: begin
                busy    <= 1'b1;
                px_req  <= 1'b1;
                px_addr <= LRC_BASE;
                px_len  <= NW[15:0];
                if (px_ack) begin
                    px_req <= 1'b0;                // ★ 铁律：ack 后立刻撤 ✓
                    st     <= S_FILL;
                end
                if (wd_hit) begin wd_e <= 1'b1; st <= S_FIN; end
            end
            //----------------------------------------------------------------
            // 边收边比：头 8 字体检 ✓；行槽每 2 字成一个槽 ✓
            S_FILL: begin
                busy <= 1'b1;
                if (px_valid) begin
                    if (wc < 8'd8) begin                       // ---- 头 ----
                        // ★★ p3-lean 步2b：这里**必须**用 `!==`（case inequality）而不是 `!=` ✗
                        //   SDRAM 未初始化时 `px_data` 是 **X**，而 `X != MAGIC` 求值为 **X**（不是 1）
                        //   ⇒ `bad` 变 X ⇒ `ok_w`/`tab_ok`/三行 `vld` 全变 X ⇒ **X 会渗进画面**
                        //     ⇒ P1/P2 的帧 golden（`obs_rgb` 逐字节比对）当场作废 ✗
                        //   用 `!==` ⇒ `X !== MAGIC` = **1**（确定）⇒ `bad=1` ⇒ `tab_ok=0`
                        //   ⇒ 三行 `vld` 恒 0 ⇒ **文本层确定地透明**（"无数据不出墨、绝不发 X" ✓）
                        if (wc == 8'd0) bad <= (px_data !== MAGIC);
                        if (wc == 8'd4) begin
                            nl_t <= px_data[31:16];            // ★ 总数在**字 4** ✓
                            if (px_data[31:16] > SLOT16) bad <= 1'b1;
                        end
                        if (wc == 8'd5) begin                      // ★ 字 5 = 歌名 {cnt,fc}
                            ttl_fc_r  <= px_data[15:0];
                            ttl_cnt_r <= px_data[31:16];
                            ttl_vld_r <= (px_data[31:16] != 16'd0);
                        end
                        if (wc == 8'd6) begin                      // ★ 字 6 = 歌手 {cnt,fc}
                            sgr_fc_r  <= px_data[15:0];
                            sgr_cnt_r <= px_data[31:16];
                            sgr_vld_r <= (px_data[31:16] != 16'd0);
                        end
                    end else if (wc[0] == 1'b0) begin          // ---- 偶数字：samples ----
                        pend_s <= px_data[23:0];
                        pend_hit <= (px_data[23:0] <= played);
                    end else begin                             // ---- 奇数字：fc | cnt ----
                        if (!bad && ({10'd0, sidx} < nl_t)) begin
                            if (pend_hit) begin                 // 命中（后面的会覆盖前面的 ✓ 取最后 ✓）
                                if(CONTEXT) begin
                                    p2_fc<=p_fc; p2_cnt<=p_cnt; p2_v<=p_v;
                                    p_fc<=sl_c[CNT_W +: FC_W];p_cnt<=sl_c[CNT_W-1:0];
                                    p_v<=c_v;
                                    f4_v<=0;
                                end
                                sl_c <= slot_in;
                                wi_c <= {10'd0, sidx};
                                c_v  <= !CONTEXT || slot_valid;
                                want <= CONTEXT ? 2'd3 : 2'd2;
                                n_v  <= 1'b0; n3_v <= 1'b0;
                            end else if (want != 2'd0) begin   // 非命中且还欠后续行 ⇒ 收下 ✓
                                if (want == (CONTEXT ? 2'd3 : 2'd2)) begin sl_n <= slot_in; n_v<=!CONTEXT || slot_valid; end
                                else if(want == (CONTEXT ? 2'd2 : 2'd1)) begin sl_3 <= slot_in; n3_v<=!CONTEXT || slot_valid; end
                                else if(CONTEXT) begin
                                    f4_fc<=px_data[8:0]; f4_cnt<=px_data[20:16];
                                    f4_v<=slot_valid;
                                end
                                want <= want - 2'd1;
                            end
                        end
                    end
                    if (wc == NW - 1) st <= S_FIN;
                    else              wc <= wc + 8'd1;
                end
                // ★ 突发被截短（`px_done` 早到）⇒ 当"读不完整"处理 ✗（绝不拿半张表去选行 ✓）
                if (px_done && (wc != NW - 1)) begin wd_e <= 1'b1; st <= S_FIN; end
                if (wd_hit) begin wd_e <= 1'b1; st <= S_FIN; end
            end
            //----------------------------------------------------------------
            // 提交：只在**这一拍**更新输出 ✓（`tick` 之间引擎随便读都不会读到半截 ✓）
            S_FIN: begin
                busy    <= 1'b0;
                done    <= 1'b1;
                err     <= bad         ? 8'h65 :
                           (wd_e       ? 8'h04 : 8'h00);
                tab_ok  <= ok_w;
                n_lines <= ok_w ? nl_t : 16'd0;
                cur_idx <= wi_c;
                nxt_idx <= wi_c + 16'd1;
                n3_idx  <= wi_c + 16'd2;
                cur_s<=sl_c[SLOT_W-1 -:24];cur_fc<=sl_c[CNT_W +:FC_W];cur_cnt<=sl_c[CNT_W-1:0];
                nxt_s<=sl_n[SLOT_W-1 -:24];nxt_fc<=sl_n[CNT_W +:FC_W];nxt_cnt<=sl_n[CNT_W-1:0];
                win_start <= (sl_n[SLOT_W-1 -:24] > SC_SAMP[23:0])
                           ? sl_n[SLOT_W-1 -:24] - SC_SAMP[23:0] : 24'd0;
                n3_s<=sl_3[SLOT_W-1 -:24];n3_fc<=sl_3[CNT_W +:FC_W];n3_cnt<=sl_3[CNT_W-1:0];
                cur_vld <= ok_w & c_v;
                nxt_vld <= ok_w & n_v;
                n3_vld  <= ok_w & n3_v;
                prev2_fc<={7'd0,p2_fc}; prev2_cnt<={11'd0,p2_cnt};
                prev_fc<={7'd0,p_fc}; prev_cnt<={11'd0,p_cnt};
                n4_fc<={7'd0,f4_fc}; n4_cnt<={11'd0,f4_cnt};
                prev2_vld<=CONTEXT && ok_w && p2_v;
                prev_vld<=CONTEXT && ok_w && p_v;
                n4_vld<=CONTEXT && ok_w && f4_v;
                // ★★ 字 5 / 6 = 歌名 / 歌手素材（表坏/超时就当没有 ⇒ 该层整层透明 ✓ 不黑屏 ✓）
                ttl_fc  <= ttl_fc_r;  ttl_cnt <= ttl_cnt_r;  ttl_vld <= ok_w & ttl_vld_r;
                sgr_fc  <= sgr_fc_r;  sgr_cnt <= sgr_cnt_r;  sgr_vld <= ok_w & sgr_vld_r;
                // ★ 真换行 ⇒ 滚行相位归零（与本块前面的累加器同拍冲突时**本处优先** ✓）
                if (wi_c != cur_idx) begin
                    off_px <= 6'd0; acc <= {ACC_W{1'b0}}; in_prev <= 1'b0; scroll_on <= 1'b0;
                    scroll_stb <= 1'b0;
                end
                st <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
