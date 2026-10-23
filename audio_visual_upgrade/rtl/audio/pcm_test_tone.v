`default_nettype none
//============================================================================
// rtl/audio/pcm_test_tone.v —— 48kHz 测试音源（32 点正弦 LUT + 分数分频节拍）
//
// ★ 这是什么：P2/S1 的"第一刀" ✓ —— **不碰 SD 卡、不碰 SDRAM** ✗，
//   只产生"48kHz 样本 + valid"喂给**厂商 HDMI 核的音频口** ✓。
//   用途：一次上板就能判决已登记的 V4 风险
//   （厂商核音频口 + ACR 到底能不能出声 ✓），把风险从"整条音频链的最后"
//   提到"第一刀" ✓ —— 不通就立刻知道是通路问题，不是缓冲/文件问题 ✓。
//
// 【时基（事实 ✓）】像素时钟 clk_pix = 25.000MHz ✓
//   48kHz **不能用整数分频**得到（25e6/48000 = 520.833 ✗）
//   ⇒ 用**分数分频累加器**（Bresenham 式）：
//        acc += 48000；若 acc >= 25e6 ⇒ 出一个样本，并 acc -= 25e6 ✓
//   ⇒ ★ **长期严格 48000 样本/秒** ✓（N 拍内样本数 = floor(N×48000/25e6) ✓ 精确等式 ✓）
//     瞬时抖动 ±1 拍（40ns ✓）由 HDMI 核内部音频 FIFO 吸收 ✓
//     （厂商例程 `hdmi_audio_tone_pcm_scale.v:55-60` 用的就是这一手 ✓ 事实 ✓）
//   ★ 必须**在 clk_pix 域**产生 ✓：核的音频口与 ACR 口都在像素时钟域
//     （APUG092 §2.2："EDID/Video/Audio/ACR 四个接口都工作在 Pixel Clock 时钟域" ✓）
//
// 【接口语义（我定 ✓，理由在 APUG092 ✓）】
//   · 每到一个节拍就出一个新样本：`sample_valid` 拉高 **1 拍**、数据同拍有效 ✓
//     —— 厂商核**没有** ready/反压口 ✗（端口清单里没有 ✓ 事实 ✓）
//     ⇒ "每秒 48000 次 valid" 本身就是契约（APUG092 §2.4.3：
//        "音频输入数据的速率需要等于音频采样率…1 秒内需要发送 48000 次" ✓）
//   · 仍保留 `sample_ready` 输出端握手 ✓ 供将来串接（如 `vol_mul` ✓）：
//     ready 为低 ⇒ valid 与数据**保持**（该样本不丢 ✓）
//   · ★ 若"上一拍还没被收走"又来一个节拍 ⇒ 这个**新样本丢弃**并计入 `drop_count` ✓
//     —— 但**绝不因此改变节拍速率** ✗：速率一旦被下游拖慢，就违反
//     APUG092 的"速率 = 采样率" ✗（Bresenham 累加器**永远在跑** ✓）
//     ⇒ 正常链路上 `drop_count` 恒为 0 ✓（TB 与板上报文都会核 ✓）
//
// 【波形】32 点 LUT ⇒ 一个正弦周期 32 个样本 ⇒ 48000/32 = **1500Hz** ✓
//   幅度 12000（16 位有符号满幅 32767 的 ~37% ✓）⇒ **不削波、不爆音** ✓、听感清楚 ✓
//   为什么 32 点而不是 16 点：16 点 ⇒ 3kHz 偏刺耳 ✗；32 点 ⇒ 1.5kHz 更适合听 ✓
//============================================================================
module pcm_test_tone #(
    parameter integer CLK_HZ    = 25000000,   // 音频链时基 = 像素时钟 ✓
    parameter integer SAMPLE_HZ = 48000
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,          // 1 = 出测试音 ✓
    output reg                sample_valid,
    input  wire               sample_ready,
    output reg  signed [15:0] sample_left,
    output reg  signed [15:0] sample_right,
    output reg  [4:0]         rom_index,       // 观测：**当前输出样本**的 LUT 索引 ✓
    output wire [31:0]        tick_count,      // 观测：**节拍数**（由 audio_sample_tick 提供 ✓）
    output reg  [31:0]        drop_count       // 观测：被丢弃的样本数（应恒为 0 ✓）
);

    localparam [31:0] CLK_HZ_C    = CLK_HZ;
    localparam [31:0] SAMPLE_HZ_C = SAMPLE_HZ;

    reg  [4:0]  idx;               // 下一个待取样的 LUT 索引 ✓
    wire        accepted = sample_valid & sample_ready;

    // ★ S2-a：48kHz 节拍**抽到独立模块** ✓（`audio_sample_tick` ✓）
    //   算法与 S1 板上验证过的那一份**逐字相同** ✗不许改 ✗（板上实测 AUD N=48000 ✓）；
    //   抽出是因为 S2 的 WAV 通路也要节拍 ✓ ⇒ 全工程只有一处 48kHz 口径 ✓。
    wire        tick;
    wire [31:0] tick_cnt_w;
    audio_sample_tick #(
        .CLK_HZ    (CLK_HZ),
        .SAMPLE_HZ (SAMPLE_HZ)
    ) u_tick (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (enable),
        .tick       (tick),
        .tick_count (tick_cnt_w)
    );
    assign tick_count = tick_cnt_w;   // 对外端口名不变 ✓ ⇒ TB 不用改 ✓

    // 32 点正弦表：round(sin(11.25°·k) × 12000)，k = 0..31 ✓
    // 例：sin22.5°×12000 = 4592、sin45° = 8485、sin67.5° = 11087、sin90° = 12000 ✓
    function signed [15:0] sine32;
        input [4:0] idx;
        begin
            case (idx)
            5'd0 : sine32 =  16'sd0;
            5'd1 : sine32 =  16'sd2341;
            5'd2 : sine32 =  16'sd4592;
            5'd3 : sine32 =  16'sd6667;
            5'd4 : sine32 =  16'sd8485;
            5'd5 : sine32 =  16'sd9978;
            5'd6 : sine32 =  16'sd11087;
            5'd7 : sine32 =  16'sd11769;
            5'd8 : sine32 =  16'sd12000;
            5'd9 : sine32 =  16'sd11769;
            5'd10: sine32 =  16'sd11087;
            5'd11: sine32 =  16'sd9978;
            5'd12: sine32 =  16'sd8485;
            5'd13: sine32 =  16'sd6667;
            5'd14: sine32 =  16'sd4592;
            5'd15: sine32 =  16'sd2341;
            5'd16: sine32 =  16'sd0;
            5'd17: sine32 = -16'sd2341;
            5'd18: sine32 = -16'sd4592;
            5'd19: sine32 = -16'sd6667;
            5'd20: sine32 = -16'sd8485;
            5'd21: sine32 = -16'sd9978;
            5'd22: sine32 = -16'sd11087;
            5'd23: sine32 = -16'sd11769;
            5'd24: sine32 = -16'sd12000;
            5'd25: sine32 = -16'sd11769;
            5'd26: sine32 = -16'sd11087;
            5'd27: sine32 = -16'sd9978;
            5'd28: sine32 = -16'sd8485;
            5'd29: sine32 = -16'sd6667;
            5'd30: sine32 = -16'sd4592;
            default: sine32 = -16'sd2341;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_valid <= 1'b0;
            sample_left  <= 16'sd0;
            sample_right <= 16'sd0;
            rom_index    <= 5'd0;
            idx          <= 5'd0;
            drop_count   <= 32'd0;
        end else if (!enable) begin
            // 停 ⇒ 相位清零 ✓（再开时总从 0° 起，行为可复现 ✓）
            sample_valid <= 1'b0;
            rom_index    <= 5'd0;
            idx          <= 5'd0;
            sample_left  <= 16'sd0;
            sample_right <= 16'sd0;
        end else begin
            // ★ 节拍由 `u_tick` 给（它**永远在跑** ✓ ⇒ 样本速率不受下游影响 ✓，
            //   这是 S1 板上验证过的性质 ✓：反压过后速率不变 ✓）
            if (tick) begin
                if (!sample_valid || accepted) begin
                    sample_valid <= 1'b1;
                    sample_left  <= sine32(idx);
                    sample_right <= sine32(idx);
                    rom_index    <= idx;                // 观测值 = **本样本**的索引 ✓
                    idx          <= idx + 5'd1;          // 5 位自然回绕 ⇒ 0..31 循环 ✓
                end else begin
                    drop_count   <= drop_count + 32'd1; // 上一拍没被收走 ⇒ 丢新样本 ✓
                end
            end else if (accepted) begin
                sample_valid <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
