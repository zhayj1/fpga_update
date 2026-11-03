`default_nettype none
//============================================================================
// rtl/audio/hdmi_audio_acr_gen.v —— HDMI ACR（音频时钟再生）参数发生器
//
// ★ 为什么需要（事实 ✓）：厂商 HDMI 核的音频口是**样本入口** ✓，
//   但"音频时钟与像素时钟的比值"必须**由我们告诉它** ✗ ——
//   APUG092 §2.4.4 原文："`I_acr_valid` 为高时，HDMI1.4b Transmitter Core
//   从 ACR 接口读取 `CTS` 和 `N` 的值，然后发送音频时钟再生辅助数据包" ✓
//
// 【N / CTS 定案（2026-10-04 ✓ 四个独立来源一致 ✓）】
//   N   = 128 × f_s(kHz)           = 128 × 48                    = **6144** ✓
//   CTS = f_pixel × N /(128 × f_s) = 25e6 × 6144 /(128 × 48000)   = **25000** ✓
//   ⇒ 等价规则（N=6144 时）：**CTS = f_pixel / 1000**（每毫秒的像素时钟数 ✓）
//   【交叉校验】
//     · 1080p60（148.5MHz）：CTS = 148500 ✓
//     · 480p59.94（25.175MHz）：CTS = 25175 ✓  两者都满足 128·f_s = f_pixel·N/CTS ✓
//   【来源（四个 ✓）】
//     ① 课程第 3 讲 §2.5 给出同一算式、同一结果 25000 ✓
//     ② 课程 ACR 模块默认 `INTERVAL_CYCLES = 25000` ✓
//     ③ 我按 CEA 表反推 ✓
//     ④ 厂商例程 `audio_arc_calculate.v` 的实测累加器口径 ✓
//   ★ 我曾把 HDMI 的 `f_TMDS` 当成"10× 比特时钟"⇒ 算成 CTS=250000 ✗ ——
//     **错 10 倍，已更正** ✓（HDMI 的 f_TMDS 指**字符时钟 = 像素时钟** ✓）
//
// 【为什么用**固定常数**、不用"测量式"（我定 ✓）】
//   本工程的 48kHz 节拍（`pcm_test_tone`）与 ACR **都从同一个 clk_pix 派生** ✓
//   ⇒ 比值 N/CTS = 6144/25000 **严格精确** ✓，与 PLL 的绝对频率无关 ✓
//   ⇒ 接收端恢复出的音频时钟**必然**与我们的样本率一致 ✓✓
//   若改成"数两次 48 样本之间的拍数"⇒ 得 24999/25000/25001 抖动 ✗，没有任何好处 ✗
//   ★ 将来若换像素时钟：只需改 `ACR_CTS = f_pixel/1000` ✓
//     （并把 `ACR_PERIOD_CYC` 同步改成 f_pixel/1000 ✓）
//
// 【发送节奏】每 `ACR_PERIOD_CYC` = 25000 拍（= **1ms** ✓）发一次 ✓、valid 单拍脉冲 ✓
//   与"48 个样本 = 1ms"同一节奏 ✓；APUG092 只要求"valid 时读值" ✓，未规定密度 ✓
//============================================================================
module hdmi_audio_acr_gen #(
    parameter [14:0] ACR_PERIOD_CYC = 15'd25000,   // 1ms @25MHz ✓
    parameter [19:0] ACR_N          = 20'd6144,
    parameter [19:0] ACR_CTS        = 20'd25000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    output reg         acr_valid,
    output reg  [19:0] acr_cts,
    output reg  [19:0] acr_n,
    output reg  [31:0] acr_count      // 观测：已发的 ACR 包数（1 秒应恰为 1000 ✓）
);

    reg [14:0] cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt       <= 15'd0;
            acr_valid <= 1'b0;
            acr_cts   <= 20'd0;
            acr_n     <= 20'd0;
            acr_count <= 32'd0;
        end else if (!enable) begin
            cnt       <= 15'd0;
            acr_valid <= 1'b0;
            acr_cts   <= 20'd0;
            acr_n     <= 20'd0;
        end else begin
            // 默认：只在 valid 那一拍呈现 CTS/N ✓（与厂商例程口径一致 ✓）
            acr_valid <= 1'b0;
            acr_cts   <= 20'd0;
            acr_n     <= 20'd0;
            if (cnt + 15'd1 >= ACR_PERIOD_CYC) begin
                cnt       <= 15'd0;
                acr_valid <= 1'b1;
                acr_cts   <= ACR_CTS;
                acr_n     <= ACR_N;
                acr_count <= acr_count + 32'd1;
            end else begin
                cnt <= cnt + 15'd1;
            end
        end
    end

endmodule

`default_nettype wire
