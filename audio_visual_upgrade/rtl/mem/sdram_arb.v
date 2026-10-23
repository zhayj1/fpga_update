`default_nettype none
//============================================================================
// rtl/mem/sdram_arb.v —— 多客户 SDRAM 仲裁器（下层 = 厂商 sdr_as_ram）
//
// ★ 状态：**已验证**（2026-10-01）。两件事都已实证：
//   ① `tb/tb_sdram_arb.v` 功能 PASS：写 2048 → 读回 2048/2048 逐字相符，三客户口可用。
//   ② 与厂商 `app_wrrd` 在**器件可见界面逐拍等价**：4096 拍（写 2048 + 读 2048，含首/末组）
//      的 `CMD/BA/A10` 与 `rd_en/rd_addr/wr_en/wr_addr` **0 拍不一致**
//      （`tb/tb_trcd_diff.v` → `doc/evidence/p0_trcd_trace150.log`）。
//   ⇒ **本文件的逻辑一行都没必要改**；"tRCD 违例"是器件模型速度档问题，见下面契约 6。
//
// 实测契约（全部来自 doc/design_music_player.md §3.4.5/§3.4.6，违反即出错）：
//   1. 地址相位：`App_rd_addr` 在**第一个 `App_rd_en` 拍**必须等于突发基址，之后与使能同拍 +1。
//      （厂商 app_wrrd 用 rd_addr_1d 多寄存一拍实现；我早期的突发引擎把首地址给成 base+1，
//        结果控制器一条 READ 都不发 —— 这是本轮最大的坑之一。）
//   2. 读写互斥：一次只做一件事（App_rd_en 与 App_wr_en 不同时）。
//   3. 有界突发：单次 ≤ MAX_BURST（默认 2048）字。实测 8192 拍连续读会触发器件 tRCD 违例。
//   4. 刷新避让：`Sdr_init_ref_vld` 为高时不得操作；突发中途遇刷新 ⇒
//      **撤使能、保持现场、等它变低后接着发**（暂停，不中止 —— 客户侧无感）。
//   5. 读数据：Sdr_rd_en 有效后每拍 1 字；延迟恒定 10 拍（实测）。
//   7. ★ 装载写 LD 的**突发长度下限 = 4 字**（2026-10-01 实测，集成层发现）：
//      真卡路径下 `bmp_load` 曾按"FIFO 非空就发"⇒ 突发恒为 1 字 ⇒ **一个字都写不进 SDRAM**
//      （器件模型无任何报错、本模块协议计数也全对 ⇒ 从接口上看不出异常）。
//      受控扫描（`+WLEN=`，每次只改这一个变量；写 N 字后读回 16 字）：
//        N=1/2/3 ⇒ 16/16 全错（**整笔被厂商控制器丢弃**）；N=4 ⇒ 前 4 字落盘；N=8/16 ⇒ 全落盘。
//      ⇒ 写侧客户**必须**保证单次 `ld_len ≥ 4`（且 ≤ MAX_BURST、不跨行）；
//        读侧（px/ctl）无此限制（长突发本就是它的形态）。
//      与契约 1（地址相位）是同一类"器件可见界面"约束：只测长突发会漏掉。
//   6. 时钟（★ 2026-10-01 新增，与相位并列的硬约束）：IP 的 **ACT→READ/WRITE 固定隔 3 拍**
//      （纯周期逻辑：100/140/145/150MHz 下间隔直方图**全是 `3:512`**）⇒ 器件必须满足
//      **tRCD ≤ 3×T**。150MHz 时 3 拍 = 20ns，而随包模型 IS42s32200.v 是 **-7 档 tRCD=21ns**
//      ⇒ **每一次** ACT→访问都报 tRCD，**厂商 app_wrrd 在同频同相位下一条不少**（各 1024 条、
//      逐条同刻成对）。⇒ 这是**模型速度档**问题，**不是本模块的错**（改本模块只会偏离厂商波形）。
//      实测边界：143MHz 仍报 16 条，**142MHz 与 100MHz 均为 0 条**。
//      上板料号 AEM638325TS-6IG 是 **166MHz 级（SDR-166）⇒ tRCD ≤ 18ns ⇒ 150MHz 合法**。
//
// ★ 握手铁律（2026-10-01 `tb_arb_soak` 实证）：`req` 是**电平**，且本模块**不做边沿检测** ⇒
//   客户必须在 **`ack` 后立刻撤 `req`**（**不能**等到 `done` 才撤）。撤晚了哪怕只多一拍，
//   就会被当成一次**新的请求**再执行一遍 —— 浸泡台里 `ctl` 因此被重复执行了 4 次
//   （读出 64 字而不是 16 字）。标准用法：
//       req<=1'b1;  while(!ack) @(posedge clk);  req<=1'b0;  while(!done) @(posedge clk);
//   （P2 的取数引擎/字库客户都必须照这个写；或把 req 做成单拍脉冲。）
//
// ★ 关于 `S_PAUSE`（遇 `Sdr_init_ref_vld` 暂停）：`self_refresh_open=1'b1` 时 IP 自己管刷新，
//   浸泡台跑约 30 万拍只见 **1 个** `ref_vld` 脉冲（高 30 拍）、**突发期间 0 次**、`S_PAUSE` 进入 **0 次**
//   ⇒ 这条分支在本配置下**几乎不可达**，只作为防御保留，别指望靠激励验证它。
//
// 客户侧（三条口，优先级 像素 > 控制 > 装载）：
//   · 像素读 PX ：长突发流式读（最高优先级、可抢占控制/装载）
//   · 控制读 CTL：短随机读（字库/歌词表）
//   · 装载写 LD ：写突发（FWFT：arb 取走时拉 ld_rd）
//   握手：req（电平，保持到 ack）→ ack（脉冲）→ done（脉冲）；读数据随 valid 流出
//============================================================================
module sdram_arb #(
    parameter integer MAX_BURST = 2048
)(
    input  wire        clk,          // = Sdr_clk
    input  wire        rst_n,

    // ---------- 到 sdr_as_ram 的裸应用口 ----------
    output reg         app_rd_en,
    output reg  [20:0] app_rd_addr,
    output reg         app_wr_en,
    output reg  [20:0] app_wr_addr,
    output reg  [3:0]  app_wr_dm,
    output wire [31:0] app_wr_din,     // ★ 组合直通 ld_data：写地址与写数据必须同拍（见文件头契约 1）
    input  wire        sdr_rd_en,
    input  wire [31:0] sdr_rd_dout,
    input  wire        sdr_busy,
    input  wire        sdr_init_done,
    input  wire        sdr_init_ref_vld,

    // ---------- 客户 0：像素（长突发流式读，最高优先级）----------
    input  wire        px_req,
    input  wire [20:0] px_addr,
    input  wire [15:0] px_len,
    output reg         px_ack,
    output reg         px_done,
    output reg  [31:0] px_data,
    output reg         px_valid,

    // ---------- 客户 1：控制/字库（短读）----------
    input  wire        ctl_req,
    input  wire [20:0] ctl_addr,
    input  wire [15:0] ctl_len,
    output reg         ctl_ack,
    output reg         ctl_done,
    output reg  [31:0] ctl_data,
    output reg         ctl_valid,

    // ---------- 客户 2：装载写 ----------
    input  wire        ld_req,
    input  wire [20:0] ld_addr,
    input  wire [15:0] ld_len,
    input  wire [31:0] ld_data,      // FWFT：arb 拉 ld_rd 即取走本拍的值
    output reg         ld_rd,
    output reg         ld_ack,
    output reg         ld_done,

    // ---------- 观测 ----------
    output reg         arb_busy,
    output reg  [3:0]  gnt            // 0=无 1=像素 2=控制 3=装载
);

    localparam [2:0] S_IDLE = 3'd0,   // 等请求
                     S_RUN  = 3'd1,   // 突发进行中（每拍发一个字）
                     S_PAUSE= 3'd2,   // 遇刷新：撤使能等它过去
                     S_DRAIN= 3'd3,   // 发完使能已撤，等读数据收齐
                     S_GAP  = 3'd4;   // 写后留给 SDRAM 控制器完成内部收尾

    reg [2:0]  st;
    reg [1:0]  act;                   // 当前服务的客户
    reg        act_wr;                // 1=写
    reg [20:0] base;
    reg [15:0] len;
    reg [15:0] n;                     // 已发字数
    reg [15:0] got;                   // 已收字数（读）
    reg [5:0]  settle;                // 刷新后沉降等待（厂商遇刷新是整段重来，我们必须补够）

    wire busy_any = px_req | ctl_req | ld_req;
    wire rd_done_now = (act_wr == 1'b0) && (got >= len);

    // ★★★ 2026-10-04（我方新增 ✓）：**刷新"截止时间"门** —— 防刷新被饿死 ✓
    //   【为什么需要】`App_ref_req` 只在"总线连续安静 63 拍"时才发（见 `sdram_top.v` ✓）。
    //     这是基于"总线约 80% 空闲"✓；但 **P2 会让总线热闹起来** ✗（音频持续写 ✓、预载 ✓）
    //     ⇒ 空档变少 ⇒ 刷新可能一直等不到安静窗口 ⇒ **又被推迟 ⇒ 漏电复发** ✗✓
    //   【做法】仲裁器**自己数**"距上次刷新过了多少拍" ✓（它本来就收 `sdr_init_ref_vld` ✓
    //     ⇒ **无需新增端口** ✓✓）：一旦超过 `URGENT_CYC` ⇒ **不再开新突发** ✓
    //     （正在跑的那一笔**照常发完** ✓ ⇒ **绝不截断任何突发** ✓✓）
    //     ⇒ 总线随即安静 ⇒ `sdram_top` 的安静门放行 ⇒ 刷新进来 ✓ ⇒ 门自动解除 ✓
    //   【逃生阀 ✓】若"该让路"持续过久（说明刷新迟迟不来 ✗，例如脉冲逻辑坏了）
    //     ⇒ **放开闸门** ✓，宁可暂缓刷新也不能把显示锁死 ✗（`ref_starve` ✓）
    //   【阈值为何取 1.5 倍周期 ✓】刷新周期 = 15.625µs = 1562 拍 @100MHz ✓
    //     ⚠️ 我曾一度取 0.75 倍（11.7µs）✗ —— 那**小于**刷新周期 ⇒ **每个周期都会先拦停约 4µs** ✗
    //        ⇒ 显示取数被周期性推迟，而**行缓冲只够约一行（≈4.8µs）** ⇒ 边缘 ⇒ 可能偶发欠载（冻结一行）✗
    //     ⇒ 正确取法：**只在"刷新真的迟了"时才让路** ✓ ⇒ 取 **1.5 倍 ≈ 23.4µs（2344 拍）** ✓
    //        ⇒ 正常时（刷新按 15.6µs 到 ✓）**这道门根本不触发** ✓，只有将饿死时才起作用 ✓✓
    //        （偶尔间隔 23µs 对保持时间无碍 ✓：64ms 内仍远超 4096 条 ✓）
    localparam [15:0] URGENT_CYC = 16'd2344;   // 23.4µs = 1.5 × 15.625µs ✓（"刷新迟了才让路" ✓）
    localparam [15:0] STARVE_CYC = 16'd12500;  // 125µs = 8 × 周期 ⇒ 逃生阀放开闸门 ✓（防锁死 ✓）
    reg  [15:0] since_ref;                     // 距上次刷新的拍数（饱和，不回绕 ✓）
    wire        ref_urgent = (since_ref >= URGENT_CYC);
    wire        ref_starve = (since_ref >= STARVE_CYC);
    wire        ref_block  = ref_urgent && !ref_starve;   // 该让路给刷新，但不许永久锁死 ✓
    always @(posedge clk) begin
        if (!rst_n)                    since_ref <= 16'd0;
        else if (sdr_init_ref_vld)     since_ref <= 16'd0;              // 刷新(或初始化刷新)发生 ⇒ 清零 ✓
        else if (since_ref < 16'hFFFF) since_ref <= since_ref + 16'd1;   // 饱和 ✓
    end

    // ★ 写数据组合直通（客户端 FWFT）：使能/地址是寄存的，数据必须与地址**同拍**。
    //   若把 ld_data 再寄存一拍，会写成"地址 k 收到数据 k-1"（整体错一位）——2026-09-30 实证。
    assign app_wr_din = ld_data;

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_IDLE; act <= 2'd0; act_wr <= 1'b0; base <= 21'd0; len <= 16'd0;
            n <= 16'd0; got <= 16'd0;
            app_rd_en <= 1'b0; app_rd_addr <= 21'd0;
            app_wr_en <= 1'b0; app_wr_addr <= 21'd0; app_wr_dm <= 4'd0;
            px_ack <= 1'b0; px_done <= 1'b0; px_data <= 32'd0; px_valid <= 1'b0;
            ctl_ack <= 1'b0; ctl_done <= 1'b0; ctl_data <= 32'd0; ctl_valid <= 1'b0;
            ld_rd <= 1'b0; ld_ack <= 1'b0; ld_done <= 1'b0;
            arb_busy <= 1'b0; gnt <= 4'd0;
        end else begin
            px_ack <= 1'b0; px_done <= 1'b0; px_valid <= 1'b0;
            ctl_ack <= 1'b0; ctl_done <= 1'b0; ctl_valid <= 1'b0;
            ld_rd <= 1'b0; ld_ack <= 1'b0; ld_done <= 1'b0;

            // 读数据直通（Sdr_rd_en 有效即该客户的数据）
            if (sdr_rd_en) begin
                got <= got + 16'd1;
                case (act)
                2'd1: begin px_data  <= sdr_rd_dout; px_valid  <= 1'b1; end
                2'd2: begin ctl_data <= sdr_rd_dout; ctl_valid <= 1'b1; end
                default: ;
                endcase
            end

            case (st)
            // ---------------- 空闲：等请求（刷新期间不发）----------------
            S_IDLE: begin
                arb_busy <= busy_any;
                // ★ 2026-10-04：加 `!ref_block` ✓ —— 刷新临近截止（`URGENT_CYC` ✓）时
                //   **不再开新突发** ✓（正在跑的那一笔照常发完 ✓）⇒ 总线随即安静 ⇒ 刷新进得来 ✓
                if (sdr_init_done && !sdr_init_ref_vld && busy_any && !ref_block) begin
                    // 优先级：像素 > 控制 > 装载
                    if (px_req)       begin act <= 2'd1; act_wr <= 1'b0;
                                             base <= px_addr;  len <= (px_len  > MAX_BURST[15:0]) ? MAX_BURST[15:0] : px_len;  end
                    else if (ctl_req) begin act <= 2'd2; act_wr <= 1'b0;
                                             base <= ctl_addr; len <= (ctl_len > MAX_BURST[15:0]) ? MAX_BURST[15:0] : ctl_len; end
                    else              begin act <= 2'd3; act_wr <= 1'b1;
                                             base <= ld_addr;  len <= (ld_len  > MAX_BURST[15:0]) ? MAX_BURST[15:0] : ld_len;  end
                    n <= 16'd0; got <= 16'd0;
                    gnt <= (px_req ? 4'd1 : (ctl_req ? 4'd2 : 4'd3));
                    // ★ 契约 1（读）：**第一个使能拍呈现的地址 = base**，之后每拍 +1。
                    //   这正是厂商 `app_wrrd` 的形态（`App_rd_addr = rd_addr_1d`，首拍 = base）——
                    //   2026-10-01 逐拍 diff 实证**0 拍差异**（见文件头状态②）。
                    //   （早期把首地址给成 base+1 会让控制器一条 READ 都不发；给成 base-1 同样是错的。）
                    app_rd_addr <= (px_req ? px_addr : (ctl_req ? ctl_addr : 21'd0));
                    app_wr_addr <= ld_addr;
                    app_rd_en   <= (px_req | ctl_req) ? 1'b1 : 1'b0;
                    app_wr_en   <= (px_req | ctl_req) ? 1'b0 : 1'b1;
                    ld_rd       <= (px_req | ctl_req) ? 1'b0 : 1'b1;
                    if (px_req)       px_ack  <= 1'b1;
                    else if (ctl_req) ctl_ack <= 1'b1;
                    else              ld_ack  <= 1'b1;
                    st <= S_RUN;
                end
            end

            // ---------------- 突发中：每拍一个字 ----------------
            S_RUN: begin
                arb_busy <= 1'b1;
                if (sdr_init_ref_vld) begin
                    // 契约 4：暂停（撤使能，保持 n/got/地址现场），等刷新过去
                    app_rd_en <= 1'b0;
                    app_wr_en <= 1'b0;
                    ld_rd     <= 1'b0;
                    settle <= 6'd32;
                    st <= S_PAUSE;
                end else begin
                    n <= n + 16'd1;
                    // 契约 1：使能每拍 +1；地址跟着 n 走（首拍已是 base-1，第二拍正好 base）
                    app_rd_addr <= base + n + 16'd1;
                    app_wr_addr <= base + n + 16'd1;
                    if (act_wr) begin
                        app_wr_en  <= 1'b1;
                        ld_rd      <= 1'b1;
                    end else begin
                        app_rd_en  <= 1'b1;
                        app_wr_en  <= 1'b0;
                    end
                    // 发放完毕？
                    if (n + 16'd1 >= len) begin
                        app_rd_en <= 1'b0;
                        app_wr_en <= 1'b0;
                        ld_rd     <= 1'b0;
                        // 写：发完即完成；读：等数据收齐
                        if (act_wr) begin
                            ld_done <= 1'b1; settle <= 6'd32;
                            st <= S_GAP; gnt <= 4'd0;
                        end else begin
                            st <= S_DRAIN;       // ★ 发完使能已撤，转收数状态
                        end
                    end
                end
            end

            // ---------------- 刷新暂停 ----------------
            S_PAUSE: begin
                arb_busy <= 1'b1;
                if (!sdr_init_ref_vld) begin
                    // 接着发（地址相位保持：下一拍给 base+n）
                    app_rd_addr <= base + n + 16'd1;
                    app_wr_addr <= base + n + 16'd1;
                    app_rd_en   <= act_wr ? 1'b0 : 1'b1;
                    app_wr_en   <= act_wr ? 1'b1 : 1'b0;
                    st <= S_RUN;
                end
            end

            S_GAP: begin
                arb_busy <= 1'b1;
                if (settle == 6'd0) begin
                    st <= S_IDLE;
                    arb_busy <= 1'b0;
                end else settle <= settle - 6'd1;
            end

            S_DRAIN: begin
                        arb_busy <= 1'b1;
                        if (got >= len) begin
                            case (act)
                            2'd1: px_done  <= 1'b1;
                            2'd2: ctl_done <= 1'b1;
                            default: ;
                            endcase
                            st <= S_IDLE; gnt <= 4'd0; arb_busy <= 1'b0;
                        end
                     end
            default: st <= S_IDLE;
            endcase

        end
    end

endmodule

`default_nettype wire
