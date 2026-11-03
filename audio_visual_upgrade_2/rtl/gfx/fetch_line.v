`default_nettype none
//============================================================================
// rtl/gfx/fetch_line.v —— 层行取数引擎（P1，每层一个实例）
//
// 规格：doc/spec/fetch_line_behavior_spec.md
// 依据：design §4.1（像素流：每层一个行预取引擎 + 双缓冲行缓冲）、§3.1（SDRAM 打包约定，
//       与 `bmp_load` **同一份**）、§3.2（欠载不冻结上一行 + 计数上报）、§6（逐像素实时合成、不落帧存）。
//
// 职责：把 SDRAM 图像槽里**某一行**的打包像素取进行缓冲，按 25MHz 像素节拍吐 `RGB888`。
//       **不算槽地址**（调用方给 `row_base`）、**不做缩放**（P1 规定 1:1）、不混合。
//
// 两个时钟域：
//   · clk_sdr = 150MHz：`px` 口突发 + 行缓冲写口
//   · clk_pix =  25MHz：行缓冲读口 + 字节去旋转 + 逐像素输出
//   行缓冲 = 厂商 `EG_LOGIC_BRAM`（MODE="SDP"：A 口写 / B 口读，clka/clkb 独立）；
//   跨域只有 3 组单比特（`rdy_tgl`/`rdy_buf` 去；`cons_tgl` 回），见规格 §3/§6。
//
// ★ 读端字节去旋转（把 §3.1 的打包字节还原成像素，**不改约定**）：
//   像素 x 占字节 b=3x..3x+2，落在字 w=(3x)>>2 的第 (3x)&3 个字节上（小端）。
//   `lane=(3x)&3` 按 0,3,2,1 循环，且 **lane==0 时 w 不前进**（其余前进 1）⇒ 需求 0.75 字/拍。
//   读口每拍最多取 1 字（1 拍延迟）⇒ 用 **4 深寄存器预取队列**：读指针 `rd_ptr` 连续递增，
//   到达的字推进队尾；像素从 `q0=mem[w]`、`q1=mem[w+1]` 取
//   `{q1,q0} >> (8*lane)` 的低 24 位。供给(1/拍) ≥ 需求(0.75/拍) ⇒ 队列水位恒 ≥2
//   （TB 用 `stall_cnt` 监视：出现即判失败）。
//
// ★ 双缓冲/跨域（"冻结上一行"）：
//   sdr 侧只在 `!rdy_valid`（上一行已被消费）时接受新 `fetch_start`，写目标 = `~cur_rd_buf`
//   ⇒ 永不写到正在被读的那一半；pix 侧在 `px_go` 时若已有新行则切换 + `cons_tgl` 应答，
//   否则 `underrun_cnt++` 且**保持原缓冲**（= §3.2 的"冻结上一行"）。
//
// 未验证：TD 综合（BRAM 落块数/Fmax）、§6 的跨域约束、与真 `sdram_arb` 联调、上板。
//============================================================================
module fetch_line #(
    parameter integer MAX_W = 640          // 行内最大像素数（决定行缓冲字数）
)(
    // ---------------- SDRAM / px 域 ----------------
    input  wire        clk_sdr,
    input  wire        rst_sdr_n,
    input  wire        fetch_start,        // 脉冲：取 `row_base` 这一行
    input  wire [20:0] row_base,           // 该行在槽内的字基址（含行序翻转，由调用方算）
    input  wire [15:0] words_per_row,      // 行字数 = stride_sdram/4，1..2048
    output reg         fetch_busy,
    output reg         fetch_err,          // **单拍脉冲**：本次请求被拒（见规格 §2）
    output reg         px_req,
    output reg  [20:0] px_addr,
    output reg  [15:0] px_len,
    input  wire        px_ack,
    input  wire        px_done,
    input  wire [31:0] px_data,
    input  wire        px_valid,

    // ---------------- 像素域 ----------------
    input  wire        clk_pix,
    input  wire        rst_pix_n,
    input  wire        px_go,              // 脉冲：从局部 x=0 开始吐本行
    input  wire [15:0] img_w,              // 行内有效像素数（层级静态配置）
    input  wire [15:0] wr_pix,             // 行字数（**与 words_per_row 同值**，静态配置）
    output reg  [23:0] px_out,             // RGB888（寄存输出）
    output reg         px_out_vld,
    output reg         px_line_done,       // 脉冲：本行吐完
    output reg  [31:0] underrun_cnt,       // `px_go` 时新行未就绪的次数（§3.2 上报；32 位防长跑回绕）
    output reg  [31:0] go_cnt,             // 收到的 `px_go` 次数（观测）
    output reg  [31:0] stall_cnt           // 预取队列"断了"的次数（**必须为 0**）
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

    // 行字数 = stride_sdram/4 = ceil(W*3/16)*4  ← ★ 别写成 ceil(W*3/16)（那是"16B 单位数"，
    //   MAX_W=640 时是 120 而真实字数是 480；写错会让 param_ok 直接拒掉 640 宽的行）
    localparam integer WORDS  = (((MAX_W * 3 + 15) / 16)) * 4;
    localparam integer STRIDE = WORDS + 1;               // 每缓冲多留 1 字（读端会预取 w+1）
    localparam integer DEPTH  = 2 * STRIDE;              // 两块交替
    localparam integer AW     = clog2f(DEPTH);           // 地址位宽（MAX_W=640 ⇒ 962 ⇒ AW=10）

    localparam [10:0] STRIDE_W = STRIDE[10:0];           // 地址按 11 位算，末端切 AW 位
    localparam [15:0] WORDS16  = WORDS[15:0];            // 供比较用（位选参数在部分工具里不稳）

    //=========================================================================
    // 1. 行缓冲：厂商 `EG_LOGIC_BRAM`（★ 2026-10-01 修正两处，见下）
    //    对照本工程**已被 TD 综合通过**的 `rtl/storage/fat32_chain.v`：
    //      它用 MODE("SP")、DATA_DEPTH=128（=2^7=2^ADDR_WIDTH）、IMPLEMENT("9K")、REGMODE_A/B("NOREG")。
    //
    //    ① MODE：原先写 "SDP" ⇒ TD 综合 Map Macro 阶段报 `SYN-8418 ERROR: Wrong MODE::SDP`。
    //       EG4 的 9K 块在 32bit 位宽下不支持 SDP（仿真模型注释里的 "SP, SDP, DP" 是**通用**模型的，
    //       不代表 EG4 原语）。本设计需要"两时钟：A 口写 clk_sdr / B 口读 clk_pix" ⇒ 用 **DP**，
    //       B 口只读（`web` 恒 0、`dib` 恒 0）。
    //    ② 深度：DEPTH=962 不是 2 的幂 ⇒ 取 `1<<AW` = 1024（多占 62 字，可忽略）；地址位宽仍是 AW。
    //       （fat32_chain 的深度 128 正好是 2 的幂，这也是它没踩到这条的原因。）
    //
    //    读延迟：`REGMODE_B="NOREG"` ⇒ 地址进、数据下一拍出（1 拍），故 `LAT` 不变 ——
    //    单元 TB 的 `LAT_MEAS=6` 会复核这一点。
    //=========================================================================
    wire        mem_we;
    wire [AW-1:0] mem_addra;
    wire [31:0] mem_dia;
    wire [AW-1:0] mem_addrb;
    wire [31:0] mem_dob;

    localparam integer DEPTH_P2 = (1 << AW);          // 2 的幂深度（≥ DEPTH）

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A (32),
        .DATA_WIDTH_B (32),
        .ADDR_WIDTH_A (AW),
        .ADDR_WIDTH_B (AW),
        .DATA_DEPTH_A (DEPTH_P2),
        .DATA_DEPTH_B (DEPTH_P2),
        .BYTE_ENABLE  (0),
        .BYTE_A       (1),
        .BYTE_B       (1),
        .MODE         ("DP"),
        .REGMODE_A    ("NOREG"),
        .REGMODE_B    ("NOREG"),
        .WRITEMODE_A  ("NORMAL"),
        .WRITEMODE_B  ("NORMAL"),
        .RESETMODE    ("SYNC"),
        .DEBUGGABLE   ("NO"),
        .PACKABLE     ("NO"),
        .FORCE_KEEP   ("OFF"),
        .INIT_FILE    ("NONE"),
        .FILL_ALL     ("NONE"),
        .IMPLEMENT    ("9K")
    ) u_linebuf (
        .dia   (mem_dia),
        .addra (mem_addra),
        .cea   (1'b1),
        .ocea  (1'b0),
        .clka  (clk_sdr),
        .wea   (mem_we),
        .rsta  (1'b0),
        .bea   (1'b0),
        .dib   (32'd0),
        .addrb (mem_addrb),
        .ceb   (1'b1),
        .oceb  (1'b1),
        .clkb  (clk_pix),
        .web   (1'b0),
        .rstb  (1'b0),
        .beb   (1'b0),
        .doa   (),
        .dob   (mem_dob)
    );

    //=========================================================================
    // 2. sdr 侧：突发取行
    //    注：`cons_tgl` 是 **pix 域** 的寄存器（在 §3 里赋值），但 sdr 侧要同步它，
    //        故提前声明（Verilog-2001 要求先声明后使用）。
    //=========================================================================
    localparam [1:0] F_IDLE = 2'd0, F_RUN = 2'd1, F_FIN = 2'd2;

    reg         cons_tgl;              // pix→sdr 消费应答（pix 域翻转）

    reg  [1:0]  fst;
    reg         acked;
    reg  [20:0] ra_l;
    reg  [15:0] nw_l;
    reg  [10:0] wr_idx;
    reg  [AW-1:0] wr_base;
    reg         wr_buf_l;              // 本次写哪一半（= 取数时刻的 ~cur_rd_buf）

    reg         rdy_tgl;
    reg         rdy_buf;
    reg         rdy_valid;
    reg         cur_rd_buf;            // pix 侧当前在读哪一半（由 cons_tgl 推得）
    reg  [1:0]  cons_s;
    reg         cons_seen;

    wire        param_ok  = (words_per_row != 16'd0) && (words_per_row <= 16'd2048) &&
                            (words_per_row <= WORDS16);
    wire        can_start = !fetch_busy && !rdy_valid && param_ok;
    wire [10:0] wr_addr11 = {1'b0, wr_base} + wr_idx;
    wire        wr_last   = (wr_idx + 11'd1) >= nw_l[10:0];

    assign mem_we    = (fst == F_RUN) && px_valid && (wr_idx < nw_l[10:0]);
    assign mem_addra = wr_addr11[AW-1:0];
    assign mem_dia   = px_data;

    always @(posedge clk_sdr) begin
        if (!rst_sdr_n) begin
            fst <= F_IDLE; acked <= 1'b0; ra_l <= 21'd0; nw_l <= 16'd0;
            wr_idx <= 11'd0; wr_base <= {AW{1'b0}}; wr_buf_l <= 1'b0;
            px_req <= 1'b0; px_addr <= 21'd0; px_len <= 16'd0;
            fetch_busy <= 1'b0; fetch_err <= 1'b0;
            rdy_tgl <= 1'b0; rdy_buf <= 1'b0; rdy_valid <= 1'b0;
            cur_rd_buf <= 1'b0; cons_s <= 2'd0; cons_seen <= 1'b0;
        end else begin
            fetch_err <= 1'b0;                       // 默认：拒绝脉冲

            // ---- pix→sdr：消费应答（单比特翻转）----
            cons_s <= {cons_s[0], cons_tgl};
            if (cons_s[1] != cons_seen) begin
                cons_seen  <= cons_s[1];
                rdy_valid  <= 1'b0;                  // 上一行已被消费 ⇒ 可以再取
                cur_rd_buf <= ~cur_rd_buf;           // 读的那一半换了
            end

            case (fst)
            //-----------------------------------------------------------------
            F_IDLE: begin
                fetch_busy <= 1'b0;
                if (fetch_start) begin
                    if (can_start) begin
                        ra_l      <= row_base;
                        nw_l      <= words_per_row;
                        wr_idx    <= 11'd0;
                        wr_buf_l  <= ~cur_rd_buf;    // 永不写正在被读的那一半
                        wr_base   <= (~cur_rd_buf) ? STRIDE_W[AW-1:0] : {AW{1'b0}};
                        px_addr   <= row_base;
                        px_len    <= words_per_row;
                        px_req    <= 1'b1;           // ★ 地址/长度与 req 同拍给出
                        acked     <= 1'b0;
                        fetch_busy<= 1'b1;
                        fst       <= F_RUN;
                    end else begin
                        fetch_err <= 1'b1;           // 参数非法 / 上一行未消费
                    end
                end
            end
            //-----------------------------------------------------------------
            F_RUN: begin
                fetch_busy <= 1'b1;
                if (px_valid) begin
                    if (wr_last) begin
                        px_req <= 1'b0;
                        fst    <= F_FIN;
                    end else begin
                        wr_idx <= wr_idx + 11'd1;
                    end
                end
                if (!acked && px_ack) begin
                    px_req <= 1'b0;                  // ★ ack 后立刻撤 req（sdram_arb 铁律）
                    acked  <= 1'b1;
                end
                if (px_done) begin
                    px_req <= 1'b0;
                    fst    <= F_FIN;
                end
            end
            //-----------------------------------------------------------------
            F_FIN: begin
                rdy_buf   <= wr_buf_l;               // 刚填满的那一半变成"就绪"
                rdy_tgl   <= ~rdy_tgl;               // 通知 pix 侧
                rdy_valid <= 1'b1;
                fetch_busy<= 1'b0;
                fst       <= F_IDLE;
            end
            default: fst <= F_IDLE;
            endcase
        end
    end

    //=========================================================================
    // 3. pix 侧：切换/冻结 + 4 深预取队列 + 逐像素去旋转
    //    队列约定：q0 = **队首**（最老），q1 次之……；push 进队尾，pop 从队首移出。
    //    q_head = 队首对应的行内字号（应与像素字号 w 一致 ⇒ 用于监视对齐）。
    //    需要的字数按 lane 定：lane∈{0,1} 只用 q0；lane∈{2,3} 还要 q1
    //    （pad 到 16B 保证"末像素跨字"的那一个字一定在行内 ⇒ 读范围 [0,words) 足够）。
    //=========================================================================
    localparam [1:0] P_IDLE = 2'd0, P_PRIME = 2'd1, P_RUN = 2'd2;

    reg  [1:0]  pst;
    reg  [1:0]  rdy_s;
    reg  [1:0]  rdy_buf_s;
    reg         rdy_seen;
    reg         rd_buf;
    reg         rdy_ever;
    reg         stream_on;
    reg  [15:0] img_w_l;
    reg  [15:0] wpix_l;
    reg  [15:0] x;
    reg  [1:0]  lane;
    reg  [10:0] w;
    reg  [10:0] rd_ptr;                 // 下一个要读的字号（行内）
    reg  [10:0] q_head;                 // 队首字对应的行内字号
    reg  [2:0]  qn;                     // 队列字数 0..4（只算"已入队"的）
    reg  [31:0] q0, q1, q2, q3;
    reg         rd_issue_d;             // 上一拍是否发出读（决定本拍是否 push）
    reg  [23:0] hold_px;                // stall 时保持的像素（保证光栅不错位）
    reg         line_ok;                // 本行是否有像素可吐（px_go 时定，整行不变）

    wire [10:0] rd_base  = rd_buf ? STRIDE_W : 11'd0;
    wire        advance  = (lane != 2'd0);
    wire [1:0]  lane_nxt = (lane == 2'd0) ? 2'd3 : (lane - 2'd1);
    wire [2:0]  qn_eff   = qn + (rd_issue_d ? 3'd1 : 3'd0);   // 含"在飞的 push"
    wire        rd_issue = stream_on && (qn_eff < 3'd4) && (rd_ptr < wpix_l[10:0]);
    wire [2:0]  qn_need  = (lane >= 2'd2) ? 3'd2 : 3'd1;
    wire        q_ok     = (q_head == w) && (qn >= qn_need);
    wire [63:0] bwin     = {q1, q0};
    wire [63:0] bsh      = bwin >> {lane, 3'b000};
    // ★ 字节序：存储里"地址递增 = R,G,B"（design §3.1），而 `px_out` 是 RGB888 端口
    //   （**R 在最高位**）⇒ 这里把三个字节倒过来摆。不改存储约定，只改端口表示。
    wire [23:0] pix_new  = {bsh[7:0], bsh[15:8], bsh[23:16]};
    wire        px_step  = (pst == P_RUN) && (x < img_w_l);   // 光栅推进（无论有没有数据）
    wire        px_run   = px_step && line_ok;                // 真正吐像素
    wire        do_pop   = px_run && advance && q_ok;
    wire        do_push  = rd_issue_d;
    wire [10:0] rd_addr11 = rd_base + rd_ptr;

    assign mem_addrb = rd_addr11[AW-1:0];

    always @(posedge clk_pix) begin
        if (!rst_pix_n) begin
            pst <= P_IDLE; rdy_s <= 2'd0; rdy_buf_s <= 2'd0; rdy_seen <= 1'b0;
            cons_tgl <= 1'b0; rd_buf <= 1'b0; rdy_ever <= 1'b0; stream_on <= 1'b0;
            img_w_l <= 16'd0; wpix_l <= 16'd0; x <= 16'd0; lane <= 2'd0; w <= 11'd0;
            rd_ptr <= 11'd0; q_head <= 11'd0; qn <= 3'd0;
            q0 <= 32'd0; q1 <= 32'd0; q2 <= 32'd0; q3 <= 32'd0;
            rd_issue_d <= 1'b0; hold_px <= 24'd0; line_ok <= 1'b0;
            px_out <= 24'd0; px_out_vld <= 1'b0; px_line_done <= 1'b0;
            underrun_cnt <= 32'd0; go_cnt <= 32'd0; stall_cnt <= 32'd0;
        end else begin
            px_line_done <= 1'b0;
            // ---- sdr→pix：就绪翻转 + 缓冲号 ----
            rdy_s     <= {rdy_s[0], rdy_tgl};
            rdy_buf_s <= {rdy_buf_s[0], rdy_buf};

            // ---- 预取队列：读口连续供字（1/拍）≥ 消费（0.75/拍）----
            rd_issue_d <= rd_issue;
            if (rd_issue) rd_ptr <= rd_ptr + 11'd1;

            // pop（队首移出）与 push（进队尾）可同拍：pop 先移位，push 再落到"腾出的尾槽"
            if (do_pop) begin
                q0 <= q1; q1 <= q2; q2 <= q3;
                q_head <= q_head + 11'd1;
                w      <= w + 11'd1;
            end
            if (do_push) begin
                case (do_pop ? (qn - 3'd1) : qn)
                3'd0: q0 <= mem_dob;
                3'd1: q1 <= mem_dob;
                3'd2: q2 <= mem_dob;
                3'd3: q3 <= mem_dob;
                default: ;                       // qn==4 且无 pop：丢弃（队列已满，不该发生）
                endcase
                if (!do_pop) qn <= qn + 3'd1;
            end else if (do_pop) begin
                qn <= qn - 3'd1;
            end

            case (pst)
            //-----------------------------------------------------------------
            P_IDLE: begin
                px_out_vld <= 1'b0;
                if (px_go) begin
                    go_cnt <= go_cnt + 32'd1;
                    if (rdy_s[1] != rdy_seen) begin
                        rdy_seen <= rdy_s[1];
                        rd_buf   <= rdy_buf_s[1];     // 切到新行
                        cons_tgl <= ~cons_tgl;        // 应答：旧的一半可以重填
                        rdy_ever <= 1'b1;
                        line_ok  <= 1'b1;
                    end else begin
                        underrun_cnt <= underrun_cnt + 32'd1;   // 冻结上一行（rd_buf 不动）
                        line_ok      <= rdy_ever;     // 从来没有就绪行 ⇒ 本行不吐像素
                    end
                    img_w_l   <= img_w;
                    wpix_l    <= wr_pix;
                    x         <= 16'd0;
                    lane      <= 2'd0;
                    w         <= 11'd0;
                    q_head    <= 11'd0;
                    rd_ptr    <= 11'd0;
                    qn        <= 3'd0;
                    rd_issue_d<= 1'b0;
                    q0 <= 32'd0; q1 <= 32'd0; q2 <= 32'd0; q3 <= 32'd0;
                    if (img_w == 16'd0) begin
                        stream_on <= 1'b0;
                        px_line_done <= 1'b1;                   // 没有像素：立即完成
                    end else begin
                        stream_on <= 1'b1;
                        pst       <= P_PRIME;                   // 先攒够队深再开吐
                    end
                end
            end
            //-----------------------------------------------------------------
            P_PRIME: begin
                if (qn >= 3'd2) pst <= P_RUN;              // 队里有 mem[0]、mem[1]
            end
            //-----------------------------------------------------------------
            // 注意：**光栅推进与"有没有数据"解耦** —— 即使本行无数据（首次欠载），
            // 也要走完 img_w 拍并给 `px_line_done`，否则调用方的行计数会卡住。
            P_RUN: begin
                if (px_step) begin
                    px_out_vld <= px_run;
                    if (px_run) begin
                        if (q_ok) begin
                            px_out <= pix_new; hold_px <= pix_new;
                        end else begin
                            stall_cnt <= stall_cnt + 32'd1;
                            px_out    <= hold_px;              // 防御：重复上一像素
                        end
                    end
                    x    <= x + 16'd1;
                    lane <= lane_nxt;
                    if ((x + 16'd1) >= img_w_l) begin
                        px_line_done <= 1'b1;
                        stream_on    <= 1'b0;
                        pst          <= P_IDLE;
                    end
                end else begin
                    px_out_vld <= 1'b0;
                    pst        <= P_IDLE;
                end
            end
            default: pst <= P_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
