`default_nettype none
//============================================================================
// rtl/load/font_load.v —— 字库文件 → SDRAM 字库槽的**纯字节搬运**装载器（P3/S2）
//
// 干什么：把卡上的一个文件**原样**拷进 SDRAM 的一个槽（不做任何解析 ✗）。
//   · `FONT.HZK` 1,046,784 B → `FONT` 槽 `0x13EC00`（261,696 字 ✓）
//   · `ASC.HZK`      6,144 B → `ASC`  槽 `0x17EA40`（  1,536 字 ✓）
//   ★ 两个槽是**紧挨着**的：0x13EC00 + 261,696 = 0x17EA40 ✓、+1,536 = 0x17F040 = `LRC_TAB` ✓
//     （`p2_sdram_map_and_traffic_plan.md:74-76` ✓）⇒ 一个模块装两遍即可 ✓
//     （`workitem_fifo_bram.md:72` 早就点名"`font_load`/`lrc_load` 复用 FIFO 范式" ✓）
//
// 与 `bmp_load` 的关系：**接口逐一对齐** ✓（`lo` 侧字节级 valid/ready、`ld` 侧突发 FWFT ✓），
//   但内部**没有**任何 BMP 语义（无 54 字节头、无行跨距、无字节序改写、无补零到行 ✗）⇒
//   FSM 从 13 态砍到 10 态 ✓、无乘法器 ✓、无行缓冲 ✓。
//
// 两个时钟域（与 `bmp_load` 相同，照 `design §4.1`）：
//   · clk     = 50MHz ：lo 字节流（storage_top）+ 控制/状态
//   · clk_sdr = 150MHz：ld 写口（sdram_arb）
//
// ★★ 接口契约（全部是上游**实测**出来的，不许改 ✗，出处见 `bmp_load.v:27-34`）：
//   1. `ld_data` 是 **FWFT** ⇒ 直接接 FIFO 的 `dout`；`ld_req` 必须在 `ld_ack` 的**下一拍**撤
//      （不是等 `ld_done` ✗），否则被当成新请求重跑；
//   2. `ld_len` **不得为 0**（arb 在 len=0 时也会发一次写使能 ⇒ 多写一个字 ✗）；
//   3. ★ **突发长度必须是 4 的倍数**：ERAM 的原子粒度是 128bit = 4 字（APUG011 §2.3.4 ✓），
//      长度不是 4 的倍数就得用 `app_wr_dm` 掩码，而**我们不驱动掩码** ✗
//      ⇒ 本模块用"**总字节数按 16B 上取整**"的办法保证：`a_words` 恒为 **4 的倍数** ✓
//      （见 §1 的 `nbytes_pad` / F_TAIL ✓），全程不需要掩码 ✓；
//   4. `lo_rd_eof` 是**单拍脉冲**（`storage_top.v:657` 每拍默认清零 ✓）⇒ 必须锁存 ✓；
//      `lo_rd_err` 是**电平**（下次 lo_accept 才清 ✓）；
//   5. lo 流必须**读干净到 eof/err** 才报 done ✓：否则 storage_top 停在 `T_READ`，
//      下一次 `lo_open` 会被拒（err_code=`0x63` ✗）—— 出处 `bmp_load.v:32-34` ✓；
//   6. `lo_rd_ready` / `lo_want` 必须是**组合**译码，且与"本拍真的会吃这个字节"**逐拍一致** ✗
//      （`bmp_load.v:300-316` 记着这条踩坑：ready 多一拍就每像素丢一个字节 ✗）。
//
// 错误码（沿用 `bmp_load` 的编号 ✓，不发明新的一套）：
//   0x02 = 参数/槽越界（含 byte_len=0 ✓）｜0x03 = 流早于期望结束（文件太短 ✓）
//   0x04 = lo 报错 / 看门狗超时 ✓
//
// 未验证：TD 综合面积/时序、真机上板（本文件只到"单元仿真 PASS" ✓）。
//============================================================================
module font_load #(
    // 看门狗：等待态连续多久无进展判超时（拍数 = CLK_HZ/1000*WD_MS）
    parameter integer CLK_HZ = 50000000,
    parameter integer WD_MS  = 2500,
    parameter integer EXTERNAL_BACKEND = 0
)(
    // ---------------- 控制/状态（clk 域）----------------
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,           // 脉冲：启动一次装载（busy 期间被忽略）
    input  wire [7:0]  file_index,      // 文件表索引（start 前稳定，保持到 done）
    input  wire [20:0] slot_base,       // 目标槽基址（32bit 字地址）
    input  wire [31:0] byte_len,        // 要拷的字节数（顶层给"期望尺寸" ⇒ 文件短了会报 0x03 ✓）
    output reg         busy,
    output reg         done,            // 单拍脉冲
    output reg  [7:0]  err,             // done 那拍有效，保持到下次 start
    output reg  [31:0] nbytes,          // 实际推进 FIFO 的字节数（含补零 ✓，诊断用）

    // ---------------- lo 读流（storage_top，clk 域）----------------
    output reg         lo_open,         // 单拍脉冲
    output reg  [7:0]  lo_open_index,
    input  wire        lo_open_busy,
    input  wire        lo_rd_valid,
    input  wire [7:0]  lo_rd_data,
    output wire        lo_rd_ready,     // ★ 组合译码
    output wire        lo_want,         // 取数需求（顶层须与音频水位策略相与 ✓）
    input  wire        lo_rd_eof,       // ★ 单拍脉冲
    input  wire        lo_rd_err,       // 电平
    input  wire [31:0] file_size,

    // ---------------- ld 写口（sdram_arb，clk_sdr 域）----------------
    input  wire        clk_sdr,
    input  wire        rst_sdr_n,
    output wire        ld_req,
    output wire [20:0] ld_addr,
    output wire [15:0] ld_len,
    output wire [31:0] ld_data,         // FWFT：直接接 FIFO 的 dout
    input  wire        ld_rd,
    input  wire        ld_ack,
    input  wire        ld_done,
    input wire fifo_full_ext, input wire backend_done_ext,
    input wire [18:0] slot_words,
    output wire fifo_flush_ext, output wire fifo_we_ext,
    output wire [7:0] fifo_di_ext,
    output wire cfg_valid_ext, output wire [20:0] cfg_first_ext,
    output wire [18:0] cfg_words_ext, output wire [15:0] cfg_wpr_ext,
    output wire cfg_down_ext,
    output wire finish_valid_ext, output wire [18:0] finish_words_ext
);

    //=========================================================================
    // 0. 参数派生
    //=========================================================================
    localparam integer WD_MAX = (CLK_HZ / 1000) * WD_MS;

    // A 侧状态（clk 域）
    localparam [3:0] F_IDLE  = 4'd0,
                     F_FRST  = 4'd1,    // FIFO 冲洗
                     F_OPENW = 4'd2,    // 等 storage 空闲
                     F_OPENP = 4'd3,    // 拉 lo_open 一拍 + 发布 cfg
                     F_COPY  = 4'd4,    // 搬字节
                     F_TAIL  = 4'd5,    // 补零到 16B 边界（保证突发是 4 的倍数 ✓）
                     F_END   = 4'd6,    // 发布 a_words + 翻转 a_end
                     F_DRAIN = 4'd7,    // 把 lo 流读干净到 eof/err
                     F_WIDLE = 4'd8,    // 等 B 侧 idle
                     F_FIN   = 4'd9;    // done

    //=========================================================================
    // 1. 目标尺寸派生
    //    ★ `nbytes_pad` = byte_len 按 **16B 上取整** ⇒ 总字节数是 16 的倍数
    //      ⇒ 总字数是 **4 的倍数** ⇒ **每一次突发都是 4 的倍数** ✓（不需要 write mask ✓）
    //      FONT 1,046,784 本来就是 16 的倍数 ⇒ **一个补零字节都不多** ✓
    //=========================================================================
    wire [31:0] nbytes_pad_w = (byte_len + 32'd15) & 32'hFFFFFFF0;
    wire [18:0] words_tgt_w  = nbytes_pad_w[20:2];              // 261,696 ⇒ 19 bit 够 ✓
    wire        len_ovf_w    = (nbytes_pad_w[31:21] != 11'd0);  // 超过 2^21 字的槽空间 ⇒ 报错 ✓
    wire [21:0] enda_w       = {1'b0, slot_base} + {3'd0, words_tgt_w};
    wire        par_bad_w    = (byte_len == 32'd0) | len_ovf_w | (enda_w > 22'd2097152) |
                              (EXTERNAL_BACKEND && words_tgt_w > slot_words);

    //=========================================================================
    // 2. 格式前端接口。整机连接公共 load_writeback；单测可使用内置后端。
    //=========================================================================
    reg fifo_flush;
    wire fifo_full, fifo_we;
    wire [7:0] fifo_di;
    wire backend_done;
    reg cfg_valid_int, finish_valid_int, cfg_issued;
    reg  [3:0]  st, st_d;
    reg  [5:0]  frst_cnt;
    reg  [31:0] rd_bytes;            // 从 lo 吃掉的**文件**字节数
    reg  [31:0] wr_bytes;            // 推进 FIFO 的字节数（含补零 ✓）
    reg  [18:0] words_tgt;           // 目标字数（4 的倍数 ✓）
    reg  [18:0] a_words;
    reg  [20:0] cfg_first;
    reg  [18:0] cfg_words;

    reg  [7:0]  err_hold;
    reg         eof_seen;
    reg  [31:0] wd;
    reg         gave_up;

    reg bidle_pend;
    reg [1:0] open_wait;

    assign fifo_flush_ext = fifo_flush;
    assign fifo_we_ext = fifo_we;
    assign fifo_di_ext = fifo_di;
    assign cfg_valid_ext = cfg_valid_int;
    assign cfg_first_ext = cfg_first;
    assign cfg_words_ext = cfg_words;
    assign cfg_wpr_ext = 16'd0;
    assign cfg_down_ext = 1'b0;
    assign finish_valid_ext = finish_valid_int;
    assign finish_words_ext = a_words;
    generate if (EXTERNAL_BACKEND) begin : g_external
        assign fifo_full = fifo_full_ext;
        assign backend_done = backend_done_ext;
        assign ld_req = 1'b0;
        assign ld_addr = 21'd0;
        assign ld_len = 16'd0;
        assign ld_data = 32'd0;
    end else begin : g_standalone
        load_writeback u_writeback (
            .clk(clk), .rst_n(rst_n), .clk_sdr(clk_sdr), .rst_sdr_n(rst_sdr_n),
            .flush(fifo_flush), .byte_we(fifo_we), .byte_data(fifo_di), .full(fifo_full),
            .cfg_valid(cfg_valid_int), .cfg_first(cfg_first), .cfg_words(cfg_words),
            .cfg_wpr(16'd0), .cfg_rows(1'b0), .cfg_down(1'b0),
            .finish_valid(finish_valid_int), .finish_words(a_words), .done(backend_done),
            .ld_req(ld_req), .ld_addr(ld_addr), .ld_len(ld_len), .ld_data(ld_data),
            .ld_take(ld_rd), .ld_ack(ld_ack), .ld_done(ld_done)
        );
    end endgenerate

    //-------------------------------------------------------------------------
    // 4.1 消费/等待分类 + 看门狗
    //-------------------------------------------------------------------------
    wire a_consume  = (st == F_COPY) | (st == F_DRAIN);
    wire a_wait     = (st == F_OPENW) | a_consume | (st == F_TAIL) | (st == F_WIDLE);
    wire accept_now = (st == F_COPY) & lo_rd_valid & lo_rd_ready;
    wire wd_hit     = a_wait & (wd == WD_MAX[31:0]);

    //-------------------------------------------------------------------------
    // 4.2 ★★ `lo_rd_ready` / `fifo_we` / `fifo_di` 一律**组合**：
    //     ready 的每一项都必须与"该状态真的会取字节"的条件**逐字一致** ✗
    //     （`bmp_load.v:300-316` 的教训：ready 多一拍 ⇒ 每行/每像素丢一个字节 ✗）
    //     同时在 FIFO 满时**必须**撤 ready（否则丢字节 ✗）—— 这是本模块唯一的流控点 ✓
    //-------------------------------------------------------------------------
    wire tail_push = (st == F_TAIL) & (wr_bytes[3:0] != 4'd0) & ~fifo_full;
    // ★★ 2026-10-05 实测踩坑：`lo_rd_ready` **必须包含 F_DRAIN** ✗ ——
    //   第一版只写了 F_COPY，结果 F_DRAIN 里 ready 恒 0 ⇒ 字节源**永远不会给 eof** ✗
    //   ⇒ F_DRAIN 空转到看门狗 ⇒ `err=0x04`（数据其实全对：261,696 字、逐字与 golden 相同 ✗✓）。
    //   对照 `bmp_load.v:312` 的 A_DRAIN 也在 ready 里 ✓ —— 这条契约是**流式的**：
    //   "你不再要字节，流就没机会告诉你它结束了" ✓
    //   ★ F_DRAIN 不推 FIFO ⇒ 不必看 `fifo_full` ✓（`accept_now`/`tail_push` 才是写口 ✓）
    assign lo_rd_ready = ((st == F_COPY) & ~fifo_full) | (st == F_DRAIN);
    assign lo_want     = (st == F_COPY) | (st == F_DRAIN);
    assign fifo_we     = accept_now | tail_push;
    assign fifo_di     = accept_now ? lo_rd_data : 8'h00;      // F_TAIL 推 0 ✓

    //=========================================================================
    // 5. A 侧时序（clk 域）
    //=========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            st <= F_IDLE; st_d <= F_IDLE;
            busy <= 1'b0; done <= 1'b0; err <= 8'h00; err_hold <= 8'h00;
            nbytes <= 32'd0;
            lo_open <= 1'b0; lo_open_index <= 8'd0;
            frst_cnt <= 6'd0; rd_bytes <= 32'd0; wr_bytes <= 32'd0;
            words_tgt <= 19'd0; a_words <= 19'd0;
            cfg_first <= 21'd0; cfg_words <= 19'd0;
            eof_seen <= 1'b0; wd <= 32'd0; gave_up <= 1'b0; open_wait <= 2'd0;
            bidle_pend <= 1'b0;
            cfg_valid_int <= 1'b0; finish_valid_int <= 1'b0; cfg_issued <= 1'b0;
            fifo_flush <= 1'b0;
        end else begin
            st_d <= st;
            done       <= 1'b0;
            cfg_valid_int <= 1'b0; finish_valid_int <= 1'b0;
            lo_open    <= 1'b0;
            fifo_flush <= 1'b0;

            // ---- B→A：b_idle 同步 + 事件锁存（A 可能几拍后才到 F_WIDLE ✓）----
            if (backend_done) bidle_pend <= 1'b1;
            else if (st == F_WIDLE && bidle_pend) bidle_pend <= 1'b0;

            // ---- lo_rd_eof 单拍脉冲 ⇒ 锁存；start 时清 ----
            if (lo_rd_eof) eof_seen <= 1'b1;

            // ---- 看门狗：吃到字节或状态推进就清零 ----
            if (accept_now | (st != st_d)) wd <= 32'd0;
            else if (wd != WD_MAX[31:0])   wd <= wd + 32'd1;

            case (st)
            //-----------------------------------------------------------------
            F_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    busy       <= 1'b1;
                    done       <= 1'b0;
                    err        <= 8'h00;
                    err_hold   <= 8'h00;
                    nbytes     <= 32'd0;
                    rd_bytes   <= 32'd0;
                    wr_bytes   <= 32'd0;
                    words_tgt  <= words_tgt_w;
                    eof_seen   <= 1'b0;
                    gave_up    <= 1'b0;
                    wd         <= 32'd0;
                    frst_cnt   <= 6'd16;
                    cfg_issued <= 1'b0;
                    bidle_pend <= 1'b0;
                    if (par_bad_w) begin
                        // 参数/槽越界 ⇒ 连 lo 都不碰（不打扰 storage ✓）
                        err_hold <= 8'h02;
                        st       <= F_FIN;
                    end else begin
                        st <= F_FRST;
                    end
                end
            end
            //-----------------------------------------------------------------
            F_FRST: begin
                busy       <= 1'b1;
                fifo_flush <= 1'b1;                 // 冲掉上次残留（含错误路径的不足一字尾巴 ✓）
                if (frst_cnt != 6'd0) frst_cnt <= frst_cnt - 6'd1;
                else begin
                    fifo_flush <= 1'b0;
                    st <= F_OPENW;
                end
            end
            //-----------------------------------------------------------------
            F_OPENW: begin
                busy <= 1'b1;
                if (wd_hit) begin
                    err_hold <= 8'h04;
                    st <= F_END;
                    gave_up <= 1'b1;
                end else if (!lo_open_busy) begin
                    lo_open_index <= file_index;
                    lo_open       <= 1'b1;
                    open_wait     <= 2'd2;
                    st            <= F_OPENP;
                end
            end
            //-----------------------------------------------------------------
            F_OPENP: begin
                busy <= 1'b1;                      // lo_open 已寄存为 1，本拍回 0
                // Wait for storage_top's synchronous descriptor/session latch.
                if (open_wait != 2'd0) open_wait <= open_wait - 2'd1;
                else begin
                    cfg_first <= slot_base;
                    cfg_words <= words_tgt;
                    cfg_valid_int <= 1'b1; cfg_issued <= 1'b1;
                    st <= F_COPY;
                end
            end
            //-----------------------------------------------------------------
            F_COPY: begin
                busy <= 1'b1;
                if (lo_rd_err) begin
                    err_hold <= 8'h04; st <= F_TAIL; gave_up <= 1'b1;
                end else if (wd_hit) begin
                    err_hold <= 8'h04; st <= F_TAIL; gave_up <= 1'b1;
                end else if (eof_seen || (rd_bytes >= file_size)) begin
                    err_hold <= 8'h03; st <= F_TAIL; gave_up <= 1'b1;
                end else if (accept_now) begin
                    rd_bytes <= rd_bytes + 32'd1;
                    wr_bytes <= wr_bytes + 32'd1;
                    if ((rd_bytes + 32'd1) >= byte_len) st <= F_TAIL;
                end
            end
            //-----------------------------------------------------------------
            // 补零到 16B 边界：既补齐"半个字"（不满 4B ✓），也补齐"不满 4 字"（突发粒度 ✓）
            // ⇒ 总字数恒为 4 的倍数 ⇒ 不需要 write mask ✓
            F_TAIL: begin
                busy <= 1'b1;
                if (tail_push) begin
                    wr_bytes <= wr_bytes + 32'd1;
                end else if (wr_bytes[3:0] == 4'd0) begin
                    st <= F_END;                    // FIFO 满时继续等（见下面那条出口 ✓）
                end else if (wd_hit) begin
                    // ★★ 2026-10-05 实测踩坑：第一版**没有这条出口** ✗ ⇒
                    //   "FIFO 满（B 侧卡住）+ 还差几个补零字节" 时 F_TAIL **空转** ✗
                    //   ⇒ 一直等到 TB 超时（实测 `st=5 bst=1 rdusedw=255` ✓）。
                    // Stop padding. The shared backend drains complete 16B
                    // groups and keeps ownership until the final write is done.
                    err_hold <= 8'h04;
                    st <= F_END;
                    gave_up <= 1'b1;
                end
            end
            //-----------------------------------------------------------------
            F_END: begin
                if (!cfg_issued) begin
                    cfg_first <= 21'd0; cfg_words <= 19'd0;
                    cfg_valid_int <= 1'b1; cfg_issued <= 1'b1;
                end
                busy      <= 1'b1;
                a_words   <= wr_bytes[20:2];
                finish_valid_int <= 1'b1;
                st        <= F_DRAIN;
            end
            //-----------------------------------------------------------------
            F_DRAIN: begin
                busy <= 1'b1;
                if (lo_rd_err || eof_seen) begin
                    st <= F_WIDLE;
                end else if (wd_hit) begin
                    err_hold <= 8'h04;
                    st <= F_WIDLE;
                    gave_up <= 1'b1;
                end else if (lo_rd_valid & lo_rd_ready) begin
                    rd_bytes <= rd_bytes + 32'd1;
                end
            end
            //-----------------------------------------------------------------
            F_WIDLE: begin
                busy <= 1'b1;
                if (bidle_pend) begin
                    st <= F_FIN;
                end else if (wd_hit) begin
                    err_hold <= 8'h04;
                    st <= F_WIDLE;
                    gave_up <= 1'b1;
                end
            end
            //-----------------------------------------------------------------
            F_FIN: begin
                fifo_flush <= 1'b1;
                busy   <= 1'b0;
                done   <= 1'b1;
                err    <= err_hold;
                nbytes <= wr_bytes;
                st     <= F_IDLE;
            end
            //-----------------------------------------------------------------
            default: st <= F_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire
