`default_nettype none
//============================================================================
// rtl/audio/audio_sample_tick.v —— 48kHz 采样节拍发生器（分数分频累加器）
//
// ★ 这个模块的算法是 **S1 板上验证过的原样搬运** ✗不许改 ✗：
//   2026-10-04 板上实测 `AUD N=48000`（16 位十进制逐字命中 ✓）⇒ 时基精确 48,000 样本/秒 ✓。
//   抽出成独立模块的理由：**S2 的 WAV 通路要自己的节拍** ✓（`pcm_test_tone` 与
//   `wav_stream_player` 共用同一个发生器 ⇒ 全工程只有一处 48kHz 口径 ✓，
//   避免出现"两个 48k 却不一致"的隐患 ✗）。
//
// 【原理（事实 ✓）】像素时钟 clk_pix = 25.000MHz ✓ 时，48kHz **不能**整数分频
//   （25e6/48000 = 520.833 ✗）⇒ 用 Bresenham 式累加器：`acc += 48000`，
//   一旦 `acc >= 25e6` 就出一个节拍并 `acc -= 25e6` ✓
//   ⇒ **长期严格**：N 拍内节拍数 = `floor(N × 48000 / 25e6)` ✓（精确等式 ✓）
//     瞬时抖动 ±1 拍（40ns ✓）由 HDMI 核内部音频 FIFO 吸收 ✓。
//   （厂商例程 `hdmi_audio_tone_pcm_scale.v:55-60` 用的是同一手 ✓ 事实 ✓）
//
// 【tick 的电平语义（重要 ✓）】`tick` 是**组合输出**、**宽 1 拍（= 一个 clk 周期）** ✓，
//   且**与 S1 逐字相同** ✓（S1 里就是 `wire tick = (acc_add >= CLK_HZ_C)` ✓）。
//   ★ 使用方必须按"**同一时钟域内的一拍脉冲**"消费 ✓：
//     同域直接用 ✓；**跨到更慢的域去"数电平"会数成多倍** ✗
//     —— 2026-10-04 板上就踩过：40ns 的脉冲被 50MHz 域按电平数了 **2 次** ✗
//     ⇒ 报文里读到 `AUD N=97634` ✗（期望 48000 ✓）。跨域要**先边沿检测** ✓。
//
// 【enable=0】累加器与计数**都清零** ✓ ⇒ 再开时总从同一相位起（行为可复现 ✓）。
//============================================================================
module audio_sample_tick #(
    parameter integer CLK_HZ    = 25000000,   // 音频链时基 = 像素时钟 ✓
    parameter integer SAMPLE_HZ = 48000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    output wire        tick,                  // 1 拍脉冲（组合 ✓，见上 ✓）
    output reg  [31:0] tick_count             // 观测：累计节拍数（1 秒应恰为 48000 ✓）
);

    localparam [31:0] CLK_HZ_C    = CLK_HZ;
    localparam [31:0] SAMPLE_HZ_C = SAMPLE_HZ;

    reg  [31:0] acc;
    wire [31:0] acc_add = acc + SAMPLE_HZ_C;

    assign tick = enable & (acc_add >= CLK_HZ_C);

    always @(posedge clk) begin
        if (!rst_n) begin
            acc        <= 32'd0;
            tick_count <= 32'd0;
        end else if (!enable) begin
            // ★ 只清**相位**，**不清累计计数** ✗ —— 与 S1 的语义逐字一致 ✓
            //   （`tick_count` 是累计观测量 ✗，被 enable 清掉会让报文数字"跳回去" ✗；
            //    `tb/tb_audio_tone.v` 的 AU-05 会核"enable=0 时计数不动" ✓ —— 我抽模块时
            //    一度把它写成清零 ✗，被 AU-05 当场抓住 ✓，已改回 ✓）
            acc        <= 32'd0;
        end else begin
            if (acc_add >= CLK_HZ_C) begin
                acc        <= acc_add - CLK_HZ_C;
                tick_count <= tick_count + 32'd1;
            end else begin
                acc        <= acc_add;
            end
        end
    end

endmodule

`default_nettype wire
