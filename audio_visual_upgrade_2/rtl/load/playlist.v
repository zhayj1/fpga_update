`default_nettype none
//============================================================================
// rtl/load/playlist.v —— 播放表（★ P2/S3-a ✓）：把卡上**平铺的文件**聚合成"首" ✓
//
// 【它是什么】`storage_top` 只给"240 个平铺的 8.3 文件" ✓（`design:49` C1 ✓），
//   **卡里根本没有"歌"这个东西** ✗ —— "一首歌"只存在于**文件名前缀**这个隐含约定里 ✓
//   （`design:802`：「分组规则：`S<2 位序号>` + 后缀」✓）。
//   本模块把这个隐含约定变成**一张显式索引** ✓，让"第 N 首"成为**可查、可判、可上报**的东西 ✓。
//
// 【三个角色（`doc/workitem_p2_s3.md` §2 ✓）】
//   ① 命名约定 → 显式索引（曲目实体化 ✓）
//   ② **可播性判定与分诊** ✓ —— 缺项/尺寸不符 ⇒ 该首标"不可播"并上报，
//      **不影响其它首** ✓（`design:714` 逐字 ✓）⇒ 这是 **A1**"播放表 ≥1 首 + 报告行如实"的落点 ✓
//   ③ 当前曲目指针 + **"下一首"的唯一来源** ✓（卡上没有顺序 ✗，FAT32 目录顺序 ≠ 曲目顺序 ✗）
//
// 【分组规则（三条，缺一不可 ✓）】
//   ① 分组键 = 名字**前缀** `S` + 2 位数字 ✓
//      ★ 字节序有硬证据 ✓：`file_table.v:26`「`[87:80]` = 第 0 字节（名字首字符）」
//        ⇒ 第 i 字节 = `file_name >> (8*(10-i))` ✓（装载器 `skeleton_core.v:644-652`
//          的相邻字节搜索用的就是这个序 ✓，且**板上已验** ✓）
//      ★ 由此**天然拒掉** `SM01BG.BMP`（`S` 后是 `M` ✗ 不是数字 ✓）、`ASC.HZK`、`HZK32H.HZK` ✓
//   ② 首内分工：**类型为主、名字为辅** ✓
//        `file_type==1` ⇒ WAV ✓、`file_type==2` ⇒ LRC ✓（★ 存储层的文件表**本来就带类型** ✓，
//        `workitem_p2_s2.md:152` 已核 ✓）；`file_type==0` 且名含 `BG`/`CV` ⇒ BG_n / CV_n ✓
//        （n = 后随那位数字 ✓，同装载器 ✓）
//      ★ `BG`/`CV` 必须**按相邻字节搜索** ✓ —— 先例：装载器早期按"固定位置"比，
//        **仿真过、板上一个都认不出** ✗（`mk_sim_image.py:82-85` ✓）⇒ 这里照装载器办 ✓
//   ③ **必需项按阶段分层** ★（P2 的关键口径 ✓）：
//        P2 必需 = **BG1/2/3 齐 + CV1/2/3 齐 + 1 个 WAV** ✓；**LRC 在 P2 非必需** ✓
//        （缺 ⇒ `lrc_ft=0`、**仍可播** ✓；P3 起才升为必需 ✓）
//      依据：`design:714` 字面把 LRC 列为必需 ✗，而 LRC 要到 **P3** 才做 ✗
//        ⇒ 照字面实现会把卡上这首（**确实没有 `S01.LRC`** ✓）判成不可播 ⇒ **A1 当场挂** ✗；
//        而 `design:716` 已给口径「**LRC 坏 ⇒ 只显示歌名歌手**」✓ ⇒ 缺 LRC **不阻断播放** ✓。
//
// 【不占总线 ✓】它**复用唯一那个文件表索引口** ✓（`skeleton_core.v:511` ✓ —— 开机给装载器、
//   `LF_DONE` 之后给音频链 ✓）：本模块只是**主动驱动 `index`**，顶层用 `lf_st` 选路 ✓
//   ⇒ **不新增任何总线口** ✓。★ 音频链的起播门就是 `lf_st == LF_DONE` ✓（`AU_IDLE` ✓ `:946` ✓）
//   ⇒ **表没扫完，音频链自动等** ✓，无时序风险 ✓。
//   代价：≤288 拍清表 + ≤240 次索引 × 5 拍 ≈ **1500 拍 = 30µs** ✓（开机器件 ✓ 可忽略 ✓）。
//
// 【逐文件判定（每个文件恰 1 拍 ✓）】先判前缀 ⇒ 再按类型/名字落字段 ⇒ 重复出现**以表里第一个为准** ✓
//   ★★ 尺寸口径（**S3-c 集成时更正** ✗→✓，理由见 `doc/workitem_p2_s3.md` §11-S3c ✓）：
//     · 本表**只判"超槽"**（`> BMP_MAX_BYTES` ⇒ `0x64` ✓，防越界是硬要求 ✓）
//     · **几何契约（是否满屏 640×480）交回装载器** ✓ —— `bmp_load` 的 `hchk_err` 本来就查 ✓，
//       装不上 ⇒ `g_ok=0` ⇒ 该组无效 ✓（单一职责 ✓ 不重复 ✗）
//     · ★ 硬理由：仿真镜像里的 BMP 是**故意做小**的测试素材（30KB/246B ✗）⇒ 若把"正好 921,654"
//       算进不可播，**整机仿真里那首歌永远是 0 首可播** ✗ ⇒ **A1 就再也测不了** ✗
//     · 原 `0x63`（BG 尺寸不符）**作废** ✗（如实登记，见工单 ✓）
//
// 【首号超出容量】`song_no > MAX_SONG` ⇒ **只计数（`skip_cnt`）并跳过** ✓ —— **不算错误** ✗
//   （可能只是别的文件碰巧前缀像 ✓；若记成错误会误伤 A1 的"报告行如实" ✗）。
//
// 【错误码（8 位 `{大类[7:4], 细码[3:0]}`，沿用 `sd_err_code`/`wav_head` 风格 ✓）】
//   0x60 缺 BG ✓ / 0x61 缺 CV ✓ / 0x62 缺 WAV ✓ / 0x64 尺寸超槽 ✓
//   ★ `0x63`（BG 尺寸不符）**已作废** ✗ —— 几何契约交回装载器 ✓（见上面那条口径 ✓）
//   0x71 **表里 0 首可播** ✓（A1 判据"≥1 首"看的就是它 ✓）
//
// 【存储（写死 ✓）】首号槽 = 32 ✓（`FILE_MAX=240` ⇒ 每首 8 文件 ⇒ 最多 30 首 ✓ `design:802` ✓）
//   · `pl_data[0:287]`：地址 = `首号*8 + 字段号`（0..2=BG1..3 ✓、3..5=CV1..3 ✓、6=WAV ✓、7=LRC ✓）
//     ★ Verilog-2001 **只允许一维非打包数组** ✗ ⇒ 用扁平数组 + 地址算式 ✓
//   · `err_arr[0:35]`：每首一个错误码 ✓
//   · 共 ≈320 B ⇒ 落成小 RAM/寄存器 ✓（判据：**不许落成大片 LUT** ✗）
//
// 【本模块的语言口径】**纯 Verilog-2001** ✓：不用 `$clog2` ✗、不用多维非打包数组 ✗、
//   不用 `logic`/`always_ff` ✗（数组地址一律用显式位宽 ✓）。
//
// 【与 S2 的口径不冲突 ✓】`LF ST=7` 稳态不变 ✓（顶层新状态取 8 ✓，`LF_DONE` 仍 7 ✓）。
//============================================================================
module playlist #(
    parameter integer MAX_SONG      = 16,        // 首号槽 ✓（★ S3-c 由 32 收到 16 ✗：`design:43` 就是"约 16 首" ✓，且**少占布线** ✓）
    parameter integer BG_BYTES      = 921654,    // 满屏 BG 的**契约尺寸** ✓（640*480*3+54 ✓，卡上实测 ✓）
                                                 // ★ S3-c 起**不参与判决** ✗：几何契约交回装载器 ✓
                                                 //   保留它只为把"素材契约"记在接口上 ✓（见文件头口径 ✓）
    parameter integer BMP_MAX_BYTES = 921654,    // 槽容量 230,400 字 = 921,600 B + 54 头 ✓
    // ★★★ 2026-10-10：**CV 槽容量上限**（比 BG 小 ✓）—— A9 零延迟预装要腾地方 ✓
    //   【为什么】地图装不下 4 组**满屏**槽 ✗（4 组要 460,800 字，而现状只腾得出 ~260,096 ✗）
    //     而真实封面 **384,054 B** ⇒ 只有满屏槽的一半 ✓ ⇒ 收紧 CV 上限即可 ✓
    //   【值怎么来的】**不是拍的** ✗ —— 由 `scripts/check_sdram_map.py` 校验 ✓：
    //     新布局把 CV3 挪进 `0x1225A0..0x14FFFF` 那条缝 ✓，缝宽 **186,976 字** ✗
    //     （★ 我口算成 187,040 ✗ 差 64 字 ⇒ **护栏当场抓到重叠** ✓ ⇒ 别心算 ✓）
    //     取圆整 **184,320 字（0x2D000）** ✓ 留 2,656 字余量 ✓
    //     BMP 行按 4 字节对齐，而 SDRAM 行按 16 字节对齐；文件大小不能直接当槽占用。
    //     穷举允许的宽高后，732,121 B 是不超过 184,320 字槽的最大文件上限。
    //   【代价（必须记账 ✗）】更大的封面会被**拒绝**（`0x64` ✓ 不是静默越界 ✓）
    //     ★ 卡上真封面 384,054 B ⇒ 只有上限的一半 ✓ ⇒ 对现有素材**零影响** ✓
    parameter integer CV_BYTES      = 732121,
    parameter integer WAIT_CYCLES   = 4,         // 换 `index` 后等几拍（同装载器 ✓）
    parameter integer SCAN_MAX      = 255        // 索引口是 8 位 ⇒ 最多扫 256 项 ✓（`FILE_MAX=240` ✓）
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---------------- 扫描控制 ----------------
    input  wire        scan_start,       // 脉冲：开始扫（顶层在 `LF_LIST` 入口给 ✓）
    output reg         scan_busy,        // 扫描中 ✓
    output reg         scan_done,        // 脉冲：扫完 ✓

    // ---------------- 文件表（← `storage_top` ✓）----------------
    input  wire [8:0]  file_total,       // 文件总数 ✓（`FILE_MAX=240` ✓）
    input  wire [87:0] file_name,        // 11 字节 8.3 名 ✓（[87:80] = 第 0 字节 ✓）
    input  wire [1:0]  file_type,
    // ★★★ P5/A9（2026-10-10）：**从第几首开始当"当前首"** ✓
    //   `0` = 老口径（取**第一个可播** ✓，与今天逐位相同 ✓）
    //   `!=0` = 切歌后重扫时给**下一首的首号** ✓ ⇒ 当前首直接落到它身上 ✓
    //   ★ 为什么收这个而不是"下一首脉冲"：切歌后**必须重扫** ✗（新首的 8 个索引都要换 ✗），
    //     而重扫已经有一条现成的路（`scan_start` ✓）⇒ 只需告诉它"从哪儿起" ✓
    //   ★ `cnt_i` 仍从 **1** 起扫 ✓（否则 `song_total` 会漏计前面的首 ✗ ⇒ 报表 `PL N=` 会说谎 ✗）
    //     ⇒ 只对"**谁当当前首**"这一件事生效 ✓
    input  wire [7:0]  start_from,        // 0=BMP / 1=WAV / 2=LRC / 3=未知 ✓
    input  wire [31:0] file_size,        // 字节数 ✓
    output reg  [7:0]  index,            // → 文件表索引口（顶层选路 ✓）

    // ---------------- 结果 ----------------
    output reg  [7:0]  song_total,       // **可播**首数 ✓（→ 报文 `PL N=` ✓）
    output reg  [7:0]  song_cur,         // 当前首号（= **第一个可播首** ✓；0 = 无可播 ✓）
    output reg  [7:0]  pl_err,           // **首条**不可播首的错误码 ✓（0 = 全可播 ✓；0x71 = 0 首可播 ✓）
    // 当前首（= `song_cur`）的素材下标 ✓
    output reg  [7:0]  wav_ft,           // ★ 音频链取它 ✓（S3-c ✓）
    output reg  [7:0]  bg_ft1, bg_ft2, bg_ft3,
    output reg  [7:0]  cv_ft1, cv_ft2, cv_ft3,
    output reg  [7:0]  lrc_ft,           // P2 只登记不消费 ✓
    // ★★★ 2026-10-10 新增：**当前首到底有没有 LRC 文件** ✓
    //   【为什么必须单独给一位，而不是让上层判 `lrc_ft != 0`】✗
    //     `lrc_ft` 是**文件表索引** ✓，而 **0 是合法索引** ✗ ——
    //     真卡实测 `BGF1=0`（`BOARD_LOG_20261010.md` ✓）已证明"合法文件可以排在第 0 个" ✓
    //     ⇒ 若某首歌的 `.LRC` 恰好是第 0 个，上层就会把它**误判成"没有歌词"** ✗
    //       （顶层原来正是这么判的：`if (pl_lrc_ft != 8'd0)` ✗ —— 已改 ✓）
    //   【本模块本来就`知道`】内部有 `seen_lrc[首号]` ✓（扫描时置位 ✓，与索引数值无关 ✓）
    //     ⇒ 直接引出来即可 ✓（1 位、0 BRAM ✓）
    output reg         lrc_vld,
    // ★★★ 2026-10-10（P5/A9）：「**下一首**」的 BG1 / CV1 文件表索引 ＋ 有效位 ✓
    //   【干什么用】A9 零延迟切歌要求：本首还在放时，**下一首的 g1（背景＋封面）已经预装进 SDRAM** ✓
    //     ⇒ 预装只需要「**索引 ＋ 目标槽**」✓ —— ★ 图像装载器 `bmp_load` 本来就是**按索引装**的 ✓
    //       （`skeleton_core.v:1114 ld_idx <= lf_scan;` ✓ —— 开机扫名字只是**为了求出索引** ✗）
    //     ⇒ 与歌词表装载同一手法 ✓（`ft_idx <= pl_lrc_ft` ✓ 零扫描 ✓）
    //   ★ 为什么不由上层判"索引 0 就是没有" ✗：索引 0 是**合法文件索引** ✗
    //     （真卡实测 `BGF1=0` ✓ 见 `BOARD_LOG_20261010.md` ✓）⇒ 必须独立给 **`nx_vld`** ✓
    //   ★ `nx_song` 用 0 表示"没有下一首" ✓ —— 那是**首号**（从 1 起 ✓），不是文件表索引 ✓，安全 ✓
    output reg         nx_vld,
    output reg  [7:0]  nx_bg1,
    output reg  [7:0]  nx_cv1,
    // ★★★ P5/A9（2026-10-10 用户纠正 ✗→✓）：**一套逻辑覆盖所有 N** ✓
    //   边界之后新首要被读的是**三组** ✓ ⇒ g2/g3 也必须补装 ✓
    //   ⇒ 播放表要一次把下一首的 **6 个索引**都给出来 ✓（不只 g1 ✗）
    output reg  [7:0]  nx_bg2,
    output reg  [7:0]  nx_cv2,
    output reg  [7:0]  nx_bg3,
    output reg  [7:0]  nx_cv3,    // ★★★ P5/A9：**下一首的首号**（`0` = 没有下一首 ✓）—— 切歌重扫时用它当 `start_from` ✓
    //   ★ 它是**首号（从 1 起）** ✓，与"文件表索引 0 是合法文件"**无关** ✗（别混 ✓）
    output reg  [7:0]  nx_song,
    output reg  [7:0]  nx_wav_ft,
    output reg  [7:0]  nx_lrc_ft,
    output reg         nx_lrc_vld,
    // ---------------- 观测（报文 ✓）----------------
    output reg  [7:0]  skip_cnt,         // 被跳过的文件数（前缀不合法/超容量/与曲目无关 ✓）
    output reg  [7:0]  song_max          // 扫到的最大首号（观测 ✓）
);

    //=========================================================================
    // 0) 参数常数（显式位宽 ⇒ 比较不靠隐式扩展 ✓）
    //=========================================================================
    localparam [31:0] BG_BYTES_C = BG_BYTES[31:0];
    localparam [31:0] BMP_MAX_C  = BMP_MAX_BYTES[31:0];
    localparam [31:0] CV_MAX_C   = CV_BYTES[31:0];      // ★ 2026-10-10：CV 槽上限（比 BG 小 ✓）
    localparam [7:0]  MAX_SONG_C = MAX_SONG[7:0];

    localparam integer PDEPTH = 136;     // ★ 16 首 × 8 + 8 ✓（最大地址 16*8+7 = 135 ✓）
    localparam integer EDEPTH = 17;     // ★ 16 首 + 1 ✓

    //=========================================================================
    // 1) 存储（扁平数组 + 地址算式 ✓ Verilog-2001 ✓）
    //=========================================================================
    reg [7:0] pl_data [0:PDEPTH-1];
    reg [7:0] err_arr [0:EDEPTH-1];

    // 每首"见过哪些字段"（1 bit/首 ✓ 用向量 ✓）
    reg [MAX_SONG:0] seen_bg1, seen_bg2, seen_bg3;
    reg [MAX_SONG:0] seen_cv1, seen_cv2, seen_cv3;
    reg [MAX_SONG:0] seen_wav, seen_lrc;
    // ★★★ 2026-10-10（P5/A9）：**下一首可播首**的捕获（在 `P_CNT` 里顺手记 ✓）
    //   ★ `nx_song` 现在是**输出端口** ✓ ⇒ 这里**不再重复声明** ✗
    //     （重复会报 `vlog-2388 already declared` ✗ —— 实测 ✓）
    reg              nx_found;
    // ★★★ P5/A9 **循环播放**：本趟扫到的**第一个可播首**（回绕目标 ✓）
    //   ★ 只在 P_CNT 里置一次 ✓；**不受 start_from 影响** ✗（回绕永远回全局第一首 ✓）
    reg  [7:0]       fst_play;
    reg  [2:0]       nx_cnt;            // P_NX 的两个读拍 ✓

    //=========================================================================
    // 2) 名字解码（组合 ✓ 与装载器同一手法 ✓）
    //=========================================================================
    wire [7:0] b0 = file_name[87:80];    // 第 0 字节 = 名字首字符 ✓（`file_table.v:26` ✓）
    wire [7:0] b1 = file_name[79:72];
    wire [7:0] b2 = file_name[71:64];

    function isdig;                       // '0'..'9' ✓
        input [7:0] c;
        begin isdig = (c >= 8'h30) && (c <= 8'h39); end
    endfunction

    // ★ 分组键：**前缀** `S` + 2 位数字 ✓（前缀就是设计规定的分组规则 ✓ `design:802` ✓）
    wire        is_song = (b0 == 8'h53) && isdig(b1) && isdig(b2);
    wire [7:0]  d_t     = b1 - 8'h30;                // 十位（0..9 ✓）
    wire [7:0]  d_u     = b2 - 8'h30;                // 个位（0..9 ✓）
    // ★★ `song_no = 10*十位 + 个位` —— **必须写成移位加** ✗✗
    //   【S3-c 实测教训 ✓】原来写 `d_t * 8'd10` ✗ ⇒ TD 落了一个 **`MULT18`** ✗
    //     ⇒ clk0 最差路径 = `file_name → MULT18 → ADDER → err_arr 写口` ✗，
    //       实测 **`Data Path Delay 19.882ns` / slack `−0.162ns` / 10 个违例端点** ✗✗
    //     —— 与本工程 `skeleton_core.v:575` 记的 **`bm_img_w*3` 落 MULT18** ✗ 是**同一个坑** ✓。
    //   `10x = 8x + 2x = (x<<3) + (x<<1)` ✓ 等价、且**无乘法器** ✓
    wire [7:0]  song_no = (d_t << 3) + (d_t << 1) + d_u;
    wire        song_ok = is_song && (song_no >= 8'd1) && (song_no <= MAX_SONG_C);
    wire [8:0]  pbase   = {1'b0, song_no} << 3;      // 首号*8 ✓（≤ 32 ⇒ ≤ 256 ✓）

    // ★ `BG`/`CV` 按**相邻字节搜索** ✓（不许固定位置 ✗ —— `mk_sim_image.py:82-85` 的教训 ✓）
    reg        bg_hit, cv_hit;
    reg  [7:0] bg_d,   cv_d;             // 后随那位字符（约定 = 组号数字 ✓）
    integer    k;
    always @* begin
        bg_hit = 1'b0; cv_hit = 1'b0; bg_d = 8'h30; cv_d = 8'h30;
        for (k = 0; k <= 8; k = k + 1) begin      // 需 k+2 ≤ 10 ✓（避免负移位 ✗）
            if (((file_name >> (8 * (10 - k))) & 8'hFF) == 8'h42 &&      // 'B'
                ((file_name >> (8 * (9  - k))) & 8'hFF) == 8'h47) begin  // 'G'
                bg_hit = 1'b1;
                bg_d   = (file_name >> (8 * (8 - k))) & 8'hFF;
            end
            if (((file_name >> (8 * (10 - k))) & 8'hFF) == 8'h43 &&      // 'C'
                ((file_name >> (8 * (9  - k))) & 8'hFF) == 8'h56) begin  // 'V'
                cv_hit = 1'b1;
                cv_d   = (file_name >> (8 * (8 - k))) & 8'hFF;
            end
        end
    end

    wire        bg_grp_ok = bg_hit && (bg_d >= 8'h31) && (bg_d <= 8'h33);   // 组号 1..3 ✓
    wire        cv_grp_ok = cv_hit && (cv_d >= 8'h31) && (cv_d <= 8'h33);
    wire [1:0]  bg_f      = bg_d - 8'h31;            // 0..2 ⇒ 字段 0..2 ✓
    wire [1:0]  cv_f      = cv_d - 8'h31;            // 0..2 ⇒ 字段 3..5 ✓
    wire [8:0]  cv_addr   = pbase + 9'd3 + {7'd0, cv_f};

    //=========================================================================
    // 2b) ★★ 名字解码的**寄存器化**（S3-c 构建实测后加 ✗→✓）
    //   【为什么】TD 实测 clk0（50MHz）最差路径 = **整条**：
    //     `文件表 BRAM → file_name[72] → ×10 乘法/移位加 → bg/cv 九次相邻字节搜索
    //      → 分首分支 → err_arr 写口` ✗ —— `Data Path Delay 19.882ns` / 12 级逻辑 ✗
    //     （去掉 MULT18 反而更差 ✗：`clk0 −0.722ns / 24 个违例端点` ✗ ⇒ 瓶颈是**这条链**本身 ✗）
    //   【修法】在 `P_WAIT` 的等待期就把解码**结果**打进寄存器 ✓
    //     ⇒ 关键路径被切成两段**都很短**：① `file_name → 解码 → 寄存器` ✓
    //       ② `寄存器 → 分首分支/译码 → err_arr/pl_data 写口` ✓
    //   ★ 语义等价 ✓：文件名/类型在等待期是**稳定**的 ✓（换 `index` 后等 4 拍才准 ✓）
    //=========================================================================
    reg        r_is_song, r_song_ok, r_bg_ok, r_cv_ok;
    reg [7:0]  r_song_no;
    reg [1:0]  r_bg_f, r_cv_f;
    wire [8:0] pb_r    = {1'b0, r_song_no} << 3;         // 首号*8 ✓（寄存器版 ✓）
    wire [8:0] cv_addr_r = pb_r + 9'd3 + {7'd0, r_cv_f};

    //=========================================================================
    // 3) 逐首最终判定 ★★ **必须顺序做（每拍一首）** ✗，不许写成组合大循环 ✗✗
    //   【S3-c 实测教训（2026-10-05 ✓）】原实现用 `always @*` + `for (si=1..32)` 一次算完 ✗
    //     ⇒ TD 综合出 **32 级串联加法器**（`song_total = song_total + 1` 串成链 ✗）
    //       + 32 路宽比较/优先链 ✗ ⇒ **clk0（50MHz）从 `+0.755ns` 掉到 `−0.327ns`** ✗✗
    //       （实测 `final_timing.rpt` ✓：clk1/clk3 没动 ✓、clk2/clk4 厂商 PHY 一字不变 ✓）
    //     ⇒ 改成在 FSM 里**每拍判一首**（`P_CNT`，32 拍 = 640ns ✓ 一次性开销 ✓）
    //       ⇒ 关键路径只剩"一拍一首"的短逻辑 ✓
    //   ★ 同理：`exists`/`e8c` 是**当拍算完就用**的局部量 ✓（阻塞赋值 ✓），不是跨拍状态 ✓
    //=========================================================================
    reg        any_song;                 // ★ 扫到过**至少一个合法首号** ✓（决定 0x71 ✓）
    reg  [6:0] cnt_i;                    // 定案用的首号游标（1..MAX_SONG ✓）
    reg        exists;                   // 该首号**有没有文件命中** ✓（当拍局部量 ✓）
    reg  [7:0] e8c;                      // 该首的错误码 ✓（当拍局部量 ✓）

    //=========================================================================
    // 4) 扫描状态机
    //=========================================================================
    // ★★★ 2026-10-10：**加宽一位** ✗→✓ —— 0..7 已用满，P5/A9 要加 `P_NX` ✓
    localparam [3:0] P_IDLE = 4'd0, P_CLR = 4'd1, P_WAIT = 4'd2, P_DEC = 4'd3,
                     P_FIN  = 4'd4, P_READ = 4'd5, P_DONE = 4'd6,
                     P_CNT  = 4'd7,      // ★ S3-c：**逐首顺序定案**（每拍一首 ✓ 见 §3 的教训 ✓）
                     // ★ P5/A9（2026-10-10）：搬「**下一首**」的 g1 索引（2 拍 ✓）
                     //   为什么单开一个状态：`nx_song` 要到 `P_CNT` **最后一拍**才稳定 ✗
                     //   ⇒ 不能在 `P_READ` 那一趟里同一拍多读一个地址 ✗
                     //     （★ 那会要 `pl_data` 的**第二个读口** ⇒ 综合器复制 RAM ⇒
                     //       `PHY-9013 emb 67 > 64` ✗ —— 本工程在 Step 0 上真踩过 ✓）
                     P_NX   = 4'd8;

    reg  [3:0]  p_st;
    reg [8:0]  clr_cnt;
    reg [2:0]  wait_cnt;
    reg [2:0]  rd_cnt;

    reg [2:0] nx_field;
    always @* begin
        case (nx_cnt)
        3'd0: nx_field = 3'd0;
        3'd1: nx_field = 3'd3;
        3'd2: nx_field = 3'd1;
        3'd3: nx_field = 3'd4;
        3'd4: nx_field = 3'd2;
        default: nx_field = nx_cnt;
        endcase
    end
    wire [7:0] read_song = (p_st == P_READ) ? song_cur : nx_song;
    wire [2:0] read_field = (p_st == P_READ) ? rd_cnt : nx_field;
    wire [8:0] read_addr = ({1'b0, read_song} << 3) + {6'd0, read_field};
    wire [7:0] read_value = pl_data[read_addr];

    // 索引口 8 位 ⇒ 最多扫 256 项 ✓（`FILE_MAX=240` ✓；超了也只扫到 256 ✓ 不越界 ✓）
    wire [8:0] scan_end = (file_total > (SCAN_MAX[8:0] + 9'd1)) ? (SCAN_MAX[8:0] + 9'd1)
                                                                : file_total;
    wire       idx_last = (index >= (scan_end - 9'd1));

    integer    q;
    // ★ S3-c 起**不再需要** `cur_base` ✗ —— 地址在 `P_READ` 里用 `song_cur` 现算 ✓
    //   （原先在 `P_FIN` 打拍会吃到 `song_cur` 的**当拍旧值** ✗）

    always @(posedge clk) begin
        if (!rst_n) begin
            p_st        <= P_IDLE;
            index       <= 8'd0;
            scan_busy   <= 1'b0;
            scan_done   <= 1'b0;
            clr_cnt     <= 9'd0;
            wait_cnt    <= 3'd0;
            rd_cnt      <= 3'd0;
            cnt_i       <= 7'd1;
            skip_cnt    <= 8'd0;
            song_max    <= 8'd0;
            any_song    <= 1'b0;
            song_total  <= 8'd0;
            song_cur    <= 8'd0;
            pl_err      <= 8'd0;
            wav_ft      <= 8'd0;
            bg_ft1 <= 8'd0; bg_ft2 <= 8'd0; bg_ft3 <= 8'd0;
            cv_ft1 <= 8'd0; cv_ft2 <= 8'd0; cv_ft3 <= 8'd0;
            lrc_ft      <= 8'd0;
            lrc_vld     <= 1'b0;        // ★ 2026-10-10：与 `lrc_ft` 同批复位 ✓
            // ★★★ P5/A9（2026-10-10）：下一首的捕获与索引 —— **必须复位** ✗
            //   （今天已在 `bmp_load` 的 `tr1` 上踩过"漏复位 ⇒ x ⇒ 判据恒假"✓）
            nx_song     <= 8'd0;
            nx_wav_ft   <= 8'd0;
            nx_lrc_ft   <= 8'd0;
            nx_lrc_vld  <= 1'b0;
            nx_found    <= 1'b0;
            fst_play    <= 8'd0;
            nx_cnt      <= 3'd0;
            nx_vld      <= 1'b0;
            nx_bg1      <= 8'd0;
            nx_cv1      <= 8'd0;
            nx_bg2      <= 8'd0; nx_cv2 <= 8'd0;
            nx_bg3      <= 8'd0; nx_cv3 <= 8'd0;
            seen_bg1 <= 0; seen_bg2 <= 0; seen_bg3 <= 0;
            seen_cv1 <= 0; seen_cv2 <= 0; seen_cv3 <= 0;
            seen_wav <= 0; seen_lrc <= 0;
            // ★★ L1M-d 实测（2026-10-07）：**撤掉这一行救不了分布式 RAM** ✗ ——
            //   删掉它之后 TD **仍然**把 `pl_data` 推断成 DRAM ✓（面积表 `bram` 仍 = 0 ✗）
            //   而且 `u_playlist` 的 lut 还涨了（970 → **1,012** ✗）⇒ **已撤回** ✓
            //   ⇒ 拦路石不是这一行 ✗，而是**读写口的形状**（8 个条件读口 + 多个条件写口 ✗）；
            //     真要 BRAM 必须显式重构（单写口 + 单读口 + 目的地译码 ✓），那是正经手术 ✓
            //     —— 记在这里，免得下次再从这一行试起 ✓
            for (q = 0; q < PDEPTH; q = q + 1) pl_data[q] <= 8'd0;
            for (q = 0; q < EDEPTH; q = q + 1) err_arr[q] <= 8'd0;
        end else begin
            scan_done <= 1'b0;

            case (p_st)
            //--------------- 等开工 ✓ ---------------
            P_IDLE: if (scan_start) begin
                        seen_bg1 <= 0; seen_bg2 <= 0; seen_bg3 <= 0;
                        seen_cv1 <= 0; seen_cv2 <= 0; seen_cv3 <= 0;
                        seen_wav <= 0; seen_lrc <= 0;
                        skip_cnt <= 8'd0;
                        song_max <= 8'd0;
                        any_song <= 1'b0;
                        err_arr[0] <= 8'd0;      // 其余由 P_CLR 逐拍清 ✓
                        clr_cnt  <= 9'd0;
                        index    <= 8'd0;
                        scan_busy<= 1'b1;
                        p_st     <= P_CLR;
                    end
            //--------------- 清表（≈288 拍 ✓）★ 扫之前必须清 ✓ ---------------
            P_CLR: begin
                       pl_data[clr_cnt] <= 8'd0;
                       if (clr_cnt < EDEPTH[8:0]) err_arr[clr_cnt[5:0]] <= 8'd0;
                       if (clr_cnt == (PDEPTH - 1)) begin
                           clr_cnt <= 9'd0;
                           // ★ 空表短路 ✓：没有文件 ⇒ 直接定案（不解读任何数据 ✗）
                           if (scan_end == 9'd0) begin
                               p_st <= P_FIN;
                           end else begin
                               wait_cnt <= WAIT_CYCLES[2:0];
                               p_st     <= P_WAIT;
                           end
                       end else begin
                           clr_cnt <= clr_cnt + 9'd1;
                       end
                   end
            //--------------- 等数据（换 index 后 ✓，同装载器 ✓）---------------
            //   ★★ S3-c：**在等待期就把解码结果打拍** ✓ —— 见 §2b 的关键路径说明 ✓
            P_WAIT: begin
                        r_is_song <= is_song;
                        r_song_ok <= song_ok;
                        r_song_no <= song_no;
                        r_bg_ok   <= bg_grp_ok;
                        r_bg_f    <= bg_f;
                        r_cv_ok   <= cv_grp_ok;
                        r_cv_f    <= cv_f;
                        if (wait_cnt != 3'd0) wait_cnt <= wait_cnt - 3'd1;
                        else                  p_st     <= P_DEC;
                    end
            //--------------- 判定**当前文件** ✓（1 拍 ✓）---------------
            P_DEC: begin
                       if (!r_song_ok) begin
                           // (a) 分组键不合法 / 超容量 ⇒ **跳过，不算错误** ✗ ✓
                           skip_cnt <= skip_cnt + 8'd1;
                       end else begin
                           any_song <= 1'b1;
                           if (song_max < r_song_no) song_max <= r_song_no;
                           // (b) 落字段 ✓（同一字段重复出现 ⇒ **以表里第一个为准** ✓）
                           if (file_type == 2'd1) begin                       // WAV ✓
                               if (!seen_wav[r_song_no]) begin
                                   pl_data[pb_r + 9'd6] <= index;
                                   seen_wav[r_song_no] <= 1'b1;
                               end
                           end else if (file_type == 2'd2) begin              // LRC ✓
                               if (!seen_lrc[r_song_no]) begin
                                   pl_data[pb_r + 9'd7] <= index;
                                   seen_lrc[r_song_no] <= 1'b1;
                               end
                           end else if (file_type == 2'd0 && r_bg_ok) begin // BG_n ✓
                               if (r_bg_f == 2'd0) begin
                                   if (!seen_bg1[r_song_no]) begin
                                       seen_bg1[r_song_no] <= 1'b1;
                                       if (file_size <= BMP_MAX_C) pl_data[pb_r + 9'd0] <= index;
                                       else                        err_arr[r_song_no] <= 8'h64;  // 超槽 ✓
                                   end
                               end else if (r_bg_f == 2'd1) begin
                                   if (!seen_bg2[r_song_no]) begin
                                       seen_bg2[r_song_no] <= 1'b1;
                                       if (file_size <= BMP_MAX_C) pl_data[pb_r + 9'd1] <= index;
                                       else                        err_arr[r_song_no] <= 8'h64;
                                   end
                               end else begin
                                   if (!seen_bg3[r_song_no]) begin
                                       seen_bg3[r_song_no] <= 1'b1;
                                       if (file_size <= BMP_MAX_C) pl_data[pb_r + 9'd2] <= index;
                                       else                        err_arr[r_song_no] <= 8'h64;
                                   end
                               end
                           end else if (file_type == 2'd0 && r_cv_ok) begin // CV_n ✓
                               if (r_cv_f == 2'd0) begin
                                   if (!seen_cv1[r_song_no]) begin
                                       seen_cv1[r_song_no] <= 1'b1;
                                       if (file_size <= CV_MAX_C) pl_data[cv_addr_r] <= index;   // ★ CV 上限（比 BG 小 ✓）
                                       else                        err_arr[r_song_no] <= 8'h64;
                                   end
                               end else if (r_cv_f == 2'd1) begin
                                   if (!seen_cv2[r_song_no]) begin
                                       seen_cv2[r_song_no] <= 1'b1;
                                       if (file_size <= CV_MAX_C) pl_data[cv_addr_r] <= index;   // ★ CV 上限（比 BG 小 ✓）
                                       else                        err_arr[r_song_no] <= 8'h64;
                                   end
                               end else begin
                                   if (!seen_cv3[r_song_no]) begin
                                       seen_cv3[r_song_no] <= 1'b1;
                                       if (file_size <= CV_MAX_C) pl_data[cv_addr_r] <= index;   // ★ CV 上限（比 BG 小 ✓）
                                       else                        err_arr[r_song_no] <= 8'h64;
                                   end
                               end
                           end else begin
                               skip_cnt <= skip_cnt + 8'd1;                    // 与曲目无关 ✓（字库/其它 BMP ✓）
                           end
                       end
                       // (c) 下一个文件 / 收尾 ✓
                       if (idx_last) begin
                           p_st <= P_FIN;
                       end else begin
                           index    <= index + 8'd1;
                           wait_cnt <= WAIT_CYCLES[2:0];
                           p_st     <= P_WAIT;
                       end
                   end
            //--------------- 定案：**逐首顺序数**（★ 见 §3 的教训：不许组合大循环 ✗）---------------
            P_FIN: begin
                       song_total <= 8'd0;
                       song_cur   <= 8'd0;
                       pl_err     <= 8'd0;
                       cnt_i      <= 7'd1;
                       rd_cnt     <= 3'd0;
                       // ★★★ P5/A9（2026-10-10）：**每趟扫描都要清这两个** ✗
                       //   不清 ⇒ 第二次扫描（切歌重扫 ✓）会沿用上一趟的"下一首" ✗
                       nx_found   <= 1'b0;
                       fst_play   <= 8'd0;
                       nx_song    <= 8'd0;
                       p_st       <= P_CNT;
                   end
            //--------------- 每拍判**一首**（32 拍 = 640ns ✓）---------------
            P_CNT: begin
                       // 该首"是否存在" = 至少一个文件命中它的前缀 ✓
                       //   ★ 不存在的槽**必须跳过** ✗ —— 否则空槽会被当成"缺 BG" ⇒ `pl_err` 恒 0x60 ✗
                       exists = seen_bg1[cnt_i] | seen_bg2[cnt_i] | seen_bg3[cnt_i] |
                                seen_cv1[cnt_i] | seen_cv2[cnt_i] | seen_cv3[cnt_i] |
                                seen_wav[cnt_i] | seen_lrc[cnt_i];
                       e8c = 8'd0;
                       if (exists) begin
                           if (err_arr[cnt_i] != 8'd0)                                     e8c = err_arr[cnt_i];
                           else if (!(seen_bg1[cnt_i] && seen_bg2[cnt_i] && seen_bg3[cnt_i])) e8c = 8'h60;  // 缺 BG ✓
                           else if (!(seen_cv1[cnt_i] && seen_cv2[cnt_i] && seen_cv3[cnt_i])) e8c = 8'h61;  // 缺 CV ✓
                           else if (!seen_wav[cnt_i])                                         e8c = 8'h62;  // 缺 WAV ✓
                           // 可播 ⇒ 计数 ✓；不可播 ⇒ 记**首条**错误码 ✓
                            if (e8c == 8'd0) begin
                                song_total <= song_total + 8'd1;
                                // ★ 2026-10-10：`start_from != 0` ⇒ 只认它之后的第一个可播 ✓
                                //   （切歌重扫时把"当前首"推到下一首 ✓；`cnt_i` 仍从 1 起扫 ✓
                                //     ⇒ `song_total` 不会漏计 ⇒ 报表 `PL N=` 不会说谎 ✓）
                                if ((song_cur == 8'd0) &&
                                    ((start_from == 8'd0) || ({1'b0, cnt_i} >= start_from)))
                                    song_cur <= {1'b0, cnt_i};
                                // ★★★ 2026-10-10（P5/A9）**循环播放**：记住**第一个可播首** ✓
                                //   【用户口径】「有多少首歌，先依次播放，播放完最后一首再回到第一首」✓
                                //     ⇒ 单首歌时就是**它自己循环** ✓
                                //   ★ **不受 `start_from` 影响** ✗ —— 回绕目标永远是**全局第一个可播** ✓
                                //     （若被它影响：从第 2 首起扫时回绕目标会变成第 2 首 ⇒ 永远漏掉第 1 首 ✗）
                                if (!fst_play) fst_play <= {1'b0, cnt_i};
                                // ★ 「**再下一个**可播首」顺手记下 ✓（`P_CNT` 本来就在逐首判可播 ✓）
                                //   ★ `nx_song` 是**首号（从 1 起）** ✓，与"文件表索引 0 是合法文件"**无关** ✗
                                if ((song_cur != 8'd0) && !nx_found) begin
                                    nx_song  <= {1'b0, cnt_i};
                                    nx_found <= 1'b1;
                                end
                            end else if (pl_err == 8'd0) begin
                                pl_err <= e8c;
                            end
                        end
                        if (cnt_i >= MAX_SONG_C[6:0]) begin
                            if (!any_song) pl_err <= 8'h71;   // **一个首都没有** ⇒ 0x71 ✓
                            // ★★★ 2026-10-10（P5/A9）**回绕** ✓：末首之后 ⇒ 回到**第一首** ✓
                            //   ⇒ 单首歌：`nx_song` 变成它自己 ⇒ **自己循环** ✓（用户口径 ✓）
                            if (!nx_found) nx_song <= fst_play;
                            p_st <= P_READ;                       end else begin
                           cnt_i <= cnt_i + 7'd1;
                       end
                   end
            //--------------- 搬当前首的素材下标（8 拍 ✓）---------------
            //   ★ 地址在**这里**才算 ✓ —— `song_cur` 到这一拍已经稳定 ✗（P_CNT 最后一拍才写它 ✓）
            P_READ: begin
                       if (rd_cnt == 3'd0)      bg_ft1 <= read_value;
                       else if (rd_cnt == 3'd1) bg_ft2 <= read_value;
                       else if (rd_cnt == 3'd2) bg_ft3 <= read_value;
                       else if (rd_cnt == 3'd3) cv_ft1 <= read_value;
                       else if (rd_cnt == 3'd4) cv_ft2 <= read_value;
                       else if (rd_cnt == 3'd5) cv_ft3 <= read_value;
                       else if (rd_cnt == 3'd6) wav_ft <= read_value;
                       else                     lrc_ft <= read_value;
                       // ★★★ 2026-10-10：**"有没有 LRC"必须独立给出** ✓（不能用 `lrc_ft != 0` 判 ✗）
                       //   与 `lrc_ft` 同一拍发布 ✓；取自内部 `seen_lrc[首号]` ✓（扫描时置位 ✓
                       //   与索引数值无关 ✓）⇒ **索引 0 也是合法文件** 这件事就不再被误判 ✓
                       lrc_vld <= seen_lrc[song_cur];
                       if (rd_cnt == 3'd7) p_st <= P_NX;
                       else                rd_cnt <= rd_cnt + 3'd1;
                   end
            //--------------- ★ P5/A9：搬「下一首」的 g1 索引（2 拍 ✓）---------------
            //   只读**两个**地址：`pl_data[nx_song*8 + 0]`（BG1 ✓）与 `+3`（CV1 ✓）
            //   ★ 一拍只读一个地址 ✓ —— 保住 `pl_data` 的**单读口** ✓（否则 BRAM 不够 ✗）
            //   ★ `nx_vld` 与 `lrc_vld` 同一手法 ✓：**独立给出"有没有下一首"** ✗
            //     （不许让上层用"索引 == 0"判 ✗ —— 索引 0 是合法文件 ✓）
            P_NX:  begin
                       // ★★ 2026-10-10 修正 ✗：**不许把它 gates 在 nx_found 上** ✗
                       //   回绕时 nx_found = 0 ✓ 但 nx_song 已被改成**第一首**（是有效的 ✓）
                       //   gates 了 ⇒ **不读** ⇒ nx_bg1 留着上一场的旧值 ✗
                       //   （实测：单首卡那一场读到 7 ✗ —— 那是上一场 S02 的索引 ✓ 应为 0 ✓）
                       // ★ 改判据为 fst_play != 0 ✓：只要卡上有可播首，回绕目标就一定有效 ✓
                       if (fst_play != 8'd0) begin
                           // ★ 6 拍搬完下一首的 6 个索引 ✓（g1/g2/g3 各 BG+CV ✓）
                           if      (nx_cnt == 3'd0) nx_bg1 <= read_value;
                           else if (nx_cnt == 3'd1) nx_cv1 <= read_value;
                           else if (nx_cnt == 3'd2) nx_bg2 <= read_value;
                           else if (nx_cnt == 3'd3) nx_cv2 <= read_value;
                           else if (nx_cnt == 3'd4) nx_bg3 <= read_value;
                           else if (nx_cnt == 3'd5) nx_cv3 <= read_value;
                           else if (nx_cnt == 3'd6) nx_wav_ft <= read_value;
                           else begin
                               nx_lrc_ft  <= read_value;
                               nx_lrc_vld <= seen_lrc[nx_song];
                           end
                       end
                       if (nx_cnt == 3'd7) begin
                           nx_cnt <= 3'd0;
                           nx_vld <= (fst_play != 8'd0);   // ★ P5/A9：口径是「有地方可去」（至少一首可播 ✓）—— 不是「有下一首」✗
                           p_st   <= P_DONE;
                       end else begin
                           nx_cnt <= nx_cnt + 3'd1;
                       end
                   end
            //--------------- 收工 ✓ ---------------
            P_DONE: begin
                        scan_done <= 1'b1;
                        scan_busy <= 1'b0;
                        p_st      <= P_IDLE;
                    end
            default: p_st <= P_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
