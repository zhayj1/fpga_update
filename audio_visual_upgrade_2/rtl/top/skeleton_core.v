`default_nettype none
//=============================================================================
// rtl/top/skeleton_core.v —— P0-2 骨架核心（**时钟全部从端口进来**，便于仿真）
//
// 为什么要拆出 core：
//   本机 ModelSim **不能**仿真 PLL（`eg_phy_pll.v` 模型不锁定，见附录 A-5），
//   而 SD 卡读写、SDRAM 往返和视频合成仍需在 core 中仿真。
//   ⇒ 把「PLL + PHY + 管脚」留给 `skeleton_top.v`（只做综合/上板），
//     把「逻辑」放在本模块：TB 直接给 clk/clk_sdr/clk_pix 就能完整仿真。
//
// 三个时钟域（各带独立复位）：
//   · clk_pix(25MHz) + rst_pix(高有效) ：彩条 → RGB→AXIS → HDMI 发射核（出 10bit TMDS 字）
//   · clk_sdr + clk_sdr_sft + rst_sdr(高有效) ：sdram_top + sdram_arb
//   · clk(50MHz) + rst_n(低有效) ：storage_top（SD/FAT32 文件服务，**板上实测就是 50MHz**）
//   ★ storage_top 保持 50MHz 是刻意的：它是上一轮在 50MHz 下验证过的产品路径，
//     不要为了省一个时钟域把它搬到 150MHz（会引入未验证的时序风险）。
// LED0 使用同步后的 SDRAM 初始化状态。
//=============================================================================
module skeleton_core #(
    parameter integer CLK_HZ     = 50000000,     // storage_top 主时钟
    parameter integer SDR_CLK_MHZ= 150,          // clk_sdr 频率
    // ★ A1：KEY4 去抖时间（ms）。板上默认 20ms；仿真里 TB 可传 1 以缩短运行时间。
    parameter integer KEY_DEBOUNCE_MS = 20,
    // ★★ S3-b：音量系数（口径见 `rtl/audio/wav_stream_player.v` 文件头 ✓）
    //   256 = ×1（**精确** ✓）；0 = 真静音 ✓；128 = ÷2 ✓
    //   ★ **满档必须是 256** ✗ 不是 255 —— `design:862` 的 A3 要求"100% 时逐样本与源**一致**" ✓，
    //     255/256 会让每个样本差千分之四 ⇒ 那条判据字面就不成立 ✗
    //     （`plan:381` 原写的"0/128/**255**"已作废 ✓，见 `doc/workitem_p2_s3.md` §3.2 ✓）
    //   ★ 本步**档位源 = 常量** ✓：**不接按键 ✗、不接拨码 ✗**（音量的法定入口是 KEY2/KEY3 ✓，
    //     且"画面显示"属 A10 ⇒ 都在 P5 ✓ `PROJECT_BRIEF.md:41-42` ✓）
    parameter [8:0]   GAIN_DEFAULT    = 9'd256,
    // ★★★ 2026-10-10 回退说明：`CWP_GAP_MS` / `WG_N` / `WR_GUARD` / `LO_EVERY` 四个**实验用参数**
    //   已随本次回退**全部删除** ✗→✓，原因逐条：
    //     · `WG_N`（读空闲写闸）      —— **被实测证伪**：闸门是**透明的**（读侧本就 ~85% 空闲 ✗）
    //     · `WR_GUARD`（写后保护期）  —— **被实测证伪**：64 与 1024 拍结果**逐字节相同** ✗
    //     · `LO_EVERY`（lo 扇区配额）—— 依赖"存储层能并发服务 lo"，而那个前提**没修成** ✗
    //     · `CWP_GAP_MS`              —— 探针 v2 改成**单笔仪表**后不再需要（无周期 ✓）
    //   ⇒ 全部结论已记进 `artifacts/step0_cw_probe_20261009/README.md` ✓ 需要时再取 ✓
    //   ★ 保留 `LD_WD_MS`：它是 `bmp_load` 看门狗门限，与并发功能无关 ✓
    //     实测教训：**不能一刀切放宽** ✗ —— 置 200ms 时，开机那笔装载若在 `A_WIDLE` 等
    //     `bidle_pend`，要等满 200ms 才被救回（原来 1ms 就救了 ✗）⇒ 整段开机崩掉 ✓
    //     ⇒ 将来并发预装必须**按上下文切换**（开机 1ms ／ 预装松 ✓）
    parameter integer LD_WD_MS        = 1,
    // ★★★ 2026-10-10：**并发预装时的看门狗门限**（ms）—— 顶层按上下文切换 ✓
    //   【为什么两档】开机独占卡 ⇒ 1ms 合适（且**必须**紧：`A_WIDLE` 等 `bidle_pend` 时靠它救回 ✓）
    //     卡与音频共用 ⇒ 卡侧字节间隔可达几十 ms ⇒ 1ms 必然误判 ✗（实测并发装载只写 3,826/7,680 ✗）
    //     ★ 但**一刀切**放大到 200ms 会把开机弄坏 ✗（实测：开机那笔在 `A_WIDLE` 要等满 200ms ✗）
    //   ⇒ 按 `cwp_active` 切换：`0`（开机/独占总线）用 `LD_WD_MS` ／ `1`（并发预装）用本值 ✓
    //   ★ 代价：一个 32 位比较器、**0 块 BRAM** ✓
    parameter integer LD_WD_MS_LOOSE  = 200,
    // Load large BMPs into fixed display geometry. Disable only for legacy
    // compact simulation fixtures that deliberately contain undersized images.
    parameter integer BMP_DOWNSCALE = 1,
    parameter integer BMP_BG_W=640, BMP_BG_H=480,
    parameter integer BMP_COVER_W=240, BMP_COVER_H=240,
    // ★★★ 2026-10-10：**默认值 = 1（频谱常开）** ✗→✓ —— 这是用户的决定 ✓
    //   【为什么默认必须是 1】参数默认值决定**任何"不显式覆盖"的构建**（尤其 GUI 构建 ✗）
    //     ⇒ 若默认 0，GUI 出来的码流会**没有频谱** ✗（实测用活模板构建：#RAMs=60、#DSPs=4 ✗
    //       而带频谱的是 63 / 8 ✓ —— 常数传播把整条 P4 链优化掉了 ✓）
    //   【仿真怎么办】集成台的 golden **不含频谱层** ✗ ⇒ **台里显式给 0** ✓
    //     （`tb_skeleton_core.v` 的 `.en_fft(0)` ✓）⇒ 两边各取所需 ✓，**RTL 一个字不用改** ✓
    parameter en_fft                  = 1'b1,
    parameter en_color_diag           = 1'b0,
    parameter en_osd                  = 1'b0,
    parameter VISUAL_CONTROLS=0,
    parameter CIRCULAR_UI=0,
    parameter SPLIT_UI=0,
    parameter TYPOGRAPHY              = 1'b0,
    // ★★★ P5/A8（2026-10-10）：**小轮播开关 ＋ 周期**
    //   · `en_rot`：默认 **1**（功能是要用的 ✓）—— 与 `en_fft` 同一套纪律 ✓
    //     ★ 台里**显式给 0** ✓ ⇒ 可做"`en_rot=0` 时 T-01..T-07 逐位不变"的 A/B ✓
    //   · `ROT_MS`：轮播周期（**毫秒** ✓）—— 为什么不用"秒" ✗：
    //     秒级最小 1s = 5,000 万拍 ✗ ⇒ 集成台（~185ms ✗）**永远看不到**轮播 ✗
    //     用毫秒后：板上默认 **20000ms = 20s** ✓、台里可给 **20ms** ✓ ⇒ **真能测到** ✓
    //   ★ `carousel` 模块自身只吃**拍数** ✓（不对时钟做假设 ✓），此处换算 ✓
    //     —— 实测教训：原来让模块吃"秒" ✗ ⇒ 台要跑 3.5 亿拍 ⇒ **直接超时** ✗✗
    parameter en_rot                  = 1'b1,
    parameter integer ROT_MS          = 20000,
    // ★★★ P5/A9（2026-10-10）：**播放期预装下一首 g1** 的开关 ✓
    //   默认 **1**（功能是要用的 ✓，与 `en_fft`/`en_rot` 同一纪律 ✓）
    //   ★ 台里显式给 **0** ✓ ⇒ 做"`en_pre=0` 时与今天逐位相同"的 A/B ✓
    //   ★ 注意：预装**只装进第 4 组槽**（当前不显示 ✓）⇒ 开着也**看不见** ✗
    //     要等 S2（边界切换 ✓）才成为可见功能 ✓ —— 但那时它已经是"已装好"的状态 ✓
    parameter en_pre                  = 1'b1,
    // ★★★ P5/A9（2026-10-10）S2：**自动顺序切歌**（一首播完 ⇒ 下一首 ✓ 硬切零延迟 ✓）
    //   默认 **1** ✓（用户要的功能 ✓）；台里显式给 **0** ✓ 做"逐位不变"的 A/B ✓
    parameter en_a9                   = 1'b1,
    parameter [8:0] FADE_STEP          = 9'd8
)(
    // ---------------- 视频域 ----------------
    input  wire        clk_pix,          // 25MHz
    input  wire        clk_pix5x,        // 125MHz（5×像素时钟；核内部不用，留给 PHY）
    input  wire        rst_pix,          // 高有效
    // ---------------- SDRAM 域 ----------------
    input  wire        clk_sdr,          // 150MHz
    input  wire        clk_sdr_sft,      // 150MHz 相移
    input  wire        rst_sdr,          // 高有效
    // ---------------- SD 域 ----------------
    input  wire        clk,              // 50MHz
    input  wire        rst_n,            // 低有效
    // ---------------- HDMI（10bit TMDS 字，串行化交给 skeleton_top 的 PHY）----------------
    output wire [9:0]  O_ch0_tmds_data,
    output wire [9:0]  O_ch1_tmds_data,
    output wire [9:0]  O_ch2_tmds_data,
    output wire [9:0]  O_clk_tmds_data,
    output wire        O_video_locked,
    output wire        O_ddc_scl,
    inout  wire        IO_ddc_sda,
    // ---------------- SD 卡 ----------------
    output wire        sd_sck,
    output wire        sd_cs_n,
    output wire        sd_mosi,
    input  wire        sd_miso,
    // ---------------- 按键（★ A1：板上 KEY4 = C1，低有效；手册《按键引脚分配》表定案）----------------
    input  wire        key2,
    input  wire        key3,
    input  wire        key4,
    // ---------------- LED / 观测 ----------------
    output wire [3:0]  led,
    // ---------------- 仿真观测（综合时是常数/可忽略，不接管脚）----------------
    output wire [7:0]  obs_axis_data,
    output wire        obs_axis_valid,
    output wire        obs_axis_user,
    output wire        obs_axis_last,
    // ★ P1 新增观测口（帧级判据用）：现有 obs_axis_data 只有 8 位（ax_data[7:0]），
    //   而 AXIS 是每像素 24 位 ⇒ 只能看到低字节、还原不出整帧 ⇒ 另开"合成器输出"这一路。
    //   命名连接 ⇒ skeleton_top 不接也兼容（不接会有未连接警告，无功能影响）。
    output wire        obs_de,
    output wire [23:0] obs_rgb
);
    // Shared display anchors for the board's established 6:5 horizontal
    // screen expansion. Cover contour and both music effects stay concentric.
    localparam integer UI_CENTER_X=SPLIT_UI ? 160 : CIRCULAR_UI ? 320 : (TYPOGRAPHY ? 160 : 260);
    localparam integer UI_CENTER_Y=CIRCULAR_UI ? 254 : 165;

    //=========================================================================
    // 1) 视频：彩条 → RGB→AXIS → HDMI 发射核
    //=========================================================================
    wire        cb_hs, cb_vs, cb_de;
    wire [7:0]  cb_r, cb_g, cb_b;

    color_bar u_bars (
        .clk   (clk_pix),
        .rst   (rst_pix),
        .hs    (cb_hs),
        .vs    (cb_vs),
        .de    (cb_de),
        .rgb_r (cb_r),
        .rgb_g (cb_g),
        .rgb_b (cb_b)
    );

    //=========================================================================
    // 1.5) ★ P1：底色 → 背景(槽) → 封面(槽+色键) 合成，**取代彩条作为视频源**
    //      彩条仍作为**时序源**（cb_vs/cb_de 供 AXIS 与图层对齐；P1 不做真 HDMI 时序源切换）
    //=========================================================================
    // 帧首检测：真件不导出 vs 边沿；★ vs_d0 复位值必须为 0（真件复位后 vs 为低 —— KI-01 教训）
    reg vs_d0, vs_p;
    always @(posedge clk_pix) begin
        if (rst_pix) begin vs_d0 <= 1'b0; vs_p <= 1'b0; end
        else         begin vs_d0 <= cb_vs; vs_p <= vs_d0; end
    end
    wire fr_start = vs_p & ~vs_d0;

    // 图层窗口/槽：背景居中；封面固定靠上，素材内的可见图案位于中上部。
    wire        bg_en, cv_en;
    wire [15:0] bg_x, bg_y, bg_w, bg_h, bg_iw, bg_ih, bg_wpr;
    wire [20:0] bg_slot;
    wire [15:0] cv_x, cv_y, cv_w, cv_h, cv_iw, cv_ih, cv_wpr;
    wire [20:0] cv_slot;
    wire [15:0] cv_pop_x,cv_pop_y,cv_pop_w,cv_pop_h;
    wire obg_en,ocv_en,old_enable,fade_busy,scene_accepted;
    wire [8:0] fade_alpha;
    wire [15:0] obg_x,obg_y,obg_w,obg_h,obg_iw,obg_ih,obg_wpr;
    wire [15:0] ocv_x,ocv_y,ocv_w,ocv_h,ocv_iw,ocv_ih,ocv_wpr;
    wire [20:0] obg_slot,ocv_slot;
    wire [15:0] ocv_pop_x,ocv_pop_y,ocv_pop_w,ocv_pop_h;
    wire [1:0] cover_pop_level;
    wire ring_vld;
    wire [23:0] ring_rgb;
    wire [7:0] ring_alpha;
    wire [23:0] obg_rgb,ocv_rgb;
    wire obg_vld,ocv_vld,obg_idle,ocv_idle;
    localparam [23:0] ch_key = 24'hFF00FF;   // ★ 色键常量（2026-10-02：原为 reg+initial ⇒ TD 警告
                                             //   "Initial value omitted on non-DFF net" ⇒ 硬件里根本没有初值 ✗）
    wire [23:0] bg_rgb, cv_rgb;
    wire        bg_vld, cv_vld;
    wire [31:0] bg_und, bg_stall, bg_ferr, bg_gap;
    wire [31:0] cv_und, cv_stall, cv_ferr, cv_gap, cv_keyed;

    // Four image caches share one SDRAM writer; text remains an independent client.
    wire        c0_req, c0_ack, c0_done, c0_valid;
    wire [20:0] c0_addr;
    wire [15:0] c0_len;
    wire [66:0] image_raster;
    wire [3:0] img_cmd,img_free,img_bank,img_ack,img_take,img_active,img_done,img_err,img_we;
    wire [83:0] img_addr;
    wire [63:0] img_words;
    wire [9:0] img_wr_addr;
    wire img_good;
    wire [4:0] clients_ack,clients_done,clients_valid;
    wire        arb_px_req, arb_px_ack, arb_px_done, arb_px_valid;
    wire [20:0] arb_px_addr;
    wire [15:0] arb_px_len;
    wire [31:0] arb_px_data;
    wire [31:0] pxa_grant, pxa_contend;

    //=========================================================================
    // 2a) ★★ p3-lean 步2b：`px_arb2` → `px_arb3`（文本成为 px 口的**第三个**客户）
    //   c0 = 背景 `u_bg`、c1 = 封面 `u_cv`（**相对次序不变** ⇒ 板上验过的行为不受影响 ✓）
    //   c2 = 文本 `u_lyr`（每字 2 笔 × ≈19 字 = 38 笔**短**突发/行）
    //=========================================================================
    wire        c2_req, c2_ack, c2_done, c2_valid;
    wire [20:0] c2_addr, c2_addr_raw;
    wire [15:0] c2_len;
    wire [31:0] c2_data;

    // ---- 文本链的线（逻辑在 §2b，位于音频段之后：那里才能引用 `wav_tick` ✓）----
    wire [23:0] ly_rgb;
    wire        ly_vld;
    wire [31:0] ly_gap, ly_on;
    wire [11:0] ly_ttl_off;                     // ★ L1M-b：歌名跑马灯偏移（→ 报文 ✓）
    // `lyric_pick` 的读口（px 形状）——它挂 `sdram_arb` 的 **ctl** 口（见 §2b 与 `u_arb` 例化）
    wire        lp_px_req, lp_px_ack, lp_px_done, lp_px_valid;
    wire [20:0] lp_px_addr, lp_px_addr_raw;
    reg [1:0] lrc_slot_sync, lrc_ok_sync;
    localparam [20:0] TEXT_LRC_BASE=TYPOGRAPHY ? 21'h10B300 : 21'h121440;
    localparam [20:0] LRC_SLOT_DELTA = TYPOGRAPHY ? 21'd1112 : (21'hD5C00 - 21'h121440);
    wire c2_lrc_addr = (c2_addr_raw >= TEXT_LRC_BASE) && (c2_addr_raw < TEXT_LRC_BASE+21'd1112);
    assign lp_px_addr = lrc_slot_sync[1] ? (lp_px_addr_raw + LRC_SLOT_DELTA) : lp_px_addr_raw;
    assign c2_addr = (lrc_slot_sync[1] && c2_lrc_addr) ?
                     (c2_addr_raw + LRC_SLOT_DELTA) : c2_addr_raw;
    wire [15:0] lp_px_len;
    wire [31:0] lp_px_data;

    px_arb5 u_pxa (
        .clk_sdr (clk_sdr), .rst_sdr_n (~rst_sdr),
        .arb_req (arb_px_req), .arb_addr (arb_px_addr), .arb_len (arb_px_len),
        .arb_ack (arb_px_ack), .arb_done (arb_px_done),
        .arb_valid (arb_px_valid),
        .c_req ({2'd0,c2_req,1'b0,c0_req}),
        .c_addr ({42'd0,c2_addr,21'd0,c0_addr}),
        .c_len ({32'd0,c2_len,16'd0,c0_len}),
        .c_ack (clients_ack),.c_done (clients_done),.c_valid (clients_valid),
        .grant_cnt (pxa_grant), .contend_cnt (pxa_contend)
    );
    assign {c2_ack,c0_ack}={clients_ack[2],clients_ack[0]};
    assign {c2_done,c0_done}={clients_done[2],clients_done[0]};
    assign {c2_valid,c0_valid}={clients_valid[2],clients_valid[0]};
    assign c2_data=arb_px_data;

    scene_raster u_image_raster(.clk_pix(clk_pix),.rst_pix_n(~rst_pix),
        .hs(cb_hs),.vs(cb_vs),.de(cb_de),.state(image_raster));
    fetch_writer4 u_image_writer(
        .clk_sdr(clk_sdr),.rst_sdr_n(~rst_sdr),.cmd_valid(img_cmd),.slot_free(img_free),
        .next_bank(img_bank),.cmd_addr(img_addr),.cmd_words(img_words),.cmd_ack(img_ack),
        .wr_take(img_take),.wr_active(img_active),.wr_done(img_done),.wr_error(img_err),
        .wr_en(img_we),.wr_addr(img_wr_addr),.wr_good(img_good),
        .px_req(c0_req),.px_addr(c0_addr),.px_len(c0_len),
        .px_ack(c0_ack),.px_done(c0_done),.px_valid(c0_valid));

    layer_bg #(.MAX_W(640), .LAT(7), .H_ACT_DLY(144), .V_ACT_DLY(35), .V_ACT_LIN(480),
               .SHARED_RASTER(1),.SHARED_WRITER(1),.GEOMETRY_BITS(10)) u_bg (
        .clk_pix (clk_pix), .rst_pix_n (~rst_pix), .hs (cb_hs), .vs (cb_vs), .de (cb_de),
        .en (bg_en),
        .win_x (bg_x), .win_y (bg_y), .win_w (bg_w), .win_h (bg_h),
        .img_w (bg_iw), .img_h (bg_ih), .words_per_row (bg_wpr), .slot_base (bg_slot),
        .dout (bg_rgb), .dout_vld (bg_vld),
        .underrun_cnt (bg_und), .stall_cnt (bg_stall), .ferr_cnt (bg_ferr), .gap_cnt (bg_gap), .idle(),
        .clk_sdr (clk_sdr), .rst_sdr_n (~rst_sdr),
        .px_req (), .px_addr (), .px_len (),
        .px_ack (1'b0), .px_done (1'b0), .px_data (arb_px_data), .px_valid (1'b0),
        .scan_state(image_raster),.cmd_valid(img_cmd[0]),.slot_free(img_free[0]),.next_bank(img_bank[0]),
        .cmd_addr(img_addr[0+:21]),.cmd_words(img_words[0+:16]),.cmd_ack(img_ack[0]),
        .wr_take(img_take[0]),.wr_active(img_active[0]),.wr_done(img_done[0]),
        .wr_error(img_err[0]),.wr_en(img_we[0]),.wr_good(img_good),.wr_addr(img_wr_addr)
    );

    layer_cover #(.MAX_W(320), .LAT(7), .H_ACT_DLY(144), .V_ACT_DLY(35), .V_ACT_LIN(480),
                  .SHARED_RASTER(1),.SHARED_WRITER(1),.SCALE(1),.GEOMETRY_BITS(10)) u_cv (
        .clk_pix (clk_pix), .rst_pix_n (~rst_pix), .hs (cb_hs), .vs (cb_vs), .de (cb_de),
        .en (cv_en), .ch_key (ch_key),
        .win_x (cv_pop_x), .win_y (cv_pop_y), .win_w (cv_pop_w), .win_h (cv_pop_h),
        .img_w (cv_iw), .img_h (cv_ih), .words_per_row (cv_wpr), .slot_base (cv_slot),
        .dout (cv_rgb), .dout_vld (cv_vld),
        .underrun_cnt (cv_und), .stall_cnt (cv_stall), .ferr_cnt (cv_ferr),
        .gap_cnt (cv_gap), .keyed_cnt (cv_keyed), .idle(),
        .clk_sdr (clk_sdr), .rst_sdr_n (~rst_sdr),
        .px_req (), .px_addr (), .px_len (),
        .px_ack (1'b0), .px_done (1'b0), .px_data (arb_px_data), .px_valid (1'b0),
        .scan_state(image_raster),.cmd_valid(img_cmd[1]),.slot_free(img_free[1]),.next_bank(img_bank[1]),
        .cmd_addr(img_addr[21+:21]),.cmd_words(img_words[16+:16]),.cmd_ack(img_ack[1]),
        .wr_take(img_take[1]),.wr_active(img_active[1]),.wr_done(img_done[1]),
        .wr_error(img_err[1]),.wr_en(img_we[1]),.wr_good(img_good),.wr_addr(img_wr_addr)
    );

    layer_bg #(.MAX_W(640),.SHARED_RASTER(1),.SHARED_WRITER(1),.GEOMETRY_BITS(10)) u_old_bg (
        .clk_pix(clk_pix),.rst_pix_n(~rst_pix),.hs(cb_hs),.vs(cb_vs),.de(cb_de),
        .en(old_enable && obg_en),.win_x(obg_x),.win_y(obg_y),.win_w(obg_w),.win_h(obg_h),
        .img_w(obg_iw),.img_h(obg_ih),.words_per_row(obg_wpr),.slot_base(obg_slot),
        .dout(obg_rgb),.dout_vld(obg_vld),.underrun_cnt(),.stall_cnt(),.ferr_cnt(),.gap_cnt(),
        .idle(obg_idle),.clk_sdr(clk_sdr),.rst_sdr_n(~rst_sdr),
        .px_req(),.px_addr(),.px_len(),.px_ack(1'b0),
        .px_done(1'b0),.px_data(arb_px_data),.px_valid(1'b0),
        .scan_state(image_raster),.cmd_valid(img_cmd[2]),.slot_free(img_free[2]),.next_bank(img_bank[2]),
        .cmd_addr(img_addr[42+:21]),.cmd_words(img_words[32+:16]),.cmd_ack(img_ack[2]),
        .wr_take(img_take[2]),.wr_active(img_active[2]),.wr_done(img_done[2]),
        .wr_error(img_err[2]),.wr_en(img_we[2]),.wr_good(img_good),.wr_addr(img_wr_addr)
    );
    layer_cover #(.MAX_W(320),.SHARED_RASTER(1),.SHARED_WRITER(1),.SCALE(1),.GEOMETRY_BITS(10)) u_old_cv (
        .clk_pix(clk_pix),.rst_pix_n(~rst_pix),.hs(cb_hs),.vs(cb_vs),.de(cb_de),
        .en(old_enable && ocv_en),.ch_key(ch_key),
        .win_x(ocv_pop_x),.win_y(ocv_pop_y),.win_w(ocv_pop_w),.win_h(ocv_pop_h),
        .img_w(ocv_iw),.img_h(ocv_ih),.words_per_row(ocv_wpr),.slot_base(ocv_slot),
        .dout(ocv_rgb),.dout_vld(ocv_vld),.underrun_cnt(),.stall_cnt(),.ferr_cnt(),.gap_cnt(),
        .keyed_cnt(),.idle(ocv_idle),.clk_sdr(clk_sdr),.rst_sdr_n(~rst_sdr),
        .px_req(),.px_addr(),.px_len(),.px_ack(1'b0),
        .px_done(1'b0),.px_data(arb_px_data),.px_valid(1'b0),
        .scan_state(image_raster),.cmd_valid(img_cmd[3]),.slot_free(img_free[3]),.next_bank(img_bank[3]),
        .cmd_addr(img_addr[63+:21]),.cmd_words(img_words[48+:16]),.cmd_ack(img_ack[3]),
        .wr_take(img_take[3]),.wr_active(img_active[3]),.wr_done(img_done[3]),
        .wr_error(img_err[3]),.wr_en(img_we[3]),.wr_good(img_good),.wr_addr(img_wr_addr)
    );

    localparam [23:0] base_rgb = 24'h0A140A; // ★ 底色常量（同上；与 PC golden 的 base 对齐）
    wire [23:0] cmp_rgb;
    wire [23:0] cmp_raw_rgb;
    wire        cmp_vld,cmp_vs,cmp_hs;
    wire [23:0] osd_rgb;
    wire osd_vld;
    wire osd_visible_clk, key_image_next, key_press_legacy;
    wire key_press = key_press_legacy; // Legacy integration TB observation.
    wire [2:0] osd_page_clk;
    wire [2:0] osd_selected_clk;
    wire [5:0] osd_sensitivity_clk;
    wire [8:0] osd_volume_clk, osd_sat_base_clk, osd_sat_max_clk;
    wire [8:0] osd_con_base_clk, osd_con_max_clk;
    wire sa_analysis_stb;
    wire [12:0] sa_flux, sa_threshold;
    wire [16:0] sa_scope_max;
    wire [15:0] sa_hit_count;
    // Shared Stage 4 loudness state is declared before the pixel color path
    // so the Verilog-2001 compiler sees the signal at its first use.
    reg [17:0] env_sum;
    reg [7:0]  env_loud_q8, env_rel_q8;
    reg [1:0] osd_visible_sync;
    reg [2:0] osd_page_s1, osd_page_s2;
    reg [2:0] osd_selected_s1, osd_selected_s2;
    reg [5:0] osd_sens_s1, osd_sens_s2;
    reg [8:0] osd_volume_s1, osd_volume_s2;
    reg [8:0] osd_sat_base_s1, osd_sat_base_s2, osd_sat_max_s1, osd_sat_max_s2;
    reg [8:0] osd_con_base_s1, osd_con_base_s2, osd_con_max_s1, osd_con_max_s2;
    always @(posedge clk_pix) begin
        if (rst_pix) begin
            osd_visible_sync<=2'b00;
            osd_page_s1<=0; osd_page_s2<=0;
            osd_selected_s1<=0; osd_selected_s2<=0;
            osd_sens_s1<=6'd16; osd_sens_s2<=6'd16;
            osd_volume_s1<=9'd100; osd_volume_s2<=9'd100;
            osd_sat_base_s1<=9'd60; osd_sat_base_s2<=9'd60;
            osd_sat_max_s1<=9'd200; osd_sat_max_s2<=9'd200;
            osd_con_base_s1<=9'd100; osd_con_base_s2<=9'd100;
            osd_con_max_s1<=9'd135; osd_con_max_s2<=9'd135;
        end else begin
            osd_visible_sync<={osd_visible_sync[0],osd_visible_clk};
            osd_page_s1<=osd_page_clk; osd_page_s2<=osd_page_s1;
            osd_selected_s1<=osd_selected_clk; osd_selected_s2<=osd_selected_s1;
            osd_sens_s1<=osd_sensitivity_clk; osd_sens_s2<=osd_sens_s1;
            osd_volume_s1<=osd_volume_clk; osd_volume_s2<=osd_volume_s1;
            osd_sat_base_s1<=osd_sat_base_clk; osd_sat_base_s2<=osd_sat_base_s1;
            osd_sat_max_s1<=osd_sat_max_clk; osd_sat_max_s2<=osd_sat_max_s1;
            osd_con_base_s1<=osd_con_base_clk; osd_con_base_s2<=osd_con_base_s1;
            osd_con_max_s1<=osd_con_max_clk; osd_con_max_s2<=osd_con_max_s1;
        end
    end
    wire [41:0] visual_colors_clk,visual_indices;
    wire [4:0] visual_effects_clk,effects;
    wire [1:0] transition_effect_clk,transition_speed_clk,active_transition_effect;
    wire [3:0] transition_settings;
    wire [23:0] color_spectrum,color_sung,color_other,color_title,color_singer,color_rings;
    wire [6:0] swatch_index;
    wire [23:0] swatch_rgb;
    generate if(VISUAL_CONTROLS) begin:g_visual_settings
        visual_settings #(.TRANSITIONS(1)) u_settings(.clk(clk),.rst_n(rst_n),
            .settings({visual_effects_clk,visual_colors_clk}),
            .transition_settings({transition_speed_clk,transition_effect_clk}),
            .transition(transition_settings),
            .clk_pix(clk_pix),.rst_pix(rst_pix),.frame_tick(fr_start),
            .swatch_index(swatch_index),.swatch_rgb(swatch_rgb),
            .spectrum(color_spectrum),.sung(color_sung),.other(color_other),
            .title(color_title),.singer(color_singer),.rings(color_rings),
            .effects(effects),.indices(visual_indices));
    end else begin:g_visual_defaults
        assign effects=5'b11111;assign visual_indices={6{7'd70}};
        assign transition_settings=4'b0100;
        assign color_spectrum=24'hD97A26;assign color_sung=24'hFFE8AA;
        assign color_other=24'hE8E4FF;assign color_title=24'hFFFFFF;
        assign color_singer=24'hBCC4D2;assign color_rings=24'h5EE8ED;
        assign swatch_rgb=24'd0;
    end endgenerate
    wire [8:0] gain_pct = osd_volume_s2;
    wire [12:0] gain_scaled = ({4'd0,gain_pct}<<5)+
                              ({4'd0,gain_pct}<<3)+{4'd0,gain_pct};
    wire [8:0] user_gain = en_osd ?
        ((gain_pct==9'd100) ? GAIN_DEFAULT : gain_scaled[12:4]) : GAIN_DEFAULT;

    //=========================================================================
    // ★★ P4 Stage 3：频谱链（`spec_fft` → `spec_bands` → `layer_fft`）
    //   · 全链在 **clk_pix（25MHz）像素域** ✓ ⇒ **无 CDC** ✓（节拍、样本、柱高、画柱同域 ✓）
    //   · layer_fft 在场消隐提交整组频带，逐行扫描；输出仍对应当前活动像素。
    //   · en_fft 默认 1；仿真可显式给 0，此时 ff_vld 恒 0。
    //   · ★ **不动 `px_arb3`** ✓：本链**不读 SDRAM** ⇒ 不加读客户端、不占仲裁带宽 ✓
    //=========================================================================
    // ★★★ 2026-10-10：**改成顶层参数**（原来是 `localparam` ✗）—— 同一个坑的第三次
    //   【为什么必须可配】仿真与出货需要**不同的值** ✗：
    //     · **仿真用 0** ✓ —— 集成台的 golden **不含频谱层** ✗（实测：置 1 时 `bad_frames=4`、
    //       坏点颜色 `00ffff` = 频谱柱色 vs 期望底色 `0a140a` ✗）
    //     · **出码流用 1** ✓ —— 用户 2026-10-10 决定"频谱常开" ✓
    //   【原来写死 `localparam` 的问题】每次出码流都要**改 RTL** ✗ ⇒ 容易忘了改回 ✗、
    //     也让"仿真过的"与"烧进去的"**不是同一份源码** ✗（本工程在 `ROT_TICK_DIV`、
    //     `dut_parameters` 上都吃过同类亏 ✓）
    //   ⇒ 现在：**台里显式给 0** ✓、**出码流时在构建脚本/TB 里给 1** ✓，RTL 一个字不动 ✓
    //   ★ 量面积/时序时**必须给 1** ✓ —— 因为给 0 时 TD 会做**常数传播** ⇒ 整条 P4 链
    //     （layer_fft→spec_bands→spec_fft）被优化掉 ✗ ⇒ 量出来是"没接"的设计 ✗
    //     （已实测：关着量 8,434 片 ✗、开着量 9,061 片 ✓，见工单 §11.14 ✓）
    //   ★★ 声明位置：**必须放在模块参数表里**（`skeleton_core #(...)` ✓）——
    //     写在模块**体里**的 parameter **不能被例化处覆盖** ✗
    //     （实测报错：`vsim-3584 Module parameter 'en_fft' not found for override` ✗）

    // ★★ Step 0（并发写探测）：`en_cwp` —— **只在探针构建里临时置 1** ✓
    //   【要回答的板上问题】装载器在**显示期间**写 SDRAM，会不会出彩色噪点？
    //     依据：`e37817c`（A1）原话 "there is no loader write during display traffic" ✓
    //           `08664a9` 噪点 = "real-silicon SDRAM read-to-write turnaround margin issue"、
    //             "dots appear **only while the loader runs**（concurrency is necessary）"
    //             —— ★ 而**它自己标注了"这是推断、不是证明"** ✗
    //   ⇒ 零延迟切歌**必然**"边显示边写" ⇒ 这一刀必须先挨 ✓
    //   ★ 仿真**抓不到**它（真硅 margin ✓ 文档原话）⇒ **只能上板** ✓
    //   【口径同 en_fft】默认 0 ✓；0 时整个探针被常数传播消掉 ⇒ **逐位不变** ✓
    //   【观测】`en_cwp=1` 时 `led[3]` 显示"探针正在写" ⇒ 板上**看得见探针在不在跑** ✓
    //     （★ 防假阴性：LED 不闪 ⇒ 探针没跑 ⇒ 本次板上结论**作废** ✓ 本工程吃过"判据空跑"的亏 ✓）
    localparam en_cwp = 1'b0;               // ★ 默认关；做 Step 0 探测时临时改 1 再出码流 ✓

    // ---- ★ 本链的**实例**放在**音频段之后** ✓（那里才能引用 `wav_tick`/`wp_l` ✓
    //        与文本链同一手法 ✓：`default_nettype none` 下**不能先用后声明** ✗ —— 已踩过一次 ✓）
    //      声明放这里 ⇒ 下面 `compositor` 例化处可以直接用 ✓
    wire [23:0] ff_rgb;
    wire        ff_vld;
    wire [3:0] spectrum_coverage;
    wire [23:0] scene_raw_rgb;

    wire [23:0] overlay_rgb;
    function [7:0] ring_channel;
        input [7:0] background, foreground, opacity;
        reg signed [8:0] delta;
        reg signed [18:0] result;
        begin
            delta=$signed({1'b0,foreground})-$signed({1'b0,background});
            result=$signed({3'b0,background,8'b0})+
                   delta*$signed({1'b0,opacity})+19'sd128;
            ring_channel=result[15:8];
        end
    endfunction
    function [23:0] ring_over;
        input [23:0] background, foreground;
        input [7:0] opacity;
        begin
            ring_over={ring_channel(background[23:16],foreground[23:16],opacity),
                       ring_channel(background[15:8],foreground[15:8],opacity),
                       ring_channel(background[7:0],foreground[7:0],opacity)};
        end
    endfunction
    wire [23:0] new_bg=bg_vld ? bg_rgb : base_rgb;
    wire [23:0] old_bg=obg_vld ? obg_rgb : base_rgb;
    reg [23:0] new_bg_d,old_bg_d,cv_rgb_d,ocv_rgb_d,overlay_rgb_d;
    reg cv_vld_d,ocv_vld_d,ring_vld_d,overlay_vld_d;
    reg overlay_text_d,overlay_text_d2;
    reg [7:0] ring_alpha_d;
    reg [8:0] fade_alpha_d;
    wire [8:0] transition_alpha;
    reg [9:0] ff_x, ff_y;
    scene_transition_mask u_transition_mask(.x(ff_x),.y(ff_y),
        .progress(fade_alpha),.effect(active_transition_effect),.alpha(transition_alpha));
    reg scene_de_d,scene_vs_d,scene_hs_d;
    always @(posedge clk_pix) begin
        if(rst_pix) begin
            new_bg_d<=0; old_bg_d<=0; cv_rgb_d<=0; ocv_rgb_d<=0;
            overlay_rgb_d<=0; cv_vld_d<=0; ocv_vld_d<=0;
            ring_vld_d<=0; overlay_vld_d<=0; ring_alpha_d<=0;
            overlay_text_d<=0; overlay_text_d2<=0;
            fade_alpha_d<=0; scene_de_d<=0; scene_vs_d<=0; scene_hs_d<=0;
        end else begin
            new_bg_d<=new_bg; old_bg_d<=old_bg;
            cv_rgb_d<=cv_rgb; ocv_rgb_d<=ocv_rgb;
            cv_vld_d<=cv_vld; ocv_vld_d<=ocv_vld;
            ring_vld_d<=ring_vld; ring_alpha_d<=ring_alpha;
            overlay_rgb_d<=overlay_rgb;
            overlay_text_d<=ly_vld;
            overlay_text_d2<=overlay_text_d;
            overlay_vld_d<=(TYPOGRAPHY ? 1'b0 : ly_vld) || (!CIRCULAR_UI && ff_vld);
            fade_alpha_d<=transition_alpha;
            scene_de_d<=cb_de; scene_vs_d<=cb_vs; scene_hs_d<=cb_hs;
        end
    end
    wire [23:0] new_image,old_image;
    wire [23:0] actual_ring_color=VISUAL_CONTROLS?color_rings:ring_rgb;
    wire [23:0] new_under=ring_vld_d?ring_over(new_bg_d,actual_ring_color,ring_alpha_d):new_bg_d;
    wire [23:0] old_under=ring_vld_d?ring_over(old_bg_d,actual_ring_color,ring_alpha_d):old_bg_d;
    generate if(VISUAL_CONTROLS) begin:g_cover_aa
        wire [3:0] coverage;
        cover_coverage #(.CENTER_X(UI_CENTER_X),.CENTER_Y(UI_CENTER_Y))
            u_coverage(.clk(clk_pix),.rst(rst_pix),.de(cb_de),
            .x(ff_x),.y(ff_y),.level(cover_pop_level),.alpha(coverage));
        alpha_blend16 #(.USE_DSP(1)) u_new(.background(new_under),.foreground(cv_rgb_d),
            .alpha(cv_vld_d?coverage:4'd0),.rgb(new_image));
        alpha_blend16 #(.USE_DSP(1)) u_old(.background(old_under),.foreground(ocv_rgb_d),
            .alpha(ocv_vld_d?coverage:4'd0),.rgb(old_image));
    end else begin:g_cover_binary
        assign new_image=cv_vld_d?cv_rgb_d:new_under;
        assign old_image=ocv_vld_d?ocv_rgb_d:old_under;
    end endgenerate
    compositor u_cmp (
        .de (cb_de), .base_rgb (base_rgb),
        .bg_rgb (24'd0), .bg_vld (1'b0),
        .cv_rgb (24'd0), .cv_vld (1'b0),
        // ★★ p3-lean 步2b：五层（歌词 > 歌名 > 封面 > 背景 > 底色）
        //   `tt_*`（歌名/歌手层）本轮**接常数 0** ⇒ 并层在步 3 落地（先占位是为了不重复改这个文件与 TB ✓）
        //   `ly_*` 由 §2b 的 `u_lyr` 驱动；**无数据时 `ly_vld` 恒 0 ⇒ 画面逐字节不变** ✓
        .ly_rgb (ly_rgb), .ly_vld (TYPOGRAPHY ? 1'b0 : ly_vld),
        // ★★ L1M 并层**已落地**：文本链的输出（歌词 + 歌名/歌手，按扫描行分时 ✓）
        //   **同时**接 `ly` 与 `tt` —— 两带与歌词窗口在扫描行上不重叠 ✓ ⇒ 层序谁高谁低无影响 ✓
        //   （`vld=0` 处透明 ✓；`en_ttl` 在没字库/没表时整带关闭 ⇒ 无数据时画面**逐字节不变** ✓）
        .tt_rgb (ly_rgb),  .tt_vld (TYPOGRAPHY ? 1'b0 : ly_vld),
        // ★★ P4 Stage 3：频谱柱层插在**歌名之下、封面之上**（design :92 的层序 ✓）
        //   本步**真的接上**了（`en_fft=0` 时 `ff_vld` 恒 0 ⇒ 那一级被短路 ⇒ 画面仍**逐位不变** ✓）
        .ff_rgb (ff_rgb), .ff_vld (!CIRCULAR_UI && ff_vld),
        .rgb (overlay_rgb), .rgb_vld ()
    );
    scene_blend u_blend (
        .clk(clk_pix),.rst(rst_pix),.de(scene_de_d),.vs(scene_vs_d),.hs(scene_hs_d),
        .old_rgb(old_image),.new_rgb(new_image),.alpha(fade_alpha_d),
        .overlay_rgb(overlay_rgb_d),.overlay_valid(overlay_vld_d),
        .rgb(scene_raw_rgb),.out_de(cmp_vld),.out_vs(cmp_vs),.out_hs(cmp_hs)
    );

    // Capsules and scene_raw_rgb both represent the raster delayed three clocks.
    // Separate AA from color processing for timing. Typography sidebands below
    // receive the same one-clock delay. Split UI maps blue to the spare DSP;
    // other channels retain exact shift/add arithmetic. No SDRAM requests.
    generate if(CIRCULAR_UI)begin:g_spectrum_aa
        wire [23:0] mixed_rgb;
        alpha_blend16 #(.USE_DSP(SPLIT_UI),.DSP_CHANNELS(1)) u_blend(.background(scene_raw_rgb),
            .foreground(ff_rgb),.alpha(spectrum_coverage),.rgb(mixed_rgb));
        if(TYPOGRAPHY)begin:g_pipeline
            reg [23:0] mixed_q;
            always @(posedge clk_pix)begin
                if(rst_pix)mixed_q<=0;else mixed_q<=mixed_rgb;
            end
            assign cmp_raw_rgb=mixed_q;
        end else assign cmp_raw_rgb=mixed_rgb;
    end else begin:g_spectrum_opaque
        assign spectrum_coverage=4'd0;
        assign cmp_raw_rgb=scene_raw_rgb;
    end endgenerate

    // Stage 4: color response follows the shared audio envelope. The text
    // overlay is selected after this transform, matching the HTML model.
    function [7:0] color_clip;
        input signed [19:0] value;
        begin
            if (value < 0) color_clip=8'd0;
            else if (value > 20'sd255) color_clip=8'd255;
            else color_clip=value[7:0];
        end
    endfunction
    // 55*r + 183*g + 18*b = 256*g + 55*(r-g) + 18*(b-g).
    // Signed floor shifting preserves every original Q8 luma value.
    function [7:0] color_luma;
        input [23:0] src;
        reg signed [8:0] red_delta,blue_delta;
        reg signed [15:0] red_wide,blue_wide,weighted;
        begin
            red_delta=$signed({1'b0,src[23:16]})-$signed({1'b0,src[15:8]});
            blue_delta=$signed({1'b0,src[7:0]})-$signed({1'b0,src[15:8]});
            red_wide={{7{red_delta[8]}},red_delta};
            blue_wide={{7{blue_delta[8]}},blue_delta};
            weighted=(red_wide<<<6)-(red_wide<<<3)-red_wide+
                     (blue_wide<<<4)+(blue_wide<<<1);
            color_luma=src[15:8]+(weighted>>>8);
        end
    endfunction
    function [23:0] color_link_gains;
        input [23:0] src;
        input [9:0] sat_gain, con_gain;
        // Exact algebra: d*256+d*(gain-256) = d*gain, including
        // the original 20-bit wrap before contrast clipping. Saturation
        // output is -1019..1274 for every 10-bit gain; signed 12 bits suffice.
        reg [7:0] r,g,b,lum;
        reg signed [10:0] sat_factor,con_factor;
        reg signed [8:0] dr,dg,db;
        reg signed [19:0] sr,sg,sb;
        reg signed [11:0] sat_r,sat_g,sat_b;
        reg signed [11:0] lr,lg,lb;
        reg signed [19:0] cr,cg,cb;
        begin
            r=src[23:16]; g=src[15:8]; b=src[7:0];
            // Canvas saturate()/contrast() uses the CSS filter luma matrix
            // 0.213/0.715/0.072. 55/183/18 is its Q8 shift/add form.
            lum=color_luma(src);
            sat_factor=$signed({1'b0,sat_gain});
            con_factor=$signed({1'b0,con_gain});
            dr=$signed({1'b0,r})-$signed({1'b0,lum});
            dg=$signed({1'b0,g})-$signed({1'b0,lum});
            db=$signed({1'b0,b})-$signed({1'b0,lum});
            sr=dr*sat_factor;
            sg=dg*sat_factor;
            sb=db*sat_factor;
            sat_r=$signed({1'b0,lum})+((sr+20'sd128)>>>8);
            sat_g=$signed({1'b0,lum})+((sg+20'sd128)>>>8);
            sat_b=$signed({1'b0,lum})+((sb+20'sd128)>>>8);
            lr=sat_r-20'sd128; lg=sat_g-20'sd128; lb=sat_b-20'sd128;
            cr=lr*con_factor;
            cg=lg*con_factor;
            cb=lb*con_factor;
            color_link_gains={color_clip(20'sd128+((cr+20'sd128)>>>8)),
                        color_clip(20'sd128+((cg+20'sd128)>>>8)),
                        color_clip(20'sd128+((cb+20'sd128)>>>8))};
        end
    endfunction
    // Retain the previous default mapping for the existing color regression.
    function [23:0] color_link;
        input [23:0] src;
        input [7:0] rel;
        reg [9:0] sat_default, con_default;
        begin
            sat_default=10'd256+((rel>>1)+(rel>>2)+(rel>>5)+(rel>>6));
            con_default=10'd256+((rel>>2)+(rel>>4)+(rel>>5));
            color_link=color_link_gains(src,sat_default,con_default);
        end
    endfunction
    wire [7:0] color_rel = (en_fft && effects[4]) ? env_rel_q8 : 8'd0;
    wire [8:0] sat_range_pct=osd_sat_max_s2-osd_sat_base_s2;
    wire [8:0] con_range_pct=osd_con_max_s2-osd_con_base_s2;
    wire [16:0] sat_rel_product=sat_range_pct*color_rel;
    wire [16:0] con_rel_product=con_range_pct*color_rel;
    wire [8:0] sat_pct_next=osd_sat_base_s2+((sat_rel_product+17'd128)>>8);
    wire [8:0] con_pct_next=osd_con_base_s2+((con_rel_product+17'd128)>>8);
    reg [8:0] sat_current_pct, con_current_pct;
    reg [9:0] sat_gain_cfg, con_gain_cfg;
    wire [13:0] sat_gain_next=({5'd0,sat_pct_next}<<5)+
        ({5'd0,sat_pct_next}<<3)+{5'd0,sat_pct_next};
    wire [13:0] con_gain_next=({5'd0,con_pct_next}<<5)+
        ({5'd0,con_pct_next}<<3)+{5'd0,con_pct_next};
    always @(posedge clk_pix) begin
        if (rst_pix) begin
            sat_current_pct<=9'd100; con_current_pct<=9'd100;
            sat_gain_cfg<=10'd256; con_gain_cfg<=10'd256;
        end else if (sa_analysis_stb) begin
            sat_current_pct<=sat_pct_next; con_current_pct<=con_pct_next;
            sat_gain_cfg<=en_fft ? sat_gain_next[13:4] : 10'd256;
            con_gain_cfg<=en_fft ? con_gain_next[13:4] : 10'd256;
        end
    end
    wire [23:0] colorized_rgb = en_osd ?
        color_link_gains(cmp_raw_rgb,sat_gain_cfg,con_gain_cfg) :
        color_link(cmp_raw_rgb,color_rel);
    wire [3:0] text_alpha;
    wire final_vld,final_vs,output_overlay_vld;
    wire ax_user,ax_valid,ax_last;
    reg ax_last_fix;
    wire [23:0] output_overlay_rgb;
    wire raw_output_overlay_vld,ax_last_use;
    wire [23:0] raw_output_overlay_rgb;
    generate if(TYPOGRAPHY) begin : g_text_composition
        reg [23:0] rgb1,rgb2,rgb3,rgb4,rgb5,color_q,overlay_q;
        reg [23:0] overlay_extra;
        reg de_extra,vs_extra,overlay_vld_extra,last_extra;
        reg [3:0] a1,a2,a3,a4,a5;
        reg de_q,vs_q,overlay_vld_q,last_q;
        always @(posedge clk_pix) begin
            if(rst_pix) begin
                rgb1<=0; rgb2<=0; rgb3<=0; rgb4<=0; rgb5<=0;
                overlay_extra<=0;de_extra<=0;vs_extra<=0;overlay_vld_extra<=0;last_extra<=0;
                a1<=0; a2<=0; a3<=0; a4<=0; a5<=0;
                color_q<=0; overlay_q<=0; overlay_vld_q<=0;
                de_q<=0; vs_q<=0; last_q<=0;
            end
            else begin rgb1<=ly_rgb; rgb2<=rgb1; rgb3<=rgb2;
                rgb4<=rgb3; rgb5<=rgb4; a1<=text_alpha; a2<=a1; a3<=a2; a4<=a3; a5<=a4;
                de_extra<=cmp_vld;vs_extra<=cmp_vs;
                overlay_extra<=raw_output_overlay_rgb;
                overlay_vld_extra<=raw_output_overlay_vld;last_extra<=ax_last_fix;
                // Separate saturation/contrast from the exact /15 text blend.
                // Delay every sideband and the final OSD/diagnostic override
                // by the same clock, preserving the visible pixel coordinates.
                color_q<=colorized_rgb; de_q<=CIRCULAR_UI?de_extra:cmp_vld;
                vs_q<=CIRCULAR_UI?vs_extra:cmp_vs;
                overlay_q<=CIRCULAR_UI?overlay_extra:raw_output_overlay_rgb;
                overlay_vld_q<=CIRCULAR_UI?overlay_vld_extra:raw_output_overlay_vld;
                last_q<=CIRCULAR_UI?last_extra:ax_last_fix;
            end
        end
        alpha_blend16 #(.USE_DSP(1)) u_text_blend(.background(color_q),.foreground(CIRCULAR_UI?rgb5:rgb4),
            .alpha(CIRCULAR_UI?a5:a4),.rgb(cmp_rgb));
        assign final_vld=de_q;
        assign final_vs=vs_q;
        assign output_overlay_rgb=overlay_q;
        assign output_overlay_vld=overlay_vld_q;
        assign ax_last_use=ax_last | last_q;
    end else begin : g_legacy_composition
        assign cmp_rgb=overlay_text_d2 ? cmp_raw_rgb : colorized_rgb;
        assign final_vld=cmp_vld;
        assign final_vs=cmp_vs;
        assign output_overlay_rgb=raw_output_overlay_rgb;
        assign output_overlay_vld=raw_output_overlay_vld;
        assign ax_last_use=ax_last | ax_last_fix;
    end endgenerate
    reg [9:0] de_pix;

    // ★ 2026-10-02：`ch_key` / `base_rgb` 已改成 **localparam 常量**（原先 reg + initial ⇒
    //   TD 警告 "Initial value omitted on non-DFF net" ⇒ **硬件里根本没有初值** ✗）。
    //   至此本模块**不再有任何 initial 块** —— 所有状态一律由复位给出。

    assign obs_de  = final_vld;
    // The observation port uses the same final pixel as the HDMI stream.

    // ★★★ 临时调试开关（2026-10-01）—— **本轮已还原为 0**（诊断结论：纯色帧均匀无网格 ⇒ 帧数据侧问题）
    localparam FORCE_SOLID = 1'b0;
    // Temporary board diagnostic: upper bar is loudness, lower bar is the
    // actual filter coefficient. The display core uses this pixel stream.
    wire diag_x = (de_pix >= 10'd512 && de_pix < 10'd624);
    wire [6:0] diag_pos = de_pix[6:0];
    wire diag_loud = diag_x && ff_y >= 10'd60 && ff_y < 10'd66;
    wire diag_rel = diag_x && ff_y >= 10'd70 && ff_y < 10'd76;
    wire [23:0] diag_rgb = diag_loud ?
        ((diag_pos < env_loud_q8[7:1]) ? 24'hD8F36A : 24'h172028) :
        ((diag_pos < color_rel[7:1]) ? 24'h2CE6DF : 24'h172028);
    assign raw_output_overlay_vld=osd_vld || (en_color_diag && (diag_loud || diag_rel));
    assign raw_output_overlay_rgb=osd_vld ? osd_rgb : diag_rgb;
    wire [23:0] ax_rgb = FORCE_SOLID ? 24'h2050A0 :
        (output_overlay_vld ? output_overlay_rgb : cmp_rgb);
    assign obs_rgb = ax_rgb;
    wire [23:0] ax_data;

    video_rgb_to_axis_640x480 u_ax (
        .I_clk   (clk_pix),
        .I_rst   (rst_pix),
        .I_vs    (final_vs),
        .I_de    (final_vld),
        .I_rgb   (ax_rgb),
        .O_video_user  (ax_user),
        .O_video_valid (ax_valid),
        .O_video_last  (ax_last),
        .O_video_data  (ax_data)
    );

    // ★★ 厂商 video_rgb_to_axis_640x480.v 的 `O_video_last` **永远不拉高**（本轮仿真实证：480 行里 0 个）。
    //   原因（off-by-one）：S_x_cnt 在"首个 DE 拍"被清零、之后才 +1 ⇒ 一个 640 像素的行里
    //   它只被比较到 638，永远等不到 `S_x_cnt == 639` 那一拍。
    //   ⇒ 不为此改厂商原件（保持可追溯），改在**本模块自己重建 last**：
    //      de_pix 在空档清零，DE 首个像素时 pre 值=0，第 640 个像素时 pre 值=639
    //      ⇒ 那时置位，正好落在"最后一个有效拍"（valid 是 de 打一拍）上。
    always @(posedge clk_pix) begin
        if (rst_pix) begin
            de_pix      <= 10'd0;
            ax_last_fix <= 1'b0;
        end else if (!cmp_vld) begin
            de_pix      <= 10'd0;
            ax_last_fix <= 1'b0;
        end else begin
            de_pix      <= de_pix + 10'd1;
            ax_last_fix <= (de_pix == 10'd639);      // ★ 与 valid 对齐的最后一拍
        end
    end

    // EDID 读触发：复位后等一会儿给一个脉冲（照 L 工程 top 的做法；不需要音频协商也能出图）
    reg [15:0] edid_cnt = 16'd0;
    reg        edid_trig = 1'b0;
    always @(posedge clk_pix) begin
        if (rst_pix) begin
            edid_cnt  <= 16'd0;
            edid_trig <= 1'b0;
        end else if (edid_cnt != 16'hFFFF) begin
            edid_cnt  <= edid_cnt + 16'd1;
            edid_trig <= (edid_cnt == 16'd2000);
        end else begin
            edid_trig <= 1'b0;
        end
    end

    //=========================================================================
    // 1b) ★★ 音频（P2 / S1 + S2）：48kHz 音源 + ACR ⇒ 厂商 HDMI 核的**音频口** ✓
    //
    //   S1（已在板上收口 ✓）：48kHz 测试音 + ACR ⇒ 判掉 V4 风险 ✓
    //   S2（本轮 ✓）：音源换成**卡里的 WAV**（BRAM 环 + 最小解析 ✓），测试音**保留** ✓
    //     作为"链路自检音源" ✓ —— 将来一旦无声 ✗，切回它就能一刀分清
    //     "是通路坏了"还是"素材/解析坏了" ✓（`audio_mux` 就是干这个的 ✓）。
    //
    //   ★ 本段只放"**音源侧**"：测试音 + ACR ✓；WAV 那一整套（解析/环/选择器/Fsm）
    //     放在 **§3.7** ✓ —— 因为它要用 `lf_st`（"开机装载已完成"）当起始门 ✓，
    //     而 `lf_st` 在**装载 FSM**那里才声明 ✓（Verilog 必须先声明后用 ✗）。
    //   ★ 两段之间的**跨段信号**（`aud_out_*` / `aud_tone_ready`）在本段先声明 ✓，
    //     再由 §3.7 的 `audio_mux` 驱动 ✓。
    //
    //   ★ 16bit → 24bit **左对齐**（`{sample, 8'h00}`）✓：核的音频口是 24bit ✓，
    //     16bit 源左对齐即 ×256 ✓，低 8 位恒 0 ⇒ 精度不丢、电平正确 ✓
    //   ★ `enable` 恒 1 ✓（测试音**一直在跑** ✓ ⇒ 报文里的 `AUD N=` 始终是"时基自检" ✓，
    //     这也是 S1 板上那条 `AUD N=48000` 判据的延续 ✓）
    //=========================================================================
    wire               tone_valid;           // ← 测试音（S1 ✓）
    wire signed [15:0] tone_l, tone_r;
    wire [4:0]         aud_rom_idx;
    wire [31:0]        aud_tick_cnt, aud_drop_cnt;
    wire               aud_acr_valid;
    wire [19:0]        aud_acr_cts, aud_acr_n;
    wire [31:0]        aud_acr_cnt;
    // ↓ 这两个由 §3.7 的 `audio_mux` 驱动（本段只是"先声明" ✓）
    wire               aud_out_valid;
    wire signed [15:0] aud_out_l, aud_out_r;
    wire               aud_tone_ready;       // → `pcm_test_tone.sample_ready` ✓（未选中 ⇒ 0 ✓）

    pcm_test_tone #(
        .CLK_HZ    (25000000),               // = clk_pix ✓（音频链唯一时基 ✓）
        .SAMPLE_HZ (48000)
    ) u_tone (
        .clk          (clk_pix),
        .rst_n        (~rst_pix),            // 像素域复位是**高有效** ⇒ 取反 ✓
        .enable       (1'b1),
        .sample_valid (tone_valid),
        .sample_ready (aud_tone_ready),      // ★ S2：不再恒 1 —— 未选中时给 0 ✓（mux 的说法 ✓）
        .sample_left  (tone_l),
        .sample_right (tone_r),
        .rom_index    (aud_rom_idx),
        .tick_count   (aud_tick_cnt),
        .drop_count   (aud_drop_cnt)
    );

    hdmi_audio_acr_gen #(
        .ACR_PERIOD_CYC (15'd25000),         // 1ms @25MHz ✓
        .ACR_N          (20'd6144),
        .ACR_CTS        (20'd25000)          // = f_pixel/1000 ✓（25.000MHz ✓）
    ) u_acr_gen (
        .clk       (clk_pix),
        .rst_n     (~rst_pix),
        .enable    (1'b1),
        .acr_valid (aud_acr_valid),
        .acr_cts   (aud_acr_cts),
        .acr_n     (aud_acr_n),
        .acr_count (aud_acr_cnt)
    );
    // 注：`aud_rom_idx/aud_tick_cnt/aud_drop_cnt/aud_acr_cnt` 只作观测 ✓
    //     ★★ 2026-10-04 起 **`aud_tick_cnt` 与 `aud_acr_cnt` 不再是"只作观测"** ✓ ——
    //        它们（clk_pix 域的**累计值**）随 §3.7 的握手搬进报文 ✓，用来替代
    //        原来"在 clk 域数 40ns 脉冲边沿"的口径 ✗（板上实测会恒 0 ✗，见 §4 之前的说明 ✓）

    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE            ("EG"),
        .HTOTAL            (800),
        .HSA               (96),
        .HFP               (16),
        .HBP               (48),
        .HACTIVE           (640),
        .VTOTAL            (525),
        .VSA               (2),
        .VFP               (10),
        .VBP               (33),
        .VACTIVE           (480),
        .VIDEO_TPG         ("Disable"),
        .VIDEO_FORMAT      ("RGB"),
        .VIDEO_VIC         (1),
        .AUDIO_SAMPLE_RATE ("48K"),
        .IIC_SCL_DIV       (250)
    ) u_hdmi (
        .I_pixel_clk        (clk_pix),
        .I_rst              (rst_pix),
        .I_edid_read_trig   (edid_trig),
        .I_axis_s_user      (ax_user),
        .I_axis_s_valid     (ax_valid),
        .I_axis_s_last      (ax_last_use),
        .I_axis_s_data      (ax_data),
        .I_audio_valid      (aud_out_valid),       // ★ S2：来自 `audio_mux`（测试音 ↔ WAV ✓）
        .I_audio_left_data  ({aud_out_l, 8'h00}),  // ★ 16bit → 24bit **左对齐** ✓（×256 ✓）
        .I_audio_right_data ({aud_out_r, 8'h00}),
        .I_acr_valid        (aud_acr_valid),
        .I_acr_cts          (aud_acr_cts),
        .I_acr_n            (aud_acr_n),
        .O_video_locked     (O_video_locked),
        .O_ddc_scl          (O_ddc_scl),
        .IO_ddc_sda         (IO_ddc_sda),
        .O_ch0_tmds_data    (O_ch0_tmds_data),
        .O_ch1_tmds_data    (O_ch1_tmds_data),
        .O_ch2_tmds_data    (O_ch2_tmds_data),
        .O_clk_tmds_data    (O_clk_tmds_data)
        // 未接：O_edid_read_valid / O_edid_read_data / O_axis_s_ready（不做反压，同 L 工程）
        // ★ Verilog 里**不要**写 (open) 或 ()：`default_nettype none` 下会报
        //   vlog-2892 "Net type of 'open' must be explicitly declared"（本轮踩过）。不接就整行不写。
    );

    assign obs_axis_data  = ax_data[7:0];
    assign obs_axis_valid = ax_valid;
    assign obs_axis_user  = ax_user;
    assign obs_axis_last  = ax_last_use;

    //=========================================================================
    // 2) SDRAM：sdram_top（物理层封装）+ sdram_arb
    //=========================================================================
    wire        sdr_init_done, sdr_ref_vld, sdr_busy, sdr_rd_en;
    wire [31:0] sdr_rd_dout;
    // ★★★ 2026-10-03（我方新增 ✓）：DRAM 命令引脚监视（由 `sdram_top` 引出 ✓）
    //   用途：**无歧义**地计数真正的 REFRESH 命令 ✓ —— 不依赖厂商信号语义 ✗
    //   （厂商 `Sdr_init_ref_vld` / `Sdr_busy` 的语义，我们文档里就写着"自相矛盾，实测为准" ✗）
    //   译码：REFRESH = RAS_n=0 & CAS_n=0 & WE_n=1 ✓（NOP=111 / ACT=011 / READ=101 / WR=100 / PRE=010 ✓）
    wire        sdr_ras_mon, sdr_cas_mon, sdr_we_mon;
    wire        sdr_ref_cmd = ~sdr_ras_mon & ~sdr_cas_mon & sdr_we_mon;
    wire        app_rd_en, app_wr_en;
    wire [20:0] app_rd_addr, app_wr_addr;
    wire [3:0]  app_wr_dm;
    wire [31:0] app_wr_din;

    sdram_top u_phy (
        .Clk(clk_sdr), .Clk_sft(clk_sdr_sft), .Rst(rst_sdr),
        .Sdr_init_done(sdr_init_done), .Sdr_init_ref_vld(sdr_ref_vld), .Sdr_busy(sdr_busy),
        .App_wr_en(app_wr_en), .App_wr_addr(app_wr_addr), .App_wr_dm(app_wr_dm), .App_wr_din(app_wr_din),
        .App_rd_en(app_rd_en), .App_rd_addr(app_rd_addr),
        .Sdr_rd_en(sdr_rd_en), .Sdr_rd_dout(sdr_rd_dout),
        // ★★★ 2026-10-03（我方新增 ✓）：命令引脚监视输出 ⇒ 用于直接计数 REFRESH 命令 ✓
        .SDR_RAS_MON(sdr_ras_mon), .SDR_CAS_MON(sdr_cas_mon), .SDR_WE_MON(sdr_we_mon)
    );

    wire        px_ack, px_done, px_valid, ctl_ack, ctl_done, ctl_valid;
    wire        ld_take, ld_ack, ld_done, arb_busy;
    wire [3:0]  gnt;
    wire [31:0] px_data, ctl_data;
    wire        px_req, ld_req;
    wire [20:0] px_addr, ld_addr;
    wire [15:0] px_len, ld_len;
    wire [31:0] ld_data;

    sdram_arb u_arb (
        .clk(clk_sdr), .rst_n(~rst_sdr),
        .app_rd_en(app_rd_en), .app_rd_addr(app_rd_addr),
        .app_wr_en(app_wr_en), .app_wr_addr(app_wr_addr), .app_wr_dm(app_wr_dm), .app_wr_din(app_wr_din),
        .sdr_rd_en(sdr_rd_en), .sdr_rd_dout(sdr_rd_dout), .sdr_busy(sdr_busy),
        .sdr_init_done(sdr_init_done), .sdr_init_ref_vld(sdr_ref_vld),
        .px_req(arb_px_req), .px_addr(arb_px_addr), .px_len(arb_px_len),
        .px_ack(arb_px_ack), .px_done(arb_px_done),
        .px_data(arb_px_data), .px_valid(arb_px_valid),
        // ★★ p3-lean 步2b：`ctl` 口交给**唯一的**文本读客户 `lyric_pick`
        //   （P2 基线把 ctl 口空着 ⇒ 只有**一个**客户 ⇒ **不需要仲裁器** ✓
        //    这正是"删掉旧版 `ctl_read_arb`"的根据 ✓）
        //   它的读是每帧**一笔 136 字**、基址 `0x17F040` 是 4 字组首 ⇒ 满足读定律 ✓
        //   （见 `doc/evidence/p3_lean_px_floor.md`：长度 ≥4 且 4 字对齐 ✓）
        .ctl_req(lp_px_req), .ctl_addr(lp_px_addr), .ctl_len(lp_px_len),
        .ctl_ack(lp_px_ack), .ctl_done(lp_px_done), .ctl_data(lp_px_data), .ctl_valid(lp_px_valid),
        // ★ P1：ld 口交给装载器（`bmp_load` 在下面例化；见"装载 FSM"一节）
        .ld_req(ld_req), .ld_addr(ld_addr), .ld_len(ld_len), .ld_data(ld_data), .ld_rd(ld_take),
        .ld_ack(ld_ack), .ld_done(ld_done),
        .arb_busy(arb_busy), .gnt(gnt)
    );

    //=========================================================================
    // 3) SD 文件服务（50MHz 域，参数保持板上实测值）
    //=========================================================================
    wire        sd_busy, sd_ready, sd_fail;
    wire [7:0]  sd_err_code;
    wire [8:0]  sd_file_total;
    wire [3:0]  sd_dbg_state, sd_dbg_init_err;
    wire        sd_dbg_sdhc;

    // ★ P1 装载侧信号：必须**在 storage_top 例化之前**声明
    //   （否则例化里的 lo_*/file_* 会先被当隐式网、再遇 wire 声明 ⇒ vlog-2388 重复声明）
    wire        lo_open, lo_open_busy, lo_rd_valid, lo_rd_ready, lo_want, lo_rd_eof, lo_rd_err;
    wire [7:0]  lo_open_index, lo_rd_data, bm_err;
    // ★★ p3-lean 步2c：`lo`/`ld` 两口改成 **2:1 mux**（0 = `bmp_load`、1 = `font_load`）
    //   依据：`storage_top` 只有**一条** `lo` 流、`sdram_arb` 只有**一个** `ld` 口 ✗
    //   ⇒ 字库/歌词表的装载必须与图像装载**分时复用**这两条通路 ✓（同拍只有一个在跑 ✓）
    wire        bm_lo_open, bm_lo_rd_ready, bm_lo_want;
    wire [7:0]  bm_lo_open_index;
    wire ft_owner, ft_fok, ft_aok, ft_lok;
    wire ft_busy, ft_done;
    wire [7:0] ft_err;
    wire [31:0] ft_nbytes;
    wire ft_lo_open, ft_lo_rd_ready, ft_lo_want;
    wire [7:0] ft_lo_open_index;
    wire bm_fifo_flush, bm_fifo_we, ft_fifo_flush, ft_fifo_we;
    wire [7:0] bm_fifo_di, ft_fifo_di;
    wire shared_fifo_full, backend_done;
    wire bm_cfg, ft_cfg, bm_finish, ft_finish, bm_down, ft_down;
    wire [20:0] bm_first, ft_first;
    wire [18:0] bm_words, bm_end_words;
    wire [19:0] ft_words, ft_end_words;
    wire [15:0] bm_wpr, ft_wpr;
    wire task_start, task_raw, task_active, task_probe;
    wire [7:0] task_index;
    wire [20:0] task_base;
    wire [31:0] task_bytes;
    wire [19:0] task_capacity;
    wire [3:0] task_tag;
    reg [3:0] parser_tag;
    assign ft_owner = task_raw;
    always @(posedge clk) begin
        if (!rst_n) parser_tag <= 4'd0;
        else if (task_start) parser_tag <= task_tag;
    end
    // ★★ P2/S2：`hi` 通道（一直闲置 ✓）现在交给 **WAV 播放链** ✓
    //   ★ 这四个信号**必须在 `storage_top` 例化之前声明** ✗（`default_nettype none` 下
    //     例化里先出现的名字会当隐式网 ⇒ vlog-2892 ✓ 本文件里已踩过同类坑 ✓）；
    //     驱动它们的整套逻辑在 **§3.7**（用 `assign` ✓ ⇒ 声明与驱动可以分开 ✓）。
    wire        au_hi_open, au_hi_want, au_hi_refill, au_hi_rd_ready;
    wire [7:0]  au_hi_open_index;
    // ★★ P2/S2：`hi` 流**回来**的那几根也要 wire（原先是"不接"⇒ 现在要接给 WAV 链 ✓）
    wire        au_hi_open_busy, au_hi_rd_valid, au_hi_rd_eof, au_hi_rd_err;
    wire [7:0]  au_hi_rd_data;
    // ★★ P2/S2：文件表索引口（开机前给装载器 `lf_scan` ✓、开机后给音频链 `au_idx` ✓）
    //   ★ 必须在这里只**声明**、用 `assign` 在 §3.7 驱动 ✗ —— 若把带初始值的声明写进 §3.7，
    //     本行的 `.file_index(au_ft_index)` 会先把名字当隐式网 ⇒ vlog-2388 "already declared" ✗
    //     （本轮实测踩到 ✓）
    wire [7:0]  au_ft_index;
    wire [87:0] sd_file_name;
    wire [1:0]  sd_file_type;
    wire [31:0] sd_file_size;
    wire sd_font_valid, sd_asc_valid;
    wire [31:0] sd_font_size, sd_asc_size;
    // ★★★ 2026-10-10：**lo 会话锁存的文件大小** ✓ —— 装载器/字库装载器必须用它 ✓
    //   实测（`[FTO]` 诊断）：共用读口在**打开那一刻**给出的值是对的 ✓，
    //   但它**每拍都可能变** ✗ ⇒ `bmp_load` 持续读实时视图 ⇒ 装载途中拿到**封面**的大小 ✗
    wire [31:0] sd_lo_file_size;
    wire        bm_busy, bm_done;
    wire [15:0] bm_img_w, bm_img_h;
    wire [7:0] lf_scan = task_index;
    // ★★ P2/S3-c：**播放表**（`playlist.v` ✓）的信号 —— 同样**必须在例化之前声明** ✗
    //   （`default_nettype none` ⇒ 否则 vlog-2892/2388 ✓ 本文件已踩过同类坑 ✓）
    //   ★ 它跑在 `clk` 域 ✓ ⇒ 结果直接给报文用 ✓ **不需要任何 CDC** ✓
    wire        pl_start;                      // 脉冲：开始扫（`LF_NEXTG` → `LF_LIST` 时给 ✓）
    wire [7:0]  pl_index;                      // → 文件表索引口（与装载器/音频链**复用同一个口** ✓）
    wire        pl_done;                       // 脉冲：扫完 ✓
    wire        pl_busy;                       // 扫描中 ✓（观测用，不参与判决 ✓）
    wire [7:0]  pl_n, pl_cur, pl_err;          // 可播首数 / 当前首号 / 首条错误码 ✓（→ 报文 ✓）
    wire [7:0]  pl_wav_ft;                     // ★ 当前首的 WAV 下标 ✓（→ 音频链 ✓）
    wire [7:0]  pl_lrc_ft;
    wire        pl_lrc_vld;                    // ★ 2026-10-10：本首**有没有** LRC（与索引数值无关 ✓）
    wire        nx_vld;                        // ★★★ P5/A9：**有没有下一首**（独立一位 ✓）
    wire [7:0]  nx_bg1, nx_cv1;                // ★ 下一首的 BG1 / CV1 文件表索引 ✓（预装用 ✓）
    // ★★★ P5/A9 v3（2026-10-10 用户纠正 ✓）：**一套逻辑覆盖所有 N** ⇒ g2/g3 也要预装 ✓
    wire [7:0]  nx_bg2, nx_cv2;
    wire [7:0]  nx_bg3, nx_cv3;
    wire [7:0]  nx_wav_ft, nx_lrc_ft;
    wire        nx_lrc_vld;
    wire        pre_g1_ready, pre_g1_bg_ok, pre_g1_cv_ok;
    wire        pre_busy;                      // ★ 预装六笔未走完（用来**暂停轮播** ✓）
    wire [2:0]  pre_stv;                       // 观测：预装步骤号 ✓
    wire [7:0]  nx_song;                       // ★ 下一首的**首号**（切歌重扫用 ✓）
    // ★★★ P5/A9（2026-10-10）S2：**切歌的三根控制线**
    //   ★★ 声明必须**放在所有使用之前** ✗ —— 今天在这上面栽了三次 ✓
    //     （`grp_nxt` 用它 ✓、`preload.clr` 用它 ✓、播放表 `.scan_start` 用它 ✓
    //      三处都在**模块前半段** ⇒ 声明只能更早 ⇒ 就放在这里 ✓）
    reg [1:0] slot_rot;
    reg        sw_req;          // 1 = 本拍要切下一首 ✓
    reg        pre_sw_pending;
    reg  [1:0] cmt_ack_sync;
    reg  [1:0] cmt_song_ack_sync;
    reg        sw_start;        // 1 = 本拍要重扫播放表 ✓（与开机那次**相或** ✓）
    reg        sw_pend;         // ★★★ 挂起：等音频走到 `AU_STOP` 才让它回 `AU_IDLE` ✓
    reg  [7:0] sw_cnt;          // ★ 瘦身：16 → 8 位 ✓（8 位足够看风暴 ✓）          // ★ 切歌触发过几次（→ 报文 `A9=` 的**高字节** ✓）
    // ★★★ 2026-10-11 **切歌冷却** ✗→✓（防"切歌风暴" ✓）
    //   【为什么加】板上 `A9=` 读回 `sw_cnt` 低字节 = `0x90 = 144` ✗
    //     ★ 而报文只发**低 8 位** ✗ ⇒ 真值可能是 400+ ✓ ⇒ 高度怀疑**切歌风暴** ✓：
    //       切歌 ⇒ 音频重开 ⇒ `wp_end` 又立刻置起 ⇒ 又判"歌播完" ⇒ 再切 ⇒ ……
    //     ⇒ ★ 预装被反复触发 ✓、**SDRAM 带宽被占满** ⇒ **字幕取不出来** ✓✓
    //       （与现象完全吻合：声音/频谱正常 ✓ 而字幕不出 ✓）
    //   【做法】切歌后 **1 秒**内不再理会"歌尾" ✓（`CLK_HZ` 拍 = 1 秒 @50MHz ✓）
    //   ★ 为什么不误伤正常播放 ✗：一首歌是**分钟级** ✓ ⇒ 1 秒冷却永远碰不到真实的下一首歌尾 ✓
    
    // ★★★ P5/A9 **S2b**（2026-10-11）：切歌后**重载歌词表**的两个小状态 ✓
    //   `lrc_re` = 欠一次重载 ✓ ／ `lrc_rdy` = 正在装 ✓
    //   ★ 它们**必须由 LF FSM 那个 always 块驱动** ✗（`ft_*` 不能有两个驱动 ✓）
    wire lrc_rdy, lrc_prepared, lrc_slot;
    wire [7:0] lrc_prep_song;
    wire [3:0] lrc_n;           // ★ 瘦身：16 → 4 位 ✓（够数重载次数 ✓）           // 取证：切歌后重载过几次歌词表 ✓
    reg  [7:0] sw_from;         // 重扫时"从哪一首当当前首"（= `nx_song` ✓）
    wire [7:0]  pl_bg1, pl_bg2, pl_bg3, pl_cv1, pl_cv2, pl_cv3;
    wire [7:0]  pl_skip, pl_smax;              // 观测 ✓
    // ★★ 2026-10-02 修复 B17（用户指出：切组黑屏 + 残影）★★
    //   旧做法：key_press ⇒ bg_en/cv_en 置 0 + 全表重扫重装 ⇒ **黑屏是主动制造的**，
    //   并且熄层再开会吐出图层内的旧缓冲 ⇒ 残影。两者都与 design §1.5 的
    //   "实时合成 ⇒ 无切换黑屏"相矛盾。
    //   新做法：**组号直接决定槽基址**，新组装进"本组专属槽"，装载期间**旧组照常显示**；
    //   两组都装完后在 **vs 帧边界** 原子提交（槽基址 + 规格 + en），全程不熄灭。
    //   ⚠️ 槽表扩展：design §3.1 只定义了 A/B 两组（0x00000/0x38400 与 0x70800/0xA8C00）；
    //   为支持"三组都无黑屏"，第 3 组落在原"预留 ~700K 字"区内（占用 460,800 字 ≈1.84MB，
    //   SDRAM 总用量 5.03+1.84 = 6.87MB < 8MB ✓）。此扩展已记入 §9 B17。
    // ⚠️ "组号→槽基址"的两个 wire 放在 `grp` 声明之后（见下方 nm_* 附近）—— ModelSim 不允许在声明前引用
    // 影子参数（装载完成后写入，等 vs 边界才提交到"生效"参数）
    reg [15:0] bg_iw_nx, bg_ih_nx, bg_wpr_nx, bg_w_nx, bg_h_nx, bg_x_nx, bg_y_nx;
    reg [20:0] bg_slot_nx;  reg bg_ok_nx;
    reg [15:0] cv_iw_nx, cv_ih_nx, cv_wpr_nx, cv_w_nx, cv_h_nx, cv_x_nx, cv_y_nx;
    reg [20:0] cv_slot_nx;  reg cv_ok_nx;
    reg        cmt_tgl, cmt_sent;   // clk 域：一次性提交请求（翻转）+ 已发标志
    wire       cmt_ack_tgl;        // Upgrade: transition finished AND old reads drained.
    reg        cmt_ack_song_slot;
    reg  [1:0] cmt_song_slot_sync;
    wire pre_sw_fire = pre_sw_pending && cmt_sent &&
                       (cmt_ack_sync[1] == cmt_tgl) &&
                       (cmt_song_ack_sync[1] == lrc_slot);
    // ★★ A1（2026-10-03）：原 C 的 `ld_left_done`（"本轮必须装载过才允许提交"）**已删除** ✗ ——
    //   它经"结构证明 + 实测 A/B 逐字相同"双重证伪：`key_press` 强制 `lf_st <= LF_WAIT`
    //   ⇒ 该门在按键后第二拍就恒真 ⇒ 与改动前**完全等价**（空操作 ✗），
    //   见 doc/evidence/switch_dots_ab_20261003.md §3。A1 之后**按键根本不再装载** ✓ ⇒ 该门失去对象 ✓。
    reg  [2:0] cmt_sync;            // clk_pix 域：同步翻转位
    reg        cmt_pend;            // clk_pix 域：已收到请求、等 vs
    reg        vs_pix_d;            // vs 打一拍（用于找帧首下降沿）
    wire [3:0] lf_st;
    wire [1:0] lf_found;
    wire [3:0] physical_bg_valid, physical_cv_valid;
    wire [3:0] pinned_slots;
    reg shape_start, shape_pending, shadow_ready, view_requested;
    reg song_view_pending, song_slot_hold;
    reg [1:0] shape_pair, confirmed_pair, pending_pair;
    reg confirmed_valid;
    wire shape_done;
    wire [9:0] shape_bw, shape_cw;
    wire [8:0] shape_bh, shape_ch;
    // Successful normalized loads always have these exact target dimensions.
    // Keep the metadata handshake/commit timing, but avoid re-decoding fixed
    // geometry through SDRAM, CDC payloads and all four display pipelines.
    wire [15:0] display_bw=BMP_DOWNSCALE ? BMP_BG_W : {6'd0,shape_bw};
    wire [15:0] display_bh=BMP_DOWNSCALE ? BMP_BG_H : {7'd0,shape_bh};
    wire [15:0] display_cw=BMP_DOWNSCALE ? BMP_COVER_W : {6'd0,shape_cw};
    wire [15:0] display_ch=BMP_DOWNSCALE ? BMP_COVER_H : {7'd0,shape_ch};
    wire view_idle = shadow_ready && !shape_pending && !shape_start &&
                     cmt_sent && (cmt_ack_sync[1] == cmt_tgl);
    assign pinned_slots = (confirmed_valid ? (4'b0001 << confirmed_pair) : 4'd0) |
                          ((shape_pending || shadow_ready) ? (4'b0001 << shape_pair) : 4'd0);

    storage_top #(
        .CLK_HZ(CLK_HZ)
    ) u_sd (
        .clk(clk), .rst_n(rst_n),
        .start(1'b0),                       // AUTO_START=1，自己起
        .busy(sd_busy), .ready(sd_ready), .fail(sd_fail), .err_code(sd_err_code),
        // ★★ P2/S2：表索引口在**开机装载完成后**交给音频链（`au_ft_index` ✓）——
        //   装载 FSM 在 `LF_DONE` 之后**不再改** `lf_scan` ✓（A1：按键也不再重装 ✓）⇒ 不冲突 ✓
        .file_index(au_ft_index), .file_total(sd_file_total),
        .file_name(sd_file_name), .file_type(sd_file_type), .file_size(sd_file_size),
        .select_start(pl_start | sw_start), .select_from(sw_from),
        .select_busy(pl_busy), .select_done(pl_done),
        .song_total(pl_n), .song_cur(pl_cur), .pl_err(pl_err),
        .skip_cnt(pl_skip), .song_max(pl_smax),
        .wav_ft(pl_wav_ft),
        .bg_ft1(pl_bg1), .bg_ft2(pl_bg2), .bg_ft3(pl_bg3),
        .cv_ft1(pl_cv1), .cv_ft2(pl_cv2), .cv_ft3(pl_cv3),
        .lrc_ft(pl_lrc_ft), .lrc_vld(pl_lrc_vld),
        .nx_vld(nx_vld), .nx_song(nx_song),
        .nx_bg1(nx_bg1), .nx_bg2(nx_bg2), .nx_bg3(nx_bg3),
        .nx_cv1(nx_cv1), .nx_cv2(nx_cv2), .nx_cv3(nx_cv3),
        .nx_wav_ft(nx_wav_ft), .nx_lrc_ft(nx_lrc_ft),
        .nx_lrc_vld(nx_lrc_vld),
        .font_valid(sd_font_valid), .asc_valid(sd_asc_valid),
        .font_size(sd_font_size), .asc_size(sd_asc_size),
        // ★★★ 2026-10-10：装载器/字库装载器用 **lo 会话锁存的大小** ✓（不是会变的实时视图 ✗）
        .lo_file_size(sd_lo_file_size),
        .lo_open(lo_open), .lo_open_index(lo_open_index), .lo_rd_ready(lo_rd_ready), .lo_want(lo_want),
        .lo_open_busy(lo_open_busy), .lo_rd_valid(lo_rd_valid), .lo_rd_data(lo_rd_data),
        .lo_rd_eof(lo_rd_eof), .lo_rd_err(lo_rd_err),
        .hi_open(au_hi_open), .hi_open_index(au_hi_open_index),
        .hi_want(au_hi_want), .hi_refill(au_hi_refill), .hi_rd_ready(au_hi_rd_ready),
        .hi_open_busy(au_hi_open_busy), .hi_rd_valid(au_hi_rd_valid),
        .hi_rd_data(au_hi_rd_data), .hi_rd_eof(au_hi_rd_eof), .hi_rd_err(au_hi_rd_err),
        .sd_sck(sd_sck), .sd_cs_n(sd_cs_n), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .dbg_state(sd_dbg_state), .dbg_init_err(sd_dbg_init_err), .dbg_sdhc(sd_dbg_sdhc)
        // ★ P1：`lo` 流已接给下面的 `bmp_load`；文件表三件（name/type/size）也引出来了，
        //   由装载 FSM 按"type==BMP"取前两枚装进 BG/CV 槽（软硬件同一套代码：板上换成大素材即可）
    );

    //=========================================================================
    // 3.5) ★ P1 装载 FSM：文件表里按 `type==BMP` 取前两枚 → 槽 0 / 0x40000 → 居中窗口
    //      lo 流：storage_top ↔ bmp_load；ld：bmp_load ↔ sdram_arb
    //      `bmp_load` 的 ld 突发下限是 4 字（契约 7），装载器内部已保证 ⇒ 此处无需额外处理
    //=========================================================================
    // ★★ A1（2026-10-03）：状态机改成"**开机把三组都装完**"，因此多两个状态：
    //   · LF_NEXTG ：本组收尾（成功或失败）⇒ 决定"下一组"还是"进开机收口"
    //   · LF_BOOTD ：开机收口 —— 提交"**第一个有效组**"；此后 `LF_DONE` 常驻、**永不再装载** ✓
    localparam [3:0] LF_WAIT = 4'd0, LF_SCAN1 = 4'd1, LF_LOAD1 = 4'd2,
                     LF_SCAN2 = 4'd3, LF_LOAD2 = 4'd4, LF_NEXTG = 4'd5,
                     LF_BOOTD = 4'd6, LF_DONE = 4'd7,
                     // ★★ P2/S3-c：**播放表扫描** ✓（插在"三组装完"与"开机收口"之间 ✓）
                     //   ★ `LF_DONE` **仍是 4'd7** ✓ ⇒ 板上 `LF ST=7` 的稳态口径**不破** ✓
                     //     （新状态取 8 ✓，只在开机过渡期出现 ⇒ S2 的判据继续有效 ✓）
                     LF_LIST = 4'd8,
                     // ★★ p3-lean 步2c：字库/歌词表装载（`LF_DONE` 仍 = 4'd7 ✓ 稳态口径不破 ✓）
                     //   顺序：出图（`LF_BOOTD` 提交）→ 装字库 → 装本首 LRC → `LF_DONE`（音频起播门 ✓）
                     LF_FONT = 4'd9, LF_LRC = 4'd10;

    //=========================================================================
    // 3.5a) ★★ Step 0：并发写探测（`en_cwp`）—— 只在探针构建里打开 ✓
    //   复用**已有的** `u_load` ✓（同一条写通路/同一个 FIFO/同一个仲裁器 ⇒ 证的是真问题 ✓
    //     自己另造一个"写发生器"证不了它 ✗）
    //   目标槽 = 备用区 `0x1C0800`（未消费 ✓，将来正是 `BG_D` 的住处 ✓）⇒ 写它**不动任何显示数据** ✓
    //   索引 = 播放表的 `pl_bg1` ✓（真 BMP ⇒ 写字数与真装载同量级 ✓）
    //   owner mux：`cwp_active` 只在 `lf_st == LF_DONE` 之后才可能为 1 ✓，
    //     而 `LF_DONE` 是**终态**、开机装载器**永不再发起装载** ✓ ⇒ **天然互斥、不需要仲裁器** ✓
    //   `en_cwp=0` ⇒ `cwp_active` 恒 0 ⇒ 三项全走原路 ⇒ 逐位不变 ✓
    //=========================================================================
    wire        cwp_active;
    wire [20:0] cwp_slot;
    wire [7:0]  cwp_idx;
    wire        cwp_start;
    wire        cwp_phase;

    wire        cwp_res_vld;
    wire [7:0]  cwp_res_err;
    wire [31:0] cwp_res_cyc;
    wire [7:0]  cwp_res_n;

    // ★★ v2（2026-10-09 重写）：**单笔、有应答**的仪表 ✓
    //   v1 是周期发起且无应答 ⇒ 三种间隔都测不到目标（吞掉 / 滥用重开）✗ 见 `cw_probe.v` 头注释 ✓
    cw_probe #(.CLK_HZ (CLK_HZ), .N_LOAD (1), .TO_MS (300)) u_cwp (
        .clk        (clk), .rst_n (rst_n),
        .en         (en_cwp && (lf_st == LF_DONE)),
        .boot_done  (lf_st == LF_DONE),
        .file_index (pl_bg1),
        .busy       (task_active || pinned_slots[3]),
        .done       (bm_done && task_probe), .err (bm_err),
        .active     (cwp_active), .slot_base (cwp_slot), .ld_idx (cwp_idx),
        .ld_start   (cwp_start),  .phase (cwp_phase),
        .res_vld    (cwp_res_vld), .res_err (cwp_res_err),
        .res_cyc    (cwp_res_cyc), .res_n (cwp_res_n)
    );

    wire [7:0] pre_err, pre_n;
    wire pre_act = task_active && !task_raw && (lf_st == LF_DONE);
    wire lrc_rdy_int = task_active && task_raw && (lf_st == LF_DONE);
    assign lrc_rdy = lrc_rdy_int;
    asset_manager #(.TYPOGRAPHY(TYPOGRAPHY)) u_assets (
        .clk(clk), .rst_n(rst_n), .sd_ready(sd_ready),
        .pl_done(pl_done), .pl_busy(pl_busy), .song(pl_cur),
        .current_images({pl_cv3,pl_bg3,pl_cv2,pl_bg2,pl_cv1,pl_bg1}),
        .current_lrc_valid(pl_lrc_vld), .current_lrc(pl_lrc_ft),
        .next_valid(nx_vld), .next_song(nx_song),
        .next_images({nx_cv3,nx_bg3,nx_cv2,nx_bg2,nx_cv1,nx_bg1}),
        .next_lrc_valid(nx_lrc_vld), .next_lrc(nx_lrc_ft),
        .font_valid(sd_font_valid), .asc_valid(sd_asc_valid),
        .font_size(sd_font_size), .asc_size(sd_asc_size),
        .enable_preload(en_pre), .song_switch(sw_req), .old_released(pre_sw_fire),
        .rotation(slot_rot), .pinned(pinned_slots),
        .probe_start(cwp_start), .probe_index(cwp_idx),
        .select_start(pl_start), .boot_state(lf_st),
        .task_start(task_start), .task_raw(task_raw),
        .task_index(task_index), .task_base(task_base), .task_bytes(task_bytes),
        .task_capacity(task_capacity), .task_tag(task_tag), .active(task_active), .probe_active(task_probe),
        .task_done(task_raw ? ft_done : bm_done), .done_tag(parser_tag),
        .task_error(task_raw ? ft_err : bm_err), .image_w(bm_img_w), .image_h(bm_img_h),
        .bg_valid(physical_bg_valid), .cv_valid(physical_cv_valid),
        .shape_start(shape_start), .shape_pair(shape_pair), .shape_done(shape_done),
        .shape_bw(shape_bw), .shape_bh(shape_bh), .shape_cw(shape_cw), .shape_ch(shape_ch),
        .ahead_ready(pre_g1_ready), .ahead_bg_ok(pre_g1_bg_ok), .ahead_cv_ok(pre_g1_cv_ok),
        .pre_busy(pre_busy), .pre_step(pre_stv), .pre_count(pre_n), .pre_error(pre_err),
        .font_ok(ft_fok), .asc_ok(ft_aok), .lrc_ok(ft_lok),
        .lrc_slot(lrc_slot), .lrc_prepared(lrc_prepared),
        .lrc_song(lrc_prep_song), .lrc_count(lrc_n)
    );

    // ★ 探针活动计数 → 报文 `CWP N=` ✓（板上判"探针到底跑没跑" ✓ 防空跑 ✓）
    //   `en_cwp=0` 时 `cwp_start` 恒 0 ⇒ 常数传播把这个计数器整个消掉 ✓（面积不变 ✓）
    reg [15:0] cwp_cnt;
    always @(posedge clk) begin
        if (!rst_n)          cwp_cnt <= 16'd0;
        else if (cwp_start)  cwp_cnt <= cwp_cnt + 16'd1;
    end

    // ★★★ 2026-10-10：**看门狗门限的上下文切换** ✓（依据见端口参数 `LD_WD_MS_LOOSE` 的注释）
    //   `cwp_active=0`（开机装载：独占卡）⇒ 紧门限，保留原有保护 ✓
    //   `cwp_active=1`（并发预装：卡与音频共用）⇒ 松门限，避免误判 ✓
    // ★★★ 2026-10-10 补 ✗→✓：**预装（`pre_*`）也必须在松门限这一侧** ✗
    //   【板上失败的根因（很可能）】预装在**播放期**读卡 ✓（与音频共用卡 ✓）
    //     而条件里**只有 `cwp_active`** ✗ ⇒ 预装落进**紧门限 1ms** ✗
    //     ⇒ 字节间隔一超 ⇒ `bmp_load` 判 `0x04`（看门狗超时 ✓）⇒ **装载失败** ✗
    //     ⇒ 第 4 槽里没有下一首的 g1 ✗ ⇒ 边界切过去是旧数据／半张 ⇒ **花屏** ✓
    //   【证据】仿真端到端：`[PRE] pre_n=2 pre_stv=2 **pre_err=04**` ✗
    //     （预装确实跑起来了 ✓ 但**报看门狗超时** ✗ —— 与板上症状一致 ✓）
    //   ⇒ 条件是"**任何播放期的装载**" ✓：`cwp_active | pre_act | pre_busy` ✓
    wire ld_wd_loose = cwp_active | pre_act | pre_busy;
    wire [31:0] ld_wd_max = ld_wd_loose ? ((CLK_HZ / 1000) * LD_WD_MS_LOOSE)
                                        : ((CLK_HZ / 1000) * LD_WD_MS);

    load_writeback u_writeback (
        .clk(clk), .rst_n(rst_n), .clk_sdr(clk_sdr), .rst_sdr_n(~rst_sdr),
        .flush(task_raw ? ft_fifo_flush : bm_fifo_flush),
        .byte_we(task_raw ? ft_fifo_we : bm_fifo_we),
        .byte_data(task_raw ? ft_fifo_di : bm_fifo_di), .full(shared_fifo_full),
        .cfg_valid(task_raw ? ft_cfg : bm_cfg), .cfg_first(task_raw ? ft_first : bm_first),
        .cfg_words(task_raw ? ft_words : {1'b0,bm_words}), .cfg_wpr(bm_wpr),
        .cfg_rows(!task_raw), .cfg_down(bm_down),
        .finish_valid(task_raw ? ft_finish : bm_finish),
        .finish_words(task_raw ? ft_end_words : {1'b0,bm_end_words}), .done(backend_done),
        .ld_req(ld_req), .ld_addr(ld_addr), .ld_len(ld_len), .ld_data(ld_data),
        .ld_take(ld_take), .ld_ack(ld_ack), .ld_done(ld_done)
    );

    bmp_load #(.MAX_W(640), .MAX_H(480), .CLK_HZ(CLK_HZ),
               .WD_MS(LD_WD_MS), .EXTERNAL_BACKEND(1),
               .DOWNSCALE(BMP_DOWNSCALE),.BG_W(BMP_BG_W),.BG_H(BMP_BG_H),
               .COVER_W(BMP_COVER_W),.COVER_H(BMP_COVER_H),
               .STREAM_WD_MS(LD_WD_MS_LOOSE)) u_load (
        .clk (clk), .rst_n (rst_n), .start (task_start && !task_raw), .file_index (task_index),
        .target_cover(task_index[2:0] >= 3'd3 && task_index[2:0] <= 3'd5),
        .slot_base (task_base), .busy (bm_busy), .done (bm_done), .err (bm_err),
        .wd_max (ld_wd_max),
        .img_w (bm_img_w), .img_h (bm_img_h),
        .lo_open (bm_lo_open), .lo_open_index (bm_lo_open_index), .lo_open_busy (lo_open_busy),
        .lo_rd_valid (lo_rd_valid), .lo_rd_data (lo_rd_data),
        .lo_rd_ready (bm_lo_rd_ready), .lo_want (bm_lo_want),
        .lo_rd_eof (lo_rd_eof), .lo_rd_err (lo_rd_err), .file_size (sd_lo_file_size),
        .clk_sdr (clk_sdr), .rst_sdr_n (~rst_sdr),
        .ld_req (), .ld_addr (), .ld_len (), .ld_data (),
        .ld_rd (1'b0), .ld_ack (1'b0), .ld_done (1'b0),
        .fifo_full_ext (shared_fifo_full), .backend_done_ext (backend_done && !task_raw),
        .slot_words(task_capacity[18:0]), .fifo_flush_ext (bm_fifo_flush),
        .fifo_we_ext (bm_fifo_we), .fifo_di_ext (bm_fifo_di),
        .cfg_valid_ext(bm_cfg), .cfg_first_ext(bm_first), .cfg_words_ext(bm_words),
        .cfg_wpr_ext(bm_wpr), .cfg_down_ext(bm_down),
        .finish_valid_ext(bm_finish), .finish_words_ext(bm_end_words)
    );

    //=========================================================================
    // 3.5b) ★★ p3-lean 步2c：字库/歌词表装载（**复用 `font_load.v`** ✓）
    //   `font_load` 是"任意长度 ≤ 槽"的**字节拷贝器**；FONT.HZK / ASC.HZK / S01.LRC 三个文件
    //   用它**分三次**装（一个实例 ⇒ 省面积 ✓）：
    //     `FONT.HZK` → 0x13EC00（261,696 字）｜`ASC.HZK` → 0x17EA40（1,536 字）｜`S01.LRC` → 0x17F040
    //   ★ 三段的索引来源不同：FONT/ASC **按整名搜子串**（与 `BG`/`CV` 同一手法 ✓）；
    //     **LRC 直接用播放表给的 `pl_lrc_ft`** ✓（零扫描、零新增总线口 ✓）
    //   ★ 名字识别的起始位必须覆盖 **0..8**：卡上真名 `FONT    HZK`（FONT 在位 0）✗
    //     原写法只覆盖 1..7 ⇒ 一个都认不出（旧会话整机实测 `FONT OK=0` ✓ 见 workitem_p3_lyric §8.9.3）
    //   ★ 装载时机：**画面已提交之后**（`LF_BOOTD` ⇒ `LF_FONT`）⇒ 不推迟出图 ✓
    //     且 `LF_DONE`（音频起播门 ✓）在它们全部收口之后 ⇒ 音频链自动等 ✓
    //=========================================================================
    font_load #(.CLK_HZ(CLK_HZ), .WD_MS(2500), .EXTERNAL_BACKEND(1)) u_fload (
        .clk (clk), .rst_n (rst_n),
        .start (task_start && task_raw), .file_index (task_index),
        .slot_base (task_base), .byte_len (task_bytes),
        .busy (ft_busy), .done (ft_done), .err (ft_err), .nbytes (ft_nbytes),
        .lo_open (ft_lo_open), .lo_open_index (ft_lo_open_index), .lo_open_busy (lo_open_busy),
        .lo_rd_valid (lo_rd_valid), .lo_rd_data (lo_rd_data),
        .lo_rd_ready (ft_lo_rd_ready), .lo_want (ft_lo_want),
        .lo_rd_eof (lo_rd_eof), .lo_rd_err (lo_rd_err), .file_size (sd_lo_file_size),
        .clk_sdr (clk_sdr), .rst_sdr_n (~rst_sdr),
        .ld_req (), .ld_addr (), .ld_len (), .ld_data (),
        .ld_rd (1'b0), .ld_ack (1'b0), .ld_done (1'b0),
        .fifo_full_ext (shared_fifo_full), .backend_done_ext (backend_done && task_raw),
        .slot_words(task_capacity), .fifo_flush_ext (ft_fifo_flush),
        .fifo_we_ext (ft_fifo_we), .fifo_di_ext (ft_fifo_di),
        .cfg_valid_ext(ft_cfg), .cfg_first_ext(ft_first), .cfg_words_ext(ft_words),
        .cfg_wpr_ext(ft_wpr), .cfg_down_ext(ft_down),
        .finish_valid_ext(ft_finish), .finish_words_ext(ft_end_words)
    );

    // ---- lo / ld 两条通路的 2:1 mux（`ft_owner` 选路；同拍只有一个在跑 ✓）----
    assign lo_open       = ft_owner ? ft_lo_open       : bm_lo_open;
    assign lo_open_index = ft_owner ? ft_lo_open_index : bm_lo_open_index;
    assign lo_rd_ready   = ft_owner ? ft_lo_rd_ready   : bm_lo_rd_ready;
    assign lo_want       = ft_owner ? ft_lo_want       : bm_lo_want;

    //=========================================================================
    // ★★★ 2026-10-10 回退：**装载写闸（`WG_N`）已删除** ✗→✓
    //   【它是什么】只在"像素读侧连续空闲 ≥ N 拍"时才放行装载器的写请求 ✓
    //   【为什么删】实测**被证伪** ✗：`WG_N=32` 与 `WG_N=0` 两跑的集成日志**逐字节相同** ✓
    //     —— 因为显示读只占 ~15% 且都是**短突发** ⇒ "空闲 ≥32 拍（320ns）"**几乎永远成立**
    //     ⇒ 闸门**从来没拦过一次**、等于没加 ✓（不是治错了病，是**根本不改变任何东西** ✗）
    //   【它想治的病**仍然存在**且未修】坏点集中在**一行的最左边**（`y=232, x=0..10`，
    //     即 `cy_f(16)` = 背景层窗口第一行 ✓）⇒ 形状是"**行首第一笔读**被污染" ✓
    //     （与 `08664a9` 当年记录的"彩色噪点在每层左边缘 = 每行第一笔读"**指纹一致** ✓）
    //     量化：29 笔写突发 → 1 行被污染 ⇒ 肇事率 ≈3~4% ✗ ⇒ 真机预装 1.3MB（2,544 笔）
    //       期望 ~80 行被污染 ✗ ⇒ **"加粗突发"远远不够**（1024 字/笔仍约 10 行 ✗）
    //   ⇒ **结论与后续手段（写后保护期、PLL 相移档位）全部记档**：
    //     `artifacts/step0_cw_probe_20261009/README.md` ✓ 需要时再取 ✓
    //=========================================================================


    // ★★ P2/S3-c：**播放表**（`rtl/load/playlist.v` ✓）—— 把卡上平铺文件聚合成"首" ✓
    //   ① 作用：分组 + **可播性判定/分诊** ✓（`design:714` ✓）+ 当前首指针 ✓
    //      ⇒ **A1**（播放表 ≥1 首 + 报告行如实 ✓）的落点 ✓
    //   ② **不占总线** ✓：它只是**主动驱动 `index`**（= 复用唯一那个文件表索引口 ✓），
    //      由 `lf_st` 在 §3.7 选路 ✓ ⇒ **零新增总线口** ✓
    //   ③ **不碰 P1 的装载路径** ✓：装载仍走"整名搜 `BG`/`CV` + 后随那位数字"（**一个字不改** ✗）
    //      ⇒ 表与装载器的一致性**用断言绑住** ✓（T-07/PL-05 ✓），到 P3/P5 再升格成表驱动 ✓
    //   ④ ★ 音频链**改用表给的 `wav_ft`** ✓（见 §3.7 的 `AU_IDLE` ✓）—— 这是播放表在 P2 的
    //      **真实消费者** ✓：卡上有多首时，"扫第一个 `type==1`"与"报表说的第几首"会**不一致** ✗
    //      ⇒ 报表会说谎 ✗ ⇒ A1 当场不成立 ✗
    // 行字数 = ceil(W*3/16)*4（design §3.1 打包约定）；窗口按**居中**放。
    // ★ 2026-10-02 教训（保留）：把 `bm_img_w * 3` 写成**移位加**（w<<1 + w）—— 原写法让 TD 落了一个
    //   **MULT18**，使 clk0（50MHz）这条路径长期贴在 0 附近（曾 -0.665ns ✗）。移位加等价且无乘法器 ✓。
    // ★★ A1（2026-10-03）：这三个式子**下移到函数**（`wpr_f`/`cx_f`/`cy_f`，见下）——
    //   因为 A1 之后几何要**按"目标组"重算**（提交时 ✓），不再是"装载完成那一刻的 bm_img_*" ✗。

    // ★ 按**8.3 名**认素材：整名里**搜索子串** "BG"=背景 / "CV"=封面。
    //   ★★ 2026-10-01 修正（板上实测定位）：原来按**固定位置**比第 5/6 字符（下标 4/5），
    //      只对仿真素材 `SM01BG`（S M 0 1 B G ⇒ 'B' 在下标 4）成立；
    //      板上素材 `S01BG1`（S 0 1 B G 1 ⇒ 'B' 在下标 3）**差一位** ⇒ 一个都认不出。
    //      板上现象：`lf_st=5`(完成) + `ERR WORDS` 高位的已找到枚数=0 + 读 0 字节。
    //      现在改成搜相邻两位的子串：`SM01BG` 与 `S01BG1` 都命中 ✓，以后换名也稳。
    //=========================================================================
    // ★ A1：KEY4（板上 C1，低有效）→ 去抖 → 切换素材组
    //   组号 = 文件名里 'BG'/'CV' **紧跟其后那位数字**（板上 S01BG1/2/3、S01CV1/2/3）。
    //   按下 ⇒ 组号 1→2→3→1 循环，并重新走一遍"扫描→装载"；新组装完才重新使能图层
    //   （所以切组瞬间画面会短暂熄灭，属预期）。
    //=========================================================================
    generate if (en_osd) begin : g_osd_keys
    osd_controls #(.EXTENDED(VISUAL_CONTROLS),.CLK_HZ(CLK_HZ),.DEBOUNCE_MS(KEY_DEBOUNCE_MS)) u_osd_controls (
        .clk(clk),.rst_n(rst_n),.key2(key2),.key3(key3),.key4(key4),
        .visible(osd_visible_clk),.page(osd_page_clk),.selected(osd_selected_clk),
        .image_next(key_image_next),
        .sensitivity(osd_sensitivity_clk),
        .volume(osd_volume_clk),.sat_base(osd_sat_base_clk),.sat_max(osd_sat_max_clk),
        .con_base(osd_con_base_clk),.con_max(osd_con_max_clk),
        .colors(visual_colors_clk),.effects(visual_effects_clk),
        .transition_effect(transition_effect_clk),.transition_speed(transition_speed_clk)
    );
    assign key_press_legacy=key_image_next;
    end else begin : g_legacy_key
        key_debounce #(.CLK_HZ(CLK_HZ),.DEBOUNCE_MS(KEY_DEBOUNCE_MS)) u_key4 (
            .clk(clk),.rst_n(rst_n),.key_in(key4),
            .press(key_press_legacy),.level()
        );
        assign key_image_next=key_press_legacy;
        assign osd_visible_clk=1'b0;
        assign visual_colors_clk={6{7'd70}};assign visual_effects_clk=5'b11111;
        assign transition_effect_clk=2'd0;assign transition_speed_clk=2'd1;
        assign osd_page_clk=2'd0;
        assign osd_selected_clk=3'd0;
        assign osd_sensitivity_clk=6'd16;
        assign osd_volume_clk=9'd100;
        assign osd_sat_base_clk=9'd60;
        assign osd_sat_max_clk=9'd200;
        assign osd_con_base_clk=9'd100;
        assign osd_con_max_clk=9'd135;
    end endgenerate

    //=========================================================================
    // ★★★ P5/A8（2026-10-10）：**小轮播** —— 只产生一个与 `key_press` 等价的脉冲 ✓
    //   【S0 查实（读代码 ✓ 不是猜 ✗）】换组的**完整动作**＝"`key_press` 的**全部**作用" ✓
    //     ＝① 那一拍的一串影子寄存器赋值 ✓（见下面 `else if (grp_adv && ...)` ✓）
    //       ② ★ **清 `cmt_sent`** ✓（见下面的提交块 ✓）—— 少了②就**永不提交** ✗
    //     ★★ 2026-10-10 板上实测教训 ✗：我当初只读到① ✗ 就断言"切换逻辑一行都不用改" ✗
    //       ⇒ 板上"每 20s 自动换组"**一动都不动** ✗（影子改了、显示没改 ✓）
    //       ⇒ ★ 教训：**"某信号的全部作用"必须靠全文件搜它 ✗ 不能只读一个块** ✓
    //         （`grep key_press` 一跑就见分晓 ✗ —— 我少搜了一次 ✓）
    //   【接口因此比原草案（`workitem_p3_lean.md` §11.17 ✓）简单得多】
    //     草案要 `song_end/grp_now → grp_sel/grp_tgl` ✗；实际只要 `en → rot_pulse` ✓
    //   【口径】`en_rot=0` ⇒ `rot_pulse` 恒 0 ⇒ 与今天**逐位相同** ✓（开关纪律 ✓）
    //=========================================================================
    wire au_end_pulse, sw_ok;
    wire rot_pulse;
    carousel #(
        .TICKS ((CLK_HZ / 1000) * ROT_MS)      // ★ 毫秒 ⇒ 拍数 ✓（模块只吃拍数 ✓）
    ) u_rot (
        .clk (clk), .rst_n (rst_n),
        // ★★★ 2026-10-10：**补装期间暂停轮播** ✗→✓
        //   预装六笔没走完时，第 2/3 组的目标槽**还没装好** ✗
        //   ⇒ 若此时轮播转过去 ⇒ 看到的是**上一首**的数据而几何按新首的 ⇒ **又花屏** ✓
        //   ⇒ 用 `pre_busy` 把它按住 ✓（`pre_busy` 天然为 0 ⇒ 与今天逐位相同 ✓）
        .en  (en_rot && !pre_busy && !pre_sw_pending && !song_view_pending && view_idle),
        .rot_pulse (rot_pulse)
    );

    // ★ 换组事件 = 按键 **或** 轮播到点 ✓（两条路**完全等价** ✓）
    wire song_view_fire = song_view_pending && view_idle;
    wire grp_adv = ((key_image_next | rot_pulse) && !pre_busy && !pre_sw_pending &&
                    !song_view_pending && view_idle && !(au_end_pulse && sw_ok)) || song_view_fire;
    always @(posedge clk) begin
        if (!rst_n) song_view_pending <= 1'b0;
        else if (sw_req) song_view_pending <= 1'b1;
        else if (song_view_fire) song_view_pending <= 1'b0;
    end

    reg  [2:0] grp;                       // ★★ A1：**当前正在显示**的组号（1..3）
    // reg  [2:0] ld_grp;                    // ★★ A1：**装载器正在装**的组号（开机 1→2→3）
    // ★★ 2026-10-10 教训：一次 `edit` 少写了行尾换行 ✗ ⇒ 把上面这行**并进了注释** ✗
    //    ⇒ 编译报 `Undefined variable: 'ld_grp'` ✗（`skeleton_core.v:1029` ✓）
    //    ⇒ 改代码时**必须让每一行独立成行** ✓ —— 注释吃掉的声明，编译器只会说"未定义" ✗
    // ★ B17：组号 → 该组的**专属槽基址**。★★ A1：改成"按任意组号取基址"的**函数** ✓
    //   （装载用 `ld_grp`、按键切换用 `grp_nxt` ⇒ 两处都不再依赖"当前显示组" ✗）
    //   design §3.1 只定义 A/B 两组；第 3 组落在原"预留"区（占 460,800 字 ≈1.84MB ✓）
    // ★★★ P5/A9（2026-10-10）：**逻辑组 → 物理槽的轮转量** ✓
    //   `0` ⇒ 第 N 组 = 第 N 个物理槽 ⇒ **与今天逐位相同** ✓（A/B 就靠这个 ✓）
    //   切歌时 +1 ✓（新首的 g1 已在第 4 槽 ✓，其 g2/g3 补装进腾空的前两槽 ✓）—— S2 做 ✓

    //   ★★ 三根控制线（`sw_req`/`sw_start`/`sw_from`）的声明**在模块前半段** ✓ ——
    //     那里才是它们**第一次被使用**的地方（`preload.clr` ✓、`grp_nxt` ✓、`.scan_start` ✓）
    //     ⇒ 这里不重复声明 ✗（重复会报 `vlog-2388 already declared` ✓ —— 实测 ✓）
    function [20:0] bg_base_f;
        input [2:0] g;
        input [1:0] rot;
        reg [1:0] bg_ix;                      // ★ 轮转后的物理槽号（0..3 ✓）
        // ★★ p3-lean 步2c-3（**板上抓出的槽冲突**）—— 最终修法：**不动图像槽，改挪字库/歌词表** ✓
        //   冲突原委：第三组背景 `0x150000..0x188400` 与 **FONT `0x13EC00..0x17EA40`**
        //     **重叠 191,040 字 = 746 KB** ✗（`ASC`/`LRC` 也整块落在里面 ✗）
        //   ⇒ 装载顺序"三组图 → 字库 → LRC"⇒ 字库一装上就覆盖第三组背景 ✗
        //     （`p2_sdram_map_and_traffic_plan.md:72-77` 早算好新槽表但 P1 实现没落地 ✗）
        //   ★ **为什么挪字库而不是挪背景**：图像槽是**板上验过**的路径（A1 的三组切换 ✓），
        //     动它有回归风险 ✗；而字库/歌词只有 `lyric_pick`/`layer_lyric` 在读，
        //     基址是**参数**（改常量即可 ✓），且是**全新**通路（本来就没上过板 ✓）⇒ 风险小得多 ✓
        //   ★ 新址 = `design_music_player.md:127` **原本给 FONT 定的 `0xE1000`** ✓（不是我编的 ✓）
        //     且 `CV_B 0xA8C00 + 230,400 = 0xE1000` **严丝合缝** ✓ ⇒ 完全落进空闲空隙 ✓
        // ★★★ 2026-10-10：**扩到 4 组**（A9 零延迟预装的前提 ✓）+ **CV3 挪位**腾空间
        //   【为什么必须扩到 4 组】A9 要求"下一首的 g1（背景＋封面）在播放期就预装进 SDRAM" ✓，
        //     边界才能硬切零等待 ✓（用户口径：「不接受边界 1s」✓）
        //   【为什么 CV3 要挪】算过账 ✗：4 组需要 4×BG(230,400) ＋ 4×CV ＋ 字库/ASC/LRC
        //     ＝ 1,937,440 字 ✓ ≤ 8MB(2,097,152 ✓) —— **装得下** ✓
        //     但**现状**的槽位摆法装不下 ✗：CV3 之后只剩 260,096 字 ✗（要 460,800 ✗）
        //     ⇒ 而 `0x1225A0..0x14FFFF` 一直空着 **187,040 字** ✓（字库块与 BG3 之间的缝 ✓）
        //   【新布局】（全部经 `scripts/check_sdram_map.py` 校验 ✓，它以前是**红的** ✓）
        //     BG1 0x000000  BG2 0x038400  BG3 0x150000  ★BG4 0x188400
        //     CV1 0x070800  CV2 0x0A8C00  ★CV3 0x1225A0（原 0x188400 ✗）  ★CV4 0x1C0800
        //     字库 0xE1000 / ASC 0x120E40 / LRC 0x121440（**都没动** ✓）
        //   【代价（必须记账 ✗）】CV 槽容量上限从 230,400 字降到 **187,040 字**（＝748,160 B ✓）
        //     ⇒ 封面若大于该尺寸会被**拒绝**（`0x64` ✓ 不是静默越界 ✓）
        //     ★ 卡上真封面 384,054 B ⇒ **只有上限的一半** ✓ ⇒ 对现有素材零影响 ✓
        //   【旁证】`design_music_player.md:144` 早写过"多占 460,800 字…仍 < 8MB ✓"
        //     —— 那笔账是按**老地图**算的 ✓，字库挪位后没人重算 ✗ ⇒ 这次补上 ✓
        // ★★★ P5/A9（2026-10-10）：**逻辑组号 → 物理槽** 改为带**轮转量** ✓
        //   【为什么需要轮转】切歌后新首的 g1 已经在**第 4 个物理槽**里（预装位 ✓），
        //     而它的 g2/g3 要补装进**被腾空的前两个物理槽** ✗
        //     ⇒ "第 N 组"落在哪个物理槽**每首歌都不一样** ✓ ⇒ 必须有一个轮转量 ✓
        //   【口径】`ix = (g - 1 + slot_rot) & 3` ✓
        //     `slot_rot = 0` ⇒ **与今天逐位相同** ✓（可做 A/B ✓）；由切换时 +1 推进 ✓（S2 ✓）
        //   ★ 同一函数同时服务"**装载目标**（`ld_grp` ✓）"与"**显示槽**（`grp_nxt` ✓）" ✓
        //     ⇒ 两者天然一致 ✓（不会出现"装到 A、显示 B" ✗）
        begin
            bg_ix = (g - 3'd1) + rot;
            bg_base_f = TYPOGRAPHY ? ((bg_ix == 2'd1) ? 21'h038400 :
                        (bg_ix == 2'd2) ? 21'h070800 :
                        (bg_ix == 2'd3) ? 21'h0A8C00 : 21'h000000) :
                        (bg_ix == 2'd1) ? 21'h38400  :
                        (bg_ix == 2'd2) ? 21'h150000 :
                        (bg_ix == 2'd3) ? 21'h188400 : 21'h00000;
        end
    endfunction
    function [20:0] cv_base_f;
        input [2:0] g;
        input [1:0] rot;
        reg [1:0] cv_ix;                      // ★ 轮转后的物理槽号（0..3 ✓）
        // ★★ 2026-10-03（分支 exp/cvc-slot-fix）：**只改这一个常量** ✗ ——
        //   原值 `0x180000` 落在 `BG_C`（占 `0x150000 ~ 0x188400`，每槽 230,400 字 ✓）**内部** ✗
        //   ⇒ 与 `BG_C` **重叠 0x8400 = 33,792 字（132KB）** ✗；装载顺序是"先 BG 后 CV" ✓
        //   ⇒ **CV3 覆盖 BG3 的尾部** ✗ ⇒ 板上表现为：第三组底部出现**洋红色横带 + 条纹圆弧** ✓✓
        //   （用素材渲染独立证实 ✓：三张背景底部均为暗色渐变 ✓、封面底部全为洋红抠图色 ✓
        //     ⇒ 那段"紫带 + 半圆"**不属于任何素材** ✓，其花纹正是封面内容 ✓）
        //   ⇒ 改到 `0x188400`（= `0x150000 + 0x38400` ✓），末槽到 `0x1C0800` ✓（仍在 8MB 内 ✓）
        //   ⚠️ 上一次我否定过这个改法 ✗，但那次依据是**一屏已经花掉的画面** ✗ ⇒ 依据无效 ✓
        // ★★★ 2026-10-10：**CV3 从 `0x188400` 挪到 `0x1225A0`** ✓，并**新增 CV4 = `0x1C0800`** ✓
        //   【为什么挪】见 `bg_base_f` 上方的完整账 ✓ —— 一句话：
        //     4 组要 460,800 字，而 CV3 之后只剩 260,096 ✗；
        //     字库块与 BG3 之间那条 **187,040 字**的缝一直空着 ✓ ⇒ 正好放得下 CV3 ✓
        //     （`0x1225A0 + 187,040 = 0x150000` **严丝合缝** ✓ 与 BG3 起点相接 ✓）
        //   【★ 这段地址的历史（必须记住 ✗）】CV3 的**上一版**是 `0x180000` ✗，
        //     它落在 `BG_C` 内部 ⇒ 重叠 33,792 字 ⇒ 板上"第三组底部洋红横带 ＋ 条纹圆弧" ✗
        //     后改成 `0x188400` ✓（见下方 2026-10-03 那段记录 ✓）
        //     ⇒ ★ 所以这次挪位**用护栏校验**（`scripts/check_sdram_map.py` ✓
        //        —— 它以前对"4 组"是**红的** ✓，挪完应变绿 ✓），不再靠记性 ✓
        //   【CV 槽容量上限】187,040 字 ⇒ 与 CV3 所在的那条缝**等宽** ✓
        //     （CV1/CV2 上限也一并收紧 ⇒ 顺带让 CV2 尾部与字库之间多出 43,360 字余量 ✓）
        // ★★★ P5/A9（2026-10-10）：与 `bg_base_f` 同一轮转口径 ✓（`ix = (g-1+slot_rot)&3` ✓）
        //   ★ 两个函数**必须用同一个轮转量** ✗ —— 否则"背景换了、封面没换" ✗（板上会看到撕裂 ✓）
        begin
            cv_ix = (g - 3'd1) + rot;
            cv_base_f = TYPOGRAPHY ? ((cv_ix == 2'd1) ? 21'h0EB8C0 :
                        (cv_ix == 2'd2) ? 21'h0F6180 :
                        (cv_ix == 2'd3) ? 21'h100A40 : 21'h0E1000) :
                        (cv_ix == 2'd1) ? 21'hA8C00  :
                        (cv_ix == 2'd2) ? 21'h1225A0 :
                        (cv_ix == 2'd3) ? 21'h1C0800 : 21'h70800;
        end
    endfunction
    // Validity is a view of the physical state, not a copied logical table.
    wire [3:0] g_ok, g_cok;
    assign g_ok[0]=1'b0; assign g_cok[0]=1'b0;
    genvar gi;
    generate for (gi=1;gi<=3;gi=gi+1) begin : g_logical_view
        wire [1:0] pi = slot_rot + (gi-1);
        assign g_ok[gi] = physical_bg_valid[pi];
        assign g_cok[gi] = physical_cv_valid[pi];
    end endgenerate
    assign lf_found = {1'b0,g_ok[1]}+{1'b0,g_ok[2]}+{1'b0,g_ok[3]};
    // 几何派生（**与装载时同一套公式** ✓；A1 之后用在"提交时按目标组重算" ✓）
    function [15:0] wpr_f;                // ((3W+15)>>4)*4 —— 移位加，无乘法器 ✓
        input [15:0] w;
        reg [16:0] x3;
        reg [13:0] q;
        begin
            x3    = ({1'b0, w} << 1) + {1'b0, w};
            q     = (x3 + 17'd15) >> 4;
            wpr_f = {2'd0, q} << 2;
        end
    endfunction
    function [15:0] cx_f;  input [15:0] w; begin cx_f = (16'd640 - w) >> 1; end endfunction
    function [15:0] cy_f;  input [15:0] h; begin cy_f = (16'd480 - h) >> 1; end endfunction

    // ★★ A1：下一组 = **下一个有效组**（环形；全无效 ⇒ 留在本组，等价于"按键不动作" ✓）
    wire [2:0] g_n1    = (grp == 3'd3) ? 3'd1 : (grp + 3'd1);
    wire [2:0] g_n2    = (g_n1 == 3'd3) ? 3'd1 : (g_n1 + 3'd1);
    wire [2:0] g_n3    = (g_n2 == 3'd3) ? 3'd1 : (g_n2 + 3'd1);   // 回绕到底 = grp
    wire [2:0] grp_nxt_raw = g_ok[g_n1] ? g_n1 : (g_ok[g_n2] ? g_n2 : (g_ok[g_n3] ? g_n3 : grp));
    // ★★★ P5/A9（2026-10-10）：**切歌 ⇒ 组号复位到第 1 组** ✓（`design:868` 的口径 ✓）
    //   ★ 只改**这一处**定义 ✓ ⇒ 下面所有用 `grp_nxt` 的地方（槽基址/几何/ok ✓）
    //     全都自动跟着复位 ✓ —— 不必去每一处加 mux ✗（那正是"漏一处就撕裂"的来源 ✗）
    wire [2:0] grp_nxt = song_view_fire ? 3'd1 : grp_nxt_raw;
    // ★★ A1：开机提交哪一组 = **第一个有效组**（全无效 ⇒ 取第 1 组，但 g_ok=0 ⇒ 不提交 ✓）
    wire [2:0] grp_fst = g_ok[3'd1] ? 3'd1 : (g_ok[3'd2] ? 3'd2 : (g_ok[3'd3] ? 3'd3 : 3'd1));

    // Resolve geometry through the narrow synchronous physical-slot memory.
    // Shadow data remains fixed from request publication until the pixel ACK.
    always @(posedge clk) begin
        if (!rst_n) begin
            grp<=3'd1; shape_start<=1'b0; shape_pending<=1'b0;
            shadow_ready<=1'b0; view_requested<=1'b0; shape_pair<=2'd0; song_slot_hold<=1'b0;
            bg_slot_nx<=21'd0; cv_slot_nx<=21'd0; bg_ok_nx<=1'b0; cv_ok_nx<=1'b0;
            bg_iw_nx<=16'd0; bg_ih_nx<=16'd0; bg_wpr_nx<=16'd0;
            bg_w_nx<=16'd0; bg_h_nx<=16'd0; bg_x_nx<=16'd0; bg_y_nx<=16'd0;
            cv_iw_nx<=16'd0; cv_ih_nx<=16'd0; cv_wpr_nx<=16'd0;
            cv_w_nx<=16'd0; cv_h_nx<=16'd0; cv_x_nx<=16'd0; cv_y_nx<=16'd0;
        end else begin
            shape_start<=1'b0;
            if ((lf_st==LF_DONE && !view_requested) || (grp_adv && lf_st==LF_DONE)) begin
                view_requested<=1'b1; shape_start<=1'b1; shape_pending<=1'b1;
                shadow_ready<=1'b0; song_slot_hold<=lrc_slot;
                grp<=view_requested ? grp_nxt : grp_fst;
                shape_pair<=slot_rot+(view_requested ? grp_nxt[1:0] : grp_fst[1:0])-2'd1;
                bg_slot_nx<=bg_base_f(view_requested ? grp_nxt : grp_fst,slot_rot);
                cv_slot_nx<=cv_base_f(view_requested ? grp_nxt : grp_fst,slot_rot);
                bg_ok_nx<=song_view_fire ? pre_g1_bg_ok : g_ok[view_requested ? grp_nxt : grp_fst];
                cv_ok_nx<=song_view_fire ? pre_g1_cv_ok : g_cok[view_requested ? grp_nxt : grp_fst];
            end
            if (shape_done && shape_pending) begin
                shape_pending<=1'b0; shadow_ready<=1'b1;
                bg_iw_nx<=display_bw; bg_w_nx<=display_bw;
                bg_ih_nx<=display_bh; bg_h_nx<=display_bh;
                bg_wpr_nx<=wpr_f(display_bw);
                bg_x_nx<=cx_f(display_bw); bg_y_nx<=cy_f(display_bh);
                cv_iw_nx<=display_cw; cv_w_nx<=display_cw;
                cv_ih_nx<=display_ch; cv_h_nx<=display_ch;
                cv_wpr_nx<=wpr_f(display_cw);
                cv_x_nx<=UI_CENTER_X-(display_cw>>1);
                cv_y_nx<=UI_CENTER_Y-(display_ch>>1);
            end
        end
    end

    // ★★ A1：提交请求现在只来自两处 —— **开机收口一次** ✓ + **每次按键一次** ✓
    //   条件 = "开机已完成（`lf_st == LF_DONE`）且影子参数就绪（`bg_ok_nx`）且尚未发过（`cmt_sent`）" ✓
    //   ★ C 的 `ld_left_done`（"本轮必须装载过才允许提交"）**已移除** ✗ —— 它经双重证伪是空操作 ✓，
    //     且 A1 之后按键**根本不再装载** ⇒ 那个门没有对象了 ✓（见 doc/evidence/switch_dots_ab_20261003.md §3）
    //   机制不变 ✓：**稳定影子参数 + 单比特翻转**跨到 clk_pix，再在 vs 帧边界**原子生效** ✓
    always @(posedge clk) begin
        if (!rst_n)          begin cmt_sent <= 1'b0; cmt_tgl <= 1'b0; end
        else if (grp_adv)    cmt_sent <= 1'b0;                      // ★ 换组请求（按键 **或轮播** ✓）⇒ 允许再提交一次
                                                                    // ★★★ 2026-10-10 板上抓出的 bug ✗：
                                                                    //   原来这里只认 `key_press` ✗ ⇒ 轮播改了影子 `*_nx`
                                                                    //   却**永不提交** ⇒ 板上"每 20s 自动换组"**完全不动** ✗
                                                                    //   （仿真也没抓到 ✗ —— 因为我的判据只数了 `grp` 寄存器 ✗
                                                                    //     没数**显示的槽** ✗ ⇒ 判据选错了对象 ✗ 已补 ✓）
        else if ((lf_st == LF_DONE) && shadow_ready && !shape_pending && !shape_start &&
                 !cmt_sent && (cmt_ack_sync[1] == cmt_tgl)) begin
            cmt_sent <= 1'b1;
            cmt_tgl  <= ~cmt_tgl;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmt_ack_sync <= 2'd0;
            cmt_song_ack_sync <= 2'd0;
            pre_sw_pending <= 1'b0;
            confirmed_pair <= 2'd0; pending_pair <= 2'd0; confirmed_valid <= 1'b0;
        end else begin
            cmt_ack_sync <= {cmt_ack_sync[0], cmt_ack_tgl};
            cmt_song_ack_sync <= {cmt_song_ack_sync[0], cmt_ack_song_slot};
            if (shadow_ready && !shape_pending && !shape_start && !cmt_sent &&
                (lf_st==LF_DONE) && cmt_ack_sync[1]==cmt_tgl)
                pending_pair <= shape_pair;
            if (cmt_sent && cmt_ack_sync[1]==cmt_tgl) begin
                confirmed_pair<=pending_pair; confirmed_valid<=1'b1;
            end
            if (sw_req) pre_sw_pending <= 1'b1;
            else if (pre_sw_fire) pre_sw_pending <= 1'b0;
        end
    end

    // Both payloads remain pinned until scene_fade acknowledges retirement.
    // No new request can overwrite shadow geometry before that acknowledgement.
    scene_fade #(.WIDTH(268),.ALPHA_STEP(FADE_STEP),.RUNTIME_CONTROLS(VISUAL_CONTROLS)) u_fade (
        .clk(clk_pix),.rst(rst_pix),.frame_tick(vs_pix_d && !cb_vs),
        .effect(transition_settings[1:0]),.speed(transition_settings[3:2]),
        .active_effect(active_transition_effect),
        .request_toggle(cmt_tgl),.old_idle(obg_idle && ocv_idle),
        .next_scene({bg_ok_nx,bg_x_nx,bg_y_nx,bg_w_nx,bg_h_nx,bg_iw_nx,bg_ih_nx,bg_wpr_nx,bg_slot_nx,
                     cv_ok_nx,cv_x_nx,cv_y_nx,cv_w_nx,cv_h_nx,cv_iw_nx,cv_ih_nx,cv_wpr_nx,cv_slot_nx}),
        .current_scene({bg_en,bg_x,bg_y,bg_w,bg_h,bg_iw,bg_ih,bg_wpr,bg_slot,
                        cv_en,cv_x,cv_y,cv_w,cv_h,cv_iw,cv_ih,cv_wpr,cv_slot}),
        .previous_scene({obg_en,obg_x,obg_y,obg_w,obg_h,obg_iw,obg_ih,obg_wpr,obg_slot,
                         ocv_en,ocv_x,ocv_y,ocv_w,ocv_h,ocv_iw,ocv_ih,ocv_wpr,ocv_slot}),
        .old_enable(old_enable),.busy(fade_busy),.ack_toggle(cmt_ack_tgl),
        .alpha(fade_alpha),.accepted(scene_accepted)
    );
    always @(posedge clk_pix) begin
        if (rst_pix) begin
            cmt_sync <= 3'd0; cmt_pend <= 1'b0; vs_pix_d <= 1'b1;
            cmt_song_slot_sync <= 2'd0;
            cmt_ack_song_slot <= 1'b0;
        end else begin
            cmt_sync <= {cmt_sync[1:0], cmt_tgl};
            cmt_song_slot_sync <= {cmt_song_slot_sync[0], song_slot_hold};
            vs_pix_d <= cb_vs;
            if (cmt_sync[2] != cmt_sync[1]) cmt_pend <= 1'b1;        // 收到提交请求
            if (scene_accepted) begin
                cmt_pend <= 1'b0;
                cmt_ack_song_slot <= cmt_song_slot_sync[1];
            end
        end
    end

    //=========================================================================
    // 3.7) ★★ P2/S2：WAV 播放链路（扫表 → 开 hi 流 → 解头 → 环播放 → 收工 ✓）
    //
    //   【为什么放在这里（§3.7 而不是 §1b）】它要用 `lf_st == LF_DONE`（**开机装载已完成** ✓）
    //   当起始门 ✓，而 `lf_st` 在装载 FSM 那里才声明 ⇒ Verilog 必须先声明后用 ✗
    //   （`default_nettype none` 下更严 ✓）。放在这里还顺带保证：
    //   ★ `hi` 的读**绝不在开机装载期间**抢 SD 卡 ✓（`sector_arbiter` 里 `hi` 是**绝对优先** ✗
    //     —— `sector_arbiter.v:71` ✓ ⇒ 若同时起，装载会被饿死 ✗）。
    //
    //   【走的是 `storage_top` **已有的字节流口** `hi_*` ✓（不碰原始扇区 ✓）】
    //     · `hi_open/hi_open_index` ✓ 开文件（描述符由 `storage_top` 自己查 ✓）
    //     · `hi_rd_valid/hi_rd_data/hi_rd_ready` ✓ 字节流（谁消费由 §3.7 的 mux 定 ✓）
    //     · `hi_rd_eof` ✓ = 读流结束；`hi_rd_err` ✓ = 读流出错
    //     · `hi_want` ✓ = "现在要数据" ⇒ **必须给 1**，否则 `sector_arbiter` 不予授权 ✓
    //     ★ 因此**不需要** `data_lba`、也**不需要**自己找文件 ✓（文件表已带 `file_type` ✓）
    //       —— 见 `doc/workitem_p2_s2.md` §6-① ✓
    //
    //   【三级"消费权"交接（这是全链路唯一容易静默出错的地方 ✓）】
    //     ① `AU_OPEN/AU_HDR` ⇒ `hi_rd_ready = wav_head.rd_ready` ✓（**只吃头** ✓，
    //        `wav_head` 命中 `data` 后**立刻撤 ready** ⇒ 一个 PCM 字节都不多吞 ✓）
    //     ② `AU_PLAY`       ⇒ `hi_rd_ready = 环的写侧 rd_ready` ✓（环快满就反压 ✓）
    //     ③ `AU_DRAIN`      ⇒ `hi_rd_ready = 1` ✓（歌尾/失败后把文件尾巴**丢弃读掉** ⇒
    //        让 `fat32_read` 正常收工、`hi` 通道回到可再用的状态 ✓）
    //
    //   【错误码】`WAV ERR=` 直接报 `wav_head.err_code`（0x1x/0x2x/0x3x ✓）；
    //     顶层链路自己的失败补一档 **0x4x** ✓：`0x40` 卡里没有 WAV ✓、`0x41` 打开/读流出错 ✓、
    //     `0x42` 超时 ✓。★ 报错后**停在 `AU_STOP`** ✓ ⇒ 音源交回**测试音** ✓
    //     （"链路自检音源" ✓：有声 ⇒ 通路好、素材坏 ✓；无声 ⇒ 通路坏 ✓ —— 一刀切开 ✓）
    //=========================================================================
    localparam [2:0] AU_IDLE = 3'd0, AU_SCAN = 3'd1, AU_OPEN = 3'd2, AU_HDR = 3'd3,
                     AU_PLAY = 3'd4, AU_DRAIN= 3'd5, AU_STOP = 3'd6, AU_NEXT = 3'd7;
    localparam [7:0] AU_EC_NOWAV = 8'h40, AU_EC_OPEN = 8'h41, AU_EC_TO = 8'h42;

    reg  [2:0]  au_st;
    reg  [7:0]  au_idx, au_open_idx, au_werr;
    reg  [3:0]  au_wait;
    reg  [19:0] au_to;                       // 超时计数（21ms @50MHz ✓ 够开文件/解头 ✓）
    reg         au_open_pulse, au_wh_start, au_start, au_play_en, au_wav_sel;
    // ★★ 步2c-5：**起播瞬间**翻转一位 ⇒ 跨到 `clk_sdr` 去把"已播样本数"归零（见 §2b ✓）
    //   依据：design 的时基口径是"**本曲已播样本数**" ✓，不是"从上电起算" ✗
    reg         au_play_tgl;
    reg  [7:0]  au_writer_song;
    reg         au_writer_ahead, au_wr_armed;
    reg  [31:0] au_total;
    // 注：`au_ft_index` 的**声明**在 §3（`storage_top` 例化之前 ✓），这里用 `assign` 驱动 ✓

    // wav_head（解头 ✓）
    wire        wh_ready, wh_done;
    wire [31:0] wh_bytes;
    wire [7:0]  wh_err;
    // 环播放器
    wire        wp_refill, wp_rd_ready, wp_sector_room, wp_valid, wp_primed, wp_end, wp_wr_done;
    wire [15:0] wp_l, wp_r, wp_raw_l, wp_raw_r;
    wire [12:0] wp_level_now, wp_level_min;
    wire [31:0] wp_uc, wp_hold;
    // 48k 节拍（与 `u_tone` 内部那一个**同算式、同复位、同 enable** ⇒ 相位逐拍相同 ✓）
    wire        wav_tick;
    wire [31:0] wav_tick_cnt;
    // ---- `hi` 通道三级消费权 ✓（assign 与声明分离 ⇒ 这四个信号在 §3 例化前已声明 ✓）----
    // ★★ P2/S3-c：索引口三选一 —— 开机装载（`lf_scan` ✓）／ **播放表扫描**（`pl_index` ✓）／
    //   开机完成后音频链（`au_idx` ✓）。三者**互斥**（由 `lf_st` 保证 ✓）⇒ 不冲突 ✓
    // ★★ p3-lean 步2c-3（**板上抓出，2026-10-06**）：字库/LRC **装载期间**索引口必须给 `ft_idx` ✗
    //   —— 否则索引仍是 `lf_scan`（扫完停在**最后一个**索引）⇒ `font_load` 的 `file_size`
    //     端口读到的是**别的文件**的大小 ⇒ 它按那个长度截流 ⇒
    //     **FONT/ASC 报"文件太短"(0x03) 而 LRC 恰好长度相符所以装对了** ✓
    //   ⇒ 板上症状正好是"歌词全对、字形全是方块"（`FONT OK=0`）✓
    //   ★ 这是我从旧版移植 LF_FONT/LF_LRC 两个状态时**漏搬的一行**（旧版 exp 有这层 ✓）。
    //   ★ 教训：装载器**必须**让"打开哪个文件"和"它有多大"指向**同一个索引** ✗ ——
    //     一个索引口被多处复用（扫描/播放表/音频/装载）时，这是最容易静默出错的地方 ✓
    assign au_ft_index = task_active ? task_index : au_idx;
    wire au_ph_hdr   = (au_st == AU_OPEN) || (au_st == AU_HDR);
    wire au_ph_play  = (au_st == AU_PLAY);
    wire au_ph_drain = (au_st == AU_DRAIN);

    // ★★ P2/S2：下面几处引用的名字都**显式声明**成 au_hi_* ✓（原先 `hi_*` 是"不接"的 ✓）
    assign au_hi_open       = au_open_pulse;
    assign au_hi_open_index = au_open_idx;
    assign au_hi_want       = au_ph_hdr | (au_ph_play && wp_sector_room) | au_ph_drain;
    assign au_hi_refill     = au_ph_hdr | au_ph_drain | wp_refill;
    assign au_hi_rd_ready   = au_ph_hdr   ? wh_ready :
                              au_ph_play  ? wp_rd_ready :
                              au_ph_drain ? 1'b1 : 1'b0;

    // ---- ② WAV 通路的 48k 节拍（★ 必须与测试音那一路**同相位** ✓）----
    audio_sample_tick #(
        .CLK_HZ    (25000000),
        .SAMPLE_HZ (48000)
    ) u_wav_tick (
        .clk        (clk_pix),
        .rst_n      (~rst_pix),
        .enable     (1'b1),                  // ★ 与 `u_tone.enable` 一致 ⇒ 累加器轨迹逐拍相同 ✓
        .tick       (wav_tick),
        .tick_count (wav_tick_cnt)
    );

    wav_head #(
        .MAX_SCAN_BYTES (32'd4096)           // 头部扫描上限 ✓（畸形文件拖不死 FSM ✓）
    ) u_wav_head (
        .clk       (clk), .rst_n (rst_n),
        .start     (au_wh_start),
        .done      (wh_done),
        .rd_valid  (au_hi_rd_valid), .rd_data (au_hi_rd_data), .rd_ready (wh_ready),
        .rd_eof    (au_hi_rd_eof),
        .data_bytes(wh_bytes), .err_code (wh_err)
        // 未接：busy（卡死由 `au_to` 兜底 ✓）/ hdr_bytes（只作单元 TB 观测 ✓）
        // ★ Verilog 里**不要**写 `.busy()` 或 `(open)`：`default_nettype none` 下会报 vlog-2892 ✓
    );

    wav_stream_player #(
        .ADDR_WIDTH (12),                    // 4096 帧 = 16KB = 85.3ms ✓（论证见件头 ✓）
        .PREFILL    (128)
    ) u_wav (
        .wr_clk       (clk), .wr_rst_n (rst_n),
        .play_enable  (au_play_en), .start (au_start), .total_bytes (au_total),
        .rd_valid     (au_hi_rd_valid), .rd_data (au_hi_rd_data), .rd_ready (wp_rd_ready),
        .rd_eof       (au_hi_rd_eof), .sector_room (wp_sector_room), .refill_urgent(wp_refill),
        .rd_clk       (clk_pix), .rd_rst_n (~rst_pix),
        .sample_tick  (wav_tick),            // ★ 48k 节拍（与测试音同相位 ✓）
        .continuous (en_a9),
        .boundary_ready (pre_g1_ready && pre_g1_bg_ok && pre_g1_cv_ok &&
                         lrc_prepared && !pl_busy),
        .sample_ready (1'b1),                // 厂商核**没有** ready 口 ✓（端口清单事实 ✓）
        .sample_valid (wp_valid),
        .sample_left  (wp_l), .sample_right (wp_r),
        .sample_raw_left(wp_raw_l), .sample_raw_right(wp_raw_r),
        .gain         (user_gain),
        .stat_clr     (1'b0),
        .level_now    (wp_level_now), .level_min (wp_level_min),
        .underrun_cnt (wp_uc), .hold_cnt (wp_hold),
        .primed       (wp_primed), .writer_done (wp_wr_done), .stream_end (wp_end)
    );

    audio_mux u_amux (
        .select_wav (au_wav_sel),
        .tone_valid (tone_valid), .tone_ready (aud_tone_ready),
        .tone_left  (tone_l),     .tone_right (tone_r),
        .wav_valid  (wp_valid),
        .wav_left   (wp_l),       .wav_right  (wp_r),
        .out_valid  (aud_out_valid), .out_ready (1'b1),   // 核无 ready ⇒ 恒 1 ✓
        .out_left   (aud_out_l),     .out_right (aud_out_r)
    );

    // ---- 读侧 `stream_end`（1 拍脉冲 @clk_pix，40ns ✓）→ clk 域：与 `aud_*_valid` 同一手法 ✓ ----
    //   ★ 40ns ≥ 1 个 clk 周期(20ns) ⇒ 2 级同步 + 边沿检测**不会漏** ✓
    //     （2026-10-04 板上那次数成 2 倍是"按电平数" ✗，不是同步器漏 ✓ —— 这里同样先边沿 ✓）
    reg wp_end_d0, wp_end_d1;
    always @(posedge clk) begin
        if (!rst_n) begin wp_end_d0 <= 1'b0; wp_end_d1 <= 1'b0; end
        else        begin wp_end_d0 <= wp_end; wp_end_d1 <= wp_end_d0; end
    end
    assign au_end_pulse = wp_end_d0 & ~wp_end_d1;

    //=========================================================================
    // ★★★ P5/A9（2026-10-10）S2：**一首播完 ⇒ 自动顺序切下一首**（硬切、零延迟 ✓）
    //
    //   【为什么能这么省】四件事**全都复用既有机制** ✓：
    //     ① 触发：`au_end_pulse` ✓（早就有了 ✓，原设计在 `AU_STOP` 处留了口 ✓）
    //     ② 显示切换：同一个 `grp_adv`（按键/轮播那条路 ✓）⇒ 影子寄存器 ＋ 帧边界原子提交 ✓
    //        —— ★ 一行都不用新写 ✗（含"清 `cmt_sent`"那一步 ✓）
    //     ③ 组号复位到 1：只改 `grp_nxt` 的**定义**一处 ✓（切歌那拍强制为 1 ✓）
    //     ④ 音频重启：原设计在 `AU_DRAIN → AU_STOP` 处写着"**S3 在这里接下一首**" ✓
    //        ⇒ 只需 `AU_STOP: if (sw_req) au_st <= AU_IDLE;` ✓ —— 它自己会去开**新的** `pl_wav_ft` ✓
    //
    //   【零延迟靠什么】新首的 g1 **已经在第 4 组槽里** ✓（`preload` 播放期装的 ✓）
    //     ⇒ 那拍只需把"第 1 组"映射到**那个物理槽** ✓ ⇒ `slot_rot += 3` ✓✓
    //       （推导：预装写在 `ix=(4-1+rot)&3` ✓；切后要求 `(1-1+rot')&3` 等于它
    //        ⇒ `rot' = rot+3` (mod 4) ✓）
    //
    //   【本步**不含**（如实记账 ✗）】切歌后歌词表**未重载** ✗ ⇒ 歌词会短暂沿用旧首 ✗
    //     —— 留作 S2b ✓（图像零延迟是本步的目标 ✓，歌词滞后几毫秒可接受 ✓）
    //   【口径】`en_a9=0` ⇒ `sw_req` 恒 0 ⇒ 与今天**逐位相同** ✓（`slot_rot` 也保持 0 ✓）
    //=========================================================================
    assign sw_ok      = en_a9 && nx_vld && pre_g1_ready &&
                             pre_g1_bg_ok && pre_g1_cv_ok && lrc_prepared &&
                             (lrc_prep_song == nx_song) && (lf_st == LF_DONE) && !pl_busy &&
                             !pre_sw_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sw_req   <= 1'b0;
            sw_start <= 1'b0;
            sw_pend  <= 1'b0;
            sw_cnt   <= 8'd0;
            sw_from  <= 8'd0;
            slot_rot <= 2'd0;                        // ★ 复位态 = 与今天逐位相同 ✓
        end else begin
            sw_req   <= 1'b0;                        // ★ 都是单拍脉冲 ✓
            sw_start <= 1'b0;
            // ★★★ 冷却门 ✗→✓：切完 1 秒内**不再理会"歌尾"** ✓
            //   （理由见 `sw_cool` 声明处 ✓ —— 防"切歌风暴"把 SDRAM 带宽占满 ✗）
            if (au_end_pulse && sw_ok) begin
                sw_req   <= 1'b1;
                sw_cnt   <= sw_cnt + 8'd1;          // ★ 取证：切歌触发次数 ✓
                sw_from  <= nx_song;
                sw_pend  <= 1'b1;                    // ★ 挂起（见 `AU_STOP` ✓）
                // ★★★ 一套逻辑覆盖所有 N ✓（**N=1 是特例不是分支** ✗ —— 用户 2026-10-10 纠正 ✓）
                //   「多首歌广义上包括一首歌，你要写多首歌的逻辑应该同样适用单首歌，
                //     而不是在分情况讨论」✓
                //   ⇒ 所以**不判**"下一首是不是自己" ✗，一律照做 ✓：
                //     · 轮转 `rot += 3` ✓（新首的 g1 已在 `(rot+3)&3` ✓
                //       ⇒ 它的 g2/g3 要落到 `(rot'+0)&3` 与 `(rot'+1)&3` ✓）
                //     · 重扫播放表 ✓（`start_from = nx_song` ✓ ⇒ N=1 时从第 1 首起 ✓ = 自己 ✓）
                slot_rot <= slot_rot + 2'd3;
                sw_start <= 1'b1;
            end
            // ★ 音频侧：挂起标志**只在钩子用过之后**才清 ✓
            //   ★★★ 2026-10-11 仿真抓出的 bug ✗→✓：原来写的是 `au_st != AU_STOP` ✗
            //     而歌尾那一拍 `au_st` 还是 **`AU_PLAY`**（≠ AU_STOP ✓）
            //     ⇒ ★ **下一拍 `sw_pend` 就被清掉** ✗ ⇒ 等音频走到 `AU_STOP` 时标志早没了 ✗
            //     ⇒ 钩子永不触发 ⇒ ★ **切完没声音** ✓✓（板上现象 ✓，仿真已复现 ✓）
            //   【正解】清的条件是"**已经回到 `AU_IDLE`**"✓ —— 那说明钩子被用掉了 ✓
            else if (sw_pend && (au_st == AU_IDLE)) begin
                sw_pend <= 1'b0;
            end
        end
    end

    // ---- 主 FSM（clk 域 = 与 `storage_top` 同域 ✓）----
    always @(posedge clk) begin
        if (!rst_n) begin
            au_st <= AU_IDLE; au_idx <= 8'd0; au_open_idx <= 8'd0;
            au_wait <= 4'd4; au_to <= 20'd0;
            au_open_pulse <= 1'b0; au_wh_start <= 1'b0;
            au_start <= 1'b0; au_play_en <= 1'b0; au_total <= 32'd0;
            au_werr <= 8'd0; au_wav_sel <= 1'b0;
            au_play_tgl <= 1'b0;
            au_writer_song <= 8'd0;
            au_writer_ahead <= 1'b0;
            au_wr_armed <= 1'b0;
        end else begin
            au_open_pulse <= 1'b0;                 // 都是 1 拍脉冲 ✓
            au_wh_start   <= 1'b0;
            au_start      <= 1'b0;
            if (au_end_pulse) begin
                au_play_tgl <= ~au_play_tgl;
                au_writer_ahead <= 1'b0;
            end
            if (au_to != 20'hFFFFF) au_to <= au_to + 20'd1;

            case (au_st)
            // 等**开机装载**全部收口（A1 之后它永远只做一次 ✓）⇒ 才碰 `hi` 通道 ✓
            // ★★ P2/S3-c：**不再"扫第一个 `file_type==1`"** ✗ —— 直接取**播放表给的 `wav_ft`** ✓
            //   理由：卡上**一旦有第二首** ✗，"扫第一个 type==1"选中的 WAV 与报表说的
            //   "当前第 1 首"**可能不是同一首** ✗ ⇒ **报表会说谎** ✗ ⇒ A1 的"报告行如实"当场不成立 ✗。
            //   ⇒ 播放表成为**唯一**的"放哪一首"来源 ✓（P1 的**画面**装载路径仍然不动 ✓）
            AU_IDLE: if (lf_st == LF_DONE) begin
                         au_idx <= 8'd0; au_wait <= 4'd4; au_to <= 20'd0;
                         if (pl_n == 8'd0) begin
                             au_werr <= AU_EC_NOWAV;       // 表里**没有可播的** ⇒ 如实报 ✓
                             au_st   <= AU_STOP;
                         end else begin
                              au_writer_song <= pl_cur;
                             au_open_idx   <= pl_wav_ft;   // ★ 表说放哪首就放哪首 ✓
                             au_open_pulse <= 1'b1;
                             au_wh_start   <= 1'b1;
                             au_st         <= AU_OPEN;
                         end
                     end
            // ★ S3-c 起 `AU_SCAN` **不再进入** ✗（保留状态号只为不改后续编码 ✓）—— 见 `AU_IDLE` ✓
            AU_SCAN: /* 已废弃 */ au_st <= AU_STOP;
            // 等 `fat32_read` 真正起来（`hi_open_busy` ✓）；起不来 ⇒ 超时报错 ✓
            AU_OPEN: if (au_hi_open_busy) begin au_to <= 20'd0; au_st <= AU_HDR; end
                     else if (au_to == 20'hFFFFF) begin
                         au_werr <= AU_EC_OPEN; au_st <= AU_STOP;
                     end
            // 解头：成 ⇒ 起环播放；败 ⇒ 报错误码并停 ✓
            AU_HDR:  if (wh_done) begin
                          if ((wh_err == 8'd0) && (wh_bytes[1:0] == 2'd0)) begin
                             au_total   <= wh_bytes;
                             au_play_en <= 1'b1;
                             // ★★ 步2c-5：**本曲起播**这一拍 ⇒ 通知 `clk_sdr` 把已播样本数归零 ✓
                             //   否则 `played_cnt` 从**复位**起数 ⇒ 多出"开机装载 + 开 WAV + 预充"
                             //   那段 ≈ 数秒的**常量偏移** ✗（板上表现为字幕与音乐整体不齐 ✓）
                              if (!au_wav_sel) au_play_tgl <= ~au_play_tgl;
                             au_start   <= 1'b1;
                              au_wr_armed <= 1'b0;
                             au_wav_sel <= 1'b1;       // ★ 音源切到 WAV ✓（此后 `tone_ready` 恒 0 ✓）
                             au_to <= 20'd0;
                             au_st  <= AU_PLAY;
                         end else begin
                             // 流本身坏了（SD 读错 ✓）⇒ 报 0x41；否则如实报解析码 ✓
                              au_werr <= au_hi_rd_err ? AU_EC_OPEN :
                                         (wh_bytes[1:0] != 2'd0) ? 8'h26 : wh_err;
                             au_st   <= AU_STOP;
                         end
                     end else if (au_to == 20'hFFFFF) begin
                         au_werr <= AU_EC_TO; au_st <= AU_STOP;
                     end
            // 播放中：等"最后一帧已放完"（`stream_end` ✓，跨域后取边沿 ✓）
             AU_PLAY: begin
                          if (!wp_wr_done) au_wr_armed <= 1'b1;
                          if (au_wr_armed && wp_wr_done) begin
                              au_to <= 20'd0;
                              au_st <= AU_DRAIN;
                          end
                      end
            // 收工：把文件尾巴丢弃读掉（让读流正常结束、`hi` 通道可再用 ✓）
            AU_DRAIN: if (au_hi_rd_eof || !au_hi_open_busy || (au_to == 20'hFFFFF)) begin
                          au_st <= AU_NEXT;
                     end
             AU_NEXT: if (!au_writer_ahead && !pl_busy && nx_vld &&
                         (pl_cur == au_writer_song)) begin
                          au_writer_song <= nx_song;
                          au_writer_ahead <= 1'b1;
                          au_open_idx <= nx_wav_ft;
                          au_open_pulse <= 1'b1;
                          au_wh_start <= 1'b1;
                          au_to <= 20'd0;
                          au_st <= AU_OPEN;
                      end
            // 终态：★ 2026-10-10 P5/A9 —— 这里就是原设计留的口 ✓（"S3 在这里接下一首" ✓）
            //   ★★★ 板上抓出的 bug ✗→✓：**原来这里判的是 `sw_req`** ✗
            //     `sw_req` 在 `au_end_pulse` 那拍就拉高过了 ✓，而 `AU_STOP` 要经
            //     `AU_DRAIN`（等文件尾读完 ✓）**过一会儿**才进 ✗ ⇒ 钩子那一拍**早已过去** ✗
            //     ⇒ 音频**永远回不到 `AU_IDLE`** ✗ ⇒ 板上现象：**字幕重放了、但没有声音** ✓✓
            //   ⇒ 改成判**挂起标志 `sw_pend`** ✓（它一直保持到被子这里用掉 ✓）
            AU_STOP: if (sw_pend) au_st <= AU_IDLE;
            default: au_st <= AU_STOP;
            endcase
        end
    end

    //=========================================================================
    // 2b) ★★ p3-lean 步2b：文本链（**口径 a —— 没有代理**，直接挂 SDRAM ✓）
    //   数据流：`lyric_pick`（每帧读一次 LRC 表、选 3 行）→ 描述符 → `layer_lyric`
    //           （每条扫描行取该行的字形行 → 行缓冲 → 像素域上色）→ `px_arb3` 的 **c2**
    //   ★ `lyric_pick` 挂 `sdram_arb` 的 **`ctl` 口**（唯一的 ctl 客户 ⇒ 无需仲裁器 ✓）
    //   ★ **无数据 / 表坏 / 读超时 ⇒ `tab_ok=0` ⇒ 三行 `vld=0` ⇒ 整层透明**
    //     ⇒ 画面与 P1/P2 **逐字节相同** ✓ —— 这是"接线不改变画面"那条回归判据的**根据** ✓
    //     （`lyric_pick.v` 的 magic 判据已改成 `!==` ⇒ 未初始化的 X 也给出确定的 `tab_ok=0` ✓）
    //=========================================================================
    // ★★ P4 Stage 3：频谱链的**实例**（`spec_fft` → `spec_bands` → `layer_fft`）
    //   · 放在**音频段之后** ✓（这里才能引用 `wav_tick`/`wp_l` ✓ —— 同一陷阱见下面那条注释 ✓）
    //   · 全链在 **clk_pix（25MHz）像素域** ✓ ⇒ **无 CDC** ✓
    //   · layer_fft 使用像素时钟推进扫描，输出无额外像素延迟，喂当前坐标。
    //   · en_fft 默认 1；显式关断时 ff_vld 恒 0。
    //   · ★ **不动 `px_arb3`** ✓：本链**不读 SDRAM** ⇒ 不加读客户端、不占仲裁带宽 ✓
    //=========================================================================
    // ---- ★ 活动像素坐标：**直接数 `de`** ✓（不猜消隐约定 ✓）⇒ x 0..639 ✓、y 0..479 ✓
    //      坐标系与 `layer_cover` 的 `win_x/win_y` 一致 ✓（都是"第几个有效像素/行" ✓）
    reg        cb_de_d;
    always @(posedge clk_pix or posedge rst_pix) begin
        if (rst_pix) begin
            ff_x <= 10'd0; ff_y <= 10'd0; cb_de_d <= 1'b0;
        end else begin
            cb_de_d <= cb_de;
            if (!cb_de) ff_x <= 10'd0;                      // 行内只在 de 高时数 ⇒ 首个有效像素 = 0 ✓
            else        ff_x <= (ff_x == 10'd639) ? ff_x : (ff_x + 10'd1);
            if (!cb_vs) ff_y <= 10'd0;                      // vs 低有效（场同步 ✓）⇒ 行号归零 ✓
            else if (!cb_de && cb_de_d)                     // de 下降沿 = 一行结束 ✓
                ff_y <= (ff_y == 10'd479) ? ff_y : (ff_y + 10'd1);
        end
    end

    wire            sp_frame_stb, sp_bin_stb;
    wire [8:0]      sp_bin_idx, sp_peak_bin;
    wire [7:0]      sp_bin_mag, sp_peak_val;
    wire            sp_samp_ready, sp_samp_valid, sp_window_overrun;
    wire signed [11:0] sp_samp;
    wire            sb_bar_stb, sb_bars_done;
    wire [5:0]      sb_bar_idx;
    wire [7:0]      sb_bar_level;
    wire            sa_band_stb, sa_hit;
    wire [4:0]      sa_band_idx, sa_hit_band;
    wire [7:0]      sa_band_level;
    reg [2:0] spec_song_sync;
    always @(posedge clk_pix) begin
        if (rst_pix) spec_song_sync <= 3'd0;
        else spec_song_sync <= {spec_song_sync[1:0], au_play_tgl};
    end
    wire spec_song_clear = spec_song_sync[2] ^ spec_song_sync[1];
    // Keep the board-approved FFT scale (78-count nonzero floor) for spectrum
    // and attack. Reconstruct the approved color-only excess exactly:
    // min(max(FFT_byte-78,0),110) == max(min(log_raw+145,255)-145,0).
    // The 110 clamp preserves the previous color saturation at 255-145.
    // Scale the mean by eight before the existing integer envelope smoothing.
    wire [7:0] env_bin_excess = (sp_bin_mag>=8'd188) ? 8'd110 :
        ((sp_bin_mag>8'd78) ? (sp_bin_mag-8'd78) : 8'd0);
    wire [8:0] env_loud_avg = env_sum[17:9];
    wire [11:0] env_loud_scaled = {env_loud_avg,3'b000};
    wire [7:0] env_loud_target = (env_loud_scaled>12'd255) ?
        8'd255 : env_loud_scaled[7:0];
    wire [8:0] env_loud_up_delta = {1'b0,env_loud_target} - {1'b0,env_loud_q8};
    wire [8:0] env_loud_dn_delta = {1'b0,env_loud_q8} - {1'b0,env_loud_target};
    wire [7:0] env_loud_up_step = env_loud_up_delta[8:1];
    wire [7:0] env_loud_dn_step = (env_loud_dn_delta[8:4] - env_loud_dn_delta[8:8]);
    wire [7:0] env_loud_next = (env_loud_target >= env_loud_q8) ?
        (env_loud_q8 + env_loud_up_step) :
        (env_loud_q8 - env_loud_dn_step);
    // Card WAV probe: accompaniment excess is about 3..6 counts, while
    // strong passages reach 16..19. In the x8 domain use 32..144.
    wire [8:0] env_rel_delta = (env_loud_next>8'd32) ?
        ({1'b0,env_loud_next}-9'd32) : 9'd0;
    wire [11:0] env_rel_scaled = (env_rel_delta<<1)+
                                  (env_rel_delta>>2)+(env_rel_delta>>5);
    wire [7:0] env_rel_raw = (env_loud_next<=8'd32) ? 8'd0 :
        (env_loud_next>=8'd144) ? 8'd255 :
        (env_rel_scaled>12'd255 ? 8'd255 : env_rel_scaled[7:0]);
    wire [8:0] env_rel_up_delta = {1'b0,env_rel_raw} - {1'b0,env_rel_q8};
    wire [8:0] env_rel_dn_delta = {1'b0,env_rel_q8} - {1'b0,env_rel_raw};
    wire [7:0] env_rel_up_step = (env_rel_up_delta>>3)+(env_rel_up_delta>>4);
    wire [7:0] env_rel_dn_step = (env_rel_dn_delta>>4)+(env_rel_dn_delta>>6);
    wire [7:0] env_rel_next = (env_rel_raw>=env_rel_q8) ?
        (env_rel_q8+env_rel_up_step) : (env_rel_q8-env_rel_dn_step);
    always @(posedge clk_pix) begin
        if (rst_pix || spec_song_clear) begin
            env_sum<=18'd0; env_loud_q8<=8'd0; env_rel_q8<=8'd0;
        end else begin
            if (sp_bin_stb) begin
                if (sp_bin_idx==9'd0) env_sum<=18'd0;
                else env_sum<=env_sum+{10'd0,env_bin_excess};
            end
            if (sp_frame_stb) begin
                env_loud_q8<=env_loud_next;
                env_rel_q8<=env_rel_next;
                env_sum<=18'd0;
            end
        end
    end
    spec_window u_spec_window (
        .clk(clk_pix), .rst_n(~rst_pix & ~spec_song_clear),
        .sample_valid(wp_valid), .sample_data(wp_raw_l[15:4]),
        .fft_ready(sp_samp_ready), .fft_valid(sp_samp_valid),
        .fft_sample(sp_samp), .window_overrun(sp_window_overrun)
    );
    spec_fft #(.N(1024), .SAMP_W(12), .FS_HZ(48000),
               .WINDOW_HANN(1), .LOG_MAG(1)) u_spec_fft (
        .clk       (clk_pix),
        .rst_n     (~rst_pix & ~spec_song_clear),
        .samp_stb  (sp_samp_valid),
        .samp_ready(sp_samp_ready),
        .samp      (sp_samp),
        .frame_stb (sp_frame_stb),
        .bin_stb   (sp_bin_stb),
        .bin_idx   (sp_bin_idx),
        .bin_mag   (sp_bin_mag),
        .peak_bin  (sp_peak_bin),
        .peak_val  (sp_peak_val)
    );

    spec_bands64 u_spec_bands (
        .clk       (clk_pix),
        .rst_n     (~rst_pix & ~spec_song_clear),
        .bin_stb   (sp_bin_stb),
        .bin_idx   (sp_bin_idx),
        .bin_mag   (sp_bin_mag),
        .frame_stb (sp_frame_stb),
        .bar_stb   (sb_bar_stb),
        .bar_idx   (sb_bar_idx),
        .bar_level (sb_bar_level),
        .bars_done (sb_bars_done),
        .attack_band_stb  (sa_band_stb),
        .attack_band_idx  (sa_band_idx),
        .attack_band_level(sa_band_level)
    );

    spec_attack18 u_spec_attack (
        .clk         (clk_pix),
        .rst_n       (~rst_pix & ~spec_song_clear),
        .band_stb    (sa_band_stb),
        .band_idx    (sa_band_idx),
        .band_level  (sa_band_level),
        .sensitivity (osd_sens_s2),
        .analysis_stb(sa_analysis_stb),
        .hit         (sa_hit),
        .hit_band    (sa_hit_band),
        .flux        (sa_flux),
        .threshold   (sa_threshold),
        .scope_max   (sa_scope_max),
        .hit_count   (sa_hit_count)
    );

    generate if (en_osd) begin : g_osd_picture
        wire [23:0] raster_rgb;
        wire raster_valid;
        reg [23:0] aligned_rgb;
        reg aligned_valid;
        // The scene path has a preparation register plus two blend stages.
        // Match those three stages using the original raster DE and X/Y.
        if(TYPOGRAPHY) begin : g_internal_align
            // The third stage now splits normalization from OSD drawing.
            always @(*) begin aligned_rgb=raster_rgb;aligned_valid=raster_valid;end
        end else begin : g_output_align
            always @(posedge clk_pix) begin
                if (rst_pix) begin aligned_rgb<=0; aligned_valid<=0; end
                else begin aligned_rgb<=raster_rgb; aligned_valid<=raster_valid; end
            end
        end
        assign osd_rgb=aligned_rgb;
        assign osd_vld=aligned_valid;
        if(TYPOGRAPHY) begin : g_small
        osd_layer_small #(.EXTENDED(VISUAL_CONTROLS)) u_osd_layer (
            .color_indices(visual_indices),.effects(effects),
            .transition_effect(transition_settings[1:0]),.transition_speed(transition_settings[3:2]),
            .swatch_index(swatch_index),.swatch_rgb(swatch_rgb),
            .clk(clk_pix),.rst(rst_pix),.de(cb_de),.x(ff_x),.y(CIRCULAR_UI ? ff_y+10'd32 : ff_y),
            .visible(osd_visible_sync[1]),.page(osd_page_s2),
            .selected(osd_selected_s2),.sensitivity(osd_sens_s2),
            .volume(osd_volume_s2),.sat_base(osd_sat_base_s2),
            .sat_max(osd_sat_max_s2),.con_base(osd_con_base_s2),
            .con_max(osd_con_max_s2),.sat_current(sat_current_pct),
            .con_current(con_current_pct),.loud(env_loud_q8),
            .relative(env_rel_q8),.analysis_stb(sa_analysis_stb),
            .attack_hit(sa_hit),.song_clear(spec_song_clear),
            .flux(sa_flux),.threshold(sa_threshold),.scope_max(sa_scope_max),
            .rgb(raster_rgb),.valid(raster_valid)
        );
        end else begin : g_legacy
        osd_layer u_osd_layer (
            .clk(clk_pix),.rst(rst_pix),.de(cb_de),.x(ff_x),.y(ff_y),
            .visible(osd_visible_sync[1]),.page(osd_page_s2),
            .selected(osd_selected_s2),.sensitivity(osd_sens_s2),
            .volume(osd_volume_s2),.sat_base(osd_sat_base_s2),
            .sat_max(osd_sat_max_s2),.con_base(osd_con_base_s2),
            .con_max(osd_con_max_s2),.sat_current(sat_current_pct),
            .con_current(con_current_pct),.loud(env_loud_q8),
            .relative(env_rel_q8),.analysis_stb(sa_analysis_stb),
            .attack_hit(sa_hit),.song_clear(spec_song_clear),
            .flux(sa_flux),.threshold(sa_threshold),.scope_max(sa_scope_max),
            .rgb(raster_rgb),.valid(raster_valid)
        );
        end
    end else begin : g_no_osd_picture
        assign osd_rgb=24'd0;
        assign osd_vld=1'b0;
    end endgenerate

    wire [23:0] spectrum_distance;
    generate if(CIRCULAR_UI) begin:g_circular_spectrum
    layer_spectrum_ring #(.USE_PRODUCT_RAM(SPLIT_UI),.CENTER_X(UI_CENTER_X),.CENTER_Y(UI_CENTER_Y)) u_layer_fft (
        .clk(clk_pix),.rst_n(~rst_pix & ~spec_song_clear),
        .bar_stb(sb_bar_stb),.bars_done(sb_bars_done),.bar_idx(sb_bar_idx),.bar_level(sb_bar_level),
        .frame_stb(fr_start),.attack_hit(sa_hit),.attack_band(sa_hit_band),
        .de(cb_de),.en(en_fft && effects[3]),.x(ff_x),.y(ff_y),
        .radius_distance(spectrum_distance),.target_color(color_spectrum),.spike_enable(effects[2]),
        .dout(ff_rgb),.dout_vld(ff_vld),.coverage(spectrum_coverage));
    end else begin:g_horizontal_spectrum
    layer_fft64 #(.DYNAMIC_COLORS(VISUAL_CONTROLS)) u_layer_fft (
        .target_color(color_spectrum),.spike_enable(effects[2]),
        .clk       (clk_pix),
        .rst_n     (~rst_pix & ~spec_song_clear),
        .bar_stb   (sb_bar_stb),
        .bars_done (sb_bars_done),
        .bar_idx   (sb_bar_idx),
        .bar_level (sb_bar_level),
        .frame_stb (fr_start),
        .attack_hit(sa_hit),
        .attack_band(sa_hit_band),
        .de        (cb_de),                     // ★ 与合成器同一个 `de` ✓
        .x         ({6'd0, ff_x}),              // ★ **当前**活动像素 ✓（不是延迟坐标 ✗）
        .y         ({6'd0, ff_y}),
        .en        (en_fft && effects[3]),                    // 0 时整层透明
        .dout      (ff_rgb),
        .dout_vld  (ff_vld)
    );

    end endgenerate

    cover_pop u_cover_pop (
        .clk(clk_pix),.rst(rst_pix || spec_song_clear || !effects[1]),
        .frame_tick(fr_start),.hit(sa_hit && en_fft && effects[1]),.level(cover_pop_level)
    );
    cover_pop_geom u_new_pop_geom (
        .x(cv_x),.y(cv_y),.w(cv_w),.h(cv_h),.level(cover_pop_level),
        .out_x(cv_pop_x),.out_y(cv_pop_y),.out_w(cv_pop_w),.out_h(cv_pop_h)
    );
    cover_pop_geom u_old_pop_geom (
        .x(ocv_x),.y(ocv_y),.w(ocv_w),.h(ocv_h),.level(cover_pop_level),
        .out_x(ocv_pop_x),.out_y(ocv_pop_y),.out_w(ocv_pop_w),.out_h(ocv_pop_h)
    );
    attack_rings #(.CENTER_X(UI_CENTER_X),.CENTER_Y(UI_CENTER_Y),
        .SHARED_DISTANCE(CIRCULAR_UI)) u_attack_rings (
        .geometry_rst(rst_pix),.radius_distance(spectrum_distance),
        .clk(clk_pix),.rst(rst_pix || spec_song_clear || !effects[0]),
        .frame_tick(fr_start),.hit(sa_hit && en_fft && effects[0]),
        .de(cb_de),.x(ff_x),.y(ff_y),.valid(ring_vld),.rgb(ring_rgb),
        .alpha(ring_alpha)
    );

    //   ★ 本段放在音频段**之后**：这里才能引用 `wav_tick`（`default_nettype none` 下不能先用后声明 ✓）
    //=========================================================================
    // ---- ① 48kHz 节拍跨域：clk_pix 的 `wav_tick` → clk_sdr 的 `samp_stb_sdr` ----
    //   单比特"翻转 + 2FF + 边沿检测" ✓（48kHz 翻转周期 ~20.8µs ≫ 两个时钟周期 ⇒ 不漏 ✓）
    reg sst_tgl;
    always @(posedge clk_pix) begin
        if (rst_pix)       sst_tgl <= 1'b0;
        else if (wav_tick) sst_tgl <= ~sst_tgl;
    end

    reg [2:0] sst_sync;
    always @(posedge clk_sdr) begin
        if (rst_sdr) sst_sync <= 3'd0;
        else         sst_sync <= {sst_sync[1:0], sst_tgl};
    end

    wire samp_stb_sdr = sst_sync[2] ^ sst_sync[1];

    // ---- ② 帧起点跨域：clk_pix 的 `fr_start` → clk_sdr 的 `pick_tick` ----
    reg fst_tgl;
    always @(posedge clk_pix) begin
        if (rst_pix)       fst_tgl <= 1'b0;
        else if (fr_start) fst_tgl <= ~fst_tgl;
    end

    reg [2:0] fst_sync;
    always @(posedge clk_sdr) begin
        if (rst_sdr) fst_sync <= 3'd0;
        else         fst_sync <= {fst_sync[1:0], fst_tgl};
    end

    wire pick_tick = fst_sync[2] ^ fst_sync[1];

    // ---- ③ 已播样本计数（24 位；本曲最大 13,556,448 < 2^24 ✓）**这是全系统的时基** ✓ ----
    // ---- ★★ 步2c-5：起播归零（跨域：`clk` 的 `au_play_tgl` → `clk_sdr` 边沿检测 ✓）----
    reg [2:0] pt_sync;
    always @(posedge clk_sdr) begin
        if (rst_sdr) pt_sync <= 3'd0;
        else         pt_sync <= {pt_sync[1:0], au_play_tgl};
    end
    wire song_start = pt_sync[2] ^ pt_sync[1];

    reg [23:0] played_cnt;
    always @(posedge clk_sdr) begin
        if (rst_sdr)           played_cnt <= 24'd0;
        else if (song_start)   played_cnt <= 24'd0;          // ★ 本曲起播 ⇒ 归零 ✓
        else if (samp_stb_sdr) played_cnt <= played_cnt + 24'd1;
    end

    // ---- ③b 累计已播秒数（48kHz 节拍比较+清零 ⇒ **零除法器** ✓）——`AUD T=` 的来源 ✓ ----
    reg [15:0] samp_in_sec;
    reg [31:0] sec_cnt;
    always @(posedge clk_sdr) begin
        if (rst_sdr) begin
            samp_in_sec <= 16'd0;
            sec_cnt     <= 32'd0;
        end else if (song_start) begin                 // ★ 步2c-5：同 `played_cnt` 一起归零 ✓
            samp_in_sec <= 16'd0;
            sec_cnt     <= 32'd0;
        end else if (samp_stb_sdr) begin
            if (samp_in_sec == 16'd47999) begin
                samp_in_sec <= 16'd0;
                sec_cnt     <= sec_cnt + 32'd1;
            end else begin
                samp_in_sec <= samp_in_sec + 16'd1;
            end
        end
    end

    // ---- ④ `lyric_pick`：每帧选行（表坏/超时 ⇒ 三行全无效 ⇒ 整层透明 ✓ 不黑屏 ✓）----
    wire        lp_busy, lp_done, lp_tab_ok;
    wire [7:0]  lp_err;
    wire [15:0] lp_nlines;
    wire [15:0] lp_cur_idx, lp_nxt_idx, lp_n3_idx;
    wire [23:0] lp_cur_s, lp_nxt_s, lp_n3_s;
    wire [15:0] lp_cur_fc, lp_nxt_fc, lp_n3_fc;
    wire [15:0] lp_cur_cnt, lp_nxt_cnt, lp_n3_cnt;
    wire        lp_cur_vld, lp_nxt_vld, lp_n3_vld;
    wire [15:0] lp_prev2_fc,lp_prev2_cnt,lp_prev_fc,lp_prev_cnt,lp_n4_fc,lp_n4_cnt;
    wire lp_prev2_vld,lp_prev_vld,lp_n4_vld;
    wire [15:0] lp_prev3_fc,lp_prev3_cnt,lp_n5_fc,lp_n5_cnt;
    wire lp_prev3_vld,lp_n5_vld;
    wire [15:0] lp_ttl_fc, lp_ttl_cnt, lp_sgr_fc, lp_sgr_cnt;
    wire        lp_ttl_vld, lp_sgr_vld;
    wire [5:0]  lp_off_px;
    wire        lp_scroll_on;
    reg         lyric_visible, lrc_slot_seen;
    always @(posedge clk_sdr) begin
        if (rst_sdr) begin
            lrc_slot_sync <= 2'd0;
            lrc_ok_sync <= 2'd0;
            lrc_slot_seen <= 1'b0;
            lyric_visible <= 1'b0;
        end else begin
            lrc_slot_sync <= {lrc_slot_sync[0], lrc_slot};
            lrc_ok_sync <= {lrc_ok_sync[0], ft_lok};
            lrc_slot_seen <= lrc_slot_sync[1];
            if (lrc_slot_seen != lrc_slot_sync[1]) lyric_visible <= 1'b0;
            else if (lp_done) lyric_visible <= 1'b1;
        end
    end

    lyric_pick #(
        // ★ 槽位新址（2026-10-06 步2c-3 避重叠）：FONT `0xE1000` / ASC `0x120E40` / LRC **`0x121440`**
        //   （三处都是 4 字对齐 ⇒ 满足读定律 ✓；与图像槽零重叠 ✓）
        //   ★★ L1H（**板上"GALA 变密织方块"的真凶**）：LRC 原写 `0x121040` ✗ ——
        //      ASC 槽 = `0x120E40` + 6,144B/4 = **1,536 字** ⇒ 跨到 `0x121440` ✓
        //      而 LRC 起点只晚 **512 字** ⇒ **把 ASC 后 1,024 字（asq≥32 ⇔ 码≥0x40）覆盖成歌词表** ✗
        //      ⇒ 'G'(0x47) 'A'(0x41) 'L'(0x4C) 全被覆盖 ⇒ 读表数据 ⇒ **密织方块** ✓
        //        而 '-' (0x2D)、空格 (0x20) 在 0x40 以下 ⇒ 完好 ✓ —— 与板上照片**逐字对上** ✓
        //      单元台查不出：TB 里 LRC/ASC 是各自独立的数组 ✗，不存在重叠 ✓
        //      ⇒ 修法：LRC 挪到 **`0x121440`**（紧贴 ASC 之后 ✓，与 BG/CV 各槽无冲突 ✓）
        .LRC_BASE (TEXT_LRC_BASE), .SLOT_MAX (64),
        .CLK_HZ   (SDR_CLK_MHZ * 1000000), .WD_MS (4),
        .SC_SAMP  (14400),      .SC_PX (SPLIT_UI ? 32 : TYPOGRAPHY ? 36 : 38), .CONTEXT(SPLIT_UI ? 2 : TYPOGRAPHY)
    ) u_pick (
        .clk_sdr (clk_sdr), .rst_sdr_n (~rst_sdr),
        .tick (pick_tick), .samp_stb (samp_stb_sdr), .played (played_cnt),
        .busy (lp_busy), .done (lp_done), .err (lp_err), .tab_ok (lp_tab_ok), .n_lines (lp_nlines),
        .cur_idx (lp_cur_idx), .nxt_idx (lp_nxt_idx), .n3_idx (lp_n3_idx),
        .cur_s (lp_cur_s), .nxt_s (lp_nxt_s), .n3_s (lp_n3_s),
        .cur_fc (lp_cur_fc), .nxt_fc (lp_nxt_fc), .n3_fc (lp_n3_fc),
        .cur_cnt (lp_cur_cnt), .nxt_cnt (lp_nxt_cnt), .n3_cnt (lp_n3_cnt),
        .cur_vld (lp_cur_vld), .nxt_vld (lp_nxt_vld), .n3_vld (lp_n3_vld),
        .prev3_fc(lp_prev3_fc),.prev3_cnt(lp_prev3_cnt),.prev3_vld(lp_prev3_vld),
        .n5_fc(lp_n5_fc),.n5_cnt(lp_n5_cnt),.n5_vld(lp_n5_vld),
        .prev2_fc(lp_prev2_fc),.prev2_cnt(lp_prev2_cnt),.prev2_vld(lp_prev2_vld),
        .prev_fc(lp_prev_fc),.prev_cnt(lp_prev_cnt),.prev_vld(lp_prev_vld),
        .n4_fc(lp_n4_fc),.n4_cnt(lp_n4_cnt),.n4_vld(lp_n4_vld),
        .ttl_fc (lp_ttl_fc), .ttl_cnt (lp_ttl_cnt), .ttl_vld (lp_ttl_vld),
        .sgr_fc (lp_sgr_fc), .sgr_cnt (lp_sgr_cnt), .sgr_vld (lp_sgr_vld),
        .off_px (lp_off_px), .scroll_on (lp_scroll_on),
        .px_req (lp_px_req), .px_addr (lp_px_addr_raw), .px_len (lp_px_len),
        .px_ack (lp_px_ack), .px_done (lp_px_done), .px_data (lp_px_data), .px_valid (lp_px_valid)
    );

    // ---- ⑤ 描述符更新脉冲（翻转位；`layer_lyric` 用 2FF 边沿捕获 ✓）----
    reg lp_desc_tgl;
    always @(posedge clk_sdr) begin
        if (rst_sdr)      lp_desc_tgl <= 1'b0;
        else if (lp_done) lp_desc_tgl <= ~lp_desc_tgl;
    end

    // ---- ⑥ 歌词层（内部例化 `lyric_row`；px 口 = `px_arb3` 的 c2 ✓）----
    // 表状态来自 SDR 域，字库状态来自 50 MHz 域；显示使能只在像素域使用。
    reg lyric_ready_sdr;
    reg [1:0] lyric_ready_pix_sync, font_ready_pix_sync;
    always @(posedge clk_sdr) begin
        if (rst_sdr) lyric_ready_sdr <= 1'b0;
        else lyric_ready_sdr <= lp_tab_ok & lrc_ok_sync[1] & lyric_visible;
    end
    always @(posedge clk_pix) begin
        if (rst_pix) begin
            lyric_ready_pix_sync <= 2'b00;
            font_ready_pix_sync <= 2'b00;
        end else begin
            lyric_ready_pix_sync <= {lyric_ready_pix_sync[0], lyric_ready_sdr};
            font_ready_pix_sync <= {font_ready_pix_sync[0], ft_fok};
        end
    end
    wire lyric_enable_pix = lyric_ready_pix_sync[1] & font_ready_pix_sync[1];
    //   `en = lp_tab_ok`：表不可用 ⇒ 整层透明（**也顺带挡住取数** ✓）
    generate if(TYPOGRAPHY) begin : g_aa_text
    // Circular layout: centered metadata, shared cover/ring center and one
    // current lyric row. The established typography pipeline is reused.
    layer_text_aa #(.VALIDATED_LYRICS(SPLIT_UI),.LRC_SMALL(SPLIT_UI),.V_ACT_DLY(35),.WIN_Y0(SPLIT_UI ? 166 : CIRCULAR_UI ? 448 : 118),
        .WIN_H(SPLIT_UI ? 216 : CIRCULAR_UI ? 24 : 167),.ROW_Y0(SPLIT_UI ? 262 : CIRCULAR_UI ? 448 : 190),
        .PITCH(SPLIT_UI ? 32 : 36),.LAST_GAP_TRIM(SPLIT_UI ? 0 : 1),.BOX_X(SPLIT_UI ? 336 : CIRCULAR_UI ? 96 : 336),
        .BOX_W(SPLIT_UI ? 288 : CIRCULAR_UI ? 448 : 288),.TTL_Y0(SPLIT_UI ? 82 : CIRCULAR_UI ? 16 : 45),
        .SGR_Y0(SPLIT_UI ? 116 : CIRCULAR_UI ? 44 : 77),.SINGLE_LINE(CIRCULAR_UI && !SPLIT_UI),.SEVEN_LINES(SPLIT_UI),.CENTER_METADATA(CIRCULAR_UI),
        .DYNAMIC_COLORS(VISUAL_CONTROLS),.FIVE_LINES(!CIRCULAR_UI),
        .LRC_X(SPLIT_UI ? 340 : CIRCULAR_UI ? 96 : 296),.LRC_W(SPLIT_UI ? 280 : CIRCULAR_UI ? 448 : 336),
        .LRC_BASE(21'h10B300),.FONT_BASE(21'h10BBB0),
        .SPP(1200),.HOLD_N(24000),.CLK_HZ(SDR_CLK_MHZ*1000000)) u_lyr (
        .alpha(text_alpha),
        .color_title(color_title),.color_singer(color_singer),
        .color_sung(color_sung),.color_other(color_other),
        .clk_pix (clk_pix), .rst_pix_n (~rst_pix), .hs (cb_hs), .vs (cb_vs), .de (cb_de),
        // ★★ p3-lean 步2c-3（**板上抓出**）：没字库就**别画** ✗
        //   板上实测过：字库没装上时，字形区里还是**第三组背景的图像数据** ⇒
        //   画出来是"密织状方块" ✗ —— 看上去像渲染 bug，其实只是"没素材" ✗。
        //   `ft_fok`（FONT 装好）当门 ⇒ 失败时**整层透明（诚实的空白）** ✓，与 `FONT OK=0` 互相印证 ✓
        // ★★★ P5/A9 S2b（2026-10-11）：**再加 `ft_lok`** ✗→✓ … ★★ **当天晚些时候回退** ✗→✓
        //   【为什么加】想保证"字幕一定是**当前这首歌**的" ✓
        //   【★★ 为什么必须撤掉】板上串口日志证明它是**帮凶** ✗：
        //     切歌风暴 ⇒ 播放表重扫被 SD 读口挤住 ⇒ `pl_lrc_vld` 瞬变 0 ✗
        //       ⇒ 我的 S2b 立刻把 `ft_lok` 清 0 ✗ ⇒ ★ **整层歌词被关掉、再也回不来** ✓✓
        //     而**同一份日志**里 `LYR CUR` 还在 0→1→2→3→4 正常推进 ✓
        //       ⇒ ★ **歌词表是好的、取数也正常** ✓ —— 纯粹是被这一位**误杀** ✗
        //   【结论】这道门**弊远大于利** ✗：宁可**短暂显示旧的一行** ✓（本就只有几十毫秒 ✓），
        //     也**绝不能**因为一个瞬态把字幕**永久关掉** ✗✓
        //     ★ 老口径 `lp_tab_ok & ft_fok` 是**板上验证过**的 ✓ ⇒ 回到它 ✓
        .en (lyric_enable_pix),
        // ★★ L1M 并层：歌名/歌手用**同一门槛**（表和字库都得在 ⇒ 否则不出字、诚实的空白 ✓）
        .en_ttl (lyric_enable_pix),
        .dout (ly_rgb), .dout_vld (ly_vld), .gap_cnt (ly_gap), .on_cnt (ly_on),
        .ttl_off (ly_ttl_off),
        .clk_sdr (clk_sdr), .rst_sdr_n (~rst_sdr), .played (played_cnt),
        .cur_fc (lp_cur_fc), .nxt_fc (lp_nxt_fc), .n3_fc (lp_n3_fc),
        .cur_cnt (lp_cur_cnt), .nxt_cnt (lp_nxt_cnt), .n3_cnt (lp_n3_cnt),
        .cur_vld (lp_cur_vld), .nxt_vld (lp_nxt_vld), .n3_vld (lp_n3_vld),
        .prev3_fc(lp_prev3_fc),.prev3_cnt(lp_prev3_cnt),.prev3_vld(lp_prev3_vld),
        .n5_fc(lp_n5_fc),.n5_cnt(lp_n5_cnt),.n5_vld(lp_n5_vld),
        .prev2_fc(lp_prev2_fc),.prev2_cnt(lp_prev2_cnt),.prev2_vld(lp_prev2_vld),
        .prev_fc(lp_prev_fc),.prev_cnt(lp_prev_cnt),.prev_vld(lp_prev_vld),
        .n4_fc(lp_n4_fc),.n4_cnt(lp_n4_cnt),.n4_vld(lp_n4_vld),
        .song_clear(lrc_slot_seen!=lrc_slot_sync[1]),
        .off_px (lp_off_px), .desc_tgl (lp_desc_tgl),
        // ★★ L1M 并层：跑马灯时基 + 歌名/歌手描述符（`lyric_pick` 本来就在输出 ✓ 零改动 ✓）
        .samp_stb (samp_stb_sdr),
        .ttl_fc (lp_ttl_fc), .ttl_cnt (lp_ttl_cnt), .ttl_vld (lp_ttl_vld),
        .sgr_fc (lp_sgr_fc), .sgr_cnt (lp_sgr_cnt), .sgr_vld (lp_sgr_vld),
        .px_req (c2_req), .px_addr (c2_addr_raw), .px_len (c2_len),
        .px_ack (c2_ack), .px_done (c2_done), .px_data (c2_data), .px_valid (c2_valid)
    );
    end else begin : g_legacy_text
        assign text_alpha=4'd0;
    layer_text #(
        .H_ACT_DLY (144), .V_ACT_DLY (35), .V_ACT_LIN (480),
        .WIN_Y0 (396), .WIN_H (76), .ROW_Y0 (404),
        // ★ 槽位新址（步2c-3 避重叠）：与装载器、`lyric_pick` **三处必须一致** ✗
        .LRC_BASE (21'h121440), .FONT_BASE (21'hE1000), .ASC_BASE (21'h120E40),
        // ★★ L1M 并层：歌名/歌手版面 —— 照旧版**冻结值**显式写出（便于一眼核对 ✓）
        .BOX_X (32), .BOX_W (160), .TTL_Y0 (13), .SGR_Y0 (41),
        .MAX_CH_L (19), .MAX_CH_T (24), .SPP (1200), .HOLD_N (24000),
        .CLK_HZ (SDR_CLK_MHZ * 1000000)
    ) u_lyr (
        .clk_pix (clk_pix), .rst_pix_n (~rst_pix), .hs (cb_hs), .vs (cb_vs), .de (cb_de),
        // ★★ p3-lean 步2c-3（**板上抓出**）：没字库就**别画** ✗
        //   板上实测过：字库没装上时，字形区里还是**第三组背景的图像数据** ⇒
        //   画出来是"密织状方块" ✗ —— 看上去像渲染 bug，其实只是"没素材" ✗。
        //   `ft_fok`（FONT 装好）当门 ⇒ 失败时**整层透明（诚实的空白）** ✓，与 `FONT OK=0` 互相印证 ✓
        // ★★★ P5/A9 S2b（2026-10-11）：**再加 `ft_lok`** ✗→✓ … ★★ **当天晚些时候回退** ✗→✓
        //   【为什么加】想保证"字幕一定是**当前这首歌**的" ✓
        //   【★★ 为什么必须撤掉】板上串口日志证明它是**帮凶** ✗：
        //     切歌风暴 ⇒ 播放表重扫被 SD 读口挤住 ⇒ `pl_lrc_vld` 瞬变 0 ✗
        //       ⇒ 我的 S2b 立刻把 `ft_lok` 清 0 ✗ ⇒ ★ **整层歌词被关掉、再也回不来** ✓✓
        //     而**同一份日志**里 `LYR CUR` 还在 0→1→2→3→4 正常推进 ✓
        //       ⇒ ★ **歌词表是好的、取数也正常** ✓ —— 纯粹是被这一位**误杀** ✗
        //   【结论】这道门**弊远大于利** ✗：宁可**短暂显示旧的一行** ✓（本就只有几十毫秒 ✓），
        //     也**绝不能**因为一个瞬态把字幕**永久关掉** ✗✓
        //     ★ 老口径 `lp_tab_ok & ft_fok` 是**板上验证过**的 ✓ ⇒ 回到它 ✓
        .en (lyric_enable_pix),
        // ★★ L1M 并层：歌名/歌手用**同一门槛**（表和字库都得在 ⇒ 否则不出字、诚实的空白 ✓）
        .en_ttl (lyric_enable_pix),
        .dout (ly_rgb), .dout_vld (ly_vld), .gap_cnt (ly_gap), .on_cnt (ly_on),
        .ttl_off (ly_ttl_off),
        .clk_sdr (clk_sdr), .rst_sdr_n (~rst_sdr), .played (played_cnt),
        .cur_fc (lp_cur_fc), .nxt_fc (lp_nxt_fc), .n3_fc (lp_n3_fc),
        .cur_cnt (lp_cur_cnt), .nxt_cnt (lp_nxt_cnt), .n3_cnt (lp_n3_cnt),
        .cur_vld (lp_cur_vld), .nxt_vld (lp_nxt_vld), .n3_vld (lp_n3_vld),
        .off_px (lp_off_px), .desc_tgl (lp_desc_tgl),
        // ★★ L1M 并层：跑马灯时基 + 歌名/歌手描述符（`lyric_pick` 本来就在输出 ✓ 零改动 ✓）
        .samp_stb (samp_stb_sdr),
        .ttl_fc (lp_ttl_fc), .ttl_cnt (lp_ttl_cnt), .ttl_vld (lp_ttl_vld),
        .sgr_fc (lp_sgr_fc), .sgr_cnt (lp_sgr_cnt), .sgr_vld (lp_sgr_vld),
        .px_req (c2_req), .px_addr (c2_addr_raw), .px_len (c2_len),
        .px_ack (c2_ack), .px_done (c2_done), .px_data (c2_data), .px_valid (c2_valid)
    );
    end endgenerate

    //=========================================================================
    // 6) LED / 观测（都在 50MHz 域，跨域信号已同步）
    //=========================================================================
    reg [24:0] hb;
    reg [2:0]  lk_sr;                        // O_video_locked → clk
    always @(posedge clk) begin
        if (!rst_n) begin hb <= 25'd0; lk_sr <= 3'd0; end
        else begin hb <= hb + 25'd1; lk_sr <= {lk_sr[1:0], O_video_locked}; end
    end

    reg [1:0] sdr_init_sync;
    always @(posedge clk) begin
        if (!rst_n) sdr_init_sync <= 2'b00;
        else        sdr_init_sync <= {sdr_init_sync[0], sdr_init_done};
    end
    assign led[0] = sdr_init_sync[1];        // SDRAM 初始化完成
    assign led[1] = lk_sr[2];                // HDMI 核锁定
    assign led[2] = sd_ready;                // SD 文件表就绪（同域）
    assign led[3] = en_cwp ? cwp_phase : hb[24];   // ★ en_cwp=1 ⇒ "探针正在写"（防假阴性 ✓）；否则心跳

endmodule

`default_nettype wire
