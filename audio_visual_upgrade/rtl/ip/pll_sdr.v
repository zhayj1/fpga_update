//=============================================================================
// rtl/ip/pll_sdr.v —— SDRAM 时钟 PLL：50MHz 参考 → 100MHz(Clk) + 100MHz 相移(Clk_sft)
//
// ★★ 2026-10-03：**125MHz → 100MHz**（用户决定："那就降频吧"）✓
//   动机：板子跑久了**彩点逐渐增多**（刚烧好没有 ✓、越久越多 ✗），且**封面窗口区域更多** ✗
//   —— 这是 **SDRAM 读采样窗口的时序余量在温度下不够** ✗ 的典型特征（详见 BOARD_LOG ✓）。
//   机理不清之处已辨明 ✓：TD/STA **看不到** 这一层 ✗（外部芯片+PCB 往返不在 SDC 内 ✓），
//   仿真也看不到 ✗（行为模型无建立/保持时间 ✓）⇒ 只能靠"买余量"的手段 ✓：
//     周期 8ns → **10ns（+25%）** ✓、`design §4.1` 本就许可 ✓、P0 实测 100MHz **零 tRCD 报错** ✓。
//   代价：带宽 500→400MB/s ✓（显示需求 ~78MB/s ✓，峰值 ~196MB/s ✓ ⇒ 仍有余量 ✓）。
//   ⚠️ 必须**同步改** `ip/sdram/global_def.v` 的 `SDR_CLK_PERIOD` ✗（APUG011 §2.5 ✓）；
//      注意 `SELF_REFRESH_INTERVAL` 换算成**时间**是 `64e6/2048 ns = 31.25µs` ✓，**与频率无关** ✓
//      ⇒ 降频**不改**刷新时间 ⇒ 它只治"读采样" ✗，治不了"保持/刷新"那一路 ✗。
//=============================================================================
// ★ 参数来源与**改了什么**（必须写清楚，不然下一个人不敢动）：
//   结构照 `rtl/ip/video_pll.v`（安路 IP 生成器的**综合版**写法：EG_LOGIC_BUFG + EG_PHY_PLL，
//   没有 EG_PHY_CONFIG，也没有 *_sim 的定标噪声）；
//   频率/相位参数照厂商 SDRAM 参考的 `sim/vref/prj/al_ip/clk_pll_sim.v`（那份就是 150M/150M相移）：
//       CLKC0_DIV=84 → 反馈支路 12.5MHz；CLKC1_DIV=7 → 150MHz；CLKC2_DIV=7 + 相移 → Clk_sft
//       FVCO = FIN/REFCLK_DIV × FBCLK_DIV × CLKC0_DIV = 50/4 × 1 × 84 = **1050 MHz**（与厂商同值）
//   唯一改动：厂商那份参考是 **25MHz** 输入（REFCLK_DIV=2），本板是 **50MHz**（管脚 R7）
//             ⇒ 只把 `FIN` 25→50、`REFCLK_DIV` 2→**4**，使 FVCO 与各 DIV/相位**完全保持原样**。
//
// ★★ 上板必做（不能只靠仿真）：PLL 相位在仿真里**无法验证**
//    （`eg_phy_pll.v` 模型在本机不锁定，见 design_music_player.md 附录 A-5），
//    必须在板上用示波器/ILA 复核 Clk 与 Clk_sft 的相位差**落在 45°~180° 窗口内**
//    （§3.4.5 约束 3；0° 会丢 25%），并尽量移到窗口中心 ≈110°。
//    若实测不在窗口内，用 TD 的 PLL IP 向导重生成本文件的 CLKC*_CPHASE/FPHASE。
//
// ★★ 2026-10-01 上板实测发现的证据与改动（P1 出图后画面有偶发品红点）：
//    布线报告的时钟表里 `sdr_clk_sft` 上升沿 = **3.333ns** ⇒ (6-CPHASE)-FPHASE/8 = 3.5 个 VCO 周期
//    （FVCO=1050MHz ⇒ 1 周期 0.952ns）⇒ **正好 180°，踩在有效窗口 45°~180° 的边界上**
//    （design_music_player.md:326 要求约 90°~135°，推荐窗口中心 ≈110°）。
//    ⇒ 采样余量为零 ⇒ 偶发读错数据 ⇒ 封面的品红（占其 75.48%）偶发渗到别处，看起来"全屏品红点"。
//    改动：CLKC2_CPHASE 2→**4**、FPHASE 4→**0** ⇒ 相移 2 个 VCO 周期 = **103°**，
//    与 0°/180° 两侧各留约 60°。仿真不受影响（TB 直接给 Clk/Clk_sft，不经过 PLL）。
//    若板上仍有残点：在 45°~180° 内换 CPHASE（6=0°、5=51°、4=103°、3=154°）逐档复测。
//=============================================================================
`timescale 1 ns / 100 fs

module pll_sdr (
    refclk,
    reset,
    extlock,
    clk0_out,       // 反馈支路 12.5MHz（不对上层使用，仅供观测/反馈）
    clk1_out,       // 150MHz  → sdr_as_ram.Sdr_clk
    clk2_out        // 150MHz  → sdr_as_ram.Sdr_clk_sft（相对 clk1 相移）
);

    input  refclk;
    input  reset;
    output extlock;
    output clk0_out;
    output clk1_out;
    output clk2_out;

    wire clk0_buf;
    wire clk1_buf;
    wire clk2_buf;

    EG_LOGIC_BUFG bufg_fb  (.i(clk0_buf), .o(clk0_out));
    EG_LOGIC_BUFG bufg_c1  (.i(clk1_buf), .o(clk1_out));
    EG_LOGIC_BUFG bufg_c2  (.i(clk2_buf), .o(clk2_out));

    EG_PHY_PLL #(
        .DPHASE_SOURCE("DISABLE"),
        .DYNCFG("DISABLE"),
        .FIN("50.000000"),
        .FEEDBK_MODE("NORMAL"),
        .FEEDBK_PATH("CLKC0_EXT"),
        .STDBY_ENABLE("DISABLE"),
        .PLLRST_ENA("ENABLE"),
        .SYNC_ENABLE("DISABLE"),
        .GMC_GAIN(0),
        .ICP_CURRENT(9),
        .KVCO(2),
        .LPF_CAPACITOR(2),
        .LPF_RESISTOR(8),
        .REFCLK_DIV(5),                         // ★ 2026-10-02：50/5=10MHz → FVCO=10×1×100=1000MHz
        .FBCLK_DIV(1),
        .FREQ_LOCK_ACCURACY(2),
        .PLL_LOCK_MODE(0),
        .CLKC0_ENABLE("ENABLE"),
        .CLKC0_DIV(100),                        // ★ 1000/100 = 10MHz（反馈支路）
        .CLKC0_CPHASE(99),
        .CLKC0_FPHASE(0),
        .CLKC1_ENABLE("ENABLE"),
        .CLKC1_DIV(10),                         // ★★ 2026-10-03：1000/10 = **100MHz**（原 8 ⇒ 125MHz）
        .CLKC1_CPHASE(9),                       //   无相移 = DIV-1
        .CLKC1_FPHASE(0),
        .CLKC2_ENABLE("ENABLE"),
        .CLKC2_DIV(10),                         // ★★ 同为 100MHz，作 Clk_sft
        .CLKC2_CPHASE(4),                       //   ★★ 2026-10-03：相移 = 4 + 1 + 0/8 = **5.0ns = 180°** ✓
        .CLKC2_FPHASE(0),                       //   ★ 用**板上已验证"读不出整块错"的那一档** ✓（2.5ns 整块读错 ✗）
                                                //   ⇒ 本次只测一件事：`self_refresh_open` 改 0 对**刷新**的影响 ✓
                                                //   （1 VCO 周期 = 1ns ✓ 公式：CPHASE + 1 + FPHASE/8 ✓）
        .CLKC3_ENABLE("DISABLE"),
        .CLKC4_ENABLE("DISABLE")
    ) pll_inst (
        .refclk(refclk),
        .reset(reset),
        .stdby(1'b0),
        .extlock(extlock),
        .load_reg(1'b0),
        .psclk(1'b0),
        .psdown(1'b0),
        .psstep(1'b0),
        .psclksel(3'b000),
        .psdone(open),
        .dclk(1'b0),
        .dcs(1'b0),
        .dwe(1'b0),
        .di(8'b00000000),
        .daddr(6'b000000),
        .do({open, open, open, open, open, open, open, open}),
        .fbclk(clk0_out),
        .clkc({open, open, clk2_buf, clk1_buf, clk0_buf})
    );

endmodule
