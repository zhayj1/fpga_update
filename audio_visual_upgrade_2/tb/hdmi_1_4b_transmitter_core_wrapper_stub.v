`timescale 1ns/1ps
`default_nettype none
//============================================================================
// hdmi_1_4b_transmitter_core_wrapper —— **仿真 stub**（仅 TB 用，不进 rtl/）
//
// 为什么：真正的 HDMI 发射核是 P0 已验证的**黑盒**（`rtl/video/hdmi_1_4b_transmitter_core_wrapper.enc.v`
//   + 一整套厂商 IP），P1 要改的是它的**输入**（AXIS 流 = 合成器输出）。
//   仿真里用本 stub 顶替，能让"合成器 → AXIS"这段被逐字节验证，而不必凑齐厂商 HDMI 文件集。
// 端口与参数**照 `rtl/top/skeleton_core.v` 第 141-182 行的实际连接**；未连的
//   O_edid_read_valid/O_edid_read_data/O_axis_s_ready 不在此列出（宽度未知，列了反而要瞎猜）。
// 行为：复位后一拍照 `O_video_locked`；TMDS 输出上留 AXIS 数据的痕迹（只作观测，不进判据）。
//============================================================================
module hdmi_1_4b_transmitter_core_wrapper #(
    parameter        DEVICE            = "EG",
    parameter integer HTOTAL            = 800,
    parameter integer HSA               = 96,
    parameter integer HFP               = 16,
    parameter integer HBP               = 48,
    parameter integer HACTIVE           = 640,
    parameter integer VTOTAL            = 525,
    parameter integer VSA               = 2,
    parameter integer VFP               = 10,
    parameter integer VBP               = 33,
    parameter integer VACTIVE           = 480,
    parameter         VIDEO_TPG         = "Disable",
    parameter         VIDEO_FORMAT      = "RGB",
    parameter integer VIDEO_VIC         = 1,
    parameter         AUDIO_SAMPLE_RATE = "48K",
    parameter integer IIC_SCL_DIV       = 250
) (
    input  wire        I_pixel_clk,
    input  wire        I_rst,
    input  wire        I_edid_read_trig,
    input  wire        I_axis_s_user,
    input  wire        I_axis_s_valid,
    input  wire        I_axis_s_last,
    input  wire [23:0] I_axis_s_data,
    input  wire        I_audio_valid,
    input  wire [23:0] I_audio_left_data,
    input  wire [23:0] I_audio_right_data,
    input  wire        I_acr_valid,
    input  wire [19:0] I_acr_cts,
    input  wire [19:0] I_acr_n,
    output reg         O_video_locked,
    output reg         O_ddc_scl,
    inout  wire        IO_ddc_sda,
    output reg  [9:0]  O_ch0_tmds_data,
    output reg  [9:0]  O_ch1_tmds_data,
    output reg  [9:0]  O_ch2_tmds_data,
    output reg  [9:0]  O_clk_tmds_data
);
    initial begin
        O_video_locked  = 1'b0;
        O_ddc_scl       = 1'b1;
        O_ch0_tmds_data = 10'd0;
        O_ch1_tmds_data = 10'd0;
        O_ch2_tmds_data = 10'd0;
        O_clk_tmds_data = 10'd0;
    end

    always @(posedge I_pixel_clk) begin
        O_video_locked <= 1'b1;                              // stub：复位后即报锁定
        O_ch0_tmds_data <= I_axis_s_valid ? {2'b00, I_axis_s_data[7:0]} : 10'd0;
        O_ch1_tmds_data <= 10'd0;
        O_ch2_tmds_data <= 10'd0;
        O_clk_tmds_data <= 10'd0;
    end
endmodule

`default_nettype wire
