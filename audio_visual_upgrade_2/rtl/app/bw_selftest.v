`default_nettype none
//=============================================================================
// rtl/app/bw_selftest.v —— SDRAM 带宽自测客户（P0-2 骨架用）
//
// 干什么：初始化完成后，反复「写一个突发 → 间隔 → 读回并逐字比对」，
//         并按固定拍数窗口统计**搬动了多少字**，换算成带宽交给 UART 报告。
//
// 为什么这么设计：
//   · 仲裁器契约（rtl/mem/sdram_arb.v 文件头）：
//     ① 一次授权 ≤2048 字；② req 是**电平**且 arb **不做边沿检测** ⇒
//        **必须在 ack 后立刻撤 req**（撤晚了会被当成新请求再执行一遍 —— 踩过）；
//     ③ 写数据 FWFT：使能与地址同拍，`ld_data` 必须当拍有效。
//   · 带宽用**固定拍窗口**统计，不做"计时除时间"，只做常数乘除，省 LUT。
//
// 带宽算式（铁律 5：必须写清算式）：
//   1 字 = 4 字节；窗口 = WIN_CYCLES 拍 @ CLK_MHZ MHz ⇒ 窗口时间 = WIN_CYCLES/CLK_MHZ µs
//   ★ 本模块按 **1 KB = 1000 B**（十进制）算，避免引入 1024 乘法：
//     KB/s = 字数 × 4 × CLK_MHZ / WIN_CYCLES × 1000 = 字数 × (4000 × CLK_MHZ) / WIN_CYCLES
//   ★★ 换算比做成**有理数参数** `BW_NUM/BW_DEN`（KB/s = 字数 × BW_NUM / BW_DEN）：
//      · 先乘后除会**溢出 32 位**（字数×4000×CLK_MHZ：2e5×6e5 = 1.2e11）；
//      · 更关键：**BW_DEN≠1 就是一个常数除法**，TD 会把它变成"乘法器+长加法链"，
//        于是 `字数 → bw_kbps` 成了一条超长组合路径。本轮 P0-3 实测到：
//        `u_bw/rd_w_reg[0] → u_bw/bw_kbps_reg[0]` slack **-19.704ns**、
//        该时钟组 Fmax 只有 **37.9MHz**（150MHz 要 6.666ns）——就是 `BW_DEN=5` 害的。
//   ★ 所以**故意把窗口选成让换算比是整数**：
//        4000 × CLK_MHZ / WIN_CYCLES = 4000×150/200000 = **3**（整除）
//        ⇒ BW_NUM=3、BW_DEN=1 ⇒ 硬件上只是 `(字数<<1)+字数`，**两个加法器、无除法、无 DSP**。
//        校验：上限 1 字/拍 ⇒ 200000 字/窗口 ⇒ 200000×3 = **600000 KB/s = 600 MB/s** ✔
//      · 窗口 200000 拍 @150MHz = 1.333ms。**够用**：一个"写 2048 + 读 2048"的突发才 4096 拍，
//        窗口里有约 48 个突发，均值已经很稳；比原来的 6.667ms 只是刷新更勤。
//   ★ 改了 WIN_CYCLES 或 CLK_MHZ，就**必须同步重算** BW_NUM/BW_DEN
//     （先约成最简分数；尽量凑成 DEN=1 以免又变成除法）。
//=============================================================================
module bw_selftest #(
    parameter integer WIN_CYCLES = 200000,       // 带宽统计窗口（拍）：150MHz ⇒ 1.333ms（见上面推导）
    parameter integer CLK_MHZ    = 150,
    parameter integer BW_NUM     = 3,            // 换算比分子（窗口/频率选定后 = 3）
    parameter integer BW_DEN     = 1,            // 换算比分母（**保持 1**：>1 会引入常数除法，拖累时序）
    parameter integer BURST      = 2048          // 每次授权字数（契约上限）
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        init_done,                // 下层初始化完成才开跑

    // ---------- 客户 0：像素读（长突发流式读）----------
    output reg         px_req,
    output reg  [20:0] px_addr,
    output reg  [15:0] px_len,
    input  wire        px_ack,
    input  wire        px_done,
    input  wire        px_valid,
    input  wire [31:0] px_data,

    // ---------- 客户 2：装载写 ----------
    output reg         ld_req,
    output reg  [20:0] ld_addr,
    output reg  [15:0] ld_len,
    output reg  [31:0] ld_data,                  // FWFT：arb 拉 ld_rd 即取走本拍的值
    input  wire        ld_rd,
    input  wire        ld_ack,
    input  wire        ld_done,

    // ---------- 报告 ----------
    output reg  [31:0] wr_words,                 // 本窗口写入字数
    output reg  [31:0] rd_words,                 // 本窗口读回字数
    output reg  [31:0] err_words,                // 累计"读回≠写入"字数（自检）
    output reg  [31:0] bw_kbps,                  // 本窗口带宽（KB/s，1KB=1000B）
    output reg         win_tick,                 // 窗口结束脉冲
    output reg  [31:0] cyc_total,                // 已运行拍数
    output reg  [15:0] n_burst                   // 已完成"写+读"轮数
);

    localparam [3:0] S_IDLE  = 4'd0,
                     S_WREQ  = 4'd1,
                     S_WACK  = 4'd2,
                     S_WWAIT = 4'd3,
                     S_WGAP  = 4'd4,
                     S_RREQ  = 4'd5,
                     S_RACK  = 4'd6,
                     S_RWAIT = 4'd7,
                     S_RGAP  = 4'd8;

    localparam [31:0] WIN_M1 = WIN_CYCLES - 1;

    reg [3:0]  st;
    reg [31:0] cyc;
    reg [31:0] wr_w, rd_w, err_t;                // 窗口内/累计
    reg [15:0] gap;
    reg [20:0] base;                             // 突发基址在 0 ⇄ 2048 之间轮换（bank 友好）
    reg [31:0] w0;                               // 本轮写突发的首字数据值
    reg [31:0] exp_r;                            // 本轮"期望读回值"，**逐字自增**（见读侧校验注释）
    reg [31:0] words_r;                          // 窗口总字数（阶段1 寄存）
    reg        bw_pend;                          // 阶段2 待换算

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_IDLE; gap <= 16'd0; base <= 21'd0; w0 <= 32'd0; exp_r <= 32'd0;
            px_req <= 1'b0; px_addr <= 21'd0; px_len <= 16'd0;
            ld_req <= 1'b0; ld_addr <= 21'd0; ld_len <= 16'd0; ld_data <= 32'd0;
            cyc <= 32'd0; wr_w <= 32'd0; rd_w <= 32'd0; err_t <= 32'd0;
            wr_words <= 32'd0; rd_words <= 32'd0; err_words <= 32'd0;
            bw_kbps <= 32'd0; win_tick <= 1'b0; cyc_total <= 32'd0; n_burst <= 16'd0;
            words_r <= 32'd0; bw_pend <= 1'b0;
        end else begin
            win_tick  <= 1'b0;
            cyc_total <= cyc_total + 32'd1;

            // ---- 写侧 FWFT：arb 取走一个字 ⇒ 数据源 +1（与使能同拍，契约 ③）----
            if (ld_rd) begin
                ld_data <= ld_data + 32'd1;
                wr_w    <= wr_w + 32'd1;
            end

            // ---- 读侧校验：写进 addr k 的是 w0+k ----
            // ★ 期望值**逐字自增**（exp_r），而不是每拍现算 `w0 + ridx`：
            //   现算会把一条 "32bit 加法 → 32bit 比较 → 时钟使能" 串成一拍，
            //   实测 slack **-0.431ns**（Fmax 140.9MHz，差一点点）。改成自增后，
            //   比较那一拍里**没有加法器**（自增本身是独立的 exp_r → +1 路径）。
            if (px_valid) begin
                if (px_data !== exp_r) err_t <= err_t + 32'd1;
                exp_r <= exp_r + 32'd1;
                rd_w  <= rd_w + 32'd1;
            end

            case (st)
            S_IDLE: begin
                if (init_done) begin
                    ld_addr <= base; ld_len <= BURST[15:0];
                    w0      <= ld_data;              // 记下本轮首字（FWFT：本拍值即首字）
                    ld_req  <= 1'b1;                 // 电平，保持到 ack
                    st      <= S_WREQ;
                end
            end
            S_WREQ:  if (ld_ack)  begin ld_req <= 1'b0; st <= S_WACK;  end     // ★ ack 后立刻撤
            S_WACK:  begin st <= S_WWAIT; end
            S_WWAIT: if (ld_done) begin gap <= 16'd16;  st <= S_WGAP;  end
            S_WGAP:  if (gap == 16'd0) begin
                         px_addr <= base; px_len <= BURST[15:0];
                         exp_r   <= w0;                    // 本轮期望值从 w0 起逐字自增
                         px_req  <= 1'b1;
                         st      <= S_RREQ;
                     end else gap <= gap - 16'd1;
            S_RREQ:  if (px_ack)  begin px_req <= 1'b0; st <= S_RACK;  end     // ★ ack 后立刻撤
            S_RACK:  begin st <= S_RWAIT; end
            S_RWAIT: if (px_done) begin
                         gap     <= 16'd16;
                         base    <= base ^ BURST[20:0];        // 0 ⇄ 2048
                         n_burst <= n_burst + 16'd1;
                         st      <= S_RGAP;
                     end
            S_RGAP:  if (gap == 16'd0) st <= S_IDLE; else gap <= gap - 16'd1;
            default: st <= S_IDLE;
            endcase

            // ---------------- 窗口边界：锁存并换算带宽（**两级**，见下）----------------
            // ★ 为什么分两级：`(wr_w+rd_w)*BW_NUM/BW_DEN` 写成一条组合路径时，
            //   TD 把 `*` 映射成 **DSP MULT18（即使乘数是常数 3 也不折叠）**再加 4 个 ADDER，
            //   实测 Data Path Delay **8.62ns**、slack **-2.07ns**（150MHz 预算 6.666ns）。
            //   窗口 1.333ms 才来一次 ⇒ **慢一拍完全无所谓**，所以拆成"先寄存和、再换算"。
            if (cyc == WIN_M1) begin
                cyc       <= 32'd0;
                wr_words  <= wr_w;
                rd_words  <= rd_w;
                err_words <= err_t;
                words_r   <= wr_w + rd_w;        // 阶段1：只做一次 32bit 加法
                bw_pend   <= 1'b1;
                wr_w      <= 32'd0;
                rd_w      <= 32'd0;
            end else begin
                cyc <= cyc + 32'd1;
                if (bw_pend) begin
                    bw_kbps <= words_r * BW_NUM[31:0] / BW_DEN[31:0];   // 阶段2：换算
                    bw_pend <= 1'b0;
                    win_tick <= 1'b1;            // 窗口脉冲推迟 1 拍（此刻数据才齐）
                end
            end
        end
    end

endmodule

`default_nettype wire
