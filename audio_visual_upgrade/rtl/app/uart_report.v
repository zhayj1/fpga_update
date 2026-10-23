`default_nettype none
//=============================================================================
// rtl/app/uart_report.v —— 把骨架的运行状态按行打到 UART（115200 8N1）
//
// 报文（每行 CRLF 结尾，'~' 表示"此处插入一个十进制数"，按出现顺序取字段）：
//   ★★ 下面的**标签**已按 2026-10-04 的改名更新 ✓（原 P0 标签与实际值的对照表见下方长注 ✓）
//   MUSIC P1 SKELETON
//   SDR INIT=~        字段0 ：sdr_init        (0/1)
//   LF ST=~           字段1 ：装载状态号 `lf_st`（7 = 开机三组装完 ✓）
//   BG W=~            字段2 ：当前显示组的**背景宽** ✓
//   BG H=~            字段3 ：当前显示组的**背景高** ✓
//   GRP VLD=~         字段4 ：{有效组数, 0, cv_ok, bg_ok}
//   SDR REF=~         字段5 ：引脚译码的**真刷新条数** ✓
//   GRP IDX=~         字段6 ：**当前显示组号** ✓
//   AUD N=~           字段7 ：本窗 48kHz 节拍数（1 秒应 = 48000 ✓）★P2/S1
//   ACR N=~           字段8 ：本窗 ACR 包数（1 秒应 = 1000 ✓）★P2/S1
//   AUD ST=~          字段9 ：音源状态（2 = WAV ✓ / 1 = 测试音 ✓）★P2/S2
//   AUD WMIN=~        字段10：本窗 WAV 环**最小水位**（帧 ✓ 判据 > 1024 ✓）★P2/S2
//   AUD UC=~          字段11：本窗**欠载次数**（判据 = 0 ✓）★P2/S2
//   WAV ERR=~         字段12：WAV 解析/链路错误码（判据 = 0 ✓）★P2/S2
//   HDMI LOCKED=~     字段13：视频核 locked
//   SD READY=~        字段14：storage_top.ready
//   SD FAIL=~         字段15：storage_top.fail
//   SD ERR=~          字段16：storage_top.err_code（{域[7:4], 细码[3:0]}）★上板诊断新增
//   SD HC=~           字段17：dbg_sdhc（1=SDHC/SDXC，0=标准 SD）★上板诊断新增
//   SD FILES=~        字段18：storage_top.file_total
//   END
//
// 实现要点：
//   · 报文是一整条 `localparam` 字符串常量，用 mchar() 按索引取字符（纯常数，可综合）。
//   · 十进制打印用"逐位减法计数"（每位最多减 9 次，一次一拍），**不做除法**，省 LUT；
//     最多 7 位，**去前导零**（但个位恒打 0）。
//   · 位数上限 7 ⇒ 可打印到 9999999；本设计的字数字段都在 1e6 量级以内。
//   · uart_tx 在本模块内例化，全部在同一个时钟域。
//=============================================================================
module uart_report #(
    parameter integer CLK_HZ = 150000000,
    parameter integer BAUD   = 115200
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        go,                  // 单拍脉冲：开始打印一轮
    // 字段来源
    input  wire        sdr_init,
    input  wire [31:0] bw_kbps,
    input  wire [31:0] wr_words,
    input  wire [31:0] rd_words,
    input  wire [31:0] err_words,
    input  wire [15:0] sdr_ref,             // 本窗口刷新脉冲数（★上板诊断）
    input  wire [17:0] busy_cyc,            // 本窗口仲裁忙拍数（★上板诊断；≤WIN_CYCLES，18 位够）
    input  wire [31:0] aud_n,               // ★★ P2/S1：本窗口 48kHz 音频**节拍数**（1 秒应 = 48000 ✓）
    input  wire [31:0] aud_acr,             // ★★ P2/S1：本窗口 ACR 包数（1 秒应 = 1000 ✓）
    // ★★ P2/S2 新增四路（WAV 通路 ✓ —— 见 `doc/workitem_p2_s2.md` §3 ✓）
    input  wire [31:0] aud_st,              // 音源状态：2 = WAV ✓ / 1 = 测试音 ✓（0 = 静音 预留 ✓）
    input  wire [31:0] aud_wmin,            // 本窗口 WAV 环的**最小水位**（帧 ✓，> 1024 为好 ✓）
    input  wire [31:0] aud_uc,              // 本窗口**欠载次数** ✓（应 = 0 ✓）
    input  wire [31:0] wav_err,             // WAV 解析/链路错误码 ✓（0 = 合规 ✓）
    // ★★ P2/S3 新增三路（**播放表** ✓ —— 见 `doc/workitem_p2_s3.md` §6 ✓）
    input  wire [7:0]  pl_n,                // 表里**可播**首数 ✓（A1 判据：≥ 1 ✓）
    input  wire [7:0]  song_cur,            // 当前首号 ✓（0 = 无可播 ✓）
    input  wire [7:0]  pl_err,              // **首条**不可播首的错误码 ✓（0 = 全可播 ✓；0x71 = 一个首都没有 ✓）
    // ★★ P3/S6-2c：歌词链在**板上的判据**（A7 的旁证 ✓ 全部取自现成信号 ⇒ 零额外硬件 ✓）
    input  wire [31:0] font_ok,             // 字库两件都装好 = 1 ✓（FONT.HZK + ASC.HZK ✓）
    input  wire [15:0] lrc_n,               // LRC 表里的行数 ✓（本曲 45 ✓）
    input  wire [7:0]  lrc_err,             // 0 / 0x65 表坏 / 0x04 超时 / **0x67 无 LRC** ✓
    input  wire [15:0] lyr_cur,             // 当前行号 ✓
    input  wire [5:0]  lyr_off,             // 滚行相位 0..38 ✓（换行瞬间才动 ✓）
    input  wire [31:0] aud_t,
    // ★★★ P5/A9（2026-10-10）**现场取证**：把四个关键量打包成一个 32 位数 ✓
    //   位域：[1:0]=`slot_rot` ／ [4:2]=`au_st` ／ [7:5]=`pre_stv`
    //         [15:8]=`pre_n` ／ [23:16]=`sw_cnt`（切歌触发过几次 ✓）
    //   【为什么要它】板上反复出现「循环没发生 ／ 花屏」✗，而**仿真测不到** ✗
    //     （集成台的 WAV 播不完 ✓ ⇒ `au_end_pulse` 永不触发 ✓）
    //     ⇒ 用一个十六进制数一次说清「切歌到底触发了没有、卡在哪一步」✓
    //   【怎么读】① `sw_cnt=00` ⇒ 切歌**根本没触发**（查 `nx_vld`/`en_a9` ✓）
    //             ② `sw_cnt>=01` 而 `rot` 不动 ⇒ 轮转没生效 ✗
    //             ③ `pre_n<06` ⇒ 六笔没走完（`pre_stv` 指出卡在第几笔 ✓）
    //             ④ `au_st` = 6（AU_STOP ✓）⇒ 音频没回 `AU_IDLE` ⇒ 没声音 ✓
    input  wire [31:0] a9_pack,               // 累计已播秒数 ✓
    // ★★ Step 0（并发写探测）：**三路诊断** —— 板上"LED 不闪（探针没跑）"时靠它们定因 ✓
    //   为什么非要有：探针的发起条件是 `en && boot_done && (index!=0) && !busy` ✓，
    //   板上没有这三个读数时**只能猜** ✗ —— 本工程已经为"没数可读"白烧过上板轮次 ✓
    //     · `LF ST=`：开机装载 FSM 状态号（7 = `LF_DONE` ✓ ⇒ `boot_done` 成立 ✓）
    //     · `BGF1=` ：播放表给的"当前首 BG1"**文件表索引**（★ = 0 ⇒ 探针的索引门被挡住 ✓）
    //     · `CWP N=`：探针**发起过几次装载**（★ = 0 且上面两个正常 ⇒ 查 `busy` ✓）
    input  wire [3:0]  lf_st,
    input  wire [7:0]  pl_bg1,
    input  wire [15:0] cwp_n,
    // ★★ L1D：**"行头被啃"的板上探针** —— `layer_lyric.gap_cnt` ✓
    //   它数的正是"`de` 有效、窗口内有字、却**没就绪**"的像素数（模块注释写着"**必须 0**" ✓）
    //   ⇒ 下一趟板测用它**一刀切开**两种可能：
    //      · `LYR GAP > 0` ⇒ 是"就绪门"那条（行头被啃 ✓）
    //      · `LYR GAP == 0` 而横纹仍在 ⇒ **不是门**，是**取回的数据本身**错 ⇒ 转去查总线/字节序 ✓
    input  wire [31:0] lyr_gap,
    // ★★ L1M-b：**"歌名跑马灯在不在走"的板上探针** —— `layer_text.ttl_off` ✓
    //   板上实测过一次"歌名静止、只看得见头 5 个字" ✗，根因是偏移被每帧清零 ✗ ——
    //   当时报文里**没有任何字段能自证** ✗，只能靠眼睛判 ⇒ 白跑一趟的风险 ✓
    //   ⇒ `TTL OFF=` 直接读出偏移：静止不动 & 恒 0 ⇒ 偏移没走 ✗；随时间增长 ⇒ 在滚 ✓
    input  wire [11:0] ttl_off,
    input  wire        vid_locked,
    input  wire        sd_ready,
    input  wire        sd_fail,
    input  wire [7:0]  sd_err,              // ★上板诊断
    input  wire        sd_hc,               // ★上板诊断
    input  wire [8:0]  sd_files,
    // UART
    output wire        tx,
    output wire        busy
);

    // ★ MSG_LEN 必须等于下面字符串的**字节数**（仿真里 TB 会逐字符核对报文；
    //   数字改错会被 TB 抓住 —— 别用"看着差不多"来估）。
    // ★★ 模板里**只写 '\n'**，CR(0x0D) 由状态机在遇到 '\n' 时自动补在前面：
    //   因为 Verilog 的 `"\r"` 在 ModelSim 里被当成**普通字符 'r'**（不是回车）！
    //   本轮踩过：模板写 "\r\n" ⇒ 线上真的发出 'r','\n'（hex 72 0a），
    //   而 TB 的期望串里 `"\r"` 也被同样解析成 'r' ⇒ **两边一起错，测试反而 PASS**。
    //   ⇒ 凡是要发控制字符，一律用 8'h0D/8'h0A 显式给出，不要靠字符串转义。
    // ★★ 2026-10-04：**标签改成说实话** ✗✓ —— 这套标签是从 P0 带宽版沿用下来的，
    //   但各字段的**值早就换了**（P1 诊断挪用），原标签会让人误读 ✗。对照表：
    //     原标签 → 实际值（现在的标签 ✓）
    //     `BW KBPS=`  → `lf_st` 装载状态号（7 = 开机三组装完 ✓）      ⇒ **`LF ST=`** ✓
    //     `WR WORDS=` → 当前显示组的**背景宽** ✓                      ⇒ **`BG W=`** ✓
    //     `RD WORDS=` → 当前显示组的**背景高** ✓                      ⇒ **`BG H=`** ✓
    //     `ERR WORDS=`→ {有效组数, 0, cv_ok, bg_ok}（`0x303` ✓）      ⇒ **`GRP VLD=`** ✓
    //     `SDR REF=`  → 引脚译码的**真刷新条数** ✓（本来就对 ✓）       ⇒ 保留 ✓
    //     `BUSY CYC=` → 原与 `SD FILES=` **完全重复** ✗（都是文件数）⇒ 腾出来放**当前组号** ✓ ⇒ **`GRP IDX=`** ✓
    //     `HDMI LOCKED / SD READY / SD FAIL / SD ERR / SD HC / SD FILES` ✓：本来就对 ✓
    //   ⇒ 报文字节数 161 → **148**（逐段核过 ✓：`BW KBPS=`−2 ✓、`WR WORDS=`−4 ✓、
    //     `RD WORDS=`−4 ✓、`ERR WORDS=`−2 ✓、`BUSY CYC=`−1 ✓，共 −13 ✓）
    // ★★ 2026-10-04（P2/S1）：**新增两行音频诊断** ✗→✓ —— `AUD N=`（48kHz 节拍数 ✓）
    //   与 `ACR N=`（ACR 包数 ✓）。它们把"没声音"的排查一刀切开：
    //     节拍在跑 + ACR 在发 + 没声 ⇒ 问题在厂商核/显示器侧 ✗；
    //     节拍不动 ⇒ 问题在我们的时基 ✓。没有这两行就只能再烧一次码流去问 ✗。
    //   ⇒ 报文字节数 148 → **164**（+`AUD N=`8 ✓ +`ACR N=`8 ✓；线长 = 164 + **17** CR = **181** ✓）
    // ★★ 2026-10-04（P2/S2，S2-d）：**再新增四行 WAV 诊断** ✓ —— 这四行就是 S2 §1 的
    //   四条可判据（"在放 WAV / 环没见底 / 没欠载 / 素材合规" ✓）：
    //     `AUD ST=`   音源状态 ✓（2 = WAV ✓ / 1 = 测试音 ✓）
    //     `AUD WMIN=` 本窗环的**最小水位**（帧 ✓，判据 > 1024 = 21ms ✓）
    //     `AUD UC=`   本窗**欠载次数** ✓（判据 = 0 ✓）
    //     `WAV ERR=`  WAV 解析/链路错误码 ✓（判据 = 0 ✓；非 0 时**不进播放** ✓）
    //   ★ 长度**实测**（不许估 ✗ —— 本工程这类手写常数已错过两次 ✗✗）：
    //     四行字符数 = 9（`AUD ST=`）+ 11（`AUD WMIN=`）+ 9（`AUD UC=`）+ 10（`WAV ERR=`）= **39** ✓
    //     ⇒ MSG_LEN 164 → **203** ✓；线长 = 203 + **21** 个 CR = **224** ✓
    //     ⚠️ 工单里原估的 "196 / 213" 是**错的** ✗（它按"每字段 +8"算，
    //        但 `AUD ST=` 是 7 个字符、再加 `~` 与换行共 9 个 ✗）—— 以 `sim/check_msg_len.py` 为准 ✓
    //     ⚠️ 字段数 15 → **19** ⇒ `fix` 位宽必须从 4 位加到 **5 位** ✗（4 位装不下 18 ✗）
    // ★★ 2026-10-04（**一次白跑的上板换来的教训** ✗→✓）：报文首行加**自证标签** ✓。
    //   起因：S2b 码流本该含"音频计数改在 clk_pix 域数"的修复 ✓，但 TD 的 `opt_gate` 步
    //   **静默中断** ✗（无 ERROR ✗、退出码 0 ✗、没有 `.opt_gate.end.f` ✗），phy 于是用了
    //   **上一版的 db** 布线 ✗ ⇒ 烧进去的其实是旧逻辑 ✗，而报文里**没有任何字段能显示这一点** ✗
    //   ⇒ 白跑一次上板 ✓。⇒ 首行改成 **`MUSIC P1 SKEL S2C`** ✓（**与旧串等长 17 字符** ✓
    //   以免动 MSG_LEN ✓）⇒ 以后"报文首行对不对"就能立刻回答"烧的是哪一版" ✓。
    // ★★ 2026-10-05（P2/S3）：**新增三行播放表诊断** ✓ —— `PL N=` / `SONG CUR=` / `PL ERR=` ✓。
    //   它们把 **A1** 的"播放表 ≥1 首 + 报告行如实"变成板上可读的事实 ✓
    //   （口径与错误码见 `doc/workitem_p2_s3.md` §3.1/§6 ✓）。
    //   ★ 三行**追加在末尾** ✓ ⇒ 既有字段的下标 0..18 **一个都没动** ✓（少一类回归风险 ✓）。
    //   ★ 首行标签同步改成 **`MUSIC P1 SKEL S3A`** ✓（**仍 17 字符** ✓ ⇒ 长度增量只来自新字段 ✓；
    //     自证标签的由来见下面 2026-10-04 那条 ✓）。
    //   ★ MSG_LEN / 线长**一律以 `python sim/check_msg_len.py --check` 实测为准** ✗ 不许估 ✗
    //     （本工程这类手写常数已错过两次 ✗✗，其中一次就是 S2 的工单估算 ✗）。
    // ★★ P3/S6-2c：22 字段 -> 28 字段（FONT OK / LRC N / LRC ERR / LYR CUR / LYR OFF / AUD T）
    //   ★ 这个值**是 python sim/check_msg_len.py --check 实测出来的** ✗ 不是估的 ✗
    // ★★ p3-lean 步2c-2：首行标签改成 **`MUSIC P1 SKEL L1A`** ✓（**与旧串等长 17 字符** ✓
    //   ⇒ 长度增量只来自新字段 ⇒ MSG_LEN 不变 ✓）
    //   ★ 为什么必须换：板上现在跑的那版也写着 `S6A` ✗ ⇒ 不换你就**分不清烧的是哪一版** ✗
    //     （旧会话正是栽在这上面：烧了旧网表却以为烧了新逻辑 ✗ —— 他们因此才加了版本标签 ✓）
    //     `L1A` = P3-**精写**（lean）第 1 版 ✓
    //   `L1A` = P3-**精写**（lean）第 1 版；★ **`L1B`** = 修掉"装载期间索引口没给 `ft_idx`"
    //   （板上抓到 ⇒ `FONT OK=0`、字形是方块）＋ 第三组背景槽挪出字库区 ＋ 无字库不出墨 ✓
    //   `L1A` = P3-**精写**第 1 版；`L1B` = 装索引口/槽位/无字库不出墨；★ **`L1C`** = 行缓冲乒乓
    //   （行头 ≈128px 被啃的修复 ✓）+ **起播归零**（`played_cnt` 从本曲起播算 ✓）
    //   ★★ 并层（步 3，2026-10-07）：标签改成 **`L1M`** ✓（**仍 17 字符** ✓ ⇒ `MSG_LEN` 不变 ✓）
    //     `L1M` = **歌名/歌手并入 `layer_text` + 跑马灯**（即并层版 ✓）。
    //     ★ 为什么必须换：`L1M` 与 `L1H` 的**画面差别只有新增的两条文字带** ✗，
    //       而报文首行若不换 ⇒ 烧的是哪一版**看不出来** ✗（本工程栽过：`uart_report.v:126` ✓）
    //   ★★ 字段数 30 → **31 → 30**：L1M-c 曾加 `TTL GAP=` ✗，**已撤** ✓（理由见端口那段注释 ✓）
    localparam integer MSG_LEN = 109;  // ★ 95 → 109：+`SD RDY=~\n`(8) +`SD N=~\n`(6) ✓
    // ★★★ 2026-10-11：板上出现 **黑屏 + `LF ST=0`** ✗ ⇒ 读代码发现
    //   `LF_WAIT`（状态 0 ✓）等的正是 **`sd_ready`** ✓ ⇒ 必须把这一位**报出来** ✗
    //   （端口本来就有 `sd_ready` ✓ 但**从没进过报文** ✗ ⇒ 每次只能猜 ✓）
    //   ★ 另：`led[2] = sd_ready` ✓ 板上**看 LED2** 也能判 ✓（零成本 ✓）
    localparam [8*MSG_LEN-1:0] MSG =
        "MUSIC P1 SKEL B1A\nAUD T=~\nAUD UC=~\nSONG CUR=~\nPL N=~\nLYR CUR=~\nLF ST=~\nBGF1=~\nCWP N=~\nSD RDY=~\nSD N=~\nA9=~\nEND\n";

    localparam [7:0] CH_LF = 8'h0A;
    localparam [7:0] CH_CR = 8'h0D;

    function [7:0] mchar(input integer i);      // 报文第 i 个字符（0 = 最左）
        mchar = MSG[8*(MSG_LEN-1-i) +: 8];
    endfunction

    function [31:0] fieldval(input [4:0] k);        // ★ S2-d：字段数 15 → 19 ⇒ 索引加宽到 5 位 ✓
        case (k)
    5'd0: fieldval = aud_t;
    5'd1: fieldval = aud_uc;
    5'd2: fieldval = song_cur;
    5'd3: fieldval = pl_n;
    5'd4: fieldval = lyr_cur;
    5'd5: fieldval = {28'd0, lf_st};        // ★ Step 0 诊断：LF ST=
    5'd6: fieldval = {24'd0, pl_bg1};       // ★ Step 0 诊断：BGF1=
    5'd7: fieldval = {16'd0, cwp_n};        // ★ Step 0 诊断：CWP N=
    // ★★★ 2026-10-11 **下标错位修复** ✗→✓（**板上数据抓出来的** ✓）
    //   【症状】用户报文：`SD RDY=11283` ✗（★ 不是 0/1 ✓）
    //   【真因】我把 `SD RDY=` / `SD N=` **插进了模板** ✓，却忘了把 `fieldval` 下标往后挪 ✗
    //     ⇒ 模板说"第 8 个是 SD RDY" ✓，而 `fieldval(8)` 给的是 **`a9_pack`** ✗
    //     ⇒ `SD RDY` 印出 `0x2C13 = 11283` ✓✓（★ 与板上数字**分毫不差** ✓）；
    //       `SD N` 印出 `sd_ready = 1` ✓（也对上 ✓）
    //   【教训】★ 模板与下标是**两张表** ✗ —— 动一张必须动另一张 ✓
    //     且"错位"**不会报任何错** ✗ ⇒ 只能靠"**这个数合不合理**"发现 ✓
    //   【正确顺序】与模板逐字对齐 ✓：CWP N(7) → SD RDY(8) → SD N(9) → A9(10) ✓
    5'd8:  fieldval = {31'd0, sd_ready};    // SD RDY=（1 = 文件表就绪 ✓；0 ⇒ LF 停在状态 0 ⇒ 黑屏 ✓）
    5'd9:  fieldval = {23'd0, sd_files};    // SD N=（扫到的文件数 ✓）
    5'd10: fieldval = a9_pack;              // A9=现场取证 ✓（见端口注释 ✓）
    default: fieldval = 32'd0;
    endcase
    endfunction

    function [31:0] p10(input [3:0] k);         // 10^k, k = 0..6
        case (k)
        4'd0: p10 = 32'd1;
        4'd1: p10 = 32'd10;
        4'd2: p10 = 32'd100;
        4'd3: p10 = 32'd1000;
        4'd4: p10 = 32'd10000;
        4'd5: p10 = 32'd100000;
        4'd6: p10 = 32'd1000000;
        default: p10 = 32'd1;
        endcase
    endfunction

    // ---------------- uart_tx ----------------
    reg        t_start;
    reg  [7:0] t_data;
    wire       t_busy;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst_n(rst_n), .tx_start(t_start), .tx_data(t_data),
        .tx_busy(t_busy), .tx(tx)
    );

    // ---------------- 报文序列 + 十进制打印 ----------------
    localparam [2:0] S_IDLE = 3'd0, S_CH = 3'd1, S_CHW = 3'd2,
                     S_NUM  = 3'd3, S_NUMW = 3'd4;
    reg [2:0]  st;
    // ★★ 2026-10-06（上板实测）：MSG_LEN 286 > 255 ⇒ 8 位索引**只发得动前 30 个字符** ✗
    //   （终止条件 `sidx == MSG_LEN[7:0]` = 286 mod 256 = 30 ⇒ 板上报文停在 `L` ✗）
    //   ⇒ 索引必须能容纳 MSG_LEN-1；**宽度与 MSG_LEN 的匹配由 sim/check_msg_len.py 机械化看住** ✓
    reg [15:0] sidx;                            // 报文索引（0..MSG_LEN-1）
    reg [4:0]  fix;                             // 字段序号（★ S2-d：0..18 ⇒ 5 位 ✓）
    reg [3:0]  dph;                             // 数位序号 0..6（10^6 → 10^0）
    reg [3:0]  ddig;                            // 当前数位的值
    reg [31:0] dval;                            // 剩余值
    reg        dstart;                          // 已输出过非零位
    reg        pend_lf;                         // 刚发了 CR，下一个要发 LF

    wire [7:0] ch = mchar(sidx);

    assign busy = (st != S_IDLE) | t_busy;

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_IDLE; sidx <= 8'd0; fix <= 5'd0; dph <= 4'd0; ddig <= 4'd0;
            dval <= 32'd0; dstart <= 1'b0; t_start <= 1'b0; t_data <= 8'd0;
            pend_lf <= 1'b0;
        end else begin
            case (st)
            S_IDLE: begin
                t_start <= 1'b0;
                if (go) begin
                    sidx <= 8'd0; fix <= 5'd0; pend_lf <= 1'b0;
                    st   <= S_CH;
                end
            end

            // 取下一位要发的字符
            S_CH: begin
                t_start <= 1'b0;
                if (!t_busy) begin
                    if (pend_lf) begin                        // 补发 LF
                        t_data  <= CH_LF;
                        t_start <= 1'b1;
                        pend_lf <= 1'b0;
                        st      <= S_CHW;
                    end else if (sidx == MSG_LEN) begin   // ★ 不许再写 MSG_LEN[7:0]（286 ⇒ 30 ✗）
                        st <= S_IDLE;                       // 一轮报完
                    end else if (ch == 8'h7E) begin          // '~' ⇒ 打印一个十进制字段
                        dval   <= fieldval(fix);
                        dph    <= 4'd0;
                        ddig   <= 4'd0;
                        dstart <= 1'b0;
                        fix    <= fix + 5'd1;
                        sidx   <= sidx + 16'd1;
                        st     <= S_NUM;
                    end else if (ch == CH_LF) begin          // 换行 ⇒ 先发 CR
                        t_data  <= CH_CR;
                        t_start <= 1'b1;
                        pend_lf <= 1'b1;
                        sidx    <= sidx + 16'd1;
                        st      <= S_CHW;
                    end else begin
                        t_data  <= ch;
                        t_start <= 1'b1;
                        sidx    <= sidx + 16'd1;
                        st      <= S_CHW;
                    end
                end
            end
            S_CHW: begin
                t_start <= 1'b0;
                if (t_busy) st <= S_CH;                     // 等这一字节发完
            end

            // 逐位减法出十进制（每位最多减 9 次，一次一拍）
            S_NUM: begin
                t_start <= 1'b0;
                if (dph == 4'd7) begin
                    st <= S_CH;                              // 7 位打完
                end else if (dval >= p10(4'd6 - dph)) begin
                    dval <= dval - p10(4'd6 - dph);
                    ddig <= ddig + 4'd1;
                end else if (!t_busy) begin
                    // 本位数码已定（ddig）。★ 前导零必须"跳位但不发"，
                    //   否则 dph 不前进会**死锁**（本轮踩过：只收到 32 字符就停住）。
                    if (dstart || ddig != 4'd0 || dph == 4'd6) begin
                        t_data  <= {4'd0, ddig} + 8'h30;     // '0' + digit
                        t_start <= 1'b1;
                        if (ddig != 4'd0) dstart <= 1'b1;
                        st      <= S_NUMW;
                    end else begin
                        st <= S_NUM;                         // 只跳位，不进 S_NUMW
                    end
                    dph  <= dph + 4'd1;
                    ddig <= 4'd0;
                end
            end
            S_NUMW: begin
                t_start <= 1'b0;
                if (t_busy) st <= S_NUM;
            end
            default: st <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
