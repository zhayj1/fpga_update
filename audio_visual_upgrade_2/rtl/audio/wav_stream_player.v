// EXPERIMENT ONLY: baseline logic, with ring RAM IMPLEMENT changed to 32K.
// Original historical comments below describe the baseline 9K implementation.
`default_nettype none
//============================================================================
// rtl/audio/wav_stream_player.v —— WAV 流播放器（BRAM 环 + 48k 取样本）
//
// ★ 它是什么：**写侧**从 `storage_top` 的 `hi_*` 字节流吃 PCM ✓、装配成"一帧一个字"
//   写进 **BRAM 环** ✓；**读侧**在 48kHz 节拍上取帧、乘音量、输出 L/R ✓。
//   ★ **完全不占 SDRAM 总线** ✓（`p2_sdram_map_and_traffic_plan.md` §定稿 §3 ✓）。
//
// 【环与容量（算式 ✓）】`2^ADDR_WIDTH` 帧 × 32bit ⇒ 默认 4096 帧 = **16KB** = **85.3ms** ✓
//   · 一首 48k/16bit/stereo 的歌 = 192,000 B/s = **48,000 帧/s** ✓；
//   · 一个扇区 512B = **128 帧 = 2.67ms** ✓；SPI 1.53MB/s 读一扇区 ≈ **0.33ms** ✓ ⇒ 8× 实时 ✓；
//   · ⇒ 85ms 的环对卡抖动有 **30× 余量** ✓（论证见 `p2` 计划 §3 ✓）。
//
// 【为什么用 `EG_LOGIC_BRAM` 而不是 `reg` 数组（B15 教训 ✓）】
//   厂商 9K 块在 **32bit 位宽下不支持 `MODE("SDP")`** ✗（`SYN-8418 ERROR: Wrong MODE::SDP` ✓），
//   而非对称位宽会被推成 **1117 LUT + 0 BRAM** ✗（B15 实测 ✓）⇒ 这里用**对称 32→32 + `MODE("DP")`** ✓
//   （与本项目 `afifo_8i_32o_bram.v` 同一手法 ✓）。★ 4096×32 = 131kbit ✗ 若落成 LUT 是灾难 ✗
//   ⇒ **S2-d 构建后必须核 `#bram` 是否 +4~5** ✓（若没涨 ⇒ 立刻换写法 ✓）。
//
// 【跨时钟域（写 `wr_clk`=50MHz ✓ / 读 `rd_clk`=25MHz ✓）】
//   读写指针用 **格雷码 + 2 级同步** ✓（相邻值只差 1 位 ⇒ 采样到中间态也只差 1 ✓，
//   不会出现"7 采成 0"那种灾难 ✗）；两侧各算一份水位 ✓。
//
// 【取样本语义（照课程 + 本项目 `design §10.1` ✓）】
//   · **预填充 `PREFILL`=128 帧** ✓（= 1 个扇区 ✓）后才开始放 ✓，避免开局就下溢 ✓；
//   · ★ 环空 ⇒ **补静音** ✓（**绝不发 `x`** ✗）；`sample_valid` 仍按节拍照发（1 拍 ✓）⇒
//     下游**从不停顿**、听感是"静音"而不是"断流" ✓；
//   · ★★ 2026-10-04（S2-d 集成时发现并修正 ✗→✓）：`sample_valid` 必须是**每节拍 1 拍脉冲** ✓，
//     **不是电平** ✗。判据（事实 ✓）：厂商 HDMI 核的音频口契约是
//       "**1 秒内需要发送 48000 次**"（APUG092 §2.4.3 ✓，本工程 `doc/p2_..._plan.md:227` ✓）
//       ⇒ **每拍 valid = 一个样本** ✓；若把 valid 挂成常高 ✗，核会按**像素时钟**(25MHz) 取样本 ✗
//       ⇒ 实际样本率变成 25MHz ⇒ 音高/时长全错 ✗。
//     ★ 唯一的**板上实证**口径 = S1 的 `pcm_test_tone`（板上已验有声 ✓）：
//       它在节拍后**只拉高 1 拍**、被取走即落 ✓ ⇒ 这里**逐字照抄**那个时序 ✓（本模块 §4 ✓）。
//   · ★ **中途**饿死才计入 `underrun_cnt` ✓；**写侧已收工**（`wr_done`）之后再放空 ⇒ 是**正常结尾** ✓
//     ⇒ 歌尾的残余帧**照常放完** ✓（否则一首歌的最后一段会被切掉 ✗）；
//   · 下游 `sample_ready` 拉低时**保持**当前样本与 valid、本拍不推进 ✓
//     ⇒ **不丢帧** ✓（计入 `hold_cnt` ✓；取走一拍后才允许装下一个样本 ✓）。
//
// 【音量口径（**为 S3/A4 定死** ✓）】`gain[8:0]`，**256 = ×1** ✓
//   ⇒ 0% / 50% / 100% = **0 / 128 / 256** ✓ 三个都是**精确**的（移位即可 ✓，无除法 ✓）
//   ⇒ A4"样本 = 源 × 系数"可以逐样本对账 ✓。实现：`(sample × gain) >>> 8` ✓（取 bit[23:8] ✓）。
//============================================================================
module wav_stream_player #(
    parameter integer ADDR_WIDTH = 12,      // 环深度 = 2^12 = 4096 帧 ✓
    parameter integer PREFILL    = 128      // 预填充帧数 ✓
)(
    // ---------------- 写侧：`wr_clk` = storage 同域（50MHz ✓）----------------
    input  wire        wr_clk,
    input  wire        wr_rst_n,
    input  wire        play_enable,        // 电平：播放中 ✓
    input  wire        start,              // 脉冲：开始吃 PCM（头已解析完 ✓）
    input  wire [31:0] total_bytes,        // PCM 总字节数（= `wav_head.data_bytes` ✓）
    input  wire        rd_valid,           // ← storage_top 的 hi_rd_valid ✓
    input  wire [7:0]  rd_data,            // ← hi_rd_data ✓
    output wire        rd_ready,           // → hi_rd_ready ✓（环快满就反压 ✓）
    output wire        refill_urgent, // write-clock domain hysteresis, 2048/3072 frames
    output wire        sector_room,        // 写侧尚可完整接收一个 512B SD 扇区
    input  wire        rd_eof,             // ← hi_rd_eof ✓
    // ---------------- 读侧：`rd_clk` = clk_pix（25MHz ✓）----------------
    input  wire        rd_clk,
    input  wire        rd_rst_n,
    input  wire        sample_tick,        // 48kHz 一拍脉冲 ✓（`audio_sample_tick` ✓）
    input  wire        continuous,         // 连播模式：曲界等下一首首帧
    input  wire        boundary_ready,     // 下一首素材已预装；未就绪时停在曲界
    input  wire        sample_ready,       // 下游就绪（HDMI 核无 ready ⇒ 恒 1 ✓）
    output reg         sample_valid,
    output reg  [15:0] sample_left,
    output reg  [15:0] sample_right,
    output reg  [15:0] sample_raw_left,
    output reg  [15:0] sample_raw_right,
    input  wire [8:0]  gain,               // 音量：**256 = ×1** ✓（S2 先恒 256 ✓）
    // ---------------- 观测（读侧域 ✓）----------------
    input  wire        stat_clr,           // 脉冲：清"最小水位/欠载"（报文每窗口清一次 ✓）
    output reg  [ADDR_WIDTH:0] level_now,
    output reg  [ADDR_WIDTH:0] level_min,
    output reg  [31:0] underrun_cnt,
    output reg  [31:0] hold_cnt,           // 观测：下游没取走而挂住的节拍数 ✓
    output reg         primed,             // 已过预填充 ✓
    output reg         writer_done,        // 当前歌曲的 PCM 已全部写入环
    output reg         stream_end          // 脉冲：最后一帧已放完 ✓
);

    localparam integer        DEPTH   = (1 << ADDR_WIDTH);
    localparam [ADDR_WIDTH:0] DEPTH_C = DEPTH[ADDR_WIDTH:0];
    localparam [ADDR_WIDTH:0] PRE_C   = PREFILL[ADDR_WIDTH:0];

    //=========================================================================
    // 1) 指针 + 格雷码跨域（两侧各一份水位 ✓）
    //=========================================================================
    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;

    function [ADDR_WIDTH:0] to_gray;
        input [ADDR_WIDTH:0] b;
        begin
            to_gray = b ^ (b >> 1);
        end
    endfunction

    function [ADDR_WIDTH:0] from_gray;
        input [ADDR_WIDTH:0] g;
        integer i;
        reg [ADDR_WIDTH:0] b;
        begin
            b[ADDR_WIDTH] = g[ADDR_WIDTH];
            for (i = ADDR_WIDTH - 1; i >= 0; i = i - 1)
                b[i] = b[i+1] ^ g[i];
            from_gray = b;
        end
    endfunction

    wire [ADDR_WIDTH:0] wr_gray = to_gray(wr_ptr);
    wire [ADDR_WIDTH:0] rd_gray = to_gray(rd_ptr);

    reg  [ADDR_WIDTH:0] wr_g_s1, wr_g_s2;      // 写域 → 读域 ✓
    reg  [ADDR_WIDTH:0] rd_g_s1, rd_g_s2;      // 读域 → 写域 ✓

    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin wr_g_s1 <= {(ADDR_WIDTH+1){1'b0}}; wr_g_s2 <= {(ADDR_WIDTH+1){1'b0}}; end
        else           begin wr_g_s1 <= wr_gray;                wr_g_s2 <= wr_g_s1;                end
    end
    always @(posedge wr_clk) begin
        if (!wr_rst_n) begin rd_g_s1 <= {(ADDR_WIDTH+1){1'b0}}; rd_g_s2 <= {(ADDR_WIDTH+1){1'b0}}; end
        else           begin rd_g_s1 <= rd_gray;                rd_g_s2 <= rd_g_s1;                end
    end

    wire [ADDR_WIDTH:0] wr_ptr_r = from_gray(wr_g_s2);     // 读侧看到的写指针 ✓
    wire [ADDR_WIDTH:0] rd_ptr_w = from_gray(rd_g_s2);     // 写侧看到的读指针 ✓
    wire [ADDR_WIDTH:0] level_w  = wr_ptr - rd_ptr_w;      // 写侧水位 ✓
    wire [ADDR_WIDTH:0] level_r  = wr_ptr_r - rd_ptr;      // 读侧水位 ✓

    // 写侧收工标志（单比特 ✓ 2FF 进读域 ✓）
    reg  [1:0] done_sr;
    reg  [1:0] boundary_ready_sr;
    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            done_sr <= 2'd0;
            boundary_ready_sr <= 2'd0;
        end else begin
            done_sr <= {done_sr[0], writer_done};
            boundary_ready_sr <= {boundary_ready_sr[0], boundary_ready};
        end
    end
    wire wr_done_r = done_sr[1];

    // Each completed PCM stream contributes one end pointer. The small
    // asynchronous FIFO keeps two adjacent song boundaries without another
    // audio RAM; the synchronized Gray pointer makes each entry stable at read.
    reg [ADDR_WIDTH:0] end_mark [0:3];
    reg [2:0] mark_wr, mark_rd;
    reg [2:0] mark_wr_s1, mark_wr_s2;
    wire [2:0] mark_wr_gray = mark_wr ^ (mark_wr >> 1);
    wire [2:0] mark_rd_gray = mark_rd ^ (mark_rd >> 1);
    wire mark_valid = (mark_wr_s2 != mark_rd_gray);
    wire [ADDR_WIDTH:0] mark_front = end_mark[mark_rd[1:0]];
    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin mark_wr_s1 <= 3'd0; mark_wr_s2 <= 3'd0; end
        else begin mark_wr_s1 <= mark_wr_gray; mark_wr_s2 <= mark_wr_s1; end
    end

    //=========================================================================
    // 2) 环：EG_LOGIC_BRAM（**对称 32→32 + MODE("DP")** ✓，见文件头）
    //=========================================================================
    wire [31:0] mem_dia;
    wire [31:0] mem_dob;
    wire [31:0] mem_doa_unused;
    wire        mem_wea;          // ★ 必须在**例化之前**声明 ✗（`default_nettype none` 下
                                  //   隐式网线是错误 ✓ —— 第一版漏了它，vlog-2892 直接拦住 ✓）

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A (32),
        .DATA_WIDTH_B (32),
        .ADDR_WIDTH_A (ADDR_WIDTH),
        .ADDR_WIDTH_B (ADDR_WIDTH),
        .DATA_DEPTH_A (DEPTH),
        .DATA_DEPTH_B (DEPTH),
        .BYTE_ENABLE  (0),
        .BYTE_A       (1),
        .BYTE_B       (1),
        .MODE         ("DP"),               // ★ 不能写 "SDP"（EG4 9K 在 32bit 下不支持 ⇒ SYN-8418）
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
        .IMPLEMENT    ("32K")
    ) u_ram (
        .dia   (mem_dia),
        .addra (wr_ptr[ADDR_WIDTH-1:0]),
        .cea   (1'b1),
        .ocea  (1'b0),
        .clka  (wr_clk),
        .wea   (mem_wea),
        .rsta  (1'b0),
        .bea   (1'b0),
        .dib   (32'd0),
        .addrb (rd_ptr[ADDR_WIDTH-1:0]),
        .ceb   (1'b1),
        .oceb  (1'b1),
        .clkb  (rd_clk),
        .web   (1'b0),
        .rstb  (1'b0),
        .beb   (1'b0),
        .doa   (mem_doa_unused),
        .dob   (mem_dob)
    );

    //=========================================================================
    // 3) 写侧：吃字节 → 装配 → 写环（**小端**：bit k*8 +: 8 ✓）
    //=========================================================================
    localparam [1:0] WS_IDLE = 2'd0, WS_FILL = 2'd1, WS_END = 2'd2;

    reg  [1:0]  wst;
    reg  [31:0] bytes_left;
    reg  [1:0]  bidx;                 // 帧内字节序号 0..3 ✓
    reg  [31:0] stage;                // 装配暂存 ✓

    // ★ 按字节序号**显式落位** ✗不用整体移位 ✗（`wav_head` 上刚踩过"移位放错字节"的坑 ✓）
    reg  [31:0] byte_pos;
    always @(*) begin
        case (bidx)
        2'd0:    byte_pos = {24'd0, rd_data};
        2'd1:    byte_pos = {16'd0, rd_data, 8'd0};
        2'd2:    byte_pos = {8'd0,  rd_data, 16'd0};
        default: byte_pos = {rd_data, 24'd0};
        endcase
    end
    wire [31:0] frame_nx = stage | byte_pos;

    wire full       = (level_w >= (DEPTH_C - 13'd4));          // 环快满 ⇒ 反压 ✓（留 4 帧 ✓）
    reg refill;
    always @(posedge wr_clk) begin
        if(!wr_rst_n) refill<=1'b1;
        else if(level_w <= (DEPTH_C >> 1)) refill<=1'b1;
        else if(level_w >= ((DEPTH_C >> 1)+(DEPTH_C >> 2))) refill<=1'b0;
    end
    assign refill_urgent=refill;
    assign sector_room = (level_w <= (DEPTH_C - 13'd132));
    wire byte_taken = rd_valid & rd_ready;
    assign rd_ready = (wst == WS_FILL) && (bytes_left != 32'd0) && !full;
    assign mem_wea  = (wst == WS_FILL) && byte_taken && (bidx == 2'd3);
    assign mem_dia  = frame_nx;                                 // 提交当拍的数据 ✓

    always @(posedge wr_clk) begin
        if (!wr_rst_n) begin
            wst <= WS_IDLE; bytes_left <= 32'd0; bidx <= 2'd0; stage <= 32'd0;
            wr_ptr <= {(ADDR_WIDTH+1){1'b0}}; writer_done <= 1'b0;
            mark_wr <= 3'd0;
        end else begin
            case (wst)
            WS_IDLE: begin
                bidx    <= 2'd0;
                stage   <= 32'd0;
                if (start && play_enable && (total_bytes != 32'd0)) begin
                    writer_done <= 1'b0;
                    bytes_left <= total_bytes;
                    wst        <= WS_FILL;
                end
            end
            WS_FILL: begin
                if (byte_taken) begin
                    // ★ 一次赋值决定"清零还是保留" ✗（分两次写会后者覆盖前者 ✗）
                    stage      <= (bidx == 2'd3) ? 32'd0 : frame_nx;
                    bidx       <= bidx + 2'd1;
                    bytes_left <= bytes_left - 32'd1;
                    if (bidx == 2'd3) wr_ptr <= wr_ptr + 2'd1;
                    if (bytes_left == 32'd1) begin
                        if (bidx == 2'd3) begin
                            end_mark[mark_wr[1:0]] <= wr_ptr + 2'd1;
                            mark_wr <= mark_wr + 3'd1;
                        end
                        wst <= WS_END;
                    end
                end else if (rd_eof) begin
                    end_mark[mark_wr[1:0]] <= wr_ptr;
                    mark_wr <= mark_wr + 3'd1;
                    wst <= WS_END;
                end
            end
            default: begin                                       // WS_END
                writer_done <= 1'b1;
                if (!play_enable) begin
                    wst <= WS_IDLE;
                end else if (start && (total_bytes != 32'd0)) begin
                    writer_done <= 1'b0;
                    bytes_left <= total_bytes;
                    bidx <= 2'd0;
                    stage <= 32'd0;
                    wst <= WS_FILL;
                end
            end
            endcase
        end
    end

    //=========================================================================
    // 4) 读侧：48k 节拍取帧 → 音量 → 输出（补静音但 valid 不停 ✓）
    //=========================================================================
    reg [31:0] dob_ff;
    always @(posedge rd_clk) begin
        if (!rd_rst_n) dob_ff <= 32'd0; else dob_ff <= mem_dob;
    end

    wire signed [15:0] raw_l = dob_ff[15:0];
    wire signed [15:0] raw_r = dob_ff[31:16];

    // 定点音量：gain = 256 ⇒ ×1 ✓（精确；无除法 ✓）
    wire signed [24:0] mul_l = raw_l * $signed({1'b0, gain});
    wire signed [24:0] mul_r = raw_r * $signed({1'b0, gain});

    wire accepted  = sample_valid & sample_ready;                 // 本拍**被取走** ✓
    wire take_now  = (!sample_valid) || accepted;                 // 可以装新样本 ✓
    wire boundary_blocked = continuous && mark_valid && ((rd_ptr + 2'd1) == mark_front) &&
                            (!boundary_ready_sr[1] || (level_r <= {{(ADDR_WIDTH-1){1'b0}}, 2'd1}));
    wire can_play  = !boundary_blocked && (level_r != {(ADDR_WIDTH+1){1'b0}}) &&
                     (primed || wr_done_r || (level_r >= PRE_C));
    // ★★ `playing` = "真的在放"（已过预填充 且 写侧还没收工 ✓）
    //   ★ 2026-10-04（S2-d **整机仿真抓到** ✗→✓）：`level_min` 原来无条件跟 `level_r` 取最小值 ✗，
    //     而复位后环**本来就是空的**（`level_r=0` 是正常的 ✗）⇒ min 被**永久钉在 0** ✗
    //     ⇒ 报文 `AUD WMIN=` 恒为 0 ✗ —— 而工单判据 3 是"WMIN > 1024"✗ ⇒ **板上会被误读成"环见底"** ✗。
    //     （T-06 抓到的就是它：其余 8 条判据全过 ✓，只 `wmin_last=0` ✗）
    //   ⇒ 只在 `playing` 期间记 min ✓；不在播时 min **跟随当前水位**（不记账 ✓）。
    //   ★ 口径随之明确：**第一份报文**的 WMIN ≈ 预填充阈值（128 ✓，因为"能播"的门就是它 ✓），
    //     从**第二份**起才是稳态值（≈ 环深 4092 ✓）⇒ 工单那条 `> 1024` 应看**第二份及以后** ✓。
    wire playing   = primed & ~wr_done_r;

    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            rd_ptr       <= {(ADDR_WIDTH+1){1'b0}};
            sample_valid <= 1'b0;
            sample_left  <= 16'sd0;
            sample_right <= 16'sd0;
            sample_raw_left <= 16'sd0;
            sample_raw_right <= 16'sd0;
            level_now    <= {(ADDR_WIDTH+1){1'b0}};
            level_min    <= {(ADDR_WIDTH+1){1'b0}};
            underrun_cnt <= 32'd0;
            hold_cnt     <= 32'd0;
            primed       <= 1'b0;
            stream_end   <= 1'b0;
            mark_rd      <= 3'd0;
        end else begin
            stream_end <= 1'b0;
            level_now  <= level_r;
            if (level_r >= PRE_C) primed <= 1'b1;

            if (stat_clr) begin
                level_min    <= level_r;
                underrun_cnt <= 32'd0;
                hold_cnt     <= 32'd0;
            end else if (!playing) begin
                level_min <= level_r;              // 未开播 / 已播完 ⇒ 跟随，不记 min ✓
            end else if (level_r < level_min) begin
                level_min <= level_r;
            end

            // ★★ 时序与 `pcm_test_tone` **逐字同构** ✓（那是板上验过的 ✓，见文件头）：
            //    节拍 ⇒ 装样本 + valid 拉高 1 拍；被取走 ⇒ 落 valid；没取走 ⇒ **保持** ✓
            if (sample_tick) begin
                if (!take_now) begin
                    hold_cnt <= hold_cnt + 32'd1;                 // 下游没取 ⇒ 保持、本拍不推进 ✓
                end else if (can_play) begin
                    sample_valid <= 1'b1;
                    sample_left  <= mul_l[23:8];                  // >>> 8 ✓（gain=256 ⇒ 原样 ✓）
                    sample_right <= mul_r[23:8];
                    sample_raw_left <= raw_l;
                    sample_raw_right <= raw_r;
                    rd_ptr       <= rd_ptr + 2'd1;
                    if (mark_valid && ((rd_ptr + 2'd1) == mark_front)) begin
                        stream_end <= 1'b1;                       // 最后一帧 ⇒ 收尾脉冲 ✓
                        mark_rd <= mark_rd + 3'd1;
                    end
                end else begin
                    // 未预填 或 中途饿死 ⇒ 补静音 ✓（valid 照发 ⇒ 下游不停顿 ✓）
                    sample_valid <= 1'b1;
                    sample_left  <= 16'sd0;
                    sample_right <= 16'sd0;
                    sample_raw_left <= 16'sd0;
                    sample_raw_right <= 16'sd0;
                    if (primed && !wr_done_r) underrun_cnt <= underrun_cnt + 32'd1;
                end
            end else if (accepted) begin
                sample_valid <= 1'b0;                             // ★ 单拍脉冲 ⇒ 交给核"数次数" ✓
            end
        end
    end

    // 展开期守卫：位宽必须够装水位 ✓（不合就报错，不静默截断 ✗）
    // synopsys translate_off
    initial begin
        if ((PREFILL < 0) || (PREFILL > DEPTH)) begin
            $display("WAV_STREAM_PLAYER ERROR: PREFILL(%0d) out of range (0..%0d)", PREFILL, DEPTH);
            $finish;
        end
    end
    // synopsys translate_on

endmodule

`default_nettype wire
