`default_nettype none
//=============================================================================
// rtl/top/skeleton_top.v —— P0-2 骨架**上板顶层**（综合目标：这就是 TD 的 TOP）
//
// 只干三件"仿真做不了"的事：
//   ① 两个 PLL：video_pll（50→25/125MHz，带 extlock）、pll_sdr（50→100MHz + 相移，带 extlock）
//   ② HDMI 串行化 PHY（lane_lvds_10_1 内部是安路 LVDS 原语，本机 ModelSim 无模型 ⇒ 只综合/上板）
//   ③ 管脚连接
// 逻辑全在 `skeleton_core`（时钟从端口进 ⇒ 可仿真，见 tb/tb_skeleton.v）。
//
// 复位策略：时钟没锁之前不放逻辑 ⇒ rst = ~rst_n | ~lock。
//   ★ 注意：这与仿真路径无关（TB 直接给 skeleton_core 时钟/复位），所以"仿真过了"不代表
//     lock 逻辑过了；lock 只能上板看 LED（led[1]=视频核 locked）。
//
// 管脚依据（都在本仓库里核过，别猜）：
//   clk=R7、rst_n=A2、led[0..3]=A4/A3/C10/B12、SD=A14/A13/A12/B14
//   HDMI: CLK_P=C3、D0_P=G5、D1_P=F1、D2_P=E1、DDC_SCL=P2、DDC_SDA=R2
//   SDRAM 是片内的（EG_PHY_SDRAM_2M_32）⇒ **不需要任何 SDRAM 管脚约束**
//=============================================================================
module skeleton_top (
    input  wire       clk,           // R7  50MHz
    input  wire       rst_n,         // A2  低有效（板上与按键共用，有上拉）
    output wire       sd_sck,        // A14
    output wire       sd_cs_n,       // A12
    output wire       sd_mosi,       // A13
    input  wire       sd_miso,       // B14
    input  wire       key2,          // B2, OSD decrease
    input  wire       key3,          // B1, OSD increase
    input  wire       key4,          // C1, short/long mode key
    output wire       HDMI_CLK_P,    // C3
    output wire       HDMI_D0_P,     // G5
    output wire       HDMI_D1_P,     // F1
    output wire       HDMI_D2_P,     // E1
    output wire       HDMI_DDC_SCL,  // P2
    inout  wire       HDMI_DDC_SDA,  // R2
    output wire [3:0] led
);

    wire clk_pix, clk_pix5x, lock_vid;
    wire clk_sdr, clk_sdr_sft, lock_sdr, sdr_fb;

    // ---------------- ① PLL ----------------
    video_pll u_pll_vid (
        .refclk  (clk),
        .reset   (~rst_n),
        .extlock (lock_vid),
        .clk0_out(clk_pix),          // 25MHz  像素时钟
        .clk1_out(clk_pix5x)         // 125MHz 5×串行时钟
    );

    pll_sdr u_pll_sdr (
        .refclk  (clk),
        .reset   (~rst_n),
        .extlock (lock_sdr),
        .clk0_out(sdr_fb),           // 10MHz 反馈支路（不外用）
        .clk1_out(clk_sdr),          // 100MHz
        .clk2_out(clk_sdr_sft)       // 100MHz 相移（上板必须实测相位，见 pll_sdr.v 文件头）
    );

    // ---------------- 逻辑复位（lock 前不放行）----------------
    wire rst_pix   = ~rst_n | ~lock_vid;
    wire rst_sdr   = ~rst_n | ~lock_sdr;
    wire core_rst_n = rst_n & lock_vid & lock_sdr;

    wire [9:0] tmds0, tmds1, tmds2, tmdsc;
    wire       vid_locked;

    // ---------------- ② 逻辑核心（可仿真部分）----------------
    skeleton_core #(
        .SDR_CLK_MHZ (100),
        .en_color_diag(1'b0),
        .en_osd(1'b1), .TYPOGRAPHY(1'b1), .VISUAL_CONTROLS(1'b1), .CIRCULAR_UI(1'b1), .SPLIT_UI(1'b1)
    ) u_core (
        .clk_pix      (clk_pix),
        .clk_pix5x    (clk_pix5x),
        .rst_pix      (rst_pix),
        .clk_sdr      (clk_sdr),
        .clk_sdr_sft  (clk_sdr_sft),
        .rst_sdr      (rst_sdr),
        .clk          (clk),
        .rst_n        (core_rst_n),
        .O_ch0_tmds_data (tmds0),
        .O_ch1_tmds_data (tmds1),
        .O_ch2_tmds_data (tmds2),
        .O_clk_tmds_data (tmdsc),
        .O_video_locked  (vid_locked),
        .O_ddc_scl       (HDMI_DDC_SCL),
        .IO_ddc_sda      (HDMI_DDC_SDA),
        .sd_sck          (sd_sck),
        .sd_cs_n         (sd_cs_n),
        .sd_mosi         (sd_mosi),
        .sd_miso         (sd_miso),
        .key2            (key2),
        .key3            (key3),
        .key4            (key4),
        .led             (led)
        // obs_axis_* 是给仿真看的观测口，上板不接 ⇒ 整行不写（不能写 () ）
    );

    // ---------------- ③ HDMI 串行化 PHY ----------------
    hdmi_phy_wrapper #(
        .DEVICE("EG")
    ) u_hdmi_phy (
        .I_pixel_clk         (clk_pix),
        .I_serial_clk        (clk_pix5x),
        .I_rst               (rst_pix),          // 实测 lane_lvds_10_1 的 I_rst 是**高有效异步**
        .I_tmds_channel_0    (tmds0),
        .I_tmds_channel_1    (tmds1),
        .I_tmds_channel_2    (tmds2),
        .I_tmds_channel_clk  (tmdsc),
        .O_tmds_ch0_p        (HDMI_D0_P),
        .O_tmds_ch1_p        (HDMI_D1_P),
        .O_tmds_ch2_p        (HDMI_D2_P),
        .O_tmds_clk_p        (HDMI_CLK_P)
    );

endmodule

`default_nettype wire
