`default_nettype none
//============================================================================
// rtl/app/frame_sig.v —— 帧签名（A2 判据的 RTL 侧，design §10.1）
//
//   N  = 像素个数
//   S1 = Σ pixel(24bit)      mod 2^32      —— 抓"值错"
//   S2 = Σ pixel × (n+1)     mod 2^32      —— 抓"位置错/换位"（n 为光栅序，从 0 起）
//
// 为什么不用真 CRC-32：像素率 25Mpx/s，字节式 CRC 要每拍吃 3 字节（~300-400 LUT + 长组合路径）；
// 而本式只要 **1 个 DSP（S2 的乘加）+ 1 个 32bit 加法器**，且任何单像素值错都会改 S1、
// 任何两像素换位都会改 S2（足够守住"背景满屏 + 封面位置正确"）。判据定义在 design §10.1，不在 TB 里。
//
// 用法：`frame_start` 在**帧首**（`vs` 下降沿）脉冲一下 —— 那一拍把上一帧的 N/S1/S2 锁存到输出、
// 同时清零累加器 ⇒ 输出的是"刚刚结束那一帧"的签名（PC 侧 golden 按同一口径算，逐项比对）。
//
// 未验证：TD 综合（乘法落 DSP 的确认）、上板。
//============================================================================
module frame_sig (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,     // 脉冲：帧首（锁存上一帧 + 清零累加器）
    input  wire        de,              // 像素有效
    input  wire [23:0] pixel,           // 合成后的像素
    output reg  [31:0] sig_n,
    output reg  [31:0] sig_s1,
    output reg  [31:0] sig_s2,
    output reg         sig_rdy          // 电平：至少锁存过一帧
);

    reg  [31:0] n, s1, s2;
    wire [31:0] pix32 = {8'd0, pixel};
    wire [31:0] wgt   = n + 32'd1;              // 权重 = n+1（n 为本像素的 0 基光栅序）
    wire [31:0] prod  = pix32 * wgt;            // 32×32 乘法（TD 落 DSP）

    always @(posedge clk) begin
        if (!rst_n) begin
            n <= 32'd0; s1 <= 32'd0; s2 <= 32'd0;
            sig_n <= 32'd0; sig_s1 <= 32'd0; sig_s2 <= 32'd0; sig_rdy <= 1'b0;
        end else if (frame_start) begin
            sig_n  <= n;
            sig_s1 <= s1;
            sig_s2 <= s2;
            sig_rdy<= 1'b1;
            n  <= 32'd0;
            s1 <= 32'd0;
            s2 <= 32'd0;
        end else if (de) begin
            n  <= n + 32'd1;
            s1 <= s1 + pix32;
            s2 <= s2 + prod;
        end
    end

endmodule

`default_nettype wire
