`default_nettype none
//============================================================================
// rtl/gfx/px_arb3.v —— `px` 口的二级仲裁（**三个**取数层 → `sdram_arb` 的单个 px 客户）
//
// 为什么需要它：`sdram_arb` 只有**一个 `px` 客户**；P3-精写后 px 口有三个取数者：
//   c0 = 背景 `layer_bg`（**每行一笔长突发**，整屏 480 行）
//   c1 = 封面 `layer_cover`（每行一笔长突发，窗口 300 行）
//   c2 = 文本 `layer_text`（**每字 2 笔 × ≈19 字 = 38 笔短突发/行**，见 `rtl/gfx/lyric_row.v`）
//   在**不改 `sdram_arb` 客户数/优先级**的前提下，在客户侧加一级 3:1 仲裁是最小改动
//   （与 `px_arb2` 同由"arb 只有一个 px 口"这个事实逼出来的；改 arb 会作废
//    `tb_sdram_arb`/`tb_arb_soak`/`tb_trcd_diff` 三套板上验过的证据）。
//
// 契约（照 `rtl/mem/sdram_arb.v` 第 30/44 行）：
//   · 客户 `req` 是**电平**，保持到 `ack`；**`ack` 后必须立刻撤 `req`**（撤晚一拍即违约）；
//   · `ack`（脉冲）之后数据随 `valid` 流出（FWFT），`done`（脉冲）表示本次突发结束；
//   · 单次突发 ≤ `MAX_BURST`（arb 默认 2048）；客户若请求更长，arb 会截断，客户必须自己分批。
//
// ★★ 优先级：**c1（封面）> c2（文本）> c0（背景）** ——
//   · `c1` 保持最高：与**已上板**的 `px_arb2` 一致（封面/背景的相对次序不变 ⇒ 那段已验证的行为不受影响）；
//   · `c2` **排在背景之前**：文本每行 38 笔短突发、且它的行缓冲只有**一条扫描行**的余量；
//     而背景每行只有**一笔**长突发、持有一整行的余量 ⇒ **让短突发先走、把长突发留在后面**更稳。
//   · ⚠️ 这是**设计判断，不是实测结论** ⇒ 必须由整机判据验收：
//     **T-13**（`px` 口最坏的图像突发序列下，文本读仍能在**该扫描行内**完成）与
//     **T-12**（最忙场景下歌词层/歌名层的 `gap_cnt` 都为 0）。若 T-13 不过 ⇒ 改 round-robin 再测。
//
// 本模块行为（与 `px_arb2` 同形，只多一路）：
//   · 空闲时按优先级选一个客户，把它的地址/长度转给 arb，并保持 `req`；
//   · `ack` 到达 ⇒ 立刻撤 arb 的 `req`，但**保持路由不变直到 `done`**（数据要送给对的那个客户）；
//   · `done` ⇒ 释放，下一拍可服务另一个客户（**已授予的突发不被抢占**）；
//   · 未被服务的客户继续把 `req` 拉高等待。
//
// 未验证：整机接线、时序、上板（本模块只有单元台 `tb/tb_px_arb3.v`）。
//============================================================================
module px_arb3 #(
    // 突发之间的**强制间隔**（拍，clk_sdr）。来历见 `px_arb2.v` 的长注：**默认 0** ——
    // 板上实测"加 16 拍间隔"反而引出新的彩点 ⇒ 判定"间隔"不是对的杠杆，还原为原行为。
    parameter integer GAP_CYC = 0
) (
    input  wire        clk_sdr,
    input  wire        rst_sdr_n,

    // ---------------- 到 sdram_arb 的 px 客户口 ----------------
    output reg         arb_req,
    output reg  [20:0] arb_addr,
    output reg  [15:0] arb_len,
    input  wire        arb_ack,
    input  wire        arb_done,
    input  wire [31:0] arb_data,
    input  wire        arb_valid,

    // ---------------- 客户 0（背景层，**最低**）----------------
    input  wire        c0_req,
    input  wire [20:0] c0_addr,
    input  wire [15:0] c0_len,
    output wire        c0_ack,
    output wire        c0_done,
    output wire [31:0] c0_data,
    output wire        c0_valid,

    // ---------------- 客户 1（封面层，**最高**）----------------
    input  wire        c1_req,
    input  wire [20:0] c1_addr,
    input  wire [15:0] c1_len,
    output wire        c1_ack,
    output wire        c1_done,
    output wire [31:0] c1_data,
    output wire        c1_valid,

    // ---------------- 客户 2（文本层，**居中**）----------------
    input  wire        c2_req,
    input  wire [20:0] c2_addr,
    input  wire [15:0] c2_len,
    output wire        c2_ack,
    output wire        c2_done,
    output wire [31:0] c2_data,
    output wire        c2_valid,

    // ---------------- 观测（上板报告用）----------------
    output reg  [31:0] grant_cnt,       // 累计授予次数
    output reg  [31:0] contend_cnt      // 累计"≥2 个客户同拍都在请求"的拍数（争用强度）
);

    reg [1:0] sel;          // 0 = 客户 0；1 = 客户 1；2 = 客户 2
    reg       busy;         // 一次突发从"授予"到"done"期间为 1
    reg [7:0] gap_cnt;      // 突发之间的强制间隔计数（见模块头注释）

    wire two_req = (c0_req & c1_req) | (c0_req & c2_req) | (c1_req & c2_req);

    always @(posedge clk_sdr) begin
        if (!rst_sdr_n) begin
            arb_req <= 1'b0; arb_addr <= 21'd0; arb_len <= 16'd0;
            sel <= 2'd0; busy <= 1'b0; gap_cnt <= 8'd0;
            grant_cnt <= 32'd0; contend_cnt <= 32'd0;
        end else begin
            // 争用统计（与授予无关，纯观测）
            if (two_req) contend_cnt <= contend_cnt + 32'd1;

            if (!busy) begin
                if (gap_cnt != 8'd0) begin
                    gap_cnt <= gap_cnt - 8'd1;      // ★ 间隔期：不授予新客户
                    arb_req <= 1'b0;
                end else if (c1_req) begin                          // ★ 封面优先（与 px_arb2 一致）
                    sel <= 2'd1; busy <= 1'b1;
                    arb_req <= 1'b1; arb_addr <= c1_addr; arb_len <= c1_len;
                    grant_cnt <= grant_cnt + 32'd1;
                end else if (c2_req) begin                          // ★ 文本次之（短突发先行）
                    sel <= 2'd2; busy <= 1'b1;
                    arb_req <= 1'b1; arb_addr <= c2_addr; arb_len <= c2_len;
                    grant_cnt <= grant_cnt + 32'd1;
                end else if (c0_req) begin                          // 背景最后（长突发、余量最大）
                    sel <= 2'd0; busy <= 1'b1;
                    arb_req <= 1'b1; arb_addr <= c0_addr; arb_len <= c0_len;
                    grant_cnt <= grant_cnt + 32'd1;
                end else begin
                    arb_req <= 1'b0;                    // 无人请求
                end
            end else begin
                if (arb_ack)  arb_req <= 1'b0;          // ★ ack 后立刻撤 req
                if (arb_done) begin
                    busy    <= 1'b0;
                    arb_req <= 1'b0;
                    gap_cnt <= GAP_CYC[7:0];            // ★ 突发结束后插入间隔
                end
            end
        end
    end

    // 路由：`sel` 在 busy 期间保持不变（数据必须送给被授予的那一方）
    assign c0_ack   = arb_ack   & (sel == 2'd0);
    assign c0_done  = arb_done  & (sel == 2'd0);
    assign c0_data  = arb_data;
    assign c0_valid = arb_valid & (sel == 2'd0);

    assign c1_ack   = arb_ack   & (sel == 2'd1);
    assign c1_done  = arb_done  & (sel == 2'd1);
    assign c1_data  = arb_data;
    assign c1_valid = arb_valid & (sel == 2'd1);

    assign c2_ack   = arb_ack   & (sel == 2'd2);
    assign c2_done  = arb_done  & (sel == 2'd2);
    assign c2_data  = arb_data;
    assign c2_valid = arb_valid & (sel == 2'd2);

endmodule

`default_nettype wire
