`timescale 1ns/1ps
`default_nettype none
// Reuse baseline checker and read-only golden assets. Scroll decisions commit
// one clock after sample capture; allow that latency without changing values.
//============================================================================
// tb/tb_lyric_pick.v —— `lyric_pick` 单元层自检 TB（P3/S4-1）
//
// 判据分三层（都不看"看起来对不对" ✓）：
//   ① **真 golden 对账**：`../music_screen_area_opt/sim/golden/S01_lrc_tab.mem`（由 `scripts/lrc_tool.py` 独立生成 ✓）
//      ⇒ 对每个 `played` 逐点核 `cur/nxt/n3` 的 **行号 + 时间戳 + 首字 + 字数** ✓
//      （golden 是 PC 侧独立产物 ⇒ 不会与 RTL 犯同一个错 ✓）
//   ② **协议不变式**：`len=0` ✗、`ack` 后不撤 `req` ✗、地址不是表基址 ✗、突发长度不是 136 ✗
//      ⇒ 全部计数为 0 才算过 ✓
//   ③ **负例/边界**（正例会掩盖崩溃 ✓）：空表 / 单行 / 满 64 行 / 行数超槽 / magic 坏 /
//      读不出来（看门狗）/ 突发被截短 / 中途复位 —— 每一个都必须"报错但不卡死" ✓
//
// 判据文件：`tb/expected_scenarios.json`；每场景过打 `SCENARIO_PASS <id>`，全过才 `TEST_PASS` ✓。
// VCD 默认关，`+VCD=<path>` 才 dump ✓。
//============================================================================
module tb_lyric_pick;

    localparam integer GMAX  = 8192;              // `LRC_TAB` 整槽 = 8192 字 ✓
    localparam [20:0]  LBASE = 21'h17F040;        // `plan:76` ✓
    localparam integer NW    = 136;               // 8 头 + 128 行槽 ✓
    localparam integer TMO   = 600000;            // 单次等待上限（拍）★ > 看门狗 400000 ✓

    //=========================================================================
    // 时钟 / 复位
    //=========================================================================
    reg clk_sdr = 1'b0;
    always #5 clk_sdr = ~clk_sdr;                 // 100MHz ✓（本模块全在 clk_sdr ✓）

    reg rst_sdr_n = 1'b0;

    //=========================================================================
    // DUT
    //=========================================================================
    reg         tick     = 1'b0;
    reg         samp_stb = 1'b0;
    reg  [23:0] played   = 24'd0;
    wire        busy, done, tab_ok, cur_vld, nxt_vld, n3_vld, scroll_on;
    wire [7:0]  err;
    wire [15:0] n_lines;
    wire [15:0] cur_idx, nxt_idx, n3_idx;
    wire [23:0] cur_s, nxt_s, n3_s;
    wire [15:0] cur_fc, nxt_fc, n3_fc, cur_cnt, nxt_cnt, n3_cnt;
    wire [5:0]  off_px;
    wire        px_req;
    wire [20:0] px_addr;
    wire [15:0] px_len;
    reg         px_ack   = 1'b0;
    reg         px_done  = 1'b0;
    reg         px_valid = 1'b0;
    reg  [31:0] px_data  = 32'd0;

    lyric_pick u_dut (
        .clk_sdr   (clk_sdr),
        .rst_sdr_n (rst_sdr_n),
        .tick      (tick),
        .samp_stb  (samp_stb),
        .played    (played),
        .busy      (busy),
        .done      (done),
        .err       (err),
        .tab_ok    (tab_ok),
        .n_lines   (n_lines),
        .cur_idx   (cur_idx),  .nxt_idx (nxt_idx),  .n3_idx (n3_idx),
        .cur_s     (cur_s),    .nxt_s   (nxt_s),    .n3_s   (n3_s),
        .cur_fc    (cur_fc),   .nxt_fc  (nxt_fc),   .n3_fc  (n3_fc),
        .cur_cnt   (cur_cnt),  .nxt_cnt (nxt_cnt),  .n3_cnt (n3_cnt),
        .cur_vld   (cur_vld),  .nxt_vld (nxt_vld),  .n3_vld (n3_vld),
        .off_px    (off_px),
        .scroll_on (scroll_on),
        .px_req    (px_req),
        .px_addr   (px_addr),
        .px_len    (px_len),
        .px_ack    (px_ack),
        .px_done   (px_done),
        .px_data   (px_data),
        .px_valid  (px_valid)
    );

    //=========================================================================
    // 工具 / 记分
    //=========================================================================
    integer scen_fail = 0;
    integer i, i2, ww;

    reg  [31:0] gold_mem [0:GMAX-1];
    integer     model_base = 0;                   // 槽基址（golden 索引 0 的绝对地址 ✓）
    integer     px_delay   = 0;
    integer     px_lat     = 2;
    integer     px_off     = 0;                   // 1 ⇒ 模型完全不响应（测看门狗 ✓）
    integer     px_cut     = 0;                   // >0 ⇒ 只发这么多字就 done（测突发截短 ✓）
    integer     mon_bursts = 0, mon_words = 0;
    integer     mon_len0   = 0, mon_reqlate = 0, mon_addrbad = 0, mon_lenbad = 0;

    task chk32;
        input [8*28-1:0] tag;
        input [31:0]     exp;
        input [31:0]     got;
        begin
            if (exp !== got) begin
                scen_fail = scen_fail + 1;
                $display("  CHECK_FAIL %0s exp=%0X got=%0X", tag, exp, got);
            end
        end
    endtask

    task chkint;
        input [8*28-1:0] tag;
        input integer    exp;
        input integer    got;
        begin
            if (exp !== got) begin
                scen_fail = scen_fail + 1;
                $display("  CHECK_FAIL %0s exp=%0d got=%0d", tag, exp, got);
            end
        end
    endtask

    task load_gold;
        input [8*64-1:0] path;
        begin
            $readmemh(path, gold_mem);
        end
    endtask

    task scen_start;
        begin
            scen_fail   = 0;
            px_delay    = 0;
            px_lat      = 2;
            px_off      = 0;
            px_cut      = 0;
            mon_bursts  = 0;
            mon_words   = 0;
            mon_len0    = 0;
            mon_reqlate = 0;
            mon_addrbad = 0;
            mon_lenbad  = 0;
        end
    endtask

    task prot_checks;
        begin
            chkint("prot_len0",    0, mon_len0);
            chkint("prot_reqlate", 0, mon_reqlate);
            chkint("prot_addr",    0, mon_addrbad);
            chkint("prot_len",     0, mon_lenbad);
        end
    endtask

    task scen_end;
        input [8*28-1:0] id;
        begin
            if (scen_fail == 0) $display("SCENARIO_PASS %0s", id);
            else begin
                $display("TEST_FAIL %0s: %0d check(s) failed", id, scen_fail);
                $finish;
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // px 口响应模型（clk_sdr）：与 `tb_fetch_line` 同一套时序口径 ✓
    //   `px_req` 电平 ⇒ 隔 `px_delay` 拍 ack(1 拍) ⇒ 隔 `px_lat` 拍开始流 `nsend` 个字
    //   ⇒ `px_done`(1 拍)。数据直接从 `gold_mem` 取（`model_base` = 槽基址 ✓）
    //-------------------------------------------------------------------------
    localparam [2:0] PX_IDLE = 3'd0, PX_ACKW = 3'd1, PX_GAP = 3'd2, PX_RUN = 3'd3;
    reg  [2:0]  pxst = PX_IDLE;
    reg  [20:0] adr_l = 21'd0;
    reg  [15:0] len_l = 16'd0;
    reg  [15:0] k     = 16'd0;
    integer     ackw  = 0;
    integer     gapw  = 0;
    reg         ack_p1 = 1'b0;
    integer     nsend  = 0;

    always @(posedge clk_sdr) begin
        if (!rst_sdr_n) begin
            pxst <= PX_IDLE; px_ack <= 1'b0; px_done <= 1'b0; px_valid <= 1'b0;
            px_data <= 32'd0; k <= 16'd0; ackw <= 0; gapw <= 0; ack_p1 <= 1'b0;
        end else begin
            px_ack  <= 1'b0;
            px_done <= 1'b0;
            ack_p1  <= px_ack;
            if (px_req && ack_p1) mon_reqlate <= mon_reqlate + 1;   // ★ ack 后必须立刻撤 req
            case (pxst)
            PX_IDLE: begin
                px_valid <= 1'b0;
                if (px_req && (px_off == 0)) begin
                    mon_bursts <= mon_bursts + 1;
                    if (px_len == 16'd0)          mon_len0 <= mon_len0 + 1;
                    if (px_addr != LBASE)         mon_addrbad <= mon_addrbad + 1;
                    if (px_len != NW[15:0])       mon_lenbad  <= mon_lenbad + 1;
                    adr_l <= px_addr;
                    len_l <= px_len;
                    nsend  = px_len;
                    if ((px_cut > 0) && (px_cut < px_len)) nsend = px_cut;
                    k    <= 16'd0;
                    ackw <= px_delay;
                    pxst <= PX_ACKW;
                end
            end
            PX_ACKW: begin
                if (ackw != 0) ackw <= ackw - 1;
                else begin
                    px_ack <= 1'b1;
                    gapw   <= px_lat;
                    pxst   <= PX_GAP;
                end
            end
            PX_GAP: begin
                if (gapw != 0) gapw <= gapw - 1;
                else begin
                    px_valid <= 1'b1;
                    px_data  <= gold_mem[adr_l - model_base[20:0] + k];
                    pxst     <= PX_RUN;
                end
            end
            PX_RUN: begin
                mon_words <= mon_words + 1;
                if ((k + 16'd1) >= nsend) begin
                    px_valid <= 1'b0;
                    px_done  <= 1'b1;
                    pxst     <= PX_IDLE;
                end else begin
                    k       <= k + 16'd1;
                    px_data <= gold_mem[adr_l - model_base[20:0] + k + 16'd1];
                end
            end
            default: pxst <= PX_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // 驱动任务
    //-------------------------------------------------------------------------
    // 发一次 `tick` 并等 `done`（成败都出 ✓）；返回时输出已稳定（下次 tick 前不会变 ✓）
    task do_pick;
        input [23:0] pv;
        begin
            played = pv;
            @(negedge clk_sdr);
            tick = 1'b1;
            @(negedge clk_sdr);
            tick = 1'b0;
            ww = 0;
            while ((done !== 1'b1) && (ww < TMO)) begin @(negedge clk_sdr); ww = ww + 1; end
            if (done !== 1'b1) begin
                $display("TEST_FAIL do_pick timeout (done never pulsed) st=%0d busy=%b pxst=%0d",
                         u_dut.st, busy, pxst);
                $finish;
            end
            @(negedge clk_sdr);                   // 让 done 落下 ✓（输出保持不变 ✓）
        end
    endtask

    // 脉冲 `samp_stb` n 次（48kHz 节拍 ✓）
    task stb_n;
        input integer n;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge clk_sdr); samp_stb = 1'b1;
                @(negedge clk_sdr); samp_stb = 1'b0;
            end
            @(negedge clk_sdr);                   // delayed decision has committed
        end
    endtask

    // 三行整槽对账（idx/s/fc/cnt/vld 一次核完 ✓）★ 时间戳是 24 位 ⇒ 端口必须 ≥24 位 ✗别用 16 位
    task chk_line;
        input [8*20-1:0] tag;
        input [31:0] ei, es, efc, ecnt, ev;
        input [31:0] gi, gs, gfc, gcnt, gv;
        begin
            chkint({tag, "_idx"}, ei,  gi);
            chkint({tag, "_s"},   es,  gs);
            chkint({tag, "_fc"},  efc, gfc);
            chkint({tag, "_cnt"}, ecnt, gcnt);
            chkint({tag, "_vld"}, ev,  gv);
        end
    endtask

    //=========================================================================
    // 场景
    //=========================================================================
    initial begin
        rst_sdr_n = 1'b0;
        repeat (20) @(posedge clk_sdr);
        rst_sdr_n = 1'b1;
        repeat (10) @(posedge clk_sdr);
        model_base = LBASE;

        //---------------------------------------------------------------------
        // LP-01：真 golden 表（45 行 ✓）逐点选行 —— 行号/时间戳/首字/字数全对账
        //---------------------------------------------------------------------
        scen_start();
        load_gold("../music_screen_area_opt/sim/golden/S01_lrc_tab.mem");

        do_pick(24'd0);                                   // 还没到第 0 行（0.395s ✓）
        chkint("p0_nlines", 45, n_lines);
        chkint("p0_tabok",  1,  tab_ok);
        chkint("p0_err",    0,  err);
        chk_line("p0_cur", 16'd0,16'd0,16'd0,16'd0,16'd0, cur_idx,cur_s,cur_fc,cur_cnt,cur_vld);
        chkint("p0_nxtvld", 0, nxt_vld);

        do_pick(24'd18959);                               // 第 0 行前 1 个样本 ✓
        chkint("p1_curvld", 0, cur_vld);

        do_pick(24'd18960);                               // ★ 第 0 行**正好**开始（≤ ✓）
        chk_line("p2_cur", 16'd0, 18960, 16'd0,  16'd12, 16'd1, cur_idx,cur_s,cur_fc,cur_cnt,cur_vld);
        chk_line("p2_nxt", 16'd1, 182400,16'd12, 16'd4,  16'd1, nxt_idx,nxt_s,nxt_fc,nxt_cnt,nxt_vld);
        chk_line("p2_n3",  16'd2, 365280,16'd16, 16'd4,  16'd1, n3_idx, n3_s, n3_fc, n3_cnt, n3_vld);

        do_pick(24'd182400);                              // 第 1 行正好开始 ✓
        chk_line("p3_cur", 16'd1, 182400,16'd12, 16'd4,  16'd1, cur_idx,cur_s,cur_fc,cur_cnt,cur_vld);
        chk_line("p3_nxt", 16'd2, 365280,16'd16, 16'd4,  16'd1, nxt_idx,nxt_s,nxt_fc,nxt_cnt,nxt_vld);

        do_pick(24'd500000);                              // 第 2 行中段 ✓
        chk_line("p4_cur", 16'd2, 365280,16'd16, 16'd4,  16'd1, cur_idx,cur_s,cur_fc,cur_cnt,cur_vld);
        chk_line("p4_nxt", 16'd3, 547680,16'd20, 16'd5,  16'd1, nxt_idx,nxt_s,nxt_fc,nxt_cnt,nxt_vld);
        chk_line("p4_n3",  16'd4, 730896,16'd25, 16'd12, 16'd1, n3_idx, n3_s, n3_fc, n3_cnt, n3_vld);

        do_pick(24'd6700000);                             // ★ 落在 35s 间奏里（24 → 25 之间 ✓）
        chk_line("p5_cur", 16'd24, 6457344, 16'd245, 16'd13, 16'd1, cur_idx,cur_s,cur_fc,cur_cnt,cur_vld);
        chk_line("p5_nxt", 16'd25, 6839856, 16'd258, 16'd7,  16'd1, nxt_idx,nxt_s,nxt_fc,nxt_cnt,nxt_vld);
        chk_line("p5_n3",  16'd26, 8428368, 16'd265, 16'd12, 16'd1, n3_idx, n3_s, n3_fc, n3_cnt, n3_vld);

        do_pick(24'd8400000);                             // 间奏后第一行 ✓
        chk_line("p6_cur", 16'd25, 6839856, 16'd258, 16'd7,  16'd1, cur_idx,cur_s,cur_fc,cur_cnt,cur_vld);
        chk_line("p6_nxt", 16'd26, 8428368, 16'd265, 16'd12, 16'd1, nxt_idx,nxt_s,nxt_fc,nxt_cnt,nxt_vld);

        do_pick(24'd13556448);                            // ★ 最后一行（282.426s ✓）：没有下一行 ✓
        chk_line("p7_cur", 16'd44, 13556448, 16'd454, 16'd7, 16'd1, cur_idx,cur_s,cur_fc,cur_cnt,cur_vld);
        chkint("p7_nxtvld", 0, nxt_vld);
        chkint("p7_n3vld",  0, n3_vld);

        do_pick(24'hFFFFFF);                              // 24 位满量程（349.5s ✓）仍停在第 44 行 ✓
        chkint("p8_cur", 44, cur_idx);

        chkint("lp01_bursts", 9, mon_bursts);             // p0..p8 = 9 次选行 ✓
        chkint("lp01_words",  9 * NW, mon_words);
        // ★★ 2026-10-05（P3/S6-2）：字 5 / 6 = 歌名 / 歌手素材（新增输出 ✓ 零额外流量 ✓）
        //   期望取自 PC 侧检查报告 doc/lrc_check_S01.txt（独立来源 ✓）：fc=461/cnt=22、fc=483/cnt=4
        chkint("ttl_fc",  461, u_dut.ttl_fc);
        chkint("ttl_cnt", 22,  u_dut.ttl_cnt);
        chkint("ttl_vld", 1,   u_dut.ttl_vld);
        chkint("sgr_fc",  483, u_dut.sgr_fc);
        chkint("sgr_cnt", 4,   u_dut.sgr_cnt);
        chkint("sgr_vld", 1,   u_dut.sgr_vld);
        prot_checks();
        $display("  LP-01 bursts=%0d words=%0d ttl_fc=%0d ttl_cnt=%0d sgr_fc=%0d sgr_cnt=%0d",
                 mon_bursts, mon_words, u_dut.ttl_fc, u_dut.ttl_cnt, u_dut.sgr_fc, u_dut.sgr_cnt);
        scen_end("LP-01");

        //---------------------------------------------------------------------
        // LP-02：magic 坏 ⇒ err=0x65 / tab_ok=0 / 三行全无效（A11 ✓ 不黑屏不崩 ✓）
        //---------------------------------------------------------------------
        scen_start();
        load_gold("../music_screen_area_opt/sim/golden/S01_lrc_tab.mem");
        gold_mem[0] = 32'hDEADBEEF;
        do_pick(24'd500000);
        chkint("lp02_err",    16'h65, err);
        chkint("lp02_tabok",  0, tab_ok);
        chkint("lp02_nlines", 0, n_lines);
        chkint("lp02_curvld", 0, cur_vld);
        chkint("lp02_nxtvld", 0, nxt_vld);
        chkint("lp02_n3vld",  0, n3_vld);
        chkint("lp02_busy",   0, busy);
        prot_checks();
        scen_end("LP-02");

        //---------------------------------------------------------------------
        // LP-03：空表（n_lines=0 ✓）⇒ tab_ok=1 / err=0 / 一行都不选 ✓
        //---------------------------------------------------------------------
        scen_start();
        load_gold("../music_screen_area_opt/sim/golden/S01_lrc_tab.mem");
        gold_mem[4] = 32'h000001CD;
        do_pick(24'hFFFFFF);
        chkint("lp03_err",    0, err);
        chkint("lp03_tabok",  1, tab_ok);
        chkint("lp03_nlines", 0, n_lines);
        chkint("lp03_curvld", 0, cur_vld);
        chkint("lp03_nxtvld", 0, nxt_vld);
        prot_checks();
        scen_end("LP-03");

        //---------------------------------------------------------------------
        // LP-04：单行表（n_lines=1 ✓）⇒ 只有 cur，没有 nxt/n3 ✓
        //---------------------------------------------------------------------
        scen_start();
        load_gold("../music_screen_area_opt/sim/golden/S01_lrc_tab.mem");
        gold_mem[4] = 32'h000101CD;
        do_pick(24'd0);                                   // 还没到（18960 ✓）
        chkint("lp04_curvld0", 0, cur_vld);
        do_pick(24'hFFFFFF);
        chk_line("lp04_cur", 16'd0, 18960, 16'd0, 16'd12, 16'd1, cur_idx,cur_s,cur_fc,cur_cnt,cur_vld);
        chkint("lp04_nxtvld", 0, nxt_vld);
        chkint("lp04_n3vld",  0, n3_vld);
        chkint("lp04_nlines", 1, n_lines);
        prot_checks();
        scen_end("LP-04");

        //---------------------------------------------------------------------
        // LP-05：★ 满表 64 行（合成表 ✓）：0 / 正好边界 / 末行 / 满量程
        //   —— 专抓"扫到 n_lines（含 ✓）"的差一错、"索引 64 越界"、以及"零值槽被当命中"✗
        //---------------------------------------------------------------------
        scen_start();
        load_gold("../music_screen_area_opt/sim/golden/S01_lrc_tab.mem");
        gold_mem[0] = 32'h3143524C;
        gold_mem[4] = 32'h00400001;                       // n_chars=1 / n_lines=64 ✓
        for (i2 = 0; i2 < 64; i2 = i2 + 1) begin
            gold_mem[8 + 2*i2] = (i2 + 1) * 1000;         // 槽 i 时间戳 = (i+1)*1000 ✓
            gold_mem[9 + 2*i2] = ((i2 + 1) << 16) | i2;   // cnt=i+1 高半 / fc=i 低半 ✓
        end
        do_pick(24'd0);                                   // 最小时间戳 1000 > 0 ⇒ 一个都不选 ✓
        chkint("lp05_curvld0", 0, cur_vld);
        chkint("lp05_nlines",  64, n_lines);
        do_pick(24'd1000);                                // ★ 第 0 行正好开始 ✓
        chk_line("lp05_a_cur", 16'd0, 1000, 16'd0, 16'd1, 16'd1, cur_idx,cur_s,cur_fc,cur_cnt,cur_vld);
        chk_line("lp05_a_nxt", 16'd1, 2000, 16'd1, 16'd2, 16'd1, nxt_idx,nxt_s,nxt_fc,nxt_cnt,nxt_vld);
        // Low timestamps must saturate the window start at zero.
        stb_n(1);
        chkint("lp05_short_window_on", 1, scroll_on);
        played = 24'd2000;
        stb_n(1);
        chkint("lp05_short_window_end", 0, scroll_on);
        do_pick(24'd32000);                               // ★ 第 31 行正好开始 ✓
        chk_line("lp05_b_cur", 16'd31, 32000, 16'd31, 16'd32, 16'd1, cur_idx,cur_s,cur_fc,cur_cnt,cur_vld);
        chk_line("lp05_b_nxt", 16'd32, 33000, 16'd32, 16'd33, 16'd1, nxt_idx,nxt_s,nxt_fc,nxt_cnt,nxt_vld);
        chk_line("lp05_b_n3",  16'd33, 34000, 16'd33, 16'd34, 16'd1, n3_idx, n3_s, n3_fc, n3_cnt, n3_vld);
        do_pick(24'd31999);                               // 前 1 个样本 ⇒ 仍是第 30 行 ✓
        chkint("lp05_c_cur", 30, cur_idx);
        do_pick(24'd64000);                               // ★ 第 63 行（末行 ✓）⇒ 无 nxt ✓
        chk_line("lp05_d_cur", 16'd63, 64000, 16'd63, 16'd64, 16'd1, cur_idx,cur_s,cur_fc,cur_cnt,cur_vld);
        chkint("lp05_d_nxtvld", 0, nxt_vld);
        chkint("lp05_d_n3vld",  0, n3_vld);
        do_pick(24'hFFFFFF);                              // 满量程 ⇒ 仍是第 63 行 ✓
        chkint("lp05_e_cur", 63, cur_idx);
        prot_checks();
        scen_end("LP-05");

        //---------------------------------------------------------------------
        // LP-06：行数 65（超槽 ✗）⇒ err=0x65 / 三行全无效 ✓
        //---------------------------------------------------------------------
        scen_start();
        load_gold("../music_screen_area_opt/sim/golden/S01_lrc_tab.mem");
        gold_mem[4] = 32'h004101CD;
        do_pick(24'd500000);
        chkint("lp06_err",    16'h65, err);
        chkint("lp06_tabok",  0, tab_ok);
        chkint("lp06_curvld", 0, cur_vld);
        prot_checks();
        scen_end("LP-06");

        //---------------------------------------------------------------------
        // LP-07：★ 读不出来（模型完全不响应）⇒ 看门狗 err=0x04 / done 照出 / busy 释放 ✓
        //        —— "卡死"是最坏的失效 ✗（画面会永远停住 ✓），必须验 ✓
        //---------------------------------------------------------------------
        scen_start();
        load_gold("../music_screen_area_opt/sim/golden/S01_lrc_tab.mem");
        px_off = 1;
        do_pick(24'd500000);
        chkint("lp07_err",    16'h04, err);
        chkint("lp07_tabok",  0, tab_ok);
        chkint("lp07_busy",   0, busy);
        chkint("lp07_curvld", 0, cur_vld);
        chkint("lp07_bursts", 0, mon_bursts);
        // 恢复 ⇒ 紧接着一次必须正常 ✓
        px_off = 0;
        do_pick(24'd500000);
        chkint("lp07b_err",   0, err);
        chkint("lp07b_cur",   2, cur_idx);
        prot_checks();
        scen_end("LP-07");

        //---------------------------------------------------------------------
        // LP-08：★ 突发被截短（只发 100 字就 done ✗）⇒ err=0x04（不拿半张表选行 ✓）
        //---------------------------------------------------------------------
        scen_start();
        load_gold("../music_screen_area_opt/sim/golden/S01_lrc_tab.mem");
        px_cut = 100;
        do_pick(24'd500000);
        chkint("lp08_err",    16'h04, err);
        chkint("lp08_tabok",  0, tab_ok);
        chkint("lp08_curvld", 0, cur_vld);
        chkint("lp08_busy",   0, busy);
        px_cut = 0;
        do_pick(24'd500000);
        chkint("lp08b_err", 0, err);
        chkint("lp08b_cur", 2, cur_idx);
        prot_checks();
        scen_end("LP-08");

        //---------------------------------------------------------------------
        // LP-09：★ 滚行相位：进入窗口预置 ⇒ 14400 拍正好 38 px（逐点对账 ✓）
        //        以及"出窗口不清零"（防跳变 ✓）与"换行才清零"✓
        //---------------------------------------------------------------------
        scen_start();
        load_gold("../music_screen_area_opt/sim/golden/S01_lrc_tab.mem");
        do_pick(24'd168000);                              // nxt_s=182400 ⇒ 距离正好 14400 ✓ 进窗口
        chkint("lp09_cur",   0, cur_idx);
        chkint("lp09_nxts",  182400, nxt_s);
        played = 24'd167999;
        stb_n(1);
        chkint("lp09_before_window", 0, scroll_on);
        played = 24'd168000;
        stb_n(1);                                         // 进入窗口那一拍（预置 ✓）
        chkint("lp09_sw",    1, scroll_on);
        chkint("lp09_o0",    0, off_px);
        stb_n(378);                                       // 38×379 = 14402 ⇒ 1 px ✓
        chkint("lp09_o1",    1, off_px);
        stb_n(379);                                       // 38×758 = 28804 ⇒ 2 px ✓
        chkint("lp09_o2",    2, off_px);
        stb_n(13642);                                     // 累计 14400 拍 ⇒ 38×14400 = 547200 ⇒ 38 px ✓
        chkint("lp09_o38",   38, off_px);
        stb_n(10);                                        // 饱和（不溢出 ✓）
        chkint("lp09_oclamp",38, off_px);
        // ---- 出窗口（played 追平 nxt_s）：只停不动，**不清零** ✓（否则会掉回 38px ✗）----
        played = 24'd182400;
        stb_n(1);
        chkint("lp09_sw_off", 0,  scroll_on);
        chkint("lp09_hold",   38, off_px);
        // ---- 真的换行（cur 0 → 1）：清零 ✓ ----
        do_pick(24'd182400);
        chkint("lp09_cur2",  1,  cur_idx);
        chkint("lp09_rst",   0,  off_px);
        chkint("lp09_sw2",   0,  scroll_on);
        stb_n(4);
        chkint("lp09_rst2",  0,  off_px);
        // ---- 没有下一行（末行）⇒ 永不滚、相位恒 0 ✓ ----
        do_pick(24'd13556448);
        chkint("lp09_last_nxtvld", 0, nxt_vld);
        stb_n(4);
        chkint("lp09_last_off", 0, off_px);
        chkint("lp09_last_sw",  0, scroll_on);
        // Real playback advances played on the same clock as samp_stb.
        // Check every sample against an independent rational phase, including
        // the inclusive start, exclusive end and the held final position.
        do_pick(24'd168000);
        for (i2 = 0; i2 < 14401; i2 = i2 + 1) begin
            @(negedge clk_sdr);
            played = 24'd168000 + i2;
            samp_stb = 1'b1;
            @(posedge clk_sdr);
            #1 played = played + 24'd1;
            @(negedge clk_sdr); samp_stb = 1'b0;
            @(negedge clk_sdr);
            if (i2 < 14400) begin
                chkint("lp09_ramp_on", 1, scroll_on);
                chkint("lp09_ramp_px", ((i2 + 1) * 38) / 14400, off_px);
            end else begin
                chkint("lp09_ramp_end", 0, scroll_on);
                chkint("lp09_ramp_hold", 38, off_px);
            end
        end
        // Force the new-line submission to overlap a pending old-window
        // event, then a coincident event. Neither may revive the old phase.
        for (i2 = 0; i2 < 2; i2 = i2 + 1) begin
            do_pick(24'd168000);
            stb_n(758);
            chkint("lp09_collision_pre", 2, off_px);
            @(negedge clk_sdr); played = 24'd182400; tick = 1'b1;
            @(negedge clk_sdr); tick = 1'b0;
            ww = 0;
            while (((i2 == 0 && !(px_valid && u_dut.wc == 8'd135)) ||
                    (i2 == 1 && u_dut.st != 3'd3)) && ww < TMO) begin
                @(negedge clk_sdr); ww = ww + 1;
            end
            if (ww == TMO) begin
                $display("TEST_FAIL scroll/line collision alignment timeout");
                $finish;
            end
            played = 24'd168000; samp_stb = 1'b1;
            @(negedge clk_sdr); samp_stb = 1'b0;
            repeat (3) @(negedge clk_sdr);
            chkint("lp09_collision_cur", 1, cur_idx);
            chkint("lp09_collision_px", 0, off_px);
            chkint("lp09_collision_on", 0, scroll_on);
            stb_n(1);
            chkint("lp09_collision_stale", 0, off_px);
            chkint("lp09_collision_newwin", 0, scroll_on);
        end
        prot_checks();
        scen_end("LP-09");

        //---------------------------------------------------------------------
        // LP-10：★ 突发中途复位 ⇒ 确定态；复位后仍要能正常选行 ✓
        //---------------------------------------------------------------------
        scen_start();
        load_gold("../music_screen_area_opt/sim/golden/S01_lrc_tab.mem");
        @(negedge clk_sdr); played = 24'd500000;
        tick = 1'b1; @(negedge clk_sdr); tick = 1'b0;
        repeat (12) @(negedge clk_sdr);                   // 突发正流着
        chkint("lp10_inrun", 1, (u_dut.st != 3'd0));      // 确实在跑（前提成立 ✓）
        rst_sdr_n = 1'b0;
        repeat (8) @(negedge clk_sdr);
        chkint("lp10_rst_busy", 0, busy);
        chkint("lp10_rst_done", 0, done);
        chkint("lp10_rst_req",  0, px_req);
        chkint("lp10_rst_vld",  0, cur_vld);
        rst_sdr_n = 1'b1;
        repeat (10) @(negedge clk_sdr);
        do_pick(24'd500000);                              // 复位后仍要正确 ✓
        chkint("lp10b_err",  0, err);
        chkint("lp10b_cur",  2, cur_idx);
        chkint("lp10b_nxt",  3, nxt_idx);
        prot_checks();
        scen_end("LP-10");

        $display("TEST_PASS");
        $finish;
    end

    //---------------------------------------------------------------------
    // 全局兜底 + 可选 VCD
    //---------------------------------------------------------------------
    initial begin
        #200000000;                                       // 200ms 仿真时间上限
        $display("TEST_FAIL global watchdog timeout at %0t", $time);
        $finish;
    end

    reg [8*128-1:0] vcd_file;
    initial begin
        if ($value$plusargs("VCD=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_lyric_pick);
        end
    end

endmodule

`default_nettype wire
