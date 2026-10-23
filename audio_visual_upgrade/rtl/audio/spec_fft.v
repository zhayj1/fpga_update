`default_nettype none
//============================================================================
// rtl/audio/spec_fft.v -- 256/512-point single-butterfly FFT.
// The historical P4 notes below describe N=256, WINDOW_HANN=0. The upgraded
// top uses N=512, WINDOW_HANN=1: 93.75 Hz/bin at 48 kHz, 256 output bins,
// periodic Hann from the idle twiddle ROM, and 2x coherent-gain correction.
// Its real/imag/ROM arrays are each 512x16 bits (one 9K BRAM each if mapped
// as intended). At 25 MHz compute + scan is about 0.584 ms per frame.
//
// 【它要满足的判据】单元台 `tb/tb_spec_fft.v`（**先写的** ✓，见工单 §11.5/§11.6）：
//   FF-01  937.5Hz 单音        ⇒ `peak_bin == 5` ✓ 且流里幅度最大的 bin 就是 5 ✓
//   FF-02  937.5 + 3937.5Hz    ⇒ `peak_bin ∈ {5,21}` ✓ 且 **bin 5 与 bin 21 都非零** ✓
//   FF-03  静音（全 0 样本）    ⇒ 流里 **128 个 bin 幅度全 0** ✓ 且 `peak_val == 0` ✓ 且 `peak_bin` 无 X ✓
//   + 每帧 `frame_stb` **单拍** ✓、一帧 = **256 个样本** ✓、一帧吐 **128 个 bin**（0..127 顺序 ✓）
//
// 【接口契约】（工单 §11.5 钉死 ✓；★ 2026-10-07 **用户拍板改成"bin 流"** ✓ 见 §11.9）
//   · `samp_stb` = 48kHz 单拍 ✓、`samp` = 12 位**有符号** PCM ✓（**音量前**同一份样本 ✓）
//   · `bin_stb/bin_idx/bin_mag` = **逐 bin 流** ✓：`bin_idx` 0..127 **自然序** ✓、`bin_mag` = 幅度 0~255 ✓
//     （`bin_stb` 单拍 ✓ 与 `bin_idx/bin_mag` 同拍 ✓；间隔 3 拍 ✓ —— 下游只认脉冲和编号 ✓）
//   · `frame_stb` = "**本帧最后一个 bin 已吐完**" ✓（单拍 ✓）—— 帧界交给下游收口 ✓
//   · ★ 柱（频带）**不在这里生成** ✗：已搬到 Stage 2 `rtl/audio/spec_bands.v` ✓
//     （理由：那里才是"256 bin → 16 对数带 + dB + 峰值保持"✓；放这里就是**重复算** ✗）
//   · ★ **算的时候新来的 `samp_stb` 直接丢** ✓（契约允许 ✓ —— 真机 5.33ms 一帧、
//     本模块算一帧约 **6.5k 拍 = 43us@150MHz** ✓ ⇒ 一帧最多丢 2~3 个样本 ✓ 无所谓 ✓）
//     ⇒ 本模块**只有 `S_COLL` 状态**才收样本 ✓（其余状态一律不理 `samp_stb` ✓）
//
// 【算法】基 2 DIT（时域抽取）✓，**输入按位倒序入 RAM** ⇒ 输出**自然顺序** ✓
//   · 阶 s = 0..7：`half = 2^s` ✓、每组 2·half 个点 ✓、蝶形对 (m, m+half) ✓
//   · 旋转因子指数步长 `step = N/(2·half) = 2^(7-s)` ✓ ⇒ 用寄存器 `twinc` 每阶**右移一位** ✓
//     （不用桶形移位器 ✓ 省 LUT ✓）
//   · 蝶形：`X1 = (A + W·B) >>> 1` ✓、`X2 = (A − W·B) >>> 1` ✓（**每阶除 2** ✓ 见下"量程"）
//
// 【量程：为什么 16 位数据通路够用】（这条不成立就会溢出，必须写清 ✓）
//   · 输入 |x| ≤ 2047 ✓（12 位有符号 ✓）；每阶除 2 ⇒ **每阶幅度包络不增** ✓
//   · 单点上下界：|A + W·B| / 2 ≤ (|A| + |B|)/2 ✓；实部/虚部分量同样满足该界 ✓
//     ⇒ 全程 |分量| 有界 ✓（最坏档按 1.21^8 ≈ 4.3 倍放量估也只到 ~8.8k ✓ ≪ 32767 ✓）
//   ⇒ 所以内部一律 **32 位有符号算、存回时取低 16 位** ✓（不走"部分位选是有符号还是无符号"的坑 ✓）
//
// 【幅度与柱高】
//   · |X| 用 **α-max-β-min 近似**：`max + min/2`（即 α=1、β=1/2 ✓ **不开方、不用 DSP** ✓）
//     ★ 它的误差是 **偏大 0 ~ +11.8%**（`|re|=|im|` 的 45° 处最坏 ✓）—— **不是 ±4%** ✗（早先写错过，改掉）
//       ⇒ 于是显示值系统性偏大：**FF-01 理论 125、实测 136（= +8.8% ✓）**，
//         落在 0~+11.8% 界内 ✓（要更准可换 α=0.96/β=0.4 ⇒ ±4% ✓，Stage 2 做 dB 时一并定 ✓）
//   · 显示值 `disp = (|X| ≥ 1024) ? 255 : (|X| >> 2)` ✓
//     —— 内部已被 8 阶除 2（= ÷256 ✓）⇒ **满量程单音正好顶到 255** ✓（2047·128/256 = 1023 ✓）
//        FF-01 的幅度 1000 ⇒ bin 5 ≈ 1000·128/256 = **500** ⇒ `disp ≈ 125` ✓（非 0 ✓）
//   · `peak_bin/peak_val`：在 **bin 1..127** 里取最大 ✓（**跳过 DC** ✓；**严格大于** ⇒
//     平局取更低 bin ✓，且全 0 时 `peak_bin` 保持 **0**（无 X ✓））
//
// 【频带映射：★ 不在本模块 ✓ 已搬到 Stage 2（2026-10-07 用户拍板 ✓ 见 §11.9）】
//   本模块只保证"**bin 号对、幅度对、一个不落、顺序是自然序**" ✓；
//   "哪几个 bin 算一根柱" 由 `spec_bands.v` 用一张 **16 项边界表**决定 ✓（表见工单 §11.9 ✓）。
//   ★ 一条**物理事实**（写在这里免得以后又忘 ✗）：256 点 @48kHz ⇒ **bin 宽 = 187.5Hz**
//     ⇒ 文档 `:728` 说的"**60Hz 下限**"**做不到** ✗（60Hz 落在 bin **0.32** ✗）
//     ⇒ 小端口径：**第 0 柱 = bin 0..1**（≈0~375Hz ✓），其余 15 柱对数分到 **bin 85 ≈ 16.0kHz** ✓，
//       **bin 86..127 不用** ✓（要改口径就得连 `design_music_player.md:728` 一起改 ✓）
//
// 【旋转因子 ROM】`tw_rom[0..127]` = cos、`tw_rom[128..255]` = sin ✓（Q15 ✓ 1.0 = 32767 ✓）
//   ⇒ 读口 **16 位宽、256 深** ⇒ EG4 9K（512×18）**占 1 块** ✓✓
//   ★ 表**不要手抄** ✗：由 `scripts/gen_spec_twiddle.py` 生成并注入
//     `==TABLE-BEGIN==` / `==TABLE-END==` 之间 ✓（重跑脚本 ⇒ 哈希不变 ✓ 可自检 ✓）
//   ★ 符号口径：本模块按 `W = cos + j·sin`（**反变换核**）算，但只输出**幅度** ✓，
//     而输入是实信号 ⇒ 幅度谱**天然共轭对称** ⇒ 正/反变换核对柱高与 `peak_bin` **没有影响** ✓
//     （由 FF-01/FF-02 判定 ✓ —— 这条是"实测口径"，不是推测 ✓）
//
// 【时序预算】（不算不知道，算了才敢说够 ✓）
//   蝶形 6 拍 × (8 阶 × 128 蝶形 = 1024) = **6144 拍** ✓；扫描 3 拍 × 128 = **384 拍** ✓
//   ⇒ 一帧计算 ≈ 6.6k 拍 ≈ **44us** ✓ ≪ 一帧 5.33ms ✓（占用率 ~0.8% ✓；@25MHz 则约 265us ✓ 仍只占 5% ✓）
//
// 【★ 试过又**退掉**的一级流水（2026-10-07 ✓ 用户拍板"退掉、保持最小改动" ✓）】
//   来历：单元探针第一版把 `clk` 当 **150MHz** 卡 ✗ —— **那是我猜错的** ✗
//     （真机 48kHz 音频时基在 **`clk_pix` = 25MHz** ✓ 见 `rtl/top/skeleton_core.v:1154` ✓；
//      像素/合成器也在 `clk_pix` ✓ ⇒ 频谱与它同域、不用跨时钟 ✓）
//     ⇒ 于是量出 Setup WNS **−11.4ns** ✗，我据此加了一级流水（把"BRAM 读出 → 幅度"那段断成两段 ✓：
//       实测 −11.18 → **−6.57ns**，仍为负 ✗）
//   口径改对（**25MHz / 40ns** ✓）后重测：**加与不加都过** ✓
//     · **本文件这一版（不加流水）**：链长实测 ≈ **17.8ns** ✓ ⇒ 余量 ≈ 22.2ns ✓（0 违例 ✓）
//     · 加流水那版：链长 ≈ **13.2ns** ✓ ⇒ 余量 ≈ 26.8ns ✓（LUT −1、触发器 +17 ✓）
//   ★ 结论：**用户选择退掉** ✓ ⇒ 本文件就是**无流水**的那一版 ✓（完整测量与换算见
//     `doc/workitem_p3_lean.md` §11.8 ✓）。**若将来并进 50MHz 域发现余量不够**（无流水只剩 ≈2.2ns ✗），
//     把 `S_SCQ` 那一级加回来即可 ✓ —— 改法与实测数据都在 §11.8 ✓。
//
// 【资源目标】LUT ≤550 ✓／9K BRAM ≤3 ✓（数据 re/im 各 1 + 旋转因子 1 ✓）／DSP ≤6 ✓（4 个 16×16 ✓）
//   —— 实际占用以 TD 面积报告为准（本文件不写"预计"当结论 ✗）。
//
// 【未验证】TD 综合/布局布线/时序（Stage 1 要单独跑一次 phy ✓）；板上效果（P6 才上板 ✓）。
//============================================================================
module spec_fft #(
    parameter integer N      = 256,        // FFT 点数 ✓
    parameter integer SAMP_W = 12,         // 采样位宽 ✓
    parameter integer FS_HZ  = 48000,      // 采样率（只用于文档口径 ✓ 逻辑不依赖它 ✓）
    parameter integer WINDOW_HANN = 0      // 512-point periodic Hann; 0 retains the board baseline
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     samp_stb,   // 48kHz single-cycle pulse
    input  wire signed [SAMP_W-1:0] samp,       // 12 位有符号 PCM ✓
    output reg                      frame_stb,  // 一帧的**最后一个 bin** 那一拍（单拍 ✓ 帧界 ✓）
    output reg                      bin_stb,    // 逐 bin 有效（单拍 ✓ 与 bin_idx/bin_mag 同拍 ✓）
    output reg  [7:0]               bin_idx,    // 本拍这个 bin 的**编号**（0..127 ✓ 自然序 ✓）
    output reg  [7:0]               bin_mag,    // 本拍这个 bin 的**幅度 0~255** ✓（= 原 disp ✓）
    output reg  [7:0]               peak_bin,   // ★ 自证用：本帧幅度最大的 bin ✓（0 = 无峰/静音 ✓）
    output reg  [7:0]               peak_val    // ★ 自证用：该 bin 的幅度（0~255 ✓）
);

    //=========================================================================
    // 0. 规模推导
    //=========================================================================
    function integer clog2f;
        input integer value;
        integer v;
        begin
            clog2f = 0;
            for (v = value - 1; v > 0; v = v >> 1) clog2f = clog2f + 1;
        end
    endfunction

    localparam integer AW   = clog2f(N);        // 8：RAM 地址位宽 ✓
    localparam integer DW   = 16;               // 数据通路位宽（有符号 ✓）
    localparam integer BIN  = N / 2;            // Positive-frequency stream: 128 or 256 bins

    //=========================================================================
    // 1. Storage: re/im are N x 16; the shared twiddle ROM is 512 x 16.
    //    ★ 读口都在**同一个 always** 里做寄存读 ⇒ 数据比地址晚 **1 拍** ✓
    //      （下面每个状态的取样点都按这 1 拍算过 ✓，见文件头"时序预算" ✓）
    //=========================================================================
    reg signed [DW-1:0] mem_re [0:N-1];
    reg signed [DW-1:0] mem_im [0:N-1];
    reg        [15:0]   tw_rom [0:511];         // 512-point cos/sin; 256-point mode reads even entries

    initial begin
        // ==TABLE-BEGIN== 由 scripts/gen_spec_twiddle.py 注入 ✓ 不要手改 ✓
        // k = 0..255: cos at k, sin at 256+k (Q15). N=256 uses even k.
        tw_rom[  0] = 16'h7FFF;  tw_rom[256] = 16'h0000;  tw_rom[  1] = 16'h7FFD;  tw_rom[257] = 16'h0192;
        tw_rom[  2] = 16'h7FF5;  tw_rom[258] = 16'h0324;  tw_rom[  3] = 16'h7FE9;  tw_rom[259] = 16'h04B6;
        tw_rom[  4] = 16'h7FD8;  tw_rom[260] = 16'h0648;  tw_rom[  5] = 16'h7FC1;  tw_rom[261] = 16'h07D9;
        tw_rom[  6] = 16'h7FA6;  tw_rom[262] = 16'h096A;  tw_rom[  7] = 16'h7F86;  tw_rom[263] = 16'h0AFB;
        tw_rom[  8] = 16'h7F61;  tw_rom[264] = 16'h0C8C;  tw_rom[  9] = 16'h7F37;  tw_rom[265] = 16'h0E1C;
        tw_rom[ 10] = 16'h7F09;  tw_rom[266] = 16'h0FAB;  tw_rom[ 11] = 16'h7ED5;  tw_rom[267] = 16'h113A;
        tw_rom[ 12] = 16'h7E9C;  tw_rom[268] = 16'h12C8;  tw_rom[ 13] = 16'h7E5F;  tw_rom[269] = 16'h1455;
        tw_rom[ 14] = 16'h7E1D;  tw_rom[270] = 16'h15E2;  tw_rom[ 15] = 16'h7DD5;  tw_rom[271] = 16'h176E;
        tw_rom[ 16] = 16'h7D89;  tw_rom[272] = 16'h18F9;  tw_rom[ 17] = 16'h7D39;  tw_rom[273] = 16'h1A82;
        tw_rom[ 18] = 16'h7CE3;  tw_rom[274] = 16'h1C0B;  tw_rom[ 19] = 16'h7C88;  tw_rom[275] = 16'h1D93;
        tw_rom[ 20] = 16'h7C29;  tw_rom[276] = 16'h1F1A;  tw_rom[ 21] = 16'h7BC5;  tw_rom[277] = 16'h209F;
        tw_rom[ 22] = 16'h7B5C;  tw_rom[278] = 16'h2223;  tw_rom[ 23] = 16'h7AEE;  tw_rom[279] = 16'h23A6;
        tw_rom[ 24] = 16'h7A7C;  tw_rom[280] = 16'h2528;  tw_rom[ 25] = 16'h7A05;  tw_rom[281] = 16'h26A8;
        tw_rom[ 26] = 16'h7989;  tw_rom[282] = 16'h2826;  tw_rom[ 27] = 16'h7909;  tw_rom[283] = 16'h29A3;
        tw_rom[ 28] = 16'h7884;  tw_rom[284] = 16'h2B1F;  tw_rom[ 29] = 16'h77FA;  tw_rom[285] = 16'h2C99;
        tw_rom[ 30] = 16'h776B;  tw_rom[286] = 16'h2E11;  tw_rom[ 31] = 16'h76D8;  tw_rom[287] = 16'h2F87;
        tw_rom[ 32] = 16'h7641;  tw_rom[288] = 16'h30FB;  tw_rom[ 33] = 16'h75A5;  tw_rom[289] = 16'h326E;
        tw_rom[ 34] = 16'h7504;  tw_rom[290] = 16'h33DF;  tw_rom[ 35] = 16'h745F;  tw_rom[291] = 16'h354D;
        tw_rom[ 36] = 16'h73B5;  tw_rom[292] = 16'h36BA;  tw_rom[ 37] = 16'h7307;  tw_rom[293] = 16'h3824;
        tw_rom[ 38] = 16'h7254;  tw_rom[294] = 16'h398C;  tw_rom[ 39] = 16'h719D;  tw_rom[295] = 16'h3AF2;
        tw_rom[ 40] = 16'h70E2;  tw_rom[296] = 16'h3C56;  tw_rom[ 41] = 16'h7022;  tw_rom[297] = 16'h3DB8;
        tw_rom[ 42] = 16'h6F5E;  tw_rom[298] = 16'h3F17;  tw_rom[ 43] = 16'h6E96;  tw_rom[299] = 16'h4073;
        tw_rom[ 44] = 16'h6DC9;  tw_rom[300] = 16'h41CE;  tw_rom[ 45] = 16'h6CF8;  tw_rom[301] = 16'h4325;
        tw_rom[ 46] = 16'h6C23;  tw_rom[302] = 16'h447A;  tw_rom[ 47] = 16'h6B4A;  tw_rom[303] = 16'h45CD;
        tw_rom[ 48] = 16'h6A6D;  tw_rom[304] = 16'h471C;  tw_rom[ 49] = 16'h698B;  tw_rom[305] = 16'h4869;
        tw_rom[ 50] = 16'h68A6;  tw_rom[306] = 16'h49B4;  tw_rom[ 51] = 16'h67BC;  tw_rom[307] = 16'h4AFB;
        tw_rom[ 52] = 16'h66CF;  tw_rom[308] = 16'h4C3F;  tw_rom[ 53] = 16'h65DD;  tw_rom[309] = 16'h4D81;
        tw_rom[ 54] = 16'h64E8;  tw_rom[310] = 16'h4EBF;  tw_rom[ 55] = 16'h63EE;  tw_rom[311] = 16'h4FFB;
        tw_rom[ 56] = 16'h62F1;  tw_rom[312] = 16'h5133;  tw_rom[ 57] = 16'h61F0;  tw_rom[313] = 16'h5268;
        tw_rom[ 58] = 16'h60EB;  tw_rom[314] = 16'h539B;  tw_rom[ 59] = 16'h5FE3;  tw_rom[315] = 16'h54C9;
        tw_rom[ 60] = 16'h5ED7;  tw_rom[316] = 16'h55F5;  tw_rom[ 61] = 16'h5DC7;  tw_rom[317] = 16'h571D;
        tw_rom[ 62] = 16'h5CB3;  tw_rom[318] = 16'h5842;  tw_rom[ 63] = 16'h5B9C;  tw_rom[319] = 16'h5964;
        tw_rom[ 64] = 16'h5A82;  tw_rom[320] = 16'h5A82;  tw_rom[ 65] = 16'h5964;  tw_rom[321] = 16'h5B9C;
        tw_rom[ 66] = 16'h5842;  tw_rom[322] = 16'h5CB3;  tw_rom[ 67] = 16'h571D;  tw_rom[323] = 16'h5DC7;
        tw_rom[ 68] = 16'h55F5;  tw_rom[324] = 16'h5ED7;  tw_rom[ 69] = 16'h54C9;  tw_rom[325] = 16'h5FE3;
        tw_rom[ 70] = 16'h539B;  tw_rom[326] = 16'h60EB;  tw_rom[ 71] = 16'h5268;  tw_rom[327] = 16'h61F0;
        tw_rom[ 72] = 16'h5133;  tw_rom[328] = 16'h62F1;  tw_rom[ 73] = 16'h4FFB;  tw_rom[329] = 16'h63EE;
        tw_rom[ 74] = 16'h4EBF;  tw_rom[330] = 16'h64E8;  tw_rom[ 75] = 16'h4D81;  tw_rom[331] = 16'h65DD;
        tw_rom[ 76] = 16'h4C3F;  tw_rom[332] = 16'h66CF;  tw_rom[ 77] = 16'h4AFB;  tw_rom[333] = 16'h67BC;
        tw_rom[ 78] = 16'h49B4;  tw_rom[334] = 16'h68A6;  tw_rom[ 79] = 16'h4869;  tw_rom[335] = 16'h698B;
        tw_rom[ 80] = 16'h471C;  tw_rom[336] = 16'h6A6D;  tw_rom[ 81] = 16'h45CD;  tw_rom[337] = 16'h6B4A;
        tw_rom[ 82] = 16'h447A;  tw_rom[338] = 16'h6C23;  tw_rom[ 83] = 16'h4325;  tw_rom[339] = 16'h6CF8;
        tw_rom[ 84] = 16'h41CE;  tw_rom[340] = 16'h6DC9;  tw_rom[ 85] = 16'h4073;  tw_rom[341] = 16'h6E96;
        tw_rom[ 86] = 16'h3F17;  tw_rom[342] = 16'h6F5E;  tw_rom[ 87] = 16'h3DB8;  tw_rom[343] = 16'h7022;
        tw_rom[ 88] = 16'h3C56;  tw_rom[344] = 16'h70E2;  tw_rom[ 89] = 16'h3AF2;  tw_rom[345] = 16'h719D;
        tw_rom[ 90] = 16'h398C;  tw_rom[346] = 16'h7254;  tw_rom[ 91] = 16'h3824;  tw_rom[347] = 16'h7307;
        tw_rom[ 92] = 16'h36BA;  tw_rom[348] = 16'h73B5;  tw_rom[ 93] = 16'h354D;  tw_rom[349] = 16'h745F;
        tw_rom[ 94] = 16'h33DF;  tw_rom[350] = 16'h7504;  tw_rom[ 95] = 16'h326E;  tw_rom[351] = 16'h75A5;
        tw_rom[ 96] = 16'h30FB;  tw_rom[352] = 16'h7641;  tw_rom[ 97] = 16'h2F87;  tw_rom[353] = 16'h76D8;
        tw_rom[ 98] = 16'h2E11;  tw_rom[354] = 16'h776B;  tw_rom[ 99] = 16'h2C99;  tw_rom[355] = 16'h77FA;
        tw_rom[100] = 16'h2B1F;  tw_rom[356] = 16'h7884;  tw_rom[101] = 16'h29A3;  tw_rom[357] = 16'h7909;
        tw_rom[102] = 16'h2826;  tw_rom[358] = 16'h7989;  tw_rom[103] = 16'h26A8;  tw_rom[359] = 16'h7A05;
        tw_rom[104] = 16'h2528;  tw_rom[360] = 16'h7A7C;  tw_rom[105] = 16'h23A6;  tw_rom[361] = 16'h7AEE;
        tw_rom[106] = 16'h2223;  tw_rom[362] = 16'h7B5C;  tw_rom[107] = 16'h209F;  tw_rom[363] = 16'h7BC5;
        tw_rom[108] = 16'h1F1A;  tw_rom[364] = 16'h7C29;  tw_rom[109] = 16'h1D93;  tw_rom[365] = 16'h7C88;
        tw_rom[110] = 16'h1C0B;  tw_rom[366] = 16'h7CE3;  tw_rom[111] = 16'h1A82;  tw_rom[367] = 16'h7D39;
        tw_rom[112] = 16'h18F9;  tw_rom[368] = 16'h7D89;  tw_rom[113] = 16'h176E;  tw_rom[369] = 16'h7DD5;
        tw_rom[114] = 16'h15E2;  tw_rom[370] = 16'h7E1D;  tw_rom[115] = 16'h1455;  tw_rom[371] = 16'h7E5F;
        tw_rom[116] = 16'h12C8;  tw_rom[372] = 16'h7E9C;  tw_rom[117] = 16'h113A;  tw_rom[373] = 16'h7ED5;
        tw_rom[118] = 16'h0FAB;  tw_rom[374] = 16'h7F09;  tw_rom[119] = 16'h0E1C;  tw_rom[375] = 16'h7F37;
        tw_rom[120] = 16'h0C8C;  tw_rom[376] = 16'h7F61;  tw_rom[121] = 16'h0AFB;  tw_rom[377] = 16'h7F86;
        tw_rom[122] = 16'h096A;  tw_rom[378] = 16'h7FA6;  tw_rom[123] = 16'h07D9;  tw_rom[379] = 16'h7FC1;
        tw_rom[124] = 16'h0648;  tw_rom[380] = 16'h7FD8;  tw_rom[125] = 16'h04B6;  tw_rom[381] = 16'h7FE9;
        tw_rom[126] = 16'h0324;  tw_rom[382] = 16'h7FF5;  tw_rom[127] = 16'h0192;  tw_rom[383] = 16'h7FFD;
        tw_rom[128] = 16'h0000;  tw_rom[384] = 16'h7FFF;  tw_rom[129] = 16'hFE6E;  tw_rom[385] = 16'h7FFD;
        tw_rom[130] = 16'hFCDC;  tw_rom[386] = 16'h7FF5;  tw_rom[131] = 16'hFB4A;  tw_rom[387] = 16'h7FE9;
        tw_rom[132] = 16'hF9B8;  tw_rom[388] = 16'h7FD8;  tw_rom[133] = 16'hF827;  tw_rom[389] = 16'h7FC1;
        tw_rom[134] = 16'hF696;  tw_rom[390] = 16'h7FA6;  tw_rom[135] = 16'hF505;  tw_rom[391] = 16'h7F86;
        tw_rom[136] = 16'hF374;  tw_rom[392] = 16'h7F61;  tw_rom[137] = 16'hF1E4;  tw_rom[393] = 16'h7F37;
        tw_rom[138] = 16'hF055;  tw_rom[394] = 16'h7F09;  tw_rom[139] = 16'hEEC6;  tw_rom[395] = 16'h7ED5;
        tw_rom[140] = 16'hED38;  tw_rom[396] = 16'h7E9C;  tw_rom[141] = 16'hEBAB;  tw_rom[397] = 16'h7E5F;
        tw_rom[142] = 16'hEA1E;  tw_rom[398] = 16'h7E1D;  tw_rom[143] = 16'hE892;  tw_rom[399] = 16'h7DD5;
        tw_rom[144] = 16'hE707;  tw_rom[400] = 16'h7D89;  tw_rom[145] = 16'hE57E;  tw_rom[401] = 16'h7D39;
        tw_rom[146] = 16'hE3F5;  tw_rom[402] = 16'h7CE3;  tw_rom[147] = 16'hE26D;  tw_rom[403] = 16'h7C88;
        tw_rom[148] = 16'hE0E6;  tw_rom[404] = 16'h7C29;  tw_rom[149] = 16'hDF61;  tw_rom[405] = 16'h7BC5;
        tw_rom[150] = 16'hDDDD;  tw_rom[406] = 16'h7B5C;  tw_rom[151] = 16'hDC5A;  tw_rom[407] = 16'h7AEE;
        tw_rom[152] = 16'hDAD8;  tw_rom[408] = 16'h7A7C;  tw_rom[153] = 16'hD958;  tw_rom[409] = 16'h7A05;
        tw_rom[154] = 16'hD7DA;  tw_rom[410] = 16'h7989;  tw_rom[155] = 16'hD65D;  tw_rom[411] = 16'h7909;
        tw_rom[156] = 16'hD4E1;  tw_rom[412] = 16'h7884;  tw_rom[157] = 16'hD367;  tw_rom[413] = 16'h77FA;
        tw_rom[158] = 16'hD1EF;  tw_rom[414] = 16'h776B;  tw_rom[159] = 16'hD079;  tw_rom[415] = 16'h76D8;
        tw_rom[160] = 16'hCF05;  tw_rom[416] = 16'h7641;  tw_rom[161] = 16'hCD92;  tw_rom[417] = 16'h75A5;
        tw_rom[162] = 16'hCC21;  tw_rom[418] = 16'h7504;  tw_rom[163] = 16'hCAB3;  tw_rom[419] = 16'h745F;
        tw_rom[164] = 16'hC946;  tw_rom[420] = 16'h73B5;  tw_rom[165] = 16'hC7DC;  tw_rom[421] = 16'h7307;
        tw_rom[166] = 16'hC674;  tw_rom[422] = 16'h7254;  tw_rom[167] = 16'hC50E;  tw_rom[423] = 16'h719D;
        tw_rom[168] = 16'hC3AA;  tw_rom[424] = 16'h70E2;  tw_rom[169] = 16'hC248;  tw_rom[425] = 16'h7022;
        tw_rom[170] = 16'hC0E9;  tw_rom[426] = 16'h6F5E;  tw_rom[171] = 16'hBF8D;  tw_rom[427] = 16'h6E96;
        tw_rom[172] = 16'hBE32;  tw_rom[428] = 16'h6DC9;  tw_rom[173] = 16'hBCDB;  tw_rom[429] = 16'h6CF8;
        tw_rom[174] = 16'hBB86;  tw_rom[430] = 16'h6C23;  tw_rom[175] = 16'hBA33;  tw_rom[431] = 16'h6B4A;
        tw_rom[176] = 16'hB8E4;  tw_rom[432] = 16'h6A6D;  tw_rom[177] = 16'hB797;  tw_rom[433] = 16'h698B;
        tw_rom[178] = 16'hB64C;  tw_rom[434] = 16'h68A6;  tw_rom[179] = 16'hB505;  tw_rom[435] = 16'h67BC;
        tw_rom[180] = 16'hB3C1;  tw_rom[436] = 16'h66CF;  tw_rom[181] = 16'hB27F;  tw_rom[437] = 16'h65DD;
        tw_rom[182] = 16'hB141;  tw_rom[438] = 16'h64E8;  tw_rom[183] = 16'hB005;  tw_rom[439] = 16'h63EE;
        tw_rom[184] = 16'hAECD;  tw_rom[440] = 16'h62F1;  tw_rom[185] = 16'hAD98;  tw_rom[441] = 16'h61F0;
        tw_rom[186] = 16'hAC65;  tw_rom[442] = 16'h60EB;  tw_rom[187] = 16'hAB37;  tw_rom[443] = 16'h5FE3;
        tw_rom[188] = 16'hAA0B;  tw_rom[444] = 16'h5ED7;  tw_rom[189] = 16'hA8E3;  tw_rom[445] = 16'h5DC7;
        tw_rom[190] = 16'hA7BE;  tw_rom[446] = 16'h5CB3;  tw_rom[191] = 16'hA69C;  tw_rom[447] = 16'h5B9C;
        tw_rom[192] = 16'hA57E;  tw_rom[448] = 16'h5A82;  tw_rom[193] = 16'hA464;  tw_rom[449] = 16'h5964;
        tw_rom[194] = 16'hA34D;  tw_rom[450] = 16'h5842;  tw_rom[195] = 16'hA239;  tw_rom[451] = 16'h571D;
        tw_rom[196] = 16'hA129;  tw_rom[452] = 16'h55F5;  tw_rom[197] = 16'hA01D;  tw_rom[453] = 16'h54C9;
        tw_rom[198] = 16'h9F15;  tw_rom[454] = 16'h539B;  tw_rom[199] = 16'h9E10;  tw_rom[455] = 16'h5268;
        tw_rom[200] = 16'h9D0F;  tw_rom[456] = 16'h5133;  tw_rom[201] = 16'h9C12;  tw_rom[457] = 16'h4FFB;
        tw_rom[202] = 16'h9B18;  tw_rom[458] = 16'h4EBF;  tw_rom[203] = 16'h9A23;  tw_rom[459] = 16'h4D81;
        tw_rom[204] = 16'h9931;  tw_rom[460] = 16'h4C3F;  tw_rom[205] = 16'h9844;  tw_rom[461] = 16'h4AFB;
        tw_rom[206] = 16'h975A;  tw_rom[462] = 16'h49B4;  tw_rom[207] = 16'h9675;  tw_rom[463] = 16'h4869;
        tw_rom[208] = 16'h9593;  tw_rom[464] = 16'h471C;  tw_rom[209] = 16'h94B6;  tw_rom[465] = 16'h45CD;
        tw_rom[210] = 16'h93DD;  tw_rom[466] = 16'h447A;  tw_rom[211] = 16'h9308;  tw_rom[467] = 16'h4325;
        tw_rom[212] = 16'h9237;  tw_rom[468] = 16'h41CE;  tw_rom[213] = 16'h916A;  tw_rom[469] = 16'h4073;
        tw_rom[214] = 16'h90A2;  tw_rom[470] = 16'h3F17;  tw_rom[215] = 16'h8FDE;  tw_rom[471] = 16'h3DB8;
        tw_rom[216] = 16'h8F1E;  tw_rom[472] = 16'h3C56;  tw_rom[217] = 16'h8E63;  tw_rom[473] = 16'h3AF2;
        tw_rom[218] = 16'h8DAC;  tw_rom[474] = 16'h398C;  tw_rom[219] = 16'h8CF9;  tw_rom[475] = 16'h3824;
        tw_rom[220] = 16'h8C4B;  tw_rom[476] = 16'h36BA;  tw_rom[221] = 16'h8BA1;  tw_rom[477] = 16'h354D;
        tw_rom[222] = 16'h8AFC;  tw_rom[478] = 16'h33DF;  tw_rom[223] = 16'h8A5B;  tw_rom[479] = 16'h326E;
        tw_rom[224] = 16'h89BF;  tw_rom[480] = 16'h30FB;  tw_rom[225] = 16'h8928;  tw_rom[481] = 16'h2F87;
        tw_rom[226] = 16'h8895;  tw_rom[482] = 16'h2E11;  tw_rom[227] = 16'h8806;  tw_rom[483] = 16'h2C99;
        tw_rom[228] = 16'h877C;  tw_rom[484] = 16'h2B1F;  tw_rom[229] = 16'h86F7;  tw_rom[485] = 16'h29A3;
        tw_rom[230] = 16'h8677;  tw_rom[486] = 16'h2826;  tw_rom[231] = 16'h85FB;  tw_rom[487] = 16'h26A8;
        tw_rom[232] = 16'h8584;  tw_rom[488] = 16'h2528;  tw_rom[233] = 16'h8512;  tw_rom[489] = 16'h23A6;
        tw_rom[234] = 16'h84A4;  tw_rom[490] = 16'h2223;  tw_rom[235] = 16'h843B;  tw_rom[491] = 16'h209F;
        tw_rom[236] = 16'h83D7;  tw_rom[492] = 16'h1F1A;  tw_rom[237] = 16'h8378;  tw_rom[493] = 16'h1D93;
        tw_rom[238] = 16'h831D;  tw_rom[494] = 16'h1C0B;  tw_rom[239] = 16'h82C7;  tw_rom[495] = 16'h1A82;
        tw_rom[240] = 16'h8277;  tw_rom[496] = 16'h18F9;  tw_rom[241] = 16'h822B;  tw_rom[497] = 16'h176E;
        tw_rom[242] = 16'h81E3;  tw_rom[498] = 16'h15E2;  tw_rom[243] = 16'h81A1;  tw_rom[499] = 16'h1455;
        tw_rom[244] = 16'h8164;  tw_rom[500] = 16'h12C8;  tw_rom[245] = 16'h812B;  tw_rom[501] = 16'h113A;
        tw_rom[246] = 16'h80F7;  tw_rom[502] = 16'h0FAB;  tw_rom[247] = 16'h80C9;  tw_rom[503] = 16'h0E1C;
        tw_rom[248] = 16'h809F;  tw_rom[504] = 16'h0C8C;  tw_rom[249] = 16'h807A;  tw_rom[505] = 16'h0AFB;
        tw_rom[250] = 16'h805A;  tw_rom[506] = 16'h096A;  tw_rom[251] = 16'h803F;  tw_rom[507] = 16'h07D9;
        tw_rom[252] = 16'h8028;  tw_rom[508] = 16'h0648;  tw_rom[253] = 16'h8017;  tw_rom[509] = 16'h04B6;
        tw_rom[254] = 16'h800B;  tw_rom[510] = 16'h0324;  tw_rom[255] = 16'h8003;  tw_rom[511] = 16'h0192;
        // ==TABLE-END==
    end

    reg                 ram_we;
    reg  [AW-1:0]       ram_waddr;
    reg  signed [DW-1:0] ram_wre, ram_wim;
    reg  [AW-1:0]       ram_raddr;
    reg  signed [DW-1:0] rd_re, rd_im;
    reg  [8:0]          tw_addr;
    reg  [15:0]         tw_q;

    always @(posedge clk) begin
        if (ram_we) begin
            mem_re[ram_waddr] <= ram_wre;
            mem_im[ram_waddr] <= ram_wim;
        end
        rd_re <= mem_re[ram_raddr];
        rd_im <= mem_im[ram_raddr];
        tw_q  <= tw_rom[tw_addr];
    end

    //=========================================================================
    // 2. 索引：位倒序 + 蝶形地址 + 旋转因子指数
    //=========================================================================
    function [AW-1:0] brev;
        input [AW-1:0] v;
        integer i;
        begin
            for (i = 0; i < AW; i = i + 1) brev[i] = v[AW-1-i];
        end
    endfunction

    reg [AW-1:0] stg;                           // 阶 0..7 ✓
    reg [AW-1:0] half;                          // 2^stg ✓
    reg [AW-1:0] twinc;                         // 2^(7-stg) ✓
    reg [AW-1:0] grp_inc;                       // 2·half ✓（stg=7 那一档会溢出，但**不使用** ✓）
    reg [AW-1:0] ngrp;                          // 本阶组数 = N/(2·half) ✓
    reg [AW-1:0] grp;                           // 本阶内已完成的组数 ✓
    reg [AW-1:0] base;                          // 本组起点 ✓
    reg [AW-1:0] j;                             // 组内蝶形序号 ✓
    reg [AW-1:0] twidx;                         // 旋转因子指数（≤127 ✓ ⇒ bit7 恒 0 ✓）

    wire [8:0] fft_tw_index = (N == 256) ? {twidx[7:0], 1'b0}
                                          : {1'b0, twidx[7:0]};

    wire [AW-1:0] bf_m  = base + j;
    wire [AW-1:0] bf_m2 = base + j + half;

    //=========================================================================
    // 3. 蝶形算术（**全 32 位有符号**，存回时取低 16 位 ✓）
    //=========================================================================
    reg  signed [DW-1:0] a_re, a_im;            // A = 蝶形上半 ✓
    reg  signed [DW-1:0] b_re, b_im;            // B = 蝶形下半 ✓
    reg  signed [DW-1:0] w_cos, w_sin;

    wire signed [31:0] p_rr = b_re * w_cos;
    wire signed [31:0] p_ii = b_im * w_sin;
    wire signed [31:0] p_ri = b_re * w_sin;
    wire signed [31:0] p_ir = b_im * w_cos;
    // W·B：实部 = b_re·cos − b_im·sin ✓；虚部 = b_re·sin + b_im·cos ✓（+2^14 做四舍五入 ✓）
    wire signed [31:0] pr = (p_rr - p_ii + 32'sd16384) >>> 15;
    wire signed [31:0] pi = (p_ri + p_ir + 32'sd16384) >>> 15;
    // 每阶除 2 ✓
    wire signed [31:0] x1r = (a_re + pr) >>> 1;
    wire signed [31:0] x1i = (a_im + pi) >>> 1;
    wire signed [31:0] x2r = (a_re - pr) >>> 1;
    wire signed [31:0] x2i = (a_im - pi) >>> 1;

    //=========================================================================
    // 4. 扫描：幅度 → 显示值 → 柱 / 峰值
    //=========================================================================
    reg  [AW-1:0] sc;                           // 扫描 bin（0..127 ✓）
    reg  [7:0]    pmax;                         // 本帧峰值 ✓
    reg  [7:0]    pbin;

    wire [DW-1:0] abs_re = rd_re[DW-1] ? (~rd_re + 16'd1) : rd_re;
    wire [DW-1:0] abs_im = rd_im[DW-1] ? (~rd_im + 16'd1) : rd_im;
    wire [DW-1:0] mag_hi = (abs_re > abs_im) ? abs_re : abs_im;
    wire [DW-1:0] mag_lo = (abs_re > abs_im) ? abs_im : abs_re;
    wire [DW:0]   mag17  = {1'b0, mag_hi} + {2'b0, mag_lo[DW-1:1]};   // max + min/2 ✓
    wire [7:0]    disp   = WINDOW_HANN
        ? ((mag17[DW:9] != 8'd0) ? 8'd255 : mag17[8:1])
        : ((mag17[DW:10] != 7'd0) ? 8'd255 : mag17[9:2]);

    //=========================================================================
    // 5. 主状态机
    //=========================================================================
    localparam [3:0] S_COLL = 4'd0,             // 收样本（唯一理 samp_stb 的状态 ✓）
                     S_BF0  = 4'd1,             // 发 A 地址 + cos 地址 ✓
                     S_BF1  = 4'd2,             // 发 B 地址 + sin 地址 ✓
                     S_BF2  = 4'd3,             // 收 A + cos ✓
                     S_BF3  = 4'd4,             // 收 B + sin ✓
                     S_BF4  = 4'd5,             // 写回 X1 ✓
                     S_BF5  = 4'd6,             // 写回 X2 + 推进索引 ✓
                     S_SCA  = 4'd7,             // 扫描：发地址 ✓
                     S_SCB  = 4'd8,             // 扫描：等读数 ✓
                     S_SCP  = 4'd9,             // 扫描：处理 ✓
                     S_OUT  = 4'd10;            // 出柱 / 峰值 / frame_stb ✓

    reg [3:0]    fst;
    reg [AW-1:0] cnt;
    wire signed [17:0] win_cos = {{2{tw_q[15]}}, tw_q};
    wire signed [17:0] win_delta = cnt[AW-1] ? (18'sd32767 + win_cos)
                                              : (18'sd32767 - win_cos);
    wire [15:0] win_weight = win_delta[16:1];
    wire signed [SAMP_W+16:0] win_product = samp * $signed({1'b0, win_weight});
    wire signed [31:0] win_sample = ($signed(win_product) + 32'sd16384) >>> 15;
    wire signed [DW-1:0] capture_sample = WINDOW_HANN
        ? win_sample[DW-1:0] : {{(DW-SAMP_W){samp[SAMP_W-1]}}, samp};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fst       <= S_COLL;
            cnt       <= {AW{1'b0}};
            ram_we    <= 1'b0;
            ram_waddr <= {AW{1'b0}};
            ram_wre   <= {DW{1'b0}};
            ram_wim   <= {DW{1'b0}};
            ram_raddr <= {AW{1'b0}};
            tw_addr   <= 9'd0;
            frame_stb <= 1'b0;
            bin_stb   <= 1'b0;
            bin_idx   <= 8'd0;
            bin_mag   <= 8'd0;
            peak_bin  <= 8'd0;
            peak_val  <= 8'd0;
            stg <= {AW{1'b0}}; half <= {AW{1'b0}}; twinc <= {AW{1'b0}}; grp_inc <= {AW{1'b0}};
            ngrp <= {AW{1'b0}}; grp <= {AW{1'b0}}; base <= {AW{1'b0}}; j <= {AW{1'b0}}; twidx <= {AW{1'b0}};
            a_re <= {DW{1'b0}}; a_im <= {DW{1'b0}}; b_re <= {DW{1'b0}}; b_im <= {DW{1'b0}};
            w_cos <= {DW{1'b0}}; w_sin <= {DW{1'b0}};
            sc <= {AW{1'b0}}; pmax <= 8'd0; pbin <= 8'd0;
        end else begin
            ram_we    <= 1'b0;                  // 默认不写 ✓（需要的状态里再置 1 ✓）
            frame_stb <= 1'b0;                  // 默认不出帧 ✓（S_OUT 里置 1 ⇒ **单拍** ✓）
            bin_stb   <= 1'b0;                  // 默认不吐 bin ✓（S_SCP 里置 1 ⇒ 每 bin 单拍 ✓）

            case (fst)
            //-------------------------------------------------------------
            // 采集：第 n 个样本写到**位倒序**地址 ✓（⇒ 输出自然是自然序 ✓）
            //-------------------------------------------------------------
            S_COLL: begin
                // The twiddle ROM is idle while collecting samples. Its cosine
                // half supplies periodic Hann weights without another BRAM.
                if (WINDOW_HANN) tw_addr <= {1'b0, cnt[7:0]};
                if (samp_stb) begin
                    ram_we    <= 1'b1;
                    ram_waddr <= brev(cnt);
                    ram_wre   <= capture_sample;
                    ram_wim   <= {DW{1'b0}};                              // 虚部 0 ✓（实信号 ✓）
                    if (cnt == N - 1) begin
                        fst     <= S_BF0;
                        cnt     <= {AW{1'b0}};
                        stg     <= {AW{1'b0}};
                        half    <= {{(AW-1){1'b0}}, 1'b1};                // 1 = 2^0 ✓
                        twinc   <= {1'b1, {(AW-1){1'b0}}};                // 128 = 2^(AW-1) = 2^(7-0) ✓
                        grp_inc <= {{(AW-2){1'b0}}, 1'b1, 1'b0};          // 2 = 2·half ✓
                        ngrp    <= BIN;                                   // 128 ✓（AW 位截断 ✓）
                        grp     <= {AW{1'b0}};
                        base    <= {AW{1'b0}};
                        j       <= {AW{1'b0}};
                        twidx   <= {AW{1'b0}};
                    end else begin
                        cnt <= cnt + {{(AW-1){1'b0}}, 1'b1};
                    end
                end
            end
            //-------------------------------------------------------------
            // 蝶形 6 拍（地址 → 地址 → 收 A/cos → 收 B/sin → 写 X1 → 写 X2 ✓）
            //-------------------------------------------------------------
            S_BF0: begin
                ram_raddr <= bf_m;
                tw_addr   <= fft_tw_index;
                fst       <= S_BF1;
            end
            S_BF1: begin
                ram_raddr <= bf_m2;
                tw_addr   <= {1'b1, fft_tw_index[7:0]};
                fst       <= S_BF2;
            end
            S_BF2: begin
                a_re <= rd_re; a_im <= rd_im;                          // A = mem[m] ✓
                w_cos <= tw_q;                                         // cos ✓
                fst  <= S_BF3;
            end
            S_BF3: begin
                b_re <= rd_re; b_im <= rd_im;                          // B = mem[m+half] ✓
                w_sin <= tw_q;                                         // sin ✓
                fst   <= S_BF4;
            end
            S_BF4: begin
                ram_we    <= 1'b1;
                ram_waddr <= bf_m;
                ram_wre   <= x1r[DW-1:0];
                ram_wim   <= x1i[DW-1:0];
                fst       <= S_BF5;
            end
            S_BF5: begin
                ram_we    <= 1'b1;
                ram_waddr <= bf_m2;
                ram_wre   <= x2r[DW-1:0];
                ram_wim   <= x2i[DW-1:0];
                // ---- 推进蝶形索引 ✓（分组 → 分阶 → 收尾 ✓）----
                if (j == half - {{(AW-1){1'b0}}, 1'b1}) begin
                    j     <= {AW{1'b0}};
                    twidx <= {AW{1'b0}};
                    if (grp == ngrp - {{(AW-1){1'b0}}, 1'b1}) begin
                        base <= {AW{1'b0}};
                        grp  <= {AW{1'b0}};
                        if (stg == AW - 1) begin                  // 最后一阶（AW = log2(N) ✓）
                            sc    <= {AW{1'b0}};
                            pmax  <= 8'd0;
                            pbin  <= 8'd0;
                            fst   <= S_SCA;
                        end else begin
                            stg     <= stg + {{(AW-1){1'b0}}, 1'b1};
                            half    <= half    << 1;               // 2^s ✓
                            twinc   <= twinc   >> 1;               // 2^(7-s) ✓
                            grp_inc <= grp_inc << 1;               // 2·half ✓
                            ngrp    <= ngrp    >> 1;               // 组数减半 ✓
                            fst     <= S_BF0;
                        end
                    end else begin
                        base <= base + grp_inc;
                        grp  <= grp + {{(AW-1){1'b0}}, 1'b1};
                        fst  <= S_BF0;
                    end
                end else begin
                    j     <= j + {{(AW-1){1'b0}}, 1'b1};
                    twidx <= twidx + twinc;
                    fst   <= S_BF0;
                end
            end
            //-------------------------------------------------------------
            // 扫描 bin 0..127：**逐 bin 吐流**（`bin_stb/bin_idx/bin_mag` ✓）＋ 峰值取最大 ✓
            //   ★ 柱的生成**不在这里**了 ✓ —— 已按 2026-10-07 的决定搬到 Stage 2 `spec_bands.v`
            //     （它才是"256 bin → 16 个对数带"的地方 ✓；这里只负责"把 bin 一个不落地吐出去" ✓）
            //   ★ 只扫一遍 ⇒ **不重复扫** ✓、也没有"柱译码"那套死逻辑 ✗（省 LUT ✓）
            //-------------------------------------------------------------
            S_SCA: begin
                ram_raddr <= sc;
                fst       <= S_SCB;
            end
            S_SCB: begin
                fst <= S_SCP;                                          // 等这 1 拍读延迟 ✓
            end
            S_SCP: begin
                // ★ 吐本 bin：编号 + 幅度（同一拍 ✓ 单拍脉冲 ✓）
                bin_stb <= 1'b1;
                bin_idx <= sc;
                bin_mag <= disp;
                // 峰值：跳过 DC ✓、严格大于（平局取更低 bin ✓）、全 0 时保持 0 ✓
                if ((sc != {AW{1'b0}}) && (disp > pmax)) begin
                    pmax <= disp;
                    pbin <= sc;
                end
                if (sc == (BIN - 1)) begin
                    fst <= S_OUT;
                end else begin
                    sc  <= sc + {{(AW-1){1'b0}}, 1'b1};
                    fst <= S_SCA;
                end
            end
            //-------------------------------------------------------------
            // 出帧：★ 语义 = "**本帧最后一个 bin 已经吐完**" ✓ ⇒ 这里只搬运峰值 + 单拍脉冲 ✓
            //   （下游 `spec_bands` 用 `bin_stb` 数 bin ✓、用 `frame_stb` 收口一帧 ✓）
            //-------------------------------------------------------------
            S_OUT: begin
                peak_bin  <= pbin;
                peak_val  <= pmax;
                frame_stb <= 1'b1;
                cnt       <= {AW{1'b0}};
                fst       <= S_COLL;
            end
            default: fst <= S_COLL;
            endcase
        end
    end

    //=========================================================================
    // 6. 展开期守卫：N 必须是 2 的幂（本模块的地址/阶数/位倒序都按这个推 ✓）
    //    否则**故意**停在"模块未定义"，不静默走错路 ✓
    //=========================================================================
    generate
    if (((N != 256) && (N != 512)) || (WINDOW_HANN && (N != 512))) begin : g_guard
        spec_fft_unsupported_configuration u_guard (.unused(1'b0));
    end
    endgenerate

endmodule

`default_nettype wire
