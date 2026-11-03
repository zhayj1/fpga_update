`default_nettype none
//============================================================================
// rtl/audio/audio_mux.v —— 音源二选一（测试音 ↔ WAV 流）
//
// ★ 为什么要有它（不是多余的一层 ✗）：S1 的**测试音**是"链路自检音源" ✓，
//   一旦将来**无声**✗，切回它就能一刀分清"是通路坏了"还是"素材/解析坏了" ✓
//   ⇒ 两条音源**长期并存** ✓，靠这个 mux 切换 ✓。
//
// ★ 唯一容易静默出错的一条：**`ready` 只路由给被选中的源** ✓
//   （未选源的握手不推进 ⇒ 它内部不会被消耗 ⇒ **不丢数据** ✓）。
//   这也是课程第 10 课强调的那一点 ✓（`audio_source_mux` ✓）。
//
// 【为什么没有独立单元 TB（记录在案 ✓）】本模块是 4 行纯组合 ✓，
//   按技能里"简单明确的单模块可直接实现并记录合理默认值"办理 ✓；
//   它的正确性**放到 S2-d 的整机回归里一并验** ✓（那里两条音源都在流动 ✓，
//   "切到 WAV 后测试音的 ready 必须为 0"这类性质才真正可判 ✓）。
//============================================================================
module audio_mux (
    // 选择：1 = WAV 流 ✓，0 = 测试音 ✓
    input  wire               select_wav,

    // 源 A：测试音 ✓
    input  wire               tone_valid,
    output wire               tone_ready,
    input  wire signed [15:0] tone_left,
    input  wire signed [15:0] tone_right,

    // 源 B：WAV 流 ✓
    input  wire               wav_valid,
    output wire               wav_ready,
    input  wire signed [15:0] wav_left,
    input  wire signed [15:0] wav_right,

    // 输出（→ HDMI 核音频口 ✓）
    output wire               out_valid,
    input  wire               out_ready,
    output wire signed [15:0] out_left,
    output wire signed [15:0] out_right
);

    assign out_valid = select_wav ? wav_valid : tone_valid;
    assign out_left  = select_wav ? wav_left  : tone_left;
    assign out_right = select_wav ? wav_right : tone_right;

    assign wav_ready  = select_wav ? out_ready : 1'b0;    // ★ ready 只给被选源 ✓
    assign tone_ready = select_wav ? 1'b0      : out_ready;

endmodule

`default_nettype wire
