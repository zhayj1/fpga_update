//=====================================================================
// carousel.v —— P5/A8「小轮播」的控制块（2026-10-10）
//
// ★★★ S0 查实（**读代码得到的 ✓ 不是猜 ✗**，`skeleton_core.v:1018-1031` ✓）：
//   · 顶层换组的**完整动作**就是"`key_press` 那一拍的一串影子寄存器赋值" ✓
//     （`grp <= grp_nxt` ＋ `bg_slot_nx/cv_slot_nx/几何/ok` 一串 ✓）
//   · "下一个**有效**组"（自动跳过无效组 ✓）**已经有了** ✓（`grp_nxt`，`:971` ✓）
//   · 一首播完的脉冲 **已经有了** ✓（`au_end_pulse`，`:1370` ✓ —— 供 A9 用 ✓）
//   ⇒ ★ 所以轮播**只需要产生一个与 `key_press` 等价的脉冲** ✓
//     —— **切换逻辑一行都不用改** ✗、**不需要新的组/槽选择信号** ✗
//   ⇒ 接口因此比原草案（`workitem_p3_lean.md` §11.17 ✓）**简单得多** ✓：
//     草案要 `song_end/grp_now → grp_sel/grp_tgl` ✗；本模块只要 **`en → rot_pulse`** ✓
//
// 【契约】
//   · `en=1`：每 `T_ROT_S` 秒输出 **一个单拍脉冲** ✓（= 上层按了一次 KEY4 ✓）
//   · `en=0`：**一个都不输出** ✓，且**计数器清零** ✓
//     ⇒ 再打开时**从头计时** ✓（= 今天的行径 ✓ ⇒ 集成台可做逐位不变的 A/B ✓）
//
// 【为什么"关掉要清零"】若不 Zero ✗，关掉 N 秒再打开会**立刻**蹦一个脉冲 ✗
//   ⇒ 板上表现为"打开轮播的瞬间突然跳组" ✗（本工程在"计数器残留"上吃过亏 ✓）
//
// 【判据】`tb/tb_carousel.v`（CR-01..CR-06 ✓ 先写台、先跑预期失败 ✓）
// 目标器件：EG4S20BG256（HX4S20）· Verilog-2001 · `default_nettype none`
//=====================================================================
`default_nettype none

module carousel #(
    // ★★★ 参数口径（2026-10-10 实测修正 ✗→✓）：**只吃"拍数"，不吃"秒"** ✓
    //   【为什么】原来收 `CLK_HZ`＋`T_ROT_S`（秒 ✓）⇒ `TICKS = CLK_HZ*T_ROT_S` ✗
    //     仿真里 `T_ROT_S=1` ⇒ **5,000 万拍/周期** ✗ ⇒ 台要跑 3.5 亿拍 ⇒ **直接超时** ✗✗
    //   【正解】本模块是**纯计数器**，不该对时钟做假设 ✗ ⇒ 收 `TICKS` 即可 ✓
    //     "秒"由**顶层**换算（`TICKS = CLK_HZ * T_ROT_S` ✓）⇒ 顶层仍是人能读的秒 ✓
    //     而台里可以直接给 **1000 拍** ⇒ 仿真瞬间跑完 ✓✓
    parameter integer TICKS = 1000000000      // 默认 20s @50MHz（顶层会显式给 ✓）
)(
    input  wire clk,
    input  wire rst_n,
    input  wire en,                         // 轮播开关（0 ⇒ 组索引**永不自动前进** ✓）
    output reg  rot_pulse                   // ★ 单拍脉冲：等价于"按了一次 KEY4" ✓
);
    localparam [31:0] TICKS_L = TICKS[31:0];      // 一个周期多少拍 ✓

    reg [31:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt       <= 32'd0;
            rot_pulse <= 1'b0;
        end else begin
            rot_pulse <= 1'b0;                    // ★ 默认归零 ⇒ 脉冲只宽**一拍** ✓
            if (!en) begin
                cnt <= 32'd0;                     // ★ 关掉即清零 ⇒ 再打开从头计时 ✓
            end else if (cnt >= (TICKS_L - 32'd1)) begin
                cnt       <= 32'd0;               // 到点 ✓
                rot_pulse <= 1'b1;                // ★ 恰好一拍 ✓
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
endmodule

`default_nettype wire
