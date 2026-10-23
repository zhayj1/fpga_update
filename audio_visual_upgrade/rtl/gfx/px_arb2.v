`default_nettype none
//============================================================================
// rtl/gfx/px_arb2.v —— `px` 口的二级仲裁（两个取数层 → `sdram_arb` 的单个 px 客户）
//
// 为什么需要它：design §9.3 的 `sdram_arb` 只有 **一个 `px` 客户**，而 P1 有两个取数层
//   （背景 `layer_bg` + 封面 `layer_cover`，各自例化一个 `fetch_line`）。
//   在**不改 `sdram_arb` 客户数/优先级**的前提下（改它属于 P2，且要重跑 `tb_sdram_arb`/`tb_arb_soak`/
//   `tb_trcd_diff`），在客户侧加一级 2:1 仲裁是最小改动。
//
// 契约（照 `rtl/mem/sdram_arb.v` 第 30/44 行）：
//   · 客户 `req` 是**电平**，保持到 `ack`；**`ack` 后必须立刻撤 `req`**（撤晚一拍即违约）；
//   · `ack`（脉冲）之后数据随 `valid` 流出（FWFT），`done`（脉冲）表示本次突发结束；
//   · 单次突发 ≤ `MAX_BURST`（arb 默认 2048）；**客户若请求更长，arb 会截断**，客户必须自己分批。
//     （本项目 `fetch_line` 每行一次突发：640 宽 = 480 字 ✓ 在界内；加宽 MAX_W 时需重新核算。）
//
// 本模块行为：
//   · 空闲时选一个客户（**c1=封面优先**，与 TB/上板一致），把它的地址/长度转给 arb，并保持 `req`；
//   · `ack` 到达 ⇒ 立刻撤 arb 的 `req`，但**保持路由不变直到 `done`**（数据要送给对的那个客户）；
//   · `done` ⇒ 释放，下一拍可服务另一个客户（**已授予的突发不被抢占**）。
//   · 未被服务的客户继续把 `req` 拉高等待（`fetch_line` 的设计如此）。
//
// 未验证：综合/时序、上板。
//============================================================================
module px_arb2 #(
    // ★ 2026-10-02：突发之间的**强制间隔**（拍，clk_sdr）。
    //   来历：本项目在**写**侧查 `ld` 突发时已实证——厂商 SDRAM 控制器要求突发之间留空档，
    //   背靠背会丢数据（当时表现为 `Bank is not Activated` + 写入丢失）。**读**侧同理：
    //   两块图层交替取数时，若 `done` 之后立刻授予下一个客户 ⇒ 突发背靠背。
    //   仿真用的是行为模型、不在乎；真硅上则表现为"中间那块（两层交替最频繁处）
    //   出现不规律的品红/底色块"（2026-10-02 板上实测）。
    //   16 拍 @150MHz ≈ 107ns；而一行 320 像素 @25MHz = 12.8µs ⇒ 开销约 2%，可忽略。
    parameter integer GAP_CYC = 0        // ★ 2026-10-02：板上实测 16 拍反而引出新的彩点（背景侧）
                                         //   ⇒ 判定"间隔"不是对的杠杆，还原为 0（= 原行为，无间隔）；
                                         //   真正要扫的是 PLL 相移档位（见 rtl/ip/pll_sdr.v 头注释对照表）。
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

    // ---------------- 客户 0（背景层）----------------
    input  wire        c0_req,
    input  wire [20:0] c0_addr,
    input  wire [15:0] c0_len,
    output wire        c0_ack,
    output wire        c0_done,
    output wire [31:0] c0_data,
    output wire        c0_valid,

    // ---------------- 客户 1（封面层，**优先级高**）----------------
    input  wire        c1_req,
    input  wire [20:0] c1_addr,
    input  wire [15:0] c1_len,
    output wire        c1_ack,
    output wire        c1_done,
    output wire [31:0] c1_data,
    output wire        c1_valid,

    // ---------------- 观测（上板报告用）----------------
    output reg  [31:0] grant_cnt,       // 累计授予次数
    output reg  [31:0] contend_cnt      // 累计"两个客户同拍都在请求"的拍数（争用强度）
);

    reg sel;            // 0 = 服务客户 0；1 = 服务客户 1
    reg busy;           // 一次突发从"授予"到"done"期间为 1
    reg [7:0] gap_cnt;  // ★ 2026-10-02：突发之间的强制间隔计数（见模块头注释）

    always @(posedge clk_sdr) begin
        if (!rst_sdr_n) begin
            arb_req <= 1'b0; arb_addr <= 21'd0; arb_len <= 16'd0;
            sel <= 1'b0; busy <= 1'b0; gap_cnt <= 8'd0;
            grant_cnt <= 32'd0; contend_cnt <= 32'd0;
        end else begin
            // 争用统计（与授予无关，纯观测）
            if (c0_req && c1_req) contend_cnt <= contend_cnt + 32'd1;

            if (!busy) begin
                if (gap_cnt != 8'd0) begin
                    gap_cnt <= gap_cnt - 8'd1;      // ★ 间隔期：不授予新客户
                    arb_req <= 1'b0;
                end else if (c1_req) begin                       // 封面优先
                    sel <= 1'b1; busy <= 1'b1;
                    arb_req <= 1'b1; arb_addr <= c1_addr; arb_len <= c1_len;
                    grant_cnt <= grant_cnt + 32'd1;
                end else if (c0_req) begin
                    sel <= 1'b0; busy <= 1'b1;
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
    assign c0_ack   = arb_ack   & ~sel;
    assign c0_done  = arb_done  & ~sel;
    assign c0_data  = arb_data;
    assign c0_valid = arb_valid & ~sel;

    assign c1_ack   = arb_ack   &  sel;
    assign c1_done  = arb_done  &  sel;
    assign c1_data  = arb_data;
    assign c1_valid = arb_valid &  sel;

endmodule

`default_nettype wire
