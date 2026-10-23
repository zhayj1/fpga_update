`default_nettype none
//============================================================================
// rtl/ip/afifo_8i_32o_bram.v —— 8bit 写 / 32bit 读 异步 FIFO（**BRAM 版**）
//
// 为什么有这个东西（工单 doc/workitem_fifo_bram.md，用户 2026-10-02 指令：
// 「肯定要装进 BRAM 里，不能占 LUT」）：
//   厂商 `afifo_8i_32o_1024` 内部的 1KB 缓冲被综合成 **1117 LUT + 32 触发器**
//   （面积报告 `ram_infer_afifo_8i_32o_1024` 行 `bram` 列 = 0 ✗），根因两条：
//     ① 该 RAM 用 `MODE("SDP")` —— EG4 的 9K 块在 **32bit 位宽下不支持 SDP**（同族报错
//        `SYN-8418 ERROR: Wrong MODE::SDP`，本项目在 `fetch_line` 上撞过一次 ✓）；
//     ② 它是 **8bit 写 / 32bit 读的非对称**宽口 RAM，厂商推断支持有限。
//   本模块把**打包搬到写域的触发器上**（攒满 4 字节再写一次 RAM）⇒ RAM 变成
//   **对称 32→32**、`MODE("DP")`、深度 256（2 的幂）⇒ 落 BRAM ✓。
//   ★ 口径（2026-10-03 综合实测 ✓）：**占 2 块 9K**，不是 1 块 —— EG4 的 9K 块是
//     **512 字 × 18 位** ⇒ 32 位数据要靠 **2 块并排**（2×18=36 ≥ 32 ✓，深度 256 ≤ 512 ✓）。
//     实测：`syn_1/skeleton_gate.area` 的 `#bram` 由 28 → **30** ✓、`u_fifo` 行 bram 列 = 2 ✓
//     （对照 `fetch_line` 的 1024×32 行缓冲 = 4 块 × 2 个实例 = 8 块 ✓ 同一口径 ✓）。
//
// 与厂商件的关系（★ 逐条对齐，出处见工单 §7.1）：
//   · **端口名/参数名逐一对齐** ⇒ `bmp_load.v` 只改**例化名一行**（其余一行不动 ✓）；
//   · 读侧 FWFT：`SHOW_AHEAD_EN=1` 时 `dout` 常驻队头、**不拉 `re` 也能读** —— `bmp_load` 依赖它 ✓；
//   · `rdusedw` 以 **32bit 字**计、**只算整字**、且因指针跨域同步而**保守（滞后不超前）** ✓；
//   · `empty_flag`/`aempty`/`valid`/`full_flag`/`afull` 的判据与厂商件**同式** ✓；
//   · 指针跨域**直接复用厂商模块** `fifo_cross_domain_addr_process_al_afifo_8i_32o_1024`
//     （**例化，不改一个字节** ✓）⇒ 同步级数（主域 1 拍 + 从域 3 拍）与厂商件逐拍一致 ✓，
//     单元 TB 用**新旧背靠背对拍**验证这一点 ✓。
//
// 与厂商件的**已知差异**（都落在本设计**未使用**的口上，见工单 §4）：
//   1. 容量：厂商 1023 **字节**；本模块 `2^ADDR_WIDTH_R - 1` = 255 **字** = 1020 字节（差 3 字节 ✓）；
//      —— 上限取 255 而不是 256，是为了保证读域 `rdusedw`（8 位）**永不回绕** ✓；
//   2. `wrusedw`：厂商按**已写字节**计（含攒着还没凑成整字的 1..3 字节）；本模块按**整字×4**计
//      ⇒ 两者差 = 攒着的 0..3 字节（`bmp_load` **不使用**该口 ✓，其注释已写明）；
//   3. `afull`：本模块容量 1020 字节 < `AL_FULL_NUM`(1021) ⇒ **恒为 0**（该口对本设计无意义 ✓）；
//   4. `OUTREG_EN`：**只实现 `"NOREG"`** ✗ —— 传其它值会在**展开期**因缺模块而**报错停下**，
//      不静默走错路 ✓（见文末 generate 守卫）。
//
// 生产者契约（与厂商件一致 ✓，`bmp_load` 已满足 ✓）：
//   写侧必须在 `full_flag=1` 时停止拉 `we`；**满时硬塞字节会造成字边界错位** ✗
//   （满时被拒的字节不进暂存、也不推进字节计数 ⇒ 不会丢字，但会与后续字节错位）。
//
// 未验证：TD 综合面积/时序（本轮工单要验的正是这个 ✓）。
//============================================================================
module afifo_8i_32o_bram #(
    parameter DATA_WIDTH_W  = 8,
    parameter DATA_WIDTH_R  = 32,
    parameter ADDR_WIDTH_W  = 10,
    parameter ADDR_WIDTH_R  = 8,
    parameter AL_FULL_NUM   = 1021,
    parameter AL_EMPTY_NUM  = 2,
    parameter SHOW_AHEAD_EN = 1'b0,
    parameter OUTREG_EN     = "NOREG"
)(
    input  wire                    rst,        // 异步复位、高有效（两侧各自同步释放 ✓）
    input  wire                    clkw,       // 写时钟
    input  wire                    clkr,       // 读时钟
    input  wire                    we,         // 写使能（写单位 = DATA_WIDTH_W 位）
    input  wire [DATA_WIDTH_W-1:0] di,
    input  wire                    re,         // 读使能（弹出一个 DATA_WIDTH_R 位字）
    output wire [DATA_WIDTH_R-1:0] dout,
    output wire                    valid,      // 读数据有效标志
    output reg                     full_flag,
    output wire                    empty_flag,
    output reg                     afull,
    output wire                    aempty,
    output wire [ADDR_WIDTH_W-1:0] wrusedw,    // 已存数据量（**写单位**计）
    output wire [ADDR_WIDTH_R-1:0] rdusedw     // 可读数据量（**字**计）
);

    //=========================================================================
    // 0. 规模推导
    //=========================================================================
    function integer clog2f;
        input integer value;
        integer v;
        begin
            clog2f = 0;
            for (v = value - 1; v > 0; v = v >> 1) clog2f = clog2f + 1;
        end
    endfunction

    localparam integer AW     = ADDR_WIDTH_R;                  // RAM 地址位宽（= log2 深度）
    localparam integer DEPTH  = (1 << AW);                     // RAM 深度（**必须 2 的幂** ✓）
    localparam integer PACK   = DATA_WIDTH_R / DATA_WIDTH_W;   // 每字装几个写单位（8→32 ⇒ 4）
    localparam integer PSH    = clog2f(PACK);                  // 打包比是 2 的幂 ⇒ 字节数用移位
    localparam integer CW     = PSH;                           // 打包计数器位宽
    localparam integer PW     = AW + 1;                        // 指针位宽（多 1 位区分满/空）

    localparam [PW-1:0] FULL_TH = (1 << AW) - 1;               // 满门限 = 255 字（见文件头"差异 1"）

    localparam integer SHOW_AHEAD = (SHOW_AHEAD_EN != 1'b0) ? 1 : 0;

    //=========================================================================
    // 1. 复位：异步置位 / 各域同步释放（与厂商件同式 ✓）
    //=========================================================================
    reg  asy_w_rst0, asy_w_rst1, asy_r_rst0, asy_r_rst1;
    wire wr_rst = asy_w_rst1;
    wire rd_rst = asy_r_rst1;

    always @(posedge clkw or posedge rst) begin
        if (rst) begin
            asy_w_rst0 <= 1'b1;
            asy_w_rst1 <= 1'b1;
        end else begin
            asy_w_rst0 <= 1'b0;
            asy_w_rst1 <= asy_w_rst0;
        end
    end

    always @(posedge clkr or posedge rst) begin
        if (rst) begin
            asy_r_rst0 <= 1'b1;
            asy_r_rst1 <= 1'b1;
        end else begin
            asy_r_rst0 <= 1'b0;
            asy_r_rst1 <= asy_r_rst0;
        end
    end

    //=========================================================================
    // 2. 指针与跨域同步（复用厂商模块 ⇒ 同步级数与厂商件一致 ✓）
    //=========================================================================
    reg  [PW-1:0] wbin;          // 写域：已**提交**（凑成整字）的字数
    reg  [PW-1:0] rbin;          // 读域：已取走的字数
    wire [PW-1:0] rbin_sync;     // 读指针 → 写域
    wire [PW-1:0] wbin_sync;     // 写指针 → 读域

    wire [PW-1:0] wr_used = wbin - rbin_sync;   // 写域"已用字数"（保守：读指针滞后 ✓）
    wire [PW-1:0] rd_used = wbin_sync - rbin;   // 读域"可读字数"（保守：写指针滞后 ✓）

    fifo_cross_domain_addr_process_al_afifo_8i_32o_1024 #(
        .ADDR_WIDTH (PW)
    ) rd_to_wr_cross_inst (
        .primary_asreset_i   (rd_rst),
        .secondary_asreset_i (wr_rst),
        .primary_clk_i       (clkr),
        .secondary_clk_i     (clkw),
        .primary_addr_i      (rbin),
        .secondary_addr_o    (rbin_sync)
    );

    fifo_cross_domain_addr_process_al_afifo_8i_32o_1024 #(
        .ADDR_WIDTH (PW)
    ) wr_to_rd_cross_inst (
        .primary_asreset_i   (wr_rst),
        .secondary_asreset_i (rd_rst),
        .primary_clk_i       (clkw),
        .secondary_clk_i     (clkr),
        .primary_addr_i      (wbin),
        .secondary_addr_o    (wbin_sync)
    );

    //=========================================================================
    // 3. 读域：FWFT 读口 + 标志
    //=========================================================================
    wire rd_en_s = re && !empty_flag;      // 与厂商件同式（空时不推进 ✓）

    always @(posedge clkr or posedge rd_rst) begin
        if (rd_rst == 1'b1) begin
            rbin <= {PW{1'b0}};
        end else if (rd_en_s) begin
            rbin <= rbin + {{(PW-1){1'b0}}, 1'b1};
        end
    end

    assign empty_flag = (rd_used == {PW{1'b0}});
    assign aempty     = (rd_used <= AL_EMPTY_NUM);
    assign rdusedw    = rd_used[ADDR_WIDTH_R-1:0];   // ≤255 ⇒ 不回绕 ✓（见文件头"差异 1"）

    // `SHOW_AHEAD_EN=0` 时按"请求后 1 拍出数"给 `valid`（同厂商件 ✓）
    reg re_r1, empty_flag_r1;
    always @(posedge clkr or posedge rd_rst) begin
        if (rd_rst == 1'b1) begin
            re_r1         <= 1'b0;
            empty_flag_r1 <= 1'b1;
        end else begin
            re_r1         <= rd_en_s;
            empty_flag_r1 <= empty_flag;
        end
    end

    assign valid = SHOW_AHEAD ? (!empty_flag) : (re_r1 && !empty_flag_r1);

    //=========================================================================
    // 4. 写域：攒 4 字节 → 一个 32bit 字 → 写 RAM ★ 本工单的核心
    //    小端：第 1 个字节落在 bit[7:0]（与 design §3.1 的打包约定一致 ✓）
    //=========================================================================
    reg  [CW-1:0]           wc;        // 已攒写单位数 0..PACK-1
    reg  [DATA_WIDTH_R-1:0] stage;     // 暂存（小端：第 1 个字节在 bit[7:0]）

    wire                    wr_accept = we && !full_flag;
    wire                    wr_commit = wr_accept && (wc == PACK - 1);
    // ★ 小端装配：第 k 个写单位（wc=k）落到 bit[DATA_WIDTH_W*k +: DATA_WIDTH_W]。
    //   ⇒ 与厂商件一致（`dout[7:0]` = **最先写入**的那个字节 ✓，单元 TB S-02/S-03 逐位核对 ✓）。
    //   注：`stage` 在提交那一拍清 0（见下）⇒ 这里用 `|` 不会串上一字的残留 ✓。
    wire [DATA_WIDTH_R-1:0] stage_shift = {{(DATA_WIDTH_R-DATA_WIDTH_W){1'b0}}, di} << (wc * DATA_WIDTH_W);
    wire [DATA_WIDTH_R-1:0] stage_nx    = stage | stage_shift;

    always @(posedge clkw or posedge wr_rst) begin
        if (wr_rst == 1'b1) begin
            wc <= {CW{1'b0}};
        end else if (wr_accept) begin
            wc <= wc + {{(CW-1){1'b0}}, 1'b1};
        end
    end

    always @(posedge clkw or posedge wr_rst) begin
        if (wr_rst == 1'b1) begin
            stage <= {DATA_WIDTH_R{1'b0}};
        end else if (wr_accept) begin
            // ★ 提交那一拍必须把 stage 清 0：该字已进 RAM，否则上一字的残留字节会串进下一个字 ✗
            stage <= wr_commit ? {DATA_WIDTH_R{1'b0}} : stage_nx;
        end
    end

    always @(posedge clkw or posedge wr_rst) begin
        if (wr_rst == 1'b1) begin
            wbin <= {PW{1'b0}};
        end else if (wr_commit) begin
            wbin <= wbin + {{(PW-1){1'b0}}, 1'b1};
        end
    end

    // 已用量换算成"写单位"（本设计 8bit ⇒ 字节）；打包比是 2 的幂 ⇒ 用移位（不占 DSP ✓）
    wire [PW+PSH:0] used_tunits = wr_used << PSH;
    assign wrusedw = used_tunits[ADDR_WIDTH_W-1:0];   // 本配置 ≤1020 ⇒ 不截断 ✓

    always @(posedge clkw or posedge wr_rst) begin
        if (wr_rst == 1'b1) begin
            full_flag <= 1'b0;
            afull     <= 1'b0;
        end else begin
            // 保守：读指针滞后 ⇒ 只会**早满**、不会溢出 ✓
            full_flag <= (wr_used >= FULL_TH);
            afull     <= (used_tunits >= AL_FULL_NUM);
        end
    end

    //=========================================================================
    // 5. 存储：厂商 `EG_LOGIC_BRAM`，**对称 32→32**、`MODE("DP")`、深度 2 的幂
    //    读口按厂商件同式做"常驻队头"：addrb = rbin + (SHOW_AHEAD & rd_en_s)
    //    ⇒ 弹出后下一拍地址自动落在新队头，`dout` 不需要"先请求再取" ✓
    //=========================================================================
    wire          mem_wea;
    wire [AW-1:0] mem_addra;
    wire [DATA_WIDTH_R-1:0] mem_dia;
    wire          mem_ceb;
    wire [AW-1:0] mem_addrb;
    wire [DATA_WIDTH_R-1:0] mem_dob;
    wire [DATA_WIDTH_R-1:0] mem_doa_unused;

    assign mem_wea   = wr_commit;
    assign mem_addra = wbin[AW-1:0];
    assign mem_dia   = stage_nx;                 // ★ 提交当拍的数据（寄存器 `stage` 是上一拍的值 ✓）
    assign mem_ceb   = SHOW_AHEAD | rd_en_s;
    assign mem_addrb = rbin[AW-1:0] + (SHOW_AHEAD & rd_en_s);

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A (DATA_WIDTH_R),       // ★ 写侧也是 32 位：打包已在触发器里做完 ✓
        .DATA_WIDTH_B (DATA_WIDTH_R),
        .ADDR_WIDTH_A (AW),
        .ADDR_WIDTH_B (AW),
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
        .IMPLEMENT    ("9K")
    ) u_ram (
        .dia   (mem_dia),
        .addra (mem_addra),
        .cea   (1'b1),
        .ocea  (1'b0),
        .clka  (clkw),
        .wea   (mem_wea),
        .rsta  (1'b0),
        .bea   (1'b0),
        .dib   ({DATA_WIDTH_R{1'b0}}),
        .addrb (mem_addrb),
        .ceb   (mem_ceb),
        .oceb  (1'b1),
        .clkb  (clkr),
        .web   (1'b0),
        .rstb  (1'b0),
        .beb   (1'b0),
        .doa   (mem_doa_unused),
        .dob   (mem_dob)
    );

    assign dout = mem_dob;

    //=========================================================================
    // 6. 展开期守卫：不支持的参数组合**故意**停在"模块未定义"（不静默走错路 ✓）
    //    · OUTREG_EN ≠ "NOREG"：本模块只实现 NOREG 直出（见文件头"差异 4"）
    //    · DATA_WIDTH_R/DATA_WIDTH_W 不是 2 的幂：字节数换算只按 2 的幂推导（见 4. 的移位）
    //=========================================================================
    generate
    if (OUTREG_EN != "NOREG") begin : g_outreg_guard
        afifo_8i_32o_bram_outreg_not_implemented_use_NOREG u_guard (.unused(1'b0));
    end
    if ((PACK & (PACK - 1)) != 0) begin : g_pack_guard
        afifo_8i_32o_bram_pack_ratio_must_be_power_of_two u_guard (.unused(1'b0));
    end
    endgenerate

endmodule

`default_nettype wire
