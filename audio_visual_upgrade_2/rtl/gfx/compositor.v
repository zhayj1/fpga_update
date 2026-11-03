`default_nettype none
//============================================================================
// rtl/gfx/compositor.v —— 合成器（**五层**优先级选择）
//
// 规格：doc/spec/compositor_behavior_spec.md §2
// 优先级：**歌词 > 歌名/歌手 > 封面 > 背景 > 底色**（design §6 的合成顺序；每层由自己的 `*_vld` 表态）。
//   色键透明**不在这里做**：`layer_cover` 给出 `cv_vld` 时已经排除了 `#FF00FF` 像素
//     ⇒ 合成器只做"选哪一层"，键只影响封面自己，绝不会误伤背景/底色。
//   文字层的透明**同样在层内决定**：`layer_lyric` 只在该像素确实是字才给 `ly_vld=1`
//     （色码 0 = 透明 ⇒ 下层透出 ✓）⇒ 合成器不碰"字/背景"的判定 ✓。
// 底面降级：所有层都没覆盖时输出底色（**不黑屏**，design §5 的要求）。
//
// ★ p3-lean 步2b：从"三层"扩成"五层"。`tt_*`（歌名/歌手层）在步 2b **暂时接常数 0**
//   （并层/该层本身在步 3 落地）；先接好端口是为了避免同一文件被改两遍、同一 TB 被改两遍 ✓。
//
// 纯组合、无流水延迟：`rgb` 与 `de` 同拍，`frame_sig` 直接用同一拍 `de` 采样 ⇒ 少一处错位风险。
//============================================================================
module compositor (
    input  wire        de,          // 像素有效（光栅）
    input  wire [23:0] base_rgb,    // 底色（每首一个主色，静态）
    input  wire [23:0] bg_rgb,      // 背景层像素
    input  wire        bg_vld,      // 背景层有效
    input  wire [23:0] cv_rgb,      // 封面层像素（色键已在 layer_cover 里剔除）
    input  wire        cv_vld,      // 封面层有效
    input  wire [23:0] ff_rgb,      // ★ 频谱柱层像素（P4 Stage 3 新增）
    input  wire        ff_vld,      // ★ 频谱柱层有效（`en_fft=0` 时**恒 0** ⇒ 与改动前逐位等价 ✓）
    input  wire [23:0] ly_rgb,      // ★ 歌词层像素（透明已由 layer_lyric 决定）
    input  wire        ly_vld,      // ★ 歌词层有效
    input  wire [23:0] tt_rgb,      // ★ 歌名/歌手层像素（步 2b 接 0）
    input  wire        tt_vld,      // ★ 歌名/歌手层有效（步 2b 接 0）
    output wire [23:0] rgb,
    output wire        rgb_vld
);

    // 优先级（design :92 的层序 ✓）：底色 < 背景 < 封面 < **频谱柱** < 歌词 < 歌名/歌手 ✓
    //   ★ 频谱插在 `tt` 与 `cv` 之间 ✓（= 在封面**之上**、在歌词/歌名**之下** ✓）
    //   ★ `ff_vld=0` 时这一级**短路掉** ⇒ 与 P4 之前的逐位行为完全一致 ✓（T-01..T-07 的保护 ✓）
    assign rgb     = ly_vld ? ly_rgb
                             : (tt_vld ? tt_rgb
                                       : (ff_vld ? ff_rgb
                                                 : (cv_vld ? cv_rgb
                                                           : (bg_vld ? bg_rgb : base_rgb))));
    assign rgb_vld = de;

endmodule

`default_nettype wire
