`default_nettype none
//=============================================================================
// rtl/storage_top.v        *** 真实封装顶层 DUT ***
//
//   TF 卡 FAT32 只读文件服务
//     上层完全不用管 SD 物理通信、上电初始化、MBR/BPB、FAT 表、簇链、LBA，
//     只做三件事：
//       1) 看 busy / ready / err_code
//       2) 用描述符索引读素材大小（通用名称/类型接口已在第一组中停用）
//       3) lo_open(index) 后收 lo_rd_valid/lo_rd_data/lo_rd_ready 的字节流
//
//   分层：
//     第 1 层 sd_phy        -> 共用命令通路 + 单个 SPI 字节引擎
//     第 2 层 fat32_mount / fat32_chain / fat32_scan / fat32_sessions / resource_catalog
//     第 3 层 storage_top   -> 编排 + 命令/状态 + 共享资源路由 + err_code 映射
//
//   单时钟域，无 CDC（需求 F-10）。
//   只读：不产生任何写卡命令（需求 F-13）。
//   内部 LBA/簇/FAT 结构全部隐藏，公共端口不出现（需求 F-12）。
//
//   需求依据：storage_top 模块需求规格(1).docx 全部条目；用户确认项 C-01 ~ C-09。
//=============================================================================
module storage_top #(
    parameter integer CLK_HZ            = 50000000,
    parameter integer INIT_SCK_HZ       = 400000,
    // 数据阶段 SCK 目标频率。
    //   ★ 2026-09-26 板上实测结论：**25MHz 采样裕量不足，默认必须用 12.5MHz**。
    //     原因：sd_spi_byte 在"抬起 SCK 的那一拍"采 MISO，留给数据到达的时间只有一个
    //     SCK 半周期 —— 25MHz 时 20ns，而 SD 卡 tODLY 规范上限就有 14ns，再加 FPGA 的
    //     FF→引脚 / 引脚→采样 FF 与 PCB 延迟，预算已经顶到甚至超了。表现为：400kHz 的
    //     初始化永远成功，一进 25MHz 的第一个数据命令（CMD17）就报 E_LBA0；而且按
    //     sd_phy 实例的布线差几 ns 决定正负余量，换一版 P&R 结果就变。
    //     降到 12.5MHz（半周期 40ns）后实测通过（50MB 文件完整读出）。
    //   注意：本模块单独使用（产品路径）时也吃这个默认值，所以这里必须是 12.5MHz。
    parameter integer DATA_SCK_HZ       = 12500000,
    parameter integer FILE_MAX          = 240,
    parameter integer POLL_TIMEOUT_MS   = 1000,
    // WATCHDOG_MS 是「进展型」看门狗（文件执行器 / fat32_scan 每完成一个扇区
    // 或一次簇链查询就复位）：约束的是"多久没有任何进展"，与文件总大小无关。
    // 因此 50MB 文件也能读完（其约 102400 个扇区、每个约 167µs），而真正的卡死
    // 仍会在 2s 内报错。文件扇区缓存预留完整容量，消费者停取不占住 SD 事务。
    parameter integer WATCHDOG_MS       = 2000,
    parameter integer SECTOR_TIMEOUT_MS = 250,
    // CMD0 之前的 0xFF 字节数（冲块，见 sd_init_spi.v 说明）；板上默认 520
    parameter integer PWR_BYTES         = 520,
    // lo 流"想要却拿不到"多久算停滞（毫秒），供 lo_stall 观测
    parameter integer LO_STALL_MS    = 1000,
    parameter         REQUIRE_SDHC      = 1'b1,
    parameter         CRC_ON            = 1'b0,
    parameter         AUTO_START        = 1'b1,
    // ---- 初始化失败自动重试（2026-09-26 加，见文件末注释）----
    //   实测：上电后第一条 CMD0 卡有时不应答（sd_init_spi 报 E_CMD0=1），
    //   隔几十毫秒重新走一次 T_RST+T_INIT 就成功。INIT_RETRY_MAX 是"总尝试次数"
    //   （1 = 不重试，等同旧行为）；INIT_RETRY_MS 是两次尝试之间的等待，
    //   等待期间保持软复位（子模块清零、SD 引脚处于 cs_n=1/sck=0/mosi=1 的静默态）。
    parameter [2:0]   INIT_RETRY_MAX    = 3'd3,
    parameter integer INIT_RETRY_MS     = 50
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 控制 ----
    input  wire        start,        // 脉冲：请求(重新)执行完整上电流程
    output wire        busy,         // 初始化+挂载+目录扫描进行中
    output wire        ready,        // 文件表就绪
    output wire        fail,         // 致命失败（保持）
    output wire [7:0]  err_code,     // {域[7:4], 细码[3:0]}

    // ---- 文件表随机访问 ----
    input  wire [7:0]  file_index,
    output wire [87:0] file_name,    // 11 字节 8.3 原始名
    output wire [1:0]  file_type,    // 0=BMP 1=WAV 2=LRC 3=未知
    output wire [31:0] file_size,    // ★ 实时视图：**当前 `file_index` 指向的那个文件**的大小
                                     //   ⚠️ 它跟着共用读口走、**每拍都可能变** ✗ ⇒ 装载器**绝不能**持续读它 ✓
    output wire [31:0] lo_file_size, // ★★★ 2026-10-10：**lo 会话锁存的文件大小** ✓（装载器必须用它 ✓）
                                     //   【实测证据（(A) 诊断 `[FTO]`）】每一次 `lo` 打开那一刻，
                                     //     读口给出的**名字与大小都是对的** ✓：
                                     //       `lo_idx=1 ft_size=30774 ft_name="S01BG1" | file_index=0` ✓
                                     //     ⇒ **`fat32_read` 拿到的对**（它按 30,774 读满了 ✓）
                                     //     ⇒ 真正错的是 **`bmp_load.file_size`**：它接**实时视图** ✗，
                                     //       装载途中地址切回音频索引 ⇒ 拿到**封面**的 15,414 ✗
                                     //       ⇒ `rd_bytes >= file_size` 提前成立 ⇒ `0x03`、只写一半 ✗
                                     //   【正解】`lo` **同时只有一个会话** ✓ ⇒ **一对寄存器就够** ✓
                                     //     锁存点：`ft_op_sel` 在 T_WOPEN 拍为 1 ⇒ **下一拍**读口数据
                                     //       **必定**是 `lo_sel_idx` 那一项 ✓（不靠巧合 ✓）
                                     //   ★ 代价：32 位寄存器一对、**0 块 BRAM** ✓
                                     //   ★ 曾试错的四条路（加第二读口 ⇒ BRAM 67>64 ✗／多借一拍 ⇒ 播放表坏 ✗／
                                     //     冻结＋延后 start ⇒ A/B 握手坏 ✗／冻结＋地址提前 ⇒ 装载量减半 ✗）
                                     //     **全部作废** ✗ —— 它们修的都是"打开时的采样"，而那里**本来是对的** ✓
    output wire [8:0]  file_total,
    input  wire        select_start,
    input  wire [7:0]  select_from,
    output wire        select_busy, select_done,
    output wire [7:0]  song_total, song_cur, pl_err, skip_cnt, song_max,
    output wire [7:0]  wav_ft, bg_ft1, bg_ft2, bg_ft3,
    output wire [7:0]  cv_ft1, cv_ft2, cv_ft3, lrc_ft,
    output wire        lrc_vld, nx_vld, nx_lrc_vld,
    output wire [7:0]  nx_song, nx_bg1, nx_bg2, nx_bg3,
    output wire [7:0]  nx_cv1, nx_cv2, nx_cv3, nx_wav_ft, nx_lrc_ft,
    output wire        font_valid, asc_valid,
    output wire [31:0] font_size, asc_size,

    // ---- 流式读取 ----
    input  wire        lo_open,         // 脉冲：打开 lo_open_index
    input  wire [7:0]  lo_open_index,
    output wire        lo_open_busy,
    output wire        lo_rd_valid,
    output wire [7:0]  lo_rd_data,
    input  wire        lo_rd_ready,
    output wire        lo_rd_eof,       // 脉冲：本文件读完
    output wire        lo_rd_err,       // 电平：本次读取出错

    // ---- SD 卡引脚 ----
    // ---- 读流 lo（低优先级）----
    input  wire        lo_want,        // 上层：现在需要 lo 的数据
    output wire [7:0]  lo_rd_err_code,  // lo 读域错误码（0=无）
    output wire        lo_stall,        // 观测：lo 想要却拿不到 > LO_STALL_MS
    // ---- 读流 hi（高优先级）----
    input  wire        hi_open,
    input  wire [7:0]  hi_open_index,
    input  wire        hi_want,
    input  wire        hi_refill, // low/high-watermark refill request; unconnected means priority
    output wire        hi_open_busy,
    output wire        hi_rd_valid,
    output wire [7:0]  hi_rd_data,
    input  wire        hi_rd_ready,
    output wire        hi_rd_eof,
    output wire        hi_rd_err,
    output wire [7:0]  hi_rd_err_code,

    output wire        sd_sck,
    output wire        sd_cs_n,
    output wire        sd_mosi,
    input  wire        sd_miso,

    // ---- 上板调试 ----
    output wire [3:0]  dbg_state,
    output wire [3:0]  dbg_init_err,
    output wire        dbg_sdhc,
    // ★ S6 观测口（I1 断言 / 板级 PREN 用）
    output wire [1:0]  dbg_arb_ow,   // 仲裁 owner：0=无 1=hi 2=lo
    output wire        dbg_arb_busy  // 仲裁判据 busy = sec_busy | chn_busy
);

    //=========================================================================
    // 顶层编排状态
    //=========================================================================
    localparam [3:0] T_IDLE   = 4'd0,
                     T_RST    = 4'd1,
                     T_INIT   = 4'd2,
                     T_MOUNT  = 4'd3,
                     T_SCAN   = 4'd4,
                     T_READY  = 4'd5,
                     T_WOPEN  = 4'd6,
                     T_READ   = 4'd7,
                     T_FAIL   = 4'd8,
                     // 初始化重试等待（编码放在 T_FAIL 之后，
                     // 保证 T_FAIL 仍是 8 —— 板级报告/数码管页沿用旧语义）
                     T_RTY    = 4'd9;

    // 两次初始化尝试之间的等待拍数
    localparam [31:0] RTY_CYCLES = (CLK_HZ / 1000) * INIT_RETRY_MS;

    reg [3:0]  state;
    reg [3:0]  rst_cnt;
    reg [2:0]  init_try;          // 已尝试次数（1 = 第一次）
    reg [31:0] rty_cnt;
    reg        auto_fired;
    reg        start_req;
    reg        abort_req;   // ★ 全局软中止请求（start 在读进行中也接受）
    reg        ready_r;
    reg        fail_r;
    reg [7:0]  err_code_r;
    reg [8:0]  file_total_r;
    reg        rd_err_r;
    reg        rd_eof_r;
    reg        init_start_r;
    reg        mnt_start_r;
    reg        scn_start_r;
    reg        rd_start_r;

    reg        ft_op_sel;

    // 文件表读地址：平时跟随上层 file_index（组合选通，保证 file_index -> file_name
    // 只有 1 拍同步读延迟）；lo_open 被接受的那一拍起临时切到 lo_open_index
        reg        hi_op_sel;      // hi 侧 ft 读端口选通
    reg        hi_start_r;     // hi 读启动脉冲
    reg [31:0] hi_rcluster;    // hi 文件首簇（描述符）
    reg [31:0] hi_rsize;       // hi 文件大小（描述符）
    reg [2:0]  hi_st;          // hi 开文件小 FSM
    // ft 读端口地址与"开文件"接受条件见文件后部 hi_rd_* 声明之后的 "★ S6 修" 段

    // 软复位：T_RST 期间拉低子模块复位，用于清除 sd_init_spi 的保持型失败态
    wire       in_soft_rst = (state == T_RST) || (state == T_RTY);
    wire       soft_rst_n  = rst_n & ~in_soft_rst;

    //=========================================================================
    // 子模块互连
    //=========================================================================
    // ---- 第 1 层 ----
    wire        init_busy, init_done, init_fail;
    wire [3:0]  init_err;
    wire        card_sdhc;
    wire        sec_busy, sec_valid, sec_done;
    wire [7:0]  sec_data;
    wire [3:0]  sec_err;
    wire        phy_sec_req, phy_sec_ready;
    wire [31:0] phy_sec_lba;

    // ---- 第 2 层：挂载 ----
    wire        mnt_busy, mnt_done, mnt_sec_req, mnt_sec_ready;
    wire [3:0]  mnt_err;
    wire [31:0] mnt_sec_lba;
    wire [31:0] part_lba, fat_lba, data_lba, root_cluster, total_clusters;
    wire [3:0]  spc_shift;

    // ---- 第 2 层：簇链 ----
    wire        chn_req, chn_busy, chn_done, chn_sec_req, chn_sec_ready;
    wire [31:0] chn_cluster, chn_next, chn_sec_lba;
    wire [3:0]  chn_err;

    // ---- 第 2 层：扫描 ----
    wire        scn_busy, scn_done, scn_sec_req, scn_sec_ready;
    wire [3:0]  scn_err;
    wire [31:0] scn_sec_lba;
    wire [8:0]  scn_file_total;
    wire        scn_chain_req;
    wire [31:0] scn_chain_cluster;
    wire        scn_ft_we;
    wire [8:0]  scn_ft_index;
    wire [87:0] scn_ft_name;
    wire [1:0]  scn_ft_type;
    wire [31:0] scn_ft_size, scn_ft_cluster;

    // ---- 第 2 层：文件读 ----
    wire        rd_busy, rd_done, rd_sec_req, rd_sec_ready;
    wire [3:0]  rd_fs_err;
    wire [31:0] rd_sec_lba;
    wire        rd_chain_req;
    wire [31:0] rd_chain_cluster;

    // ---- 文件表读端口 ----
    wire ft_rvalid, lo_index_valid, hi_index_valid;
    wire [31:0] ft_rsize, ft_rcluster;

    //=========================================================================
    // 共享资源路由（时间上互斥，固定优先级：mount > chain > read > scan）
    //
    // sec_own 保持整个事务的 mount/chain/file/scan 归属，数据阶段请求脉冲已消失。
    // LBA 在请求拍选择；ready 在数据阶段根据锁存归属选择。
    // 文件执行器在完整 SD/FAT 事务结束后调度会话，各路缓存和滑板保留数据归属。
    // want 做 x 容忍：未连接时 lo 视为 1、hi 视为 0，兼容旧的单流调用。
    //=========================================================================
    wire lo_want_i = (lo_want !== 1'b0) && !abort_req;
    wire hi_want_i = (hi_want === 1'b1);

    wire hi_rd_busy, hi_rd_done, hi_rd_dvalid;
    wire [3:0] hi_rd_fs_err;
    wire [7:0] hi_rd_ddata;
    wire [1:0] arb_owner;
    wire executor_idle;
    //-----------------------------------------------------------------
    // ★ S6 修：ft 读端口只有一个 ⇒ 两条流"开文件"必须互斥，且 1 拍脉冲不能丢（B2）；
    //   hi 的描述符原先比 lo 早一拍捕获 ⇒ 抓到的是 file_index 的条目（B1）。
    //   lo 侧：地址拍 = T_WOPEN（ft_op_sel=1），捕获拍 = T_READ（共享执行器下一拍采）。
    //   hi 侧：地址拍 = st=1（hi_op_sel=1），捕获拍 = st=2。
    //-----------------------------------------------------------------
    reg        lo_open_pend;    // lo_open 脉冲已锁存（被 hi 抢先时不会丢）
    reg  [7:0] lo_open_idx_p;
    reg  [7:0] lo_sel_idx;      // 本次被接受的 lo index（T_WOPEN 地址拍用）
    reg        hi_open_pend;    // hi_open 脉冲已锁存
    reg  [7:0] hi_open_idx_p;
    reg  [7:0] hi_sel_idx;      // 本次被接受的 hi index（st=1 地址拍用）

    wire lo_open_vld = (state == T_READY) && lo_open &&
                       lo_index_valid;
    wire hi_open_vld = hi_open && hi_index_valid;
    // lo 本拍想用 ft 端口（还没考虑 hi 抢占）
    wire lo_accept_raw = (state == T_READY) && (lo_open_pend || lo_open_vld);
    // hi 优先（两条流同拍要端口时 lo 让位）；ft_op_sel=1 说明 lo 正在地址拍，
    // 此时 hi 起的地址拍会与之重叠 ⇒ 让 hi 等这一拍（只差 1 拍，不丢请求）
    wire hi_ft_req = hi_open_pend && ready && !hi_rd_busy &&
                     (hi_st == 3'd0) && !ft_op_sel;
    wire lo_accept = lo_accept_raw && !hi_ft_req;
    wire [7:0] ft_raddr = hi_op_sel ? hi_sel_idx :
                          (ft_op_sel ? lo_sel_idx : file_index);

    // 请求锁存：只有"看见了却没被接受"的请求才留在 pend 里
    //   （★ 注意：被接受的那一拍必须清零，否则会自我重开 ⇒ 读完后自动重读同一个文件）
    //   同拍"接受旧请求 + 又来新脉冲"⇒ 新请求继续留在 pend（不丢）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)              lo_open_pend <= 1'b0;
        else if (state == T_RST) lo_open_pend <= 1'b0;
        else if (lo_accept)      lo_open_pend <= lo_open_vld && lo_open_pend;
        else if (lo_open_vld)    lo_open_pend <= 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)           lo_open_idx_p <= 8'd0;
        else if (lo_open_vld) lo_open_idx_p <= lo_open_index;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)         lo_sel_idx <= 8'd0;
        else if (lo_accept) lo_sel_idx <= lo_open_pend ? lo_open_idx_p : lo_open_index;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)              hi_open_pend <= 1'b0;
        else if (state == T_RST) hi_open_pend <= 1'b0;
        else if (hi_ft_req)      hi_open_pend <= hi_open_vld && hi_open_pend;
        else if (hi_open_vld)    hi_open_pend <= 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)           hi_open_idx_p <= 8'd0;
        else if (hi_open_vld) hi_open_idx_p <= hi_open_index;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)         hi_sel_idx <= 8'd0;
        else if (hi_ft_req) hi_sel_idx <= hi_open_idx_p;
    end
    wire rd_sec_go=rd_sec_req;
    wire [31:0] rd_sec_lba_sel=rd_sec_lba;
    wire [1:0] sec_sel = mnt_sec_req ? 2'd0 :
                         chn_sec_req ? 2'd1 :
                         rd_sec_go ? 2'd2 : 2'd3;

    reg  [1:0] sec_own;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)            sec_own <= 2'd0;
        else if (mnt_sec_req)  sec_own <= 2'd0;
        else if (chn_sec_req)  sec_own <= 2'd1;
        else if (rd_sec_go) sec_own <= 2'd2;
        else if (scn_sec_req)  sec_own <= 2'd3;
    end

    assign phy_sec_req = mnt_sec_req | chn_sec_req | rd_sec_go | scn_sec_req;

    // LBA 用当拍优先级：sd_phy 在请求拍锁存 LBA，此时 sec_own 还没更新
    assign phy_sec_lba = (sec_sel == 2'd0) ? mnt_sec_lba :
                         (sec_sel == 2'd1) ? chn_sec_lba :
                         (sec_sel == 2'd2) ? rd_sec_lba_sel : scn_sec_lba;

    // ready 用锁存归属：它在整个数据阶段都要保持正确
    assign phy_sec_ready = (sec_own == 2'd0) ? mnt_sec_ready :
                           (sec_own == 2'd1) ? chn_sec_ready :
                           (sec_own == 2'd2) ? rd_sec_ready  : scn_sec_ready;

    assign chn_req     = scn_chain_req | rd_chain_req;
    assign chn_cluster = scn_chain_req    ? scn_chain_cluster :
                     rd_chain_cluster;

    //=========================================================================
    // 第 1 层实例
    //=========================================================================
    sd_phy #(
        .CLK_HZ            (CLK_HZ),
        .INIT_SCK_HZ       (INIT_SCK_HZ),
        .DATA_SCK_HZ       (DATA_SCK_HZ),
        .POLL_TIMEOUT_MS   (POLL_TIMEOUT_MS),
        .WATCHDOG_MS       (WATCHDOG_MS),
        .SECTOR_TIMEOUT_MS (SECTOR_TIMEOUT_MS),
        .RESP_MAX_BYTES    (16),
        .PWR_BYTES         (PWR_BYTES),
        .REQUIRE_SDHC      (REQUIRE_SDHC),
        .CRC_ON            (CRC_ON)
    ) u_sd_phy (
        .clk          (clk),
        .rst_n        (soft_rst_n),
        .init_start   (init_start_r),
        .init_busy    (init_busy),
        .init_done    (init_done),
        .init_fail    (init_fail),
        .init_err     (init_err),
        .card_ocr     (),
        .card_sdhc    (card_sdhc),
        .sec_req      (phy_sec_req),
        .sec_lba      (phy_sec_lba),
        .sec_busy     (sec_busy),
        .sec_valid    (sec_valid),
        .sec_data     (sec_data),
        .sec_ready    (phy_sec_ready),
        .sec_done     (sec_done),
        .sec_err      (sec_err),
        .sec_crc_rx   (),
        .sec_crc_calc (),
        .sd_sck       (sd_sck),
        .sd_cs_n      (sd_cs_n),
        .sd_mosi      (sd_mosi),
        .sd_miso      (sd_miso)
    );

    //=========================================================================
    // 第 2 层实例
    //=========================================================================
    fat32_mount u_mount (
        .clk            (clk),
        .rst_n          (soft_rst_n),
        .start          (mnt_start_r),
        .busy           (mnt_busy),
        .done           (mnt_done),
        .err            (mnt_err),
        .part_lba       (part_lba),
        .fat_lba        (fat_lba),
        .data_lba       (data_lba),
        .spc_shift      (spc_shift),
        .root_cluster   (root_cluster),
        .total_clusters (total_clusters),
        .sec_req        (mnt_sec_req),
        .sec_lba        (mnt_sec_lba),
        .sec_valid      (sec_valid),
        .sec_data       (sec_data),
        .sec_done       (sec_done),
        .sec_err        (sec_err),
        .sec_ready      (mnt_sec_ready)
    );

    fat32_chain u_chain (
        .clk            (clk),
        .rst_n          (soft_rst_n),
        .req            (chn_req),
        .cluster        (chn_cluster),
        .busy           (chn_busy),
        .done           (chn_done),
        .err            (chn_err),
        .next_cluster   (chn_next),
        .fat_lba        (fat_lba),
        .total_clusters (total_clusters),
        .sec_req        (chn_sec_req),
        .sec_lba        (chn_sec_lba),
        .sec_valid      (sec_valid),
        .sec_data       (sec_data),
        .sec_done       (sec_done),
        .sec_err        (sec_err),
        .sec_ready      (chn_sec_ready)
    );

    fat32_scan #(
        .FILE_MAX    (FILE_MAX),
        .CLK_HZ      (CLK_HZ),
        .WATCHDOG_MS (WATCHDOG_MS)
    ) u_scan (
        .clk            (clk),
        .rst_n          (soft_rst_n),
        .start          (scn_start_r),
        .busy           (scn_busy),
        .done           (scn_done),
        .err            (scn_err),
        .file_total     (scn_file_total),
        .data_lba       (data_lba),
        .spc_shift      (spc_shift),
        .root_cluster   (root_cluster),
        .total_clusters (total_clusters),
        .chain_req      (scn_chain_req),
        .chain_cluster  (scn_chain_cluster),
        .chain_done     (chn_done),
        .chain_err      (chn_err),
        .chain_next     (chn_next),
        .sec_req        (scn_sec_req),
        .sec_lba        (scn_sec_lba),
        .sec_valid      (sec_valid),
        .sec_data       (sec_data),
        .sec_done       (sec_done),
        .sec_err        (sec_err),
        .sec_ready      (scn_sec_ready),
        .ft_we          (scn_ft_we),
        .ft_index       (scn_ft_index),
        .ft_name        (scn_ft_name),
        .ft_type        (scn_ft_type),
        .ft_size        (scn_ft_size),
        .ft_cluster     (scn_ft_cluster)
    );

    fat32_sessions #(.CLK_HZ(CLK_HZ),.WATCHDOG_MS(WATCHDOG_MS),.LO_STALL_MS(LO_STALL_MS)) u_files (
        .clk(clk),.rst_n(soft_rst_n),
        .lo_start(rd_start_r),.lo_cluster(ft_rcluster),.lo_size(ft_rsize),
        .hi_start(hi_start_r),.hi_cluster(hi_rcluster),.hi_size(hi_rsize),
        .lo_want(lo_want_i),.hi_want(hi_want_i && !abort_req),.hi_refill(hi_refill !== 1'b0),
        .lo_busy(rd_busy),.hi_busy(hi_rd_busy),.lo_done(rd_done),.hi_done(hi_rd_done),
        .lo_err(rd_fs_err),.hi_err(hi_rd_fs_err),
        .lo_valid(lo_rd_valid),.lo_data(lo_rd_data),.lo_ready(lo_rd_ready),
        .hi_valid(hi_rd_dvalid),.hi_data(hi_rd_ddata),.hi_ready(hi_rd_ready),
        .data_lba(data_lba),.spc_shift(spc_shift),.total_clusters(total_clusters),
        .sec_req(rd_sec_req),.sec_lba(rd_sec_lba),.sec_ready(rd_sec_ready),
        .sec_busy(sec_busy),.sec_valid(sec_valid && sec_own==2'd2),.sec_data(sec_data),
        .sec_done(sec_done && sec_own==2'd2),.sec_err(sec_err),
        .chain_req(rd_chain_req),.chain_cluster(rd_chain_cluster),.chain_busy(chn_busy),
        .chain_done(chn_done),.chain_err(chn_err),.chain_next(chn_next),
        .owner(arb_owner),.safe_idle(executor_idle),.lo_stall(lo_stall)
    );

    resource_catalog u_ft (
        .clk        (clk),
        .rst_n      (rst_n),
        .clear      (scn_start_r),
        .wr_en      (scn_ft_we),
        .wr_name    (scn_ft_name),
        .wr_type    (scn_ft_type),
        .wr_size    (scn_ft_size),
        .wr_cluster (scn_ft_cluster),
        .rd_index   (ft_raddr),
        .rd_valid   (ft_rvalid),
        .lo_index(lo_open_index), .hi_index(hi_open_index),
        .lo_valid(lo_index_valid), .hi_valid(hi_index_valid),
        .rd_size    (ft_rsize),
        .rd_cluster (ft_rcluster),
        .select_start(select_start), .start_from(select_from),
        .select_busy(select_busy), .select_done(select_done),
        .song_total(song_total), .song_cur(song_cur), .pl_err(pl_err),
        .skip_cnt(skip_cnt), .song_max(song_max),
        .wav_ft(wav_ft), .bg_ft1(bg_ft1), .bg_ft2(bg_ft2), .bg_ft3(bg_ft3),
        .cv_ft1(cv_ft1), .cv_ft2(cv_ft2), .cv_ft3(cv_ft3),
        .lrc_ft(lrc_ft), .lrc_vld(lrc_vld),
        .nx_vld(nx_vld), .nx_song(nx_song),
        .nx_bg1(nx_bg1), .nx_bg2(nx_bg2), .nx_bg3(nx_bg3),
        .nx_cv1(nx_cv1), .nx_cv2(nx_cv2), .nx_cv3(nx_cv3),
        .nx_wav_ft(nx_wav_ft), .nx_lrc_ft(nx_lrc_ft),
        .nx_lrc_vld(nx_lrc_vld),
        .font_valid(font_valid), .asc_valid(asc_valid),
        .font_size(font_size), .asc_size(asc_size)
    );

    //=========================================================================
    // 文件表读地址仲裁：lo_open 期间临时切到 lo_open_index，其余时间跟随 file_index
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          ft_op_sel <= 1'b0;
        else if (lo_accept)  ft_op_sel <= 1'b1;
        else                 ft_op_sel <= 1'b0;
    end

    //=========================================================================
    // 启动请求仲裁
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            auto_fired <= 1'b0;
            start_req  <= 1'b0;
            abort_req  <= 1'b0;
        end else begin
            start_req <= 1'b0;
            if (AUTO_START && !auto_fired) begin
                auto_fired <= 1'b1;
                start_req  <= 1'b1;
            end
            // 用户重新初始化：lo_open_busy 期间忽略，避免中途切断 SPI 数据块
            if (start && !rd_busy && !hi_rd_busy &&
                ((state == T_IDLE) || (state == T_READY) || (state == T_FAIL))) begin
                start_req <= 1'b1;
            end
            // ★ 全局软中止（S5）：读进行中也接受 start ⇒ 只置标志；
            //   置位/清零都在本块内完成（避免跨块多驱动），主块只做 state 跳转。
            if (start && (rd_busy || hi_rd_busy)) abort_req <= 1'b1;
            if (abort_req && executor_idle && !sec_busy && !chn_busy) abort_req <= 1'b0;
        end
    end

    //=========================================================================
    // 编排状态机
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= T_IDLE;
            rst_cnt      <= 4'd0;
            init_try     <= 3'd0;
            rty_cnt      <= 32'd0;
            ready_r      <= 1'b0;
            fail_r       <= 1'b0;
            err_code_r   <= 8'h00;
            file_total_r <= 9'd0;
            rd_err_r     <= 1'b0;
            rd_eof_r     <= 1'b0;
            init_start_r <= 1'b0;
            mnt_start_r  <= 1'b0;
            scn_start_r  <= 1'b0;
            rd_start_r   <= 1'b0;
        end else begin
            init_start_r <= 1'b0;
            mnt_start_r  <= 1'b0;
            scn_start_r  <= 1'b0;
            rd_start_r   <= 1'b0;
            // ★ S5：软中止到达扇区边界（无事务/无链查询在飞）⇒ 拉回 T_RST。
            //   放在 case 之前：本块的 state 赋值只归本块；若当前状态没有
            //   其它 state 赋值（例如 T_READ 在等 rd_done），本条即生效。
            if (abort_req && executor_idle && !sec_busy && !chn_busy) begin
                state     <= T_RST;
            end
            rd_eof_r     <= 1'b0;

            case (state)
            //-----------------------------------------------------------------
            T_IDLE: begin
                ready_r <= 1'b0;
                if (start_req) begin
                    rst_cnt  <= 4'd0;
                    init_try <= 3'd0;          // 新的一轮：重试计数清零
                    state    <= T_RST;
                end
            end
            //-----------------------------------------------------------------
            // 软复位 8 拍：清除全部子模块（含 sd_init_spi 的保持型失败态）
            T_RST: begin
                ready_r      <= 1'b0;
                fail_r       <= 1'b0;
                err_code_r   <= 8'h00;
                file_total_r <= 9'd0;
                rd_err_r     <= 1'b0;
                if (rst_cnt == 4'd7) begin
                    init_start_r <= 1'b1;      // 软复位释放的同一拍发出初始化脉冲
                    state        <= T_INIT;
                end else begin
                    rst_cnt <= rst_cnt + 4'd1;
                end
            end
            //-----------------------------------------------------------------
            T_INIT: begin
                if (init_done) begin
                    // 单拍脉冲：只在进入 T_MOUNT 的瞬间启动一次挂载
                    mnt_start_r <= 1'b1;
                    state       <= T_MOUNT;
                end else if (init_fail) begin
                    // 上电瞬态（例如第一条 CMD0 不应答）不直接判死：
                    // 还有重试次数就先等一会儿，再走一次 T_RST+T_INIT。
                    if (init_try + 3'd1 < INIT_RETRY_MAX) begin
                        init_try <= init_try + 3'd1;
                        rty_cnt  <= RTY_CYCLES;
                        state    <= T_RTY;
                    end else begin
                        err_code_r <= {4'h1, init_err};
                        state      <= T_FAIL;
                    end
                end
            end
            //-----------------------------------------------------------------
            // 重试等待：期间 in_soft_rst=1（子模块清零、SD 引脚静默），等够了再重来
            T_RTY: begin
                ready_r <= 1'b0;
                if (rty_cnt >= 32'd1) begin
                    rty_cnt <= rty_cnt - 32'd1;
                end else begin
                    rst_cnt <= 4'd0;
                    state   <= T_RST;
                end
            end
            //-----------------------------------------------------------------
            T_MOUNT: begin
                if (mnt_done) begin
                    if (mnt_err != 4'd0) begin
                        err_code_r <= {4'h3, mnt_err};
                        state      <= T_FAIL;
                    end else begin
                        // 单拍脉冲：只在进入 T_SCAN 的瞬间启动一次扫描
                        scn_start_r <= 1'b1;
                        state       <= T_SCAN;
                    end
                end
            end
            //-----------------------------------------------------------------
            T_SCAN: begin
                if (scn_done) begin
                    if (scn_err != 4'd0) begin
                        err_code_r <= {4'h4, scn_err};
                        state      <= T_FAIL;
                    end else begin
                        file_total_r <= scn_file_total;
                        ready_r      <= 1'b1;
                        state        <= T_READY;
                    end
                end
            end
            //-----------------------------------------------------------------
            T_READY: begin
                ready_r <= 1'b1;
                if (lo_accept) begin
                    rd_err_r <= 1'b0;
                    state    <= T_WOPEN;
                end else if (lo_open && !lo_open_vld && !lo_open_pend) begin
                    // 无效索引：仍按旧语义报 0x61；被 hi 抢 ft 端口则什么都不做
                    err_code_r <= {4'h6, 4'h1};
                end
            end
            //-----------------------------------------------------------------
            // 等文件表读端口把 lo_open_index 的首簇/大小取出（同步读 1 拍）
            T_WOPEN: begin
                ready_r    <= 1'b1;
                rd_start_r <= 1'b1;
                state      <= T_READ;
            end
            //-----------------------------------------------------------------
            T_READ: begin
                ready_r <= 1'b1;
                if (lo_open) err_code_r <= {4'h6, 4'h3};        // 0x63 读取中重复 lo_open
                if (rd_done) begin
                    if (rd_fs_err != 4'd0) begin
                        err_code_r <= {4'h5, rd_fs_err};
                        rd_err_r   <= 1'b1;
                    end else begin
                        rd_eof_r   <= 1'b1;
                    end
                    state <= T_READY;
                end
            end
            //-----------------------------------------------------------------
            // 注：T_FAIL 期间忽略 lo_open，以免用 0x62 覆盖已锁存的致命错误码
            T_FAIL: begin
                ready_r <= 1'b0;
                fail_r  <= 1'b1;
            end
            //-----------------------------------------------------------------
            default: begin
                err_code_r <= 8'hF0;
                state      <= T_FAIL;
            end
            endcase
        end
    end

    //=========================================================================
    // 对外输出
    //=========================================================================
    assign busy       = (state == T_RST) || (state == T_INIT) ||
                        (state == T_MOUNT) || (state == T_SCAN);

    assign ready      = ready_r;
    assign fail       = fail_r;
    assign err_code   = err_code_r;
    assign file_total = file_total_r;

    assign file_name  = 88'd0;
    assign file_type  = 2'd3;
    assign file_size  = ft_rsize;

    //=========================================================================
    // ★★★ 2026-10-10 正解（**64 个寄存器、0 块 BRAM** ✓）：**lo 会话的大小/首簇锁存** ✓
    //   依据见端口 `lo_file_size` 的注释（`[FTO]` 实测：打开那一刻读口给的是**对的** ✓，
    //   错在 `bmp_load` 持续读实时视图 ✗）✓
    //   时序（`file_table` 读数据是**寄存输出** ⇒ 比地址晚一拍 ✓）：
    //     周期0 `T_READY` `lo_accept=1` ⇒ `lo_sel_idx` 已置入
    //     周期1 `T_WOPEN` `ft_op_sel=1` ⇒ `ft_raddr = lo_sel_idx`（此拍数据仍是上一个 ✗）
    //     周期2 `T_READ`1 `ft_op_sel_d=1` ⇒ **数据 = lo 那一项** ✓ ← ★ 锁存点（保证正确 ✓）
    //   ★ 只锁大小与首簇（装载器需要的两样 ✓），**不锁名字/类型** ⇒ 不动实时视图 ✓
    //=========================================================================
    reg        ft_op_sel_d;
    reg [31:0] lo_fsize_r;
    reg [31:0] lo_fclust_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ft_op_sel_d <= 1'b0;
        else        ft_op_sel_d <= ft_op_sel;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)           begin lo_fsize_r <= 32'd0; lo_fclust_r <= 32'd0; end
        else if (ft_op_sel_d) begin lo_fsize_r <= ft_rsize; lo_fclust_r <= ft_rcluster; end
    end
    assign lo_file_size = lo_fsize_r;

    assign lo_open_busy  = (state == T_READ);

    // hi 侧由共享执行器 u_files 中的独立音频会话驱动。
    assign lo_rd_eof     = rd_eof_r;
    assign lo_rd_err     = rd_err_r;
    // lo 读域错误码：无错 0x00；出错 0x5x（与 hi 同构）
    assign lo_rd_err_code = rd_err_r ? {4'h5, rd_fs_err} : 8'h00;

    assign dbg_state    = state;
    assign dbg_init_err = init_err;
    assign dbg_sdhc     = card_sdhc;
    assign dbg_arb_ow   = arb_owner;
    assign dbg_arb_busy = sec_busy | chn_busy;


    //-----------------------------------------------------------------
    // 第二路读流 hi（S4a：实例就位，消费侧接真值）
    //   S4b 待做：hi 文件描述符（共享 file_table 读端口分时）、hi 开文件小 FSM、
    //            两条读流共用扇区 mux 的 slot 2、按 arb_owner 选通响应、
    //            hi_req 以 raw 请求进仲裁器（门控后才进共享 chain）
    //   现 start 接 0、响应接 0、sec_wait 接 1 ⇒ 只占资源、不产生任何行为
    //-----------------------------------------------------------------

    assign hi_open_busy   = hi_rd_busy;
    assign hi_rd_valid    = hi_rd_dvalid;
    assign hi_rd_data     = hi_rd_ddata;
    assign hi_rd_eof      = hi_rd_done;
    assign hi_rd_err      = (hi_rd_fs_err != 4'd0);
    assign hi_rd_err_code = hi_rd_err ? {4'h5, hi_rd_fs_err} : 8'h00;

    //-----------------------------------------------------------------
    // S4b-1：hi 开文件小 FSM（只驱动本块自己的寄存器）
    //   open 合法（hi_ft_req，见文件前部）⇒ 本拍起是"地址拍"(st=1)；下一拍 (st=2)
    //   等 ft 同步读输出生效后再捕获描述符 ⇒ 脉冲 start 给 u_files 的 hi 会话 ⇒ 等它跑完。
    //   ★ S6 修：原先地址拍与捕获拍合成一拍 ⇒ 抓的是上一拍地址(file_index)的条目。
    //-----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hi_op_sel   <= 1'b0;
            hi_start_r  <= 1'b0;
            hi_rcluster <= 32'd0;
            hi_rsize    <= 32'd0;
            hi_st       <= 3'd0;
        end else begin
            hi_start_r <= 1'b0;
            case (hi_st)
            3'd0: if (hi_ft_req) begin            // 被接受 ⇒ 本拍就是地址拍
                      hi_op_sel <= 1'b1;
                      hi_st     <= 3'd1;
                  end
            3'd1: begin                           // 地址拍结束：等 ft 同步读输出
                      hi_op_sel <= 1'b0;
                      hi_st     <= 3'd2;
                  end
            3'd2: begin                           // 捕获拍：此刻 ft 输出 = hi 的条目
                      hi_rcluster <= ft_rcluster;
                      hi_rsize    <= ft_rsize;
                      hi_start_r  <= 1'b1;
                      hi_st       <= 3'd3;
                  end
            3'd3: if (hi_rd_busy) hi_st <= 3'd4;   // 等读真正起来
            3'd4: if (!hi_rd_busy) hi_st <= 3'd0;  // 读完/出错后可再 open
            default: hi_st <= 3'd0;
            endcase
        end
    end

endmodule
`default_nettype wire
