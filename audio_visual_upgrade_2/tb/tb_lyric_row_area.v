`timescale 1ns/1ps
`default_nettype none
// Reuse baseline checker and read-only golden assets; assertions are unchanged.
//============================================================================
// tb/tb_lyric_row.v —— `lyric_row` 单元层自检 TB（P3/S4-2a）
//
// 判据三层（都不看"像不像字" ✓）：
//   ① **PC 侧独立 golden 逐字对账**：`../music_screen_area_opt/sim/golden/LR_gold.mem`（5 用例 × 40 字 ✓）
//      由 `scripts/mk_lyric_row_golden.py` **直接读卡上原件**（`card_out/S01.LRC` ✓
//      `card/FONT.HZK` ✓ `card/ASC.HZK` ✓）另写一套实现算出来的 ✓
//      ⇒ RTL 与 golden 的公共依赖只有"卡上的字节"本身 ✓（正是要验的东西 ✓）
//   ② **写口边界**：缓冲预填哨兵 ⇒ 只允许写 `[buf_base, buf_base+nw)` ✓，
//      其余字（含**另一个 bank** ✓）必须原封不动 ✓；写地址越界单独计数 ✓
//   ③ **负例/边界**：超 20 字 / 空行 / 码非法 / 读不出来 / 突发被截短 ⇒ 报错但**绝不卡死** ✓
//
// 判据文件 `tb/expected_scenarios.json`；每场景过打 `SCENARIO_PASS`，全过才 `TEST_PASS` ✓。
//============================================================================
module tb_lyric_row;

    localparam integer LRC_W  = 8192;
    localparam integer FONT_W = 261696;
    localparam integer ASC_W  = 1536;
    localparam integer GNW    = 200;                 // 5 用例 × 40 字 ✓
    localparam [20:0]  LBASE  = 21'h17F040;
    localparam [20:0]  FBASE  = 21'h13EC00;
    localparam [20:0]  ABASE  = 21'h17EA40;
    localparam [31:0]  SENT   = 32'hA5A5A5A5;        // 哨兵 ✓
    localparam integer TMO    = 600000;              // ★ > 看门狗 400000 ✓

    reg clk_sdr = 1'b0;
    always #5 clk_sdr = ~clk_sdr;                    // 100MHz ✓

    reg rst_sdr_n = 1'b0;

    //--------------------------------------------------------------- DUT
    reg         start    = 1'b0;
    reg  [5:0]  buf_base = 6'd0;
    reg  [15:0] fc       = 16'd0;
    reg  [15:0] cnt      = 16'd0;
    reg  [4:0]  grow     = 5'd0;
    reg  [23:0] played   = 24'd0;
    wire        busy, done;
    wire [7:0]  err;
    wire [5:0]  nw;
    wire        wr_en;
    wire [6:0]  wr_addr;
    wire [31:0] wr_data;
    wire        px_req;
    wire [20:0] px_addr;
    wire [15:0] px_len;
    reg         px_ack = 1'b0, px_done = 1'b0, px_valid = 1'b0;
    reg  [31:0] px_data = 32'd0;

    lyric_row u_dut (
        .clk_sdr (clk_sdr), .rst_sdr_n (rst_sdr_n),
        .start (start), .buf_base (buf_base), .fc (fc), .cnt (cnt), .grow (grow),
        .played (played), .busy (busy), .done (done), .err (err), .nw (nw),
        .wr_en (wr_en), .wr_addr (wr_addr), .wr_data (wr_data),
        .px_req (px_req), .px_addr (px_addr), .px_len (px_len),
        .px_ack (px_ack), .px_done (px_done), .px_data (px_data), .px_valid (px_valid)
    );

    //--------------------------------------------------------------- 记分
    integer scen_fail = 0;
    integer i, ww;

    reg [31:0] lrc_mem  [0:LRC_W-1];
    reg [31:0] font_mem [0:FONT_W-1];
    reg [31:0] asc_mem  [0:ASC_W-1];
    reg [31:0] gold_mem [0:GNW-1];
    reg [31:0] wmem     [0:127];                     // 写口影子（乒乓 0..79 ✓）

    integer px_delay = 0, px_lat = 2, px_off = 0, px_cut = 0;
    integer mon_bursts = 0, mon_words = 0, mon_len0 = 0, mon_reqlate = 0;
    integer mon_addrbad = 0, mon_wrbad = 0;
    // ★★ T-14（p3-lean 步1）：读定律守卫。**桩内存会无条件回正确数据 ⇒ 结构上抓不到非法的读** ✗
    //   ⇒ 必须由 TB 对**发出的请求**下协议断言：每一次读都要 (a) 长度 ≥4、(b) 4 字组对齐
    //   （定律见 `doc/evidence/p3_lean_px_floor.md`；违反 ⇒ 真器件会回错数据 ✓）
    integer mon_lenlt4 = 0, mon_unalign = 0, mon_bursts_all = 0;   // 最后那个**不随场景清零**（防空跑 ✓）

    task chk32;
        input [8*28-1:0] tag; input [31:0] exp; input [31:0] got;
        begin
            if (exp !== got) begin
                scen_fail = scen_fail + 1;
                $display("  CHECK_FAIL %0s exp=%08X got=%08X", tag, exp, got);
            end
        end
    endtask

    task chkint;
        input [8*28-1:0] tag; input integer exp; input integer got;
        begin
            if (exp !== got) begin
                scen_fail = scen_fail + 1;
                $display("  CHECK_FAIL %0s exp=%0d got=%0d", tag, exp, got);
            end
        end
    endtask

    task scen_start;
        begin
            scen_fail = 0; px_delay = 0; px_lat = 2; px_off = 0; px_cut = 0;
            mon_bursts = 0; mon_words = 0; mon_len0 = 0; mon_reqlate = 0;
            mon_addrbad = 0; mon_wrbad = 0;
            mon_lenlt4 = 0; mon_unalign = 0;              // ★ T-14 逐场景清零（`mon_bursts_all` 不清 ✓）
        end
    endtask

    task prot_checks;
        begin
            chkint("prot_len0",    0, mon_len0);
            chkint("prot_reqlate", 0, mon_reqlate);
            chkint("prot_addr",    0, mon_addrbad);
            chkint("prot_wrbad",   0, mon_wrbad);
            chkint("prot_len4",    0, mon_lenlt4);        // ★ T-14(a) 长度 ≥ 4 字
            chkint("prot_align",   0, mon_unalign);       // ★ T-14(b) 4 字组对齐
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

    //--------------------------------------------------------------- 写口影子
    always @(posedge clk_sdr) begin
        if (wr_en) begin
            if (wr_addr > 7'd79) mon_wrbad <= mon_wrbad + 1;
            else                 wmem[wr_addr] <= wr_data;
        end
    end

    //--------------------------------------------------------------- px 口模型
    localparam [2:0] PX_IDLE = 3'd0, PX_ACKW = 3'd1, PX_GAP = 3'd2, PX_RUN = 3'd3;
    reg  [2:0]  pxst = PX_IDLE;
    reg  [20:0] adr_l = 21'd0;
    reg  [15:0] k = 16'd0;
    integer     ackw = 0, gapw = 0, nsend = 0;
    reg         ack_p1 = 1'b0;

    // 一个客户口 ⇒ 按地址范围选槽 ✓（三段互不重叠：FONT < ASC < LRC ✓）
    function [31:0] mem_at;
        input [20:0] a;
        begin
            if      ((a >= FBASE) && (a < FBASE + FONT_W)) mem_at = font_mem[a - FBASE];
            else if ((a >= ABASE) && (a < ABASE + ASC_W))  mem_at = asc_mem [a - ABASE];
            else if ((a >= LBASE) && (a < LBASE + LRC_W))  mem_at = lrc_mem [a - LBASE];
            else                                            mem_at = 32'hDEADBEEF;
        end
    endfunction

    always @(posedge clk_sdr) begin
        if (!rst_sdr_n) begin
            pxst <= PX_IDLE; px_ack <= 1'b0; px_done <= 1'b0; px_valid <= 1'b0;
            px_data <= 32'd0; k <= 16'd0; ackw <= 0; gapw <= 0; ack_p1 <= 1'b0;
        end else begin
            px_ack  <= 1'b0;
            px_done <= 1'b0;
            ack_p1  <= px_ack;
            if (px_req && ack_p1) mon_reqlate <= mon_reqlate + 1;
            case (pxst)
            PX_IDLE: begin
                px_valid <= 1'b0;
                if (px_req && (px_off == 0)) begin
                    mon_bursts <= mon_bursts + 1;
                    mon_bursts_all <= mon_bursts_all + 1;
                    if (px_len == 16'd0) mon_len0 <= mon_len0 + 1;
                    // ★★ T-14：读定律守卫（对**发出的请求**断言，不依赖桩内存怎么答 ✓）
                    if (px_len < 16'd4)       mon_lenlt4  <= mon_lenlt4  + 1;
                    if (px_addr[1:0] != 2'd0) mon_unalign <= mon_unalign + 1;
                    if (!(((px_addr >= FBASE) && (px_addr < FBASE + FONT_W)) ||
                          ((px_addr >= ABASE) && (px_addr < ABASE + ASC_W))  ||
                          ((px_addr >= LBASE) && (px_addr < LBASE + LRC_W))))
                        mon_addrbad <= mon_addrbad + 1;   // 地址跑到槽外 ⇒ 算术错 ✓
                    adr_l <= px_addr;
                    nsend  = px_len;
                    if ((px_cut > 0) && (px_cut < px_len)) nsend = px_cut;
                    k    <= 16'd0;
                    ackw <= px_delay;
                    pxst <= PX_ACKW;
                end
            end
            PX_ACKW: begin
                if (ackw != 0) ackw <= ackw - 1;
                else begin px_ack <= 1'b1; gapw <= px_lat; pxst <= PX_GAP; end
            end
            PX_GAP: begin
                if (gapw != 0) gapw <= gapw - 1;
                else begin px_valid <= 1'b1; px_data <= mem_at(adr_l); pxst <= PX_RUN; end
            end
            PX_RUN: begin
                mon_words <= mon_words + 1;
                if ((k + 16'd1) >= nsend) begin px_valid <= 1'b0; px_done <= 1'b1; pxst <= PX_IDLE; end
                else begin
                    k       <= k + 16'd1;
                    px_data <= mem_at(adr_l + k + 16'd1);   // ★ 下一字（基址 + k+1 ✓ 不递增基址 ✓）
                end
            end
            default: pxst <= PX_IDLE;
            endcase
        end
    end

    //--------------------------------------------------------------- 驱动
    task do_row;
        input [5:0] bb; input [15:0] fcv, cntv; input [4:0] grv; input [23:0] pv;
        begin
            buf_base = bb; fc = fcv; cnt = cntv; grow = grv; played = pv;
            for (i = 0; i < 128; i = i + 1) wmem[i] = SENT;
            @(negedge clk_sdr);
            start = 1'b1;
            @(negedge clk_sdr);
            start = 1'b0;
            ww = 0;
            while ((done !== 1'b1) && (ww < TMO)) begin @(negedge clk_sdr); ww = ww + 1; end
            if (done !== 1'b1) begin
                $display("TEST_FAIL do_row timeout st=%0d busy=%b pxst=%0d", u_dut.st, busy, pxst);
                $finish;
            end
            @(negedge clk_sdr);
        end
    endtask

    // 对账：本 bank 内 [0,nw) == golden ✓、[nw,40) 与另一个 bank 全为哨兵 ✓
    task chk_row;
        input integer     case_i;        // golden 用例号
        input [5:0]       bb;
        input integer     nw_exp;
        integer j;
        begin
            chkint("err",  0, err);
            chkint("nw",   nw_exp, nw);
            for (j = 0; j < 40; j = j + 1) begin
                if ((j < nw_exp) && (bb == 6'd0))
                    chk32("w", gold_mem[case_i * 40 + j], wmem[j]);
                else if ((j < nw_exp) && (bb == 6'd40))
                    chk32("w", gold_mem[case_i * 40 + j], wmem[40 + j]);
                else if ((bb == 6'd0) && (wmem[j] !== SENT)) begin
                    scen_fail = scen_fail + 1;
                    $display("  CHECK_FAIL untouched[%0d] = %08X (expect sentinel)", j, wmem[j]);
                end else if ((bb == 6'd40) && (wmem[40 + j] !== SENT)) begin
                    scen_fail = scen_fail + 1;
                    $display("  CHECK_FAIL untouched[%0d] = %08X (expect sentinel)", 40 + j, wmem[40 + j]);
                end
            end
            if (bb == 6'd0) begin
                for (j = 40; j < 80; j = j + 1)
                    if (wmem[j] !== SENT) begin
                        scen_fail = scen_fail + 1;
                        $display("  CHECK_FAIL otherbank[%0d] = %08X", j, wmem[j]);
                    end
            end else begin
                for (j = 0; j < 40; j = j + 1)
                    if (wmem[j] !== SENT) begin
                        scen_fail = scen_fail + 1;
                        $display("  CHECK_FAIL otherbank[%0d] = %08X", j, wmem[j]);
                    end
            end
        end
    endtask

    //=========================================================================
    initial begin
        rst_sdr_n = 1'b0;
        $readmemh("../music_screen_area_opt/sim/golden/S01_lrc_tab.mem", lrc_mem);
        $readmemh("../music_screen_area_opt/sim/golden/FONT_slot.mem",   font_mem);
        $readmemh("../music_screen_area_opt/sim/golden/ASC_slot.mem",    asc_mem);
        $readmemh("../music_screen_area_opt/sim/golden/LR_gold.mem",     gold_mem);
        for (i = 0; i < 128; i = i + 1) wmem[i] = SENT;
        repeat (20) @(posedge clk_sdr);
        rst_sdr_n = 1'b1;
        repeat (10) @(posedge clk_sdr);

        //---------------------------------------------------------------------
        // LR-01..LR-05：PC 侧独立 golden 逐字对账 ✓
        //   LR-01 行0 grow16 played18960（ASCII 已唱、追未唱 ⇒ 混合高亮 ✓）
        //   LR-02 同上一行但全已唱（与 LR-01 必须不同 ✓ 已由脚本自检 ✓）
        //   LR-03 行0 grow8 / LR-04 行4 grow16（**用 bank 1** ✓）/ LR-05 末行 grow30 ✓
        //---------------------------------------------------------------------
        scen_start();
        do_row(6'd0,  lrc_mem[9] & 16'hFFFF, lrc_mem[9] >> 16, 5'd16, 24'd18960);
        chk_row(0, 6'd0, 17);
        chkint("bursts", 24, mon_bursts);                 // 12 字 × 2 笔 ✓（p3-lean 后**笔数不变** ✓）
        chkint("words",  96, mon_words);                  // ★ p3-lean：每笔都是对齐 4 字组 ⇒ 12×(4+4) ✓
        prot_checks();
        $display("  LR-01 golden line0 grow16 mixed-highlight OK");
        scen_end("LR-01");

        scen_start();
        do_row(6'd0,  lrc_mem[9] & 16'hFFFF, lrc_mem[9] >> 16, 5'd16, 24'd21360);
        chk_row(1, 6'd0, 17);
        chkint("bursts", 24, mon_bursts);
        prot_checks();
        scen_end("LR-02");

        scen_start();
        do_row(6'd0,  lrc_mem[9] & 16'hFFFF, lrc_mem[9] >> 16, 5'd8,  24'd18960);
        chk_row(2, 6'd0, 17);
        chkint("bursts", 24, mon_bursts);
        prot_checks();
        scen_end("LR-03");

        scen_start();
        do_row(6'd40, lrc_mem[9 + 2*4] & 16'hFFFF, lrc_mem[9 + 2*4] >> 16, 5'd16, 24'd10000000);
        chk_row(3, 6'd40, 24);                            // ★ bank 1 + 全是汉字（2 字/字 ✓）
        chkint("bursts", 24, mon_bursts);
        prot_checks();
        $display("  LR-04 fc!=0 (char_off honored) + bank1 OK");
        scen_end("LR-04");

        scen_start();
        do_row(6'd0,  lrc_mem[9 + 2*44] & 16'hFFFF, lrc_mem[9 + 2*44] >> 16, 5'd30, 24'd14000000);
        chk_row(4, 6'd0, 14);
        chkint("bursts", 14, mon_bursts);                 // 7 字 × 2 笔 ✓
        chkint("words",  56, mon_words);                  // ★ p3-lean：7×(4+4) ✓
        prot_checks();
        $display("  LR-05 last-line grow30 OK");
        scen_end("LR-05");

        //---------------------------------------------------------------------
        // LR-06：再渲染一次同一行（**可重复触发 ✓ 幂等 ✓**）—— 边界：连续两次不能串味 ✓
        //---------------------------------------------------------------------
        scen_start();
        do_row(6'd0, lrc_mem[9] & 16'hFFFF, lrc_mem[9] >> 16, 5'd16, 24'd18960);
        chk_row(0, 6'd0, 17);
        do_row(6'd40, lrc_mem[9] & 16'hFFFF, lrc_mem[9] >> 16, 5'd16, 24'd18960);
        chk_row(0, 6'd40, 17);
        prot_checks();
        scen_end("LR-06");

        //---------------------------------------------------------------------
        // LR-07：cnt = 21（超硬上限 ✗）⇒ err=0x66 / nw=0 / **一笔读都不发** ✓
        //---------------------------------------------------------------------
        scen_start();
        do_row(6'd0, 16'd0, 16'd21, 5'd16, 24'd0);
        chkint("err21",  16'h66, err);
        chkint("nw21",   0, nw);
        chkint("busy21", 0, busy);
        chkint("burst21",0, mon_bursts);
        prot_checks();
        scen_end("LR-07");

        //---------------------------------------------------------------------
        // LR-08：cnt = 0（空行 ✓ 不算错 ✓）⇒ nw=0 且不发请求 ✓
        //---------------------------------------------------------------------
        scen_start();
        do_row(6'd0, 16'd0, 16'd0, 5'd16, 24'd0);
        chkint("err0c",  0, err);
        chkint("nw0c",   0, nw);
        chkint("burst0c",0, mon_bursts);
        prot_checks();
        scen_end("LR-08");

        //---------------------------------------------------------------------
        // LR-09：码非法（注入 qu=0x50 < 0xA1 ✗）⇒ err=0x66 / 一个字都不写 ✓
        //---------------------------------------------------------------------
        scen_start();
        lrc_mem[136] = 32'h00001050;              // 第 0 个字的码 = 0x5010（非法 ✓）
        do_row(6'd0, 16'd0, 16'd1, 5'd16, 24'd0);
        chkint("errbad",  16'h66, err);
        chkint("nwbad",   0, nw);
        chkint("untouched_bad", 1, (wmem[0] === SENT));
        $readmemh("../music_screen_area_opt/sim/golden/S01_lrc_tab.mem", lrc_mem);   // 还原 ✓
        prot_checks();
        scen_end("LR-09");

        //---------------------------------------------------------------------
        // LR-10：读不出来（模型完全不响应）⇒ 看门狗 err=0x04 / done 照出 / busy 释放 ✓
        //---------------------------------------------------------------------
        scen_start();
        px_off = 1;
        do_row(6'd0, lrc_mem[9] & 16'hFFFF, lrc_mem[9] >> 16, 5'd16, 24'd18960);
        chkint("err_to",  16'h04, err);
        chkint("nw_to",   0, nw);
        chkint("busy_to", 0, busy);
        px_off = 0;
        do_row(6'd0, lrc_mem[9] & 16'hFFFF, lrc_mem[9] >> 16, 5'd16, 24'd18960);  // 恢复后正常 ✓
        chk_row(0, 6'd0, 17);
        prot_checks();
        scen_end("LR-10");

        //---------------------------------------------------------------------
        // LR-11：突发被截短（2 字的字记录只发 1 字 ✗）⇒ err=0x04 ✓
        //---------------------------------------------------------------------
        scen_start();
        px_cut = 1;
        do_row(6'd0, lrc_mem[9] & 16'hFFFF, lrc_mem[9] >> 16, 5'd16, 24'd18960);
        chkint("err_cut",  16'h04, err);
        chkint("nw_cut",   0, nw);
        px_cut = 0;
        do_row(6'd0, lrc_mem[9] & 16'hFFFF, lrc_mem[9] >> 16, 5'd16, 24'd18960);
        chk_row(0, 6'd0, 17);
        prot_checks();
        scen_end("LR-11");

        //---------------------------------------------------------------------
        // LR-12：★ **19/20 边界**（口径 3/10：19 字为上限 ✓ >19 就不画 ✓）
        //   `design:753` 原写 20 ✗ 已被口径改掉（20×32=640px = 满屏 0 边距 ✗）
        //   19 字 ⇒ 正常画（nw=19 或 38 ✓）；20 字 ⇒ `err=0x66` / 零请求 ✓
        //   （本场景用真素材的 cnt=12 行改不了 ⇒ 用 `cnt=19` 走"合法"路径的**边界**：
        //    这里只验 19 与 20 的分界，不比 golden ✓ 因为是同一批量下界抽查 ✓）
        //---------------------------------------------------------------------
        scen_start();
        do_row(6'd0, lrc_mem[9] & 16'hFFFF, 16'd19, 5'd16, 24'd18960);
        chkint("err19",  0, err);
        chkint("nw19_between", 1, ((nw >= 6'd19) && (nw <= 6'd38)) ? 1 : 0);
        do_row(6'd0, lrc_mem[9] & 16'hFFFF, 16'd20, 5'd16, 24'd18960);
        chkint("err20",  16'h66, err);
        chkint("nw20",   0, nw);
        prot_checks();
        $display("  LR-12 cnt 19/20 boundary (19 draws, 20 refuses) OK");
        scen_end("LR-12");

        // ★★ T-14 收口：防空跑 + 打印定律守卫的覆盖与结果
        //   （阈值取 20：本台每渲染一行 = 字数 × 2 笔突发，正常一轮远超 20 ✓；
        //     若哪天"一笔都没发"，这里必须失败 —— 否则 `prot_len4/align == 0` 是废话 ✓）
        if (mon_bursts_all < 20) begin
            $display("TEST_FAIL PROT_TXT_LEN vacuous: only %0d bursts checked", mon_bursts_all);
            $finish;
        end
        $display("PROT_TXT_LEN bursts=%0d all_len_ge4=%0d all_aligned=%0d",
                 mon_bursts_all,
                 (mon_lenlt4 == 0) ? 1 : 0,
                 (mon_unalign == 0) ? 1 : 0);

        $display("TEST_PASS");
        $finish;
    end

    initial begin
        #200000000;
        $display("TEST_FAIL global watchdog timeout at %0t", $time);
        $finish;
    end

    reg [8*128-1:0] vcd_file;
    initial begin
        if ($value$plusargs("VCD=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_lyric_row);
        end
    end

endmodule

`default_nettype wire
