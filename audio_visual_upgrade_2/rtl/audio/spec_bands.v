`default_nettype none
//============================================================================
// rtl/audio/spec_bands.v -- streaming bin-to-band reducer.
// The historical P4 notes below describe BARS=16, BIN=128. Upgraded mode
// BARS=24, BIN=256 excludes DC, groups bins 1..170 by rounded Mel boundaries,
// blends 3/4 band maximum with 1/4 width-normalized mean, and uses calibrated
// 12/16/22-level release per FFT frame (low/mid/high). No extra band BRAM.
//
// 【它要满足的判据】单元台 `tb/tb_spec_bands.v`（**先写的** ✓ 见工单 §11.10/§11.11 ✓）：
//   SB-01 单 bin（`bin5=128`）⇒ `bars[4] == 224` ✓ 且**其余 15 柱 == 0** ✓
//   SB-02 静音（128 个 bin 全 0）⇒ 16 柱全 0 ✓ 且 `peak_bars` 全 0 ✓
//   SB-03 带边界（`bin1/bin2/bin85/bin86`）⇒ 前三个只点亮 `bars[0]/[1]/[15]` ✓；
//         ★ **`bin86` 及上去（86..127）一根柱都不许动** ✓
//   SB-04 平滑/峰值（先 `bin5=128` 一帧、随后全 0）⇒ 显示值**逐帧 −1** ✓、
//         峰值**保持 8 帧**后同样 −1 ✓
//   SB-05 ★ **半截帧**（只喂 20 个 bin 就拉 `frame_stb` ✓）⇒ ① 该帧照样出 `bars_stb` ✓
//         ② `bars[4]` 仍按已收的 bin 算对 ✓ ③ ★ **对齐不许漂** ✓：
//         紧接着再喂一整帧（`bin2=128`）⇒ 必须得到 `bars[1]==224` ✓
//
// 【接口】= 工单 §11.10(b) ✓（用户 2026-10-07 拍板 ✓）
//   · 入：`bin_stb / bin_idx[7:0] / bin_mag[7:0]`（逐 bin ✓ 自然序 ✓）＋ `frame_stb`（★ 见下 ✓）
//   · 出：`bars_stb`（一帧更新完 **单拍** ✓）、`bars`（平滑后 ✓）、`peak_bars`（峰值保持 ✓ 单独出脚 ✓）
//   · ★ `frame_stb` 的用法（**改过一次，这里写清** ✓）：
//       正常帧界 = 自己数满 **128** 个 `bin_stb` ✓（不依赖上游 ✓）；
//       `frame_stb` **只用来发现"半截帧"** ✓：若它在"还没数满 128"时到来（`cnt != 0` ✓）
//       ⇒ 判定上游这一帧提前结束了 ✗ ⇒ 走**排空**把 16 个带补齐 ✓。
//     （上游 `spec_fft` 的 `frame_stb` 比第 128 个 `bin_stb` **晚一拍** ✓ ⇒ 那时 `cnt` 已清 0 ✓
//      ⇒ 正常帧**不会**误触发半截分支 ✓✓）
//
// 【★ 状态用"旋转移位寄存器"，不用变量索引】（2026-10-07 **实测逼出来的** ✓ 见工单 §11.11 ✓）
//   上一版把 16 根柱的状态放在寄存器堆里、用 `bars[8*band +: 8]` 这种**变量位选**读写 ⇒
//   综合出 **两套 16:1 读 mux ＋ 16 路写译码** ⇒ 实测 `u_bands` LUT = **438** ✗，
//   而"只改一处"的实验（`scripts/_exp_bands_cost.py` ✓）量出**光那两套读 mux 就占 185 LUT（42%）** ✗。
//   本版把状态改成**旋转移位寄存器** ✓：
//     · 当前带永远在**头位**（`bars[7:0]` ✓、`peak_bars[7:0]` ✓、`hold_sr[3:0]` ✓）⇒ 读是**连线** ✓
//     · 收口时"更新头位 ＋ 整寄存器右旋 8 位（hold 旋 4 位）" ⇒ 写也是**连线** ✓（**0 LUT** ✓）
//     · ★ 一帧恰好 **16 次 × 8 位 = 128 位 = 整圈** ✓ ⇒ **帧末自动回到原对齐** ✓✓
//       （下游只在 `bars_stb` 那一拍取值 ✓ ⇒ 帧中间"看起来在转"完全看不见 ✓）
//   ⇒ 代价：状态量不变（≈320 FF ✓），但**寻址逻辑全没了** ✓（实测见 §11.11 ✓）
//
// 【带表】`{2,1,1,1,1,1,2,2,3,3,4,6,7,9,11,32}` ✓ **和 = 86** ✓ ⇒ 覆盖 **bin 0..85** ✓
//   （带 0 = bin 0..1 ≈0~375Hz ✓；带 15 = bin 54..85 ≈10.1~16.1kHz ✓；**bin 86..127 一律丢** ✓）
//
// 【dB】`lvl = (p<<5) + TBL[mant]` ✓（`p` = 最高位位置 ✓、`mant` = 紧邻的 3 位 ✓）
//   `TBL = {0,5,10,15,19,22,26,29}` = `round(32·log2(1+mant/8))` ✓ ⇒ **每倍频 32 级** ✓
//   ⇒ **2 的幂给出整数** ✓（`32→160`、`64→192`、`128→224` ✓）⇒ 判据能写**等式** ✓
//
// 【平滑 / 峰值】上升**立即** ✓；下降 **−1/帧**（到 0 停 ✓）；峰值**保持 8 帧**后同样 −1 ✓
//
// 【★ 半截帧的补救 = "排空"】（用户 2026-10-07 拍板 ✓）
//   若帧界到来时带还没走完（`band < BARS` ✓）⇒ 进入 `drain` ✓：**每拍补一个带、`nl` 取 0** ✓
//   （= "本帧这个带没有能量" ✓ ⇒ 它按口径正常衰减 ✓）直到 16 个带补齐 ✓ ⇒ ① 语义对 ✓
//   ② **旋转补满一整圈** ⇒ 对齐不漂 ✓✓。排空最长 16 拍 ✓。
//   ★ **真机上的代价（要写清）**：排空期间来的 `bin_stb` 会被丢（最长 ≈16 拍 ≈ 5 个 bin ✓）
//     ⇒ 紧随其后的那一帧会错位一次 ✗（下一个帧界自动恢复 ✓）。
//     上游 `spec_fft` **固定吐 128 个 bin** ✓ ⇒ 这条路径本该永不触发 ✓（属恢复路径 ✓）。
//
// 【预算】Stage 2 上限 ≤150 LUT **是我估的、已被实测推翻** ✗（见 §11.11 ✓）；本版实测数写在该节 ✓。
//   **BRAM 0 枚** ✓、**DSP 0 个** ✓（兑现"9K 已用满，一块都不许再要" ✓）。
//
// 【时钟域】`clk_pix` **25MHz** ✓（与 `spec_fft`、像素/合成器同域 ⇒ 全链无 CDC ✓）。
//============================================================================
module spec_bands #(
    parameter integer BARS = 16,        // 16 legacy or 24 upgraded bands
    parameter integer BIN  = 128        // 128 legacy or 256 upgraded bins
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 bin_stb,     // 逐 bin 有效（单拍 ✓）
    input  wire [7:0]           bin_idx,     // 0..127 ✓ 自然序 ✓（本模块不读它 ✓ 只依赖顺序 ✓）
    input  wire [7:0]           bin_mag,     // 该 bin 幅度 0~255 ✓
    input  wire                 frame_stb,   // ★ 只用来发现"半截帧" ✓（见文件头 ✓）
    output reg                  bars_stb,    // 一帧更新完（单拍 ✓）
    output reg  [8*BARS-1:0]    bars,        // 16 根柱（平滑后 ✓）= **旋转状态本身** ✓
    output reg  [8*BARS-1:0]    peak_bars    // 16 根柱的峰值保持 ✓ = 另一个旋转状态 ✓
);

    localparam integer AW = 7;                  // cnt[AW:0] counts 0..255

    //=========================================================================
    // 0. 两张小表（组合查表 ✓ 极小 ✓ 不占 BRAM ✓）
    //=========================================================================
    function [5:0] bsize;
        input [4:0] b;                          // 24 is the completed-band sentinel
        begin
            if (BARS == 24) begin
                // Rounded Mel boundaries for bins 1..170 at 48 kHz / 512.
                // Widths sum to 170; bin 0 is skipped explicitly below.
                case (b)
                5'd0 : bsize = 6'd2;   5'd1 : bsize = 6'd1;   5'd2 : bsize = 6'd2;   5'd3 : bsize = 6'd2;
                5'd4 : bsize = 6'd1;   5'd5 : bsize = 6'd3;   5'd6 : bsize = 6'd2;   5'd7 : bsize = 6'd3;
                5'd8 : bsize = 6'd3;   5'd9 : bsize = 6'd4;   5'd10: bsize = 6'd4;   5'd11: bsize = 6'd4;
                5'd12: bsize = 6'd6;   5'd13: bsize = 6'd5;   5'd14: bsize = 6'd7;   5'd15: bsize = 6'd8;
                5'd16: bsize = 6'd9;   5'd17: bsize = 6'd9;   5'd18: bsize = 6'd12;  5'd19: bsize = 6'd12;
                5'd20: bsize = 6'd15;  5'd21: bsize = 6'd16;  5'd22: bsize = 6'd19;  5'd23: bsize = 6'd21;
                default: bsize = 6'd0;
                endcase
            end else begin
                case (b)
                5'd0 : bsize = 6'd2;    5'd1 : bsize = 6'd1;    5'd2 : bsize = 6'd1;    5'd3 : bsize = 6'd1;
                5'd4 : bsize = 6'd1;    5'd5 : bsize = 6'd1;    5'd6 : bsize = 6'd2;    5'd7 : bsize = 6'd2;
                5'd8 : bsize = 6'd3;    5'd9 : bsize = 6'd3;    5'd10: bsize = 6'd4;    5'd11: bsize = 6'd6;
                5'd12: bsize = 6'd7;    5'd13: bsize = 6'd9;    5'd14: bsize = 6'd11;   5'd15: bsize = 6'd32;
                default: bsize = 6'd0;
                endcase
            end
        end
    endfunction

    function [11:0] recip_width;
        input [5:0] width;
        begin
            case (width)
            6'd1: recip_width = 12'd2048; 6'd2: recip_width = 12'd1024;
            6'd3: recip_width = 12'd683;  6'd4: recip_width = 12'd512;
            6'd5: recip_width = 12'd410;  6'd6: recip_width = 12'd341;
            6'd7: recip_width = 12'd293;  6'd8: recip_width = 12'd256;
            6'd9: recip_width = 12'd228;  6'd12: recip_width = 12'd171;
            6'd15: recip_width = 12'd137; 6'd16: recip_width = 12'd128;
            6'd19: recip_width = 12'd108; 6'd21: recip_width = 12'd98;
            default: recip_width = 12'd0;
            endcase
        end
    endfunction

    function [7:0] db_lvl;                      // lvl = (p<<5) + TBL[mant] ✓
        input [7:0] m;
        integer i;
        reg [2:0] p;
        reg [2:0] mant;
        begin
            if (m == 8'd0) begin
                db_lvl = 8'd0;                  // 无能量 = 0 ✓
            end else begin
                p = 3'd0;
                for (i = 0; i < 8; i = i + 1) if (m[i]) p = i[2:0];   // 最后一次赋值胜 ⇒ 最高位 ✓
                case (p)                        // 紧邻最高位下面的 3 位（不足则左移补 0 ✓）
                3'd7: mant = m[6:4];
                3'd6: mant = m[5:3];
                3'd5: mant = m[4:2];
                3'd4: mant = m[3:1];
                3'd3: mant = m[2:0];
                3'd2: mant = {m[1:0], 1'b0};
                3'd1: mant = {m[0],   2'b00};
                default: mant = 3'b000;
                endcase
                case (mant)                     // TBL = round(32·log2(1+mant/8)) ✓
                3'd0: db_lvl = 8'd0;    3'd1: db_lvl = 8'd5;    3'd2: db_lvl = 8'd10;   3'd3: db_lvl = 8'd15;
                3'd4: db_lvl = 8'd19;   3'd5: db_lvl = 8'd22;   3'd6: db_lvl = 8'd26;   3'd7: db_lvl = 8'd29;
                endcase
                db_lvl = db_lvl + {p, 5'b00000};    // ＋ (p<<5) ✓
            end
        end
    endfunction

    //=========================================================================
    // 1. 状态（★ 都在"头位"上操作 ⇒ 无 mux ✓）+ 组合量
    //=========================================================================
    reg [4*BARS-1:0] hold_sr;                   // 16 × 4 位（与柱同步旋转 ✓）
    reg [4:0]        band;                      // 0..15 ✓（**16 = 走完了** ✓ ⇒ 5 位 ✓）
    reg [5:0]        rem;                       // 本带还剩几个 bin ✓
    reg [7:0]        band_max;                  // 本带迄今最大幅度 ✓
    reg [12:0]       band_sum;                  // 24-band mode: sum for width-normalized mean
    reg [AW:0]       cnt;                       // 本帧已收 bin 数 ✓
    reg              drain;                     // 排空中（半截帧补救 ✓）
    integer          i;

    wire [7:0] cur   = bars[7:0];               // ★ 当前带的显示值（**头位** ⇒ 连线 ✓）
    wire [7:0] curp  = peak_bars[7:0];          // ★ 当前带的峰值（头位 ✓）
    wire [3:0] hcur  = hold_sr[3:0];            // ★ 当前带的保持计数（头位 ✓）

    wire [7:0] bm_nx = (bin_mag > band_max) ? bin_mag : band_max;   // 含本 bin 的带内最大 ✓
    wire [12:0] sum_nx = band_sum + {5'd0, bin_mag};
    wire [24:0] mean_product = sum_nx * recip_width(bsize(band));
    wire [13:0] mean_full = (mean_product + 25'd1024) >> 11;
    wire [7:0] mean_mag = (mean_full > 14'd255) ? 8'd255 : mean_full[7:0];
    wire [9:0] mix_sum = {2'b0, bm_nx} + {1'b0, bm_nx, 1'b0}
                       + {2'b0, mean_mag} + 10'd2;
    wire [7:0] band_mag = (BARS == 24) ? mix_sum[9:2] : bm_nx;
    wire [7:0] nl    = db_lvl(band_mag);
    wire       fend  = (cnt == (BIN - 1));                         // Last bin of this frame
    wire       early = frame_stb && (cnt != 0);                    // ★ 半截帧：帧界提前到 ✓
    wire       skip_dc = (BARS == 24) && (cnt == 0);
    wire       bcomp = (rem == 6'd1) && (band < BARS) && !skip_dc;
    wire       comp  = drain | (bin_stb && !drain && !fend && bcomp);
    wire [7:0] nlv   = drain ? 8'd0 : nl;                          // ★ 排空 = "本帧这带没能量" ✓

    // 收口后的新值（升立即 / 降 −1 / 峰值保持 8 帧 ✓）
    wire [7:0] decay_step = (band < 5'd6) ? 8'd12
                          : ((band < 5'd15) ? 8'd16 : 8'd22);
    wire [7:0] lvl_nx = (nlv >= cur) ? nlv
                        : (BARS == 24 ? ((cur > decay_step) ? cur - decay_step : 8'd0)
                                      : ((cur == 0) ? 8'd0 : cur - 8'd1));
    wire [7:0] pk_nx  = (nlv >= curp) ? nlv
                      : ((hcur != 4'd0) ? curp
                         : (BARS == 24 ? ((curp > decay_step) ? curp - decay_step : 8'd0)
                                       : ((curp == 0) ? 8'd0 : curp - 8'd1)));
    wire [3:0] hd_nx  = (nlv >= curp) ? 4'd8 : ((hcur != 4'd0) ? (hcur - 4'd1) : 4'd0);

    //=========================================================================
    // 2. 主逻辑
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bars      <= {(8*BARS){1'b0}};
            peak_bars <= {(8*BARS){1'b0}};
            hold_sr   <= {(4*BARS){1'b0}};
            band      <= 5'd0;
            rem       <= 6'd2;                  // First band width is two in both modes
            band_max  <= 8'd0;
            band_sum  <= 13'd0;
            cnt       <= {(AW+1){1'b0}};
            drain     <= 1'b0;
            bars_stb  <= 1'b0;
        end else begin
            bars_stb <= 1'b0;                   // 默认单拍 ✓

            // ---- 收口（**正常与排空共用这一套** ✓）：更新头位 + 整寄存器旋转 ✓ ----
            if (comp) begin
                bars      <= {lvl_nx, bars[8*BARS-1:8]};            // 右旋 8 位 = 纯连线 ✓
                peak_bars <= {pk_nx,  peak_bars[8*BARS-1:8]};
                hold_sr   <= {hd_nx,  hold_sr[4*BARS-1:4]};         // 右旋 4 位 ✓
                band      <= band + 5'd1;
                rem       <= bsize(band + 5'd1);                    // band=15 ⇒ 16 ⇒ 0 ✓
                band_max  <= 8'd0;
                band_sum  <= 13'd0;
            end else if (bin_stb && !drain && (rem != 6'd0) && !fend && !skip_dc) begin
                band_max <= bm_nx;                                  // 本带还没走完 ⇒ 并最大值 ✓
                band_sum <= sum_nx;
                rem      <= rem - 6'd1;
            end

            // ---- 帧界：自己数满 128 ✓ -------------------------------------------------
            if (bin_stb && !drain) begin
                if (fend) begin
                    if (band < BARS) begin
                        drain <= 1'b1;              // ★ 半截帧（本该走完却没走完）⇒ 排空补齐 ✓
                    end else begin
                        bars_stb <= 1'b1;           // 正常收帧 ✓
                        cnt      <= {(AW+1){1'b0}};
                        band     <= 5'd0;
                        rem      <= bsize(5'd0);
                        band_max <= 8'd0;
                        band_sum <= 13'd0;
                    end
                end else begin
                    cnt <= cnt + {{AW{1'b0}}, 1'b1};
                end
            end

            // ---- 上游提前拉帧界 ⇒ 也判为半截 ✓（正常帧不会触发：那时 cnt 已清 0 ✓）----
            if (early && !drain) drain <= 1'b1;

            // ---- 排空最后一拍：收帧 + 走带复位（★ 此时旋转正好补满一整圈 ✓）----
            if (drain && (band == (BARS - 1))) begin
                drain    <= 1'b0;
                bars_stb <= 1'b1;
                cnt      <= {(AW+1){1'b0}};
                band     <= 5'd0;
                rem      <= bsize(5'd0);
                band_max <= 8'd0;
                band_sum <= 13'd0;
            end
        end
    end

endmodule

`default_nettype wire
