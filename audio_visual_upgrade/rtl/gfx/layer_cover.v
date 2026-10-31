`default_nettype none
//============================================================================
// rtl/gfx/layer_cover.v —— 封面图层（P1-A2 第二段：窗口 + #FF00FF 色键透明）
//
// 规格：doc/spec/compositor_behavior_spec.md §1.5 / §2
// 依据：design §6（封面：从 SDRAM 取封面区像素、按色键透明叠加；P1 为静态位置 1:1）、§9.3（模块名）。
//
// 结构：**复用 `layer_bg` 的取数引擎**（窗口化 1:1 图像图层，其调度/双缓冲/对齐已在 C-01..C-07 验证），
//       本模块**只加"色键"这一层语义** ⇒ 需要新验证的面积最小（TB 只需覆盖键与窗口位置）。
//   design §9.3 的两个名字都保留：
//     · `layer_bg.v`    = 通用图像图层（P1 里作背景：全屏窗口）；**本身不做色键**
//     · `layer_cover.v` = 封面（窗口 + 色键；内部例化 `layer_bg`）
//
// 色键：`ch_key` 端口上匹配的像素**不输出**（`dout_vld=0`）⇒ 合成器让下一层透出。
//   P1 顶层接常数 `24'hFF00FF`（design §6 的约定）；做成**端口**是为了可配置、且让 TB 能用
//   "同素材换键色"来证明键不是硬编码的（见 `tb/tb_compositor.v` 的 C-11）。
//   ★ 键**只作用于本层像素**，绝不作用于背景/底色（"封面 > 背景 > 底色"的选择在合成器里做）。
//
// 未验证：综合/时序、上板。
//============================================================================
module layer_cover #(
    parameter integer MAX_W     = 640,   // 透传 layer_bg
    parameter integer LAT       = 7,     // 透传 layer_bg（px_go 被采样那拍 → 首像素）
    parameter integer H_ACT_DLY = 144,   // 透传 layer_bg（行首 → 首个 de 的拍数）
    parameter integer V_ACT_DLY = 35,    // 透传 layer_bg（帧首 → 首个有效行的行数）
    parameter integer V_ACT_LIN = 480,   // 透传 layer_bg（一帧有效行数）
    parameter integer SHARED_RASTER=0,SHARED_WRITER=0,SCALE=0,GEOMETRY_BITS=16
)(
    // ---------------- 像素域（25MHz）----------------
    input  wire        clk_pix,
    input  wire        rst_pix_n,
    input  wire        hs,
    input  wire        vs,
    input  wire        de,
    input  wire        en,              // 层使能
    input  wire [23:0] ch_key,          // 色键（P1 顶层接常数 24'hFF00FF；做成端口便于配置/验证）
    input  wire [15:0] win_x,
    input  wire [15:0] win_y,
    input  wire [15:0] win_w,
    input  wire [15:0] win_h,
    input  wire [15:0] img_w,
    input  wire [15:0] img_h,
    input  wire [15:0] words_per_row,
    input  wire [20:0] slot_base,
    output wire [23:0] dout,            // 已做色键：仅在 dout_vld=1 时代表"本层要显示的像素"
    output wire        dout_vld,
    output wire [31:0] underrun_cnt,
    output wire [31:0] stall_cnt,
    output wire [31:0] ferr_cnt,
    output wire [31:0] gap_cnt,
    output wire [31:0] keyed_cnt,       // 本层累计：被色键抠掉的像素数（★每帧可达 30 万 ⇒ 必须 32 位，16 位会回绕）
    output wire        idle,

    // ---------------- SDRAM / px 域（150MHz）----------------
    input  wire        clk_sdr,
    input  wire        rst_sdr_n,
    output wire        px_req,
    output wire [20:0] px_addr,
    output wire [15:0] px_len,
    input  wire        px_ack,
    input  wire        px_done,
    input  wire [31:0] px_data,
    input  wire        px_valid,
    input wire [66:0] scan_state,
    output wire cmd_valid,slot_free,next_bank,
    output wire [20:0] cmd_addr,
    output wire [15:0] cmd_words,
    input wire cmd_ack,wr_take,wr_active,wr_done,wr_error,wr_en,wr_good,
    input wire [9:0] wr_addr
);

    wire [23:0] raw_px;
    wire        raw_vld;

    layer_bg #(
        .MAX_W     (MAX_W),
        .LAT       (LAT),
        .H_ACT_DLY (H_ACT_DLY),
        .V_ACT_DLY (V_ACT_DLY),
        .V_ACT_LIN (V_ACT_LIN),.SHARED_RASTER(SHARED_RASTER),.SHARED_WRITER(SHARED_WRITER),
        .SCALE(SCALE),.GEOMETRY_BITS(GEOMETRY_BITS)
    ) u_img (
        .clk_pix       (clk_pix),
        .rst_pix_n     (rst_pix_n),
        .hs            (hs),
        .vs            (vs),
        .de            (de),
        .en            (en),
        .win_x         (win_x),
        .win_y         (win_y),
        .win_w         (win_w),
        .win_h         (win_h),
        .img_w         (img_w),
        .img_h         (img_h),
        .words_per_row (words_per_row),
        .slot_base     (slot_base),
        .dout          (raw_px),
        .dout_vld      (raw_vld),
        .underrun_cnt  (underrun_cnt),
        .stall_cnt     (stall_cnt),
        .ferr_cnt      (ferr_cnt),
        .gap_cnt       (gap_cnt),
        .idle          (idle),
        .clk_sdr       (clk_sdr),
        .rst_sdr_n     (rst_sdr_n),
        .px_req        (px_req),
        .px_addr       (px_addr),
        .px_len        (px_len),
        .px_ack        (px_ack),
        .px_done       (px_done),
        .px_data       (px_data),
        .px_valid      (px_valid),
        .scan_state(scan_state),.cmd_valid(cmd_valid),.slot_free(slot_free),.next_bank(next_bank),
        .cmd_addr(cmd_addr),.cmd_words(cmd_words),.cmd_ack(cmd_ack),.wr_take(wr_take),
        .wr_active(wr_active),.wr_done(wr_done),.wr_error(wr_error),.wr_en(wr_en),
        .wr_good(wr_good),.wr_addr(wr_addr)
    );

    wire keyed = (raw_px == ch_key);

    reg [31:0] key_c;
    always @(posedge clk_pix) begin
        if (!rst_pix_n) key_c <= 32'd0;
        else if (raw_vld && keyed) key_c <= key_c + 32'd1;
    end

    assign dout      = raw_px;
    assign dout_vld  = raw_vld && !keyed;      // 色键像素不输出 ⇒ 下层透出
    assign keyed_cnt = key_c;

endmodule

`default_nettype wire
