`timescale 1ns/1ps
`default_nettype none
//============================================================================
// tb/tb_font_load.v —— `font_load` 单元层自检 TB（P3/S2）
//
// 层级：**单元层**（HANDOVER §11）—— 用 `$fread` 直喂**真字库文件**，**不经 FAT32** ✓
//
// 两个"外设响应模型"（都不是 DUT 内部状态 ✓，语义照 `bmp_load` 的 TB 与实测契约）：
//   ① lo 字节流模型（clk 域）
//        · `lo_open` 单拍脉冲 ⇒ 延迟 `src_wait` 拍后供字节（模拟开卡/FAT 查找 ✓）
//        · `valid` 保持到 `ready`（`fat32_read.v:244` ✓）
//        · `lo_rd_eof` 是**单拍脉冲**，且只在"数据已供完、DUT 又来取"的那一拍发 ✓
//          （★ 这条很关键：若不等 DUT 来取就白送 eof，就**测不出**"必须读干净"的契约 ✗）
//        · `lo_rd_err` 是**电平**（`storage_top.v:744` ✓）
//   ② ld 突发响应模型（clk_sdr 域），照 `sdram_arb.v` 客户端时序
//        · `ld_req` 电平 ⇒ 下一拍 `ld_ack`(1 拍) **并同拍开始取数**
//        · `ld_rd` 高 `len` 拍（第一拍 = ack 拍）；`ld_done` = 最后一个取数拍的下一拍
//        · 取走的值 = 当拍 `ld_data`（**FWFT** ✓）⇒ 写进 `cap_mem` 并与 golden 逐字比 ✓
//
// 判据来源：`tb/expected_scenarios_font_load.json`（FF-01..FF-07 ✓）
// 每个场景过打 `SCENARIO_PASS <id>`，全过才打一次 `TEST_PASS` ✓
//
// ★ golden 的**独立性**（这条很重要 ✓）：
//   · FF-01/FF-02 的 golden 是 **PC 侧脚本**（`scripts/mk_slot_golden.py`）生成的
//     `sim/golden/FONT_slot.mem` / `ASC_slot.mem` ⇒ 与 TB 自己的打包逻辑**无关** ✓
//     （能抓"字节序/地址错"这类共因错 ✗）；
//   · FF-03 的 golden 由本 TB 现场生成 —— 它专测**补零与对齐**，不是测打包 ✓（已在注释里写明 ✓）。
//
// VCD：默认关；只有 `+VCD=<path>` 时 dump ✓
//============================================================================
module tb_font_load;

    //=========================================================================
    // 参数 / 规模
    //=========================================================================
    localparam integer CLK_HZ = 50000000;
    // ★ TB 里把看门狗压到 1ms（RTL 默认 2500ms）：合法"无进展"间隔只有几十拍，
    //   而 FF-06 的超时路径只要 ~1ms 就能验完 ✓（默认值行为由 RTL 参数保证 ✓）
    localparam integer WD_MS  = 1;
    localparam integer SRCW   = 1046784;     // ≥ FONT.HZK 1,046,784 B
    localparam integer WORDW  = 262144;      // ≥ 261,696 字（FONT 槽内字数 ✓）
    localparam integer TMO    = 4000000;     // 等待上限（clk 拍）

    // 真素材路径（相对 music_screen/ ✓，与 tb_bmp_load 同风格）
    localparam [8*64-1:0] P_FONT = "card/FONT.HZK";
    localparam [8*64-1:0] P_ASC  = "card/ASC.HZK";
    localparam [8*64-1:0] G_FONT = "../music_screen_area_opt/sim/golden/FONT_slot.mem";
    localparam [8*64-1:0] G_ASC  = "../music_screen_area_opt/sim/golden/ASC_slot.mem";

    // 槽基址（`p2_sdram_map_and_traffic_plan.md:74-75` ✓）
    localparam [20:0] FONT_BASE = 21'h13EC00;
    localparam [20:0] ASC_BASE  = 21'h17EA40;

    //=========================================================================
    // 时钟 / 复位
    //=========================================================================
    reg clk     = 1'b0;
    reg clk_sdr = 1'b0;
    always #10    clk     = ~clk;                  // 50MHz
    always #3.333 clk_sdr = ~clk_sdr;              // 150MHz

    reg rst_n     = 1'b0;
    reg rst_sdr_n = 1'b0;

    //=========================================================================
    // DUT
    //=========================================================================
    reg         start      = 1'b0;
    reg  [7:0]  file_index = 8'd0;
    reg  [20:0] slot_base  = 21'd0;
    reg  [31:0] byte_len   = 32'd0;
    wire        busy;
    wire        done;
    wire [7:0]  err;
    wire [31:0] nbytes;

    wire        lo_open;
    wire [7:0]  lo_open_index;
    reg         lo_open_busy = 1'b0;
    reg         lo_rd_valid  = 1'b0;
    reg  [7:0]  lo_rd_data   = 8'd0;
    wire        lo_rd_ready;
    wire        lo_want;
    reg         lo_rd_eof    = 1'b0;
    reg         lo_rd_err    = 1'b0;
    reg  [31:0] file_size_r  = 32'd0;

    wire        ld_req;
    wire [20:0] ld_addr;
    wire [15:0] ld_len;
    wire [31:0] ld_data;
    reg         ld_rd   = 1'b0;
    reg         ld_ack  = 1'b0;
    reg         ld_done = 1'b0;

    font_load #(
        .CLK_HZ(CLK_HZ),
        .WD_MS (WD_MS)
    ) u_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .file_index    (file_index),
        .slot_base     (slot_base),
        .byte_len      (byte_len),
        .busy          (busy),
        .done          (done),
        .err           (err),
        .nbytes        (nbytes),
        .lo_open       (lo_open),
        .lo_open_index (lo_open_index),
        .lo_open_busy  (lo_open_busy),
        .lo_rd_valid   (lo_rd_valid),
        .lo_rd_data    (lo_rd_data),
        .lo_rd_ready   (lo_rd_ready),
        .lo_want       (lo_want),
        .lo_rd_eof     (lo_rd_eof),
        .lo_rd_err     (lo_rd_err),
        .file_size     (file_size_r),
        .clk_sdr       (clk_sdr),
        .rst_sdr_n     (rst_sdr_n),
        .ld_req        (ld_req),
        .ld_addr       (ld_addr),
        .ld_len        (ld_len),
        .ld_data       (ld_data),
        .ld_rd         (ld_rd),
        .ld_ack        (ld_ack),
        .ld_done       (ld_done)
    );

    //=========================================================================
    // 工具变量
    //=========================================================================
    integer scen_fail = 0;
    integer i;
    integer w;
    integer tmo;
    integer residue;

    reg [7:0]  src_mem [0:SRCW-1];        // lo 侧字节源（$fread 真文件 / 或现场合成 ✓）
    reg [31:0] gold_mem[0:WORDW-1];       // golden 字（$readmemh ✓）
    reg [31:0] cap_mem [0:WORDW-1];       // 实际被 ld 取走的字 ✓
    reg  [7:0] cap_gen [0:WORDW-1];       // 每个地址最后一次被写的"代"号 ✓
    reg  [7:0] gen = 8'd0;

    integer src_n     = 0;                // 本次 lo 模型能供的字节数
    integer inj_err_at= -1;               // ≥0：在该交付序号处把 lo_rd_err 拉成电平
    integer src_wait  = 6;                // lo_open 之后的开卡延迟（拍）
    integer ld_delay  = 0;                // ack 前额外等待拍数（模拟被像素客户抢占 ✓）
    integer ld_stuck  = 0;                // 1 = 永不 ack（看门狗场景 ✓）

    reg  [31:0] fsize_shown = 32'd0;      // 给 DUT 的 file_size（可故意写大 ⇒ 测"文件太短" ✓）
    integer     fsize_actual = 0;
    integer     exp_words = 0;            // 本场景期望写入的字数（上限口径 ✓）
    reg         cmp_en    = 1'b0;         // 是否与 golden 逐字比
    integer     cmp_errs  = 0;
    integer     mis_model = 0;
    integer     cmp_first_idx = -1;
    reg  [31:0] cmp_first_exp = 32'd0;
    reg  [31:0] cmp_first_got = 32'd0;

    //=========================================================================
    // ① lo 字节流模型（clk 域）
    //=========================================================================
    localparam [1:0] L_IDLE = 2'd0, L_DELAY = 2'd1, L_STREAM = 2'd2, L_WERR = 2'd3;
    reg  [1:0] ls = L_IDLE;
    integer    di = 0;                    // 已交付字节数
    integer    waitc = 0;
    reg        err_lvl = 1'b0;

    always @(posedge clk) begin
        if (!rst_n) begin
            ls <= L_IDLE; lo_open_busy <= 1'b0; lo_rd_valid <= 1'b0; lo_rd_data <= 8'd0;
            lo_rd_eof <= 1'b0; lo_rd_err <= 1'b0; di <= 0; waitc <= 0; err_lvl <= 1'b0;
        end else begin
            lo_rd_eof <= 1'b0;                       // 单拍脉冲 ✓
            lo_rd_err <= err_lvl;                    // 电平 ✓
            case (ls)
            L_IDLE: begin
                lo_open_busy <= 1'b0;
                lo_rd_valid  <= 1'b0;
                if (lo_open) begin
                    ls    <= L_DELAY;
                    waitc <= src_wait;
                    di    <= 0;
                end
            end
            L_DELAY: begin
                lo_open_busy <= 1'b1;                // 开卡/FAT 查找期间 busy=1 ✓
                if (waitc != 0) waitc <= waitc - 1;
                else            ls    <= L_STREAM;
            end
            L_STREAM: begin
                lo_open_busy <= 1'b1;
                if ((inj_err_at >= 0) && (di >= inj_err_at)) begin
                    err_lvl     <= 1'b1;             // 注入 lo 错误（电平，保持 ✓）
                    lo_rd_valid <= 1'b0;
                    ls          <= L_WERR;
                end else if (di >= src_n) begin
                    // ★ 数据供完了：**只在 DUT 真的来取时**才给 eof 单拍脉冲 ✓
                    //   给完 eof 就把 busy 放回 0（= storage_top 回到 T_READY ✓）
                    //   —— 第一版忘了放 0，下一个场景永远开不了卡 ✗（2026-10-05 实测 ✓）
                    lo_rd_valid <= 1'b0;
                    if (lo_rd_ready) begin
                        lo_rd_eof <= 1'b1;
                        ls        <= L_IDLE;
                    end
                end else if (!lo_rd_valid) begin
                    lo_rd_valid <= 1'b1;
                    lo_rd_data  <= src_mem[di];
                end else if (lo_rd_ready) begin
                    di <= di + 1;
                    if ((di + 1) < src_n) lo_rd_data <= src_mem[di + 1];
                    else                  lo_rd_valid <= 1'b0;
                end
            end
            L_WERR: begin
                // 错误是**电平**（下次 lo_accept 才清 ✓）：DUT 停止取数即视为流结束 ✓
                lo_open_busy <= 1'b1;
                lo_rd_valid  <= 1'b0;
                if (!lo_rd_ready) ls <= L_IDLE;
            end
            default: ls <= L_IDLE;
            endcase
        end
    end

    //=========================================================================
    // ② ld 突发响应模型（clk_sdr 域）+ 协议检查 + 抓取/golden 比对
    //=========================================================================
    localparam [2:0] LD_IDLE = 3'd0, LD_WAIT = 3'd1, LD_TAKE = 3'd2, LD_STUCK = 3'd3;
    reg  [2:0]  ld_state = LD_IDLE;
    reg  [20:0] cur_addr = 21'd0;
    reg  [15:0] cur_len  = 16'd0;
    integer     take_k   = 0;
    integer     ackw     = 0;
    integer     wr_cnt     = 0;
    integer     burst_cnt  = 0;
    integer     prot_len0    = 0;
    integer     prot_align   = 0;      // 突发长度不是 4 的倍数（会需要 write mask ✗）
    integer     prot_reqlate = 0;      // ack 后 req 没撤
    integer     prot_dmove   = 0;      // 等 ack 期间 addr/len/req/data 变动
    integer     anom_cnt     = 0;      // 地址不连续（第一笔之外 ✓）
    reg  [20:0] prev_end  = 21'd0;
    reg         have_prev = 1'b0;
    reg         req_prev  = 1'b0;
    reg         ack_prev  = 1'b0;
    reg  [31:0] rc_first  = 32'd0;
    reg         rc_have   = 1'b0;

    always @(posedge clk_sdr) begin
        if (!rst_sdr_n) begin
            ld_ack <= 1'b0; ld_rd <= 1'b0; ld_done <= 1'b0; ld_state <= LD_IDLE;
            take_k <= 0; ackw <= 0; rc_have <= 1'b0; req_prev <= 1'b0; ack_prev <= 1'b0;
        end else begin
            ld_ack  <= 1'b0;                       // ack/done 都是单拍 ✓
            ld_done <= 1'b0;
            ack_prev <= ld_ack;
            if (ld_req && ack_prev) prot_reqlate <= prot_reqlate + 1;   // ack 后必须撤 req ✓

            case (ld_state)
            LD_IDLE: begin
                if (ld_req) begin
                    burst_cnt <= burst_cnt + 1;
                    if (ld_len == 16'd0)     prot_len0  <= prot_len0 + 1;
                    if (ld_len[1:0] != 2'd0) prot_align <= prot_align + 1;
                    if (have_prev && (ld_addr !== prev_end)) begin
                        anom_cnt <= anom_cnt + 1;
                        if (anom_cnt < 6)
                            $display("ADDR_ANOM n=%0d addr=%06X exp=%06X len=%0d",
                                     anom_cnt, ld_addr, prev_end, ld_len);
                    end
                    prev_end  <= ld_addr + {5'd0, ld_len};
                    have_prev <= 1'b1;
                    cur_addr  <= ld_addr;
                    cur_len   <= ld_len;
                    take_k    <= 0;
                    if (ld_stuck) begin
                        ld_state <= LD_STUCK;
                    end else begin
                        ackw     <= ld_delay;
                        rc_have  <= 1'b0;
                        rc_first <= ld_data;
                        ld_state <= LD_WAIT;
                    end
                end
            end
            // 等 ack 期间：req/addr/len/数据都必须稳住 ✓
            LD_WAIT: begin
                if (ld_addr !== cur_addr) prot_dmove <= prot_dmove + 1;
                if (ld_len  !== cur_len)  prot_dmove <= prot_dmove + 1;
                if (ld_req  !== req_prev) prot_dmove <= prot_dmove + 1;
                if (!rc_have) begin rc_have <= 1'b1; rc_first <= ld_data; end
                else if (ld_data !== rc_first) prot_dmove <= prot_dmove + 1;
                if (ackw != 0) begin
                    ackw <= ackw - 1;
                end else begin
                    ld_ack   <= 1'b1;              // ack 拍 = 第一个取数拍 ✓
                    ld_rd    <= 1'b1;
                    ld_state <= LD_TAKE;
                end
            end
            LD_TAKE: begin
                // 本拍取走一个字：取的就是当拍 ld_data（FWFT ✓）
                if ((cur_addr + take_k) >= slot_base) begin
                    cap_mem[cur_addr + take_k - slot_base] <= ld_data;
                    cap_gen[cur_addr + take_k - slot_base] <= gen;
                    wr_cnt <= wr_cnt + 1;
                end
                if (cmp_en == 1) begin
                    if ((cur_addr + take_k) >= slot_base) begin
                        if (ld_data !== gold_mem[cur_addr + take_k - slot_base]) begin
                            cmp_errs <= cmp_errs + 1;
                            mis_model = mis_model + 1;
                            if (mis_model < 8)
                                $display("MODEL_MIS #%0d addr=%06X got=%08X gold=%08X",
                                         mis_model, cur_addr + take_k, ld_data,
                                         gold_mem[cur_addr + take_k - slot_base]);
                            if (cmp_first_idx < 0) begin
                                cmp_first_idx <= cur_addr + take_k - slot_base;
                                cmp_first_exp <= gold_mem[cur_addr + take_k - slot_base];
                                cmp_first_got <= ld_data;
                            end
                        end
                    end
                end
                if ((take_k + 1) >= cur_len) begin
                    ld_rd    <= 1'b0;
                    ld_done  <= 1'b1;              // = sdram_arb：最后一个取数拍的下一拍 ✓
                    ld_state <= LD_IDLE;
                end else begin
                    take_k <= take_k + 1;
                end
            end
            LD_STUCK: begin
                // Resume the already captured request; do not count it twice.
                if (!ld_stuck) begin
                    ackw <= ld_delay;
                    rc_have <= 1'b0;
                    rc_first <= ld_data;
                    ld_state <= LD_WAIT;
                end
            end
            default: ld_state <= LD_IDLE;
            endcase
            req_prev <= ld_req;
        end
    end

    //=========================================================================
    // "真的动过"证据（HANDOVER 铁律 12）
    //=========================================================================
    integer   mv_open = 0, mv_want = 0, mv_ready = 0, mv_done = 0, mv_req = 0;
    reg [7:0] seen_open_index = 8'hFF;

    always @(posedge clk) begin
        if (lo_open) begin
            mv_open <= mv_open + 1;
            seen_open_index <= lo_open_index;
        end
        if (lo_want)     mv_want  <= mv_want + 1;
        if (lo_rd_ready) mv_ready <= mv_ready + 1;
        if (done)        mv_done  <= mv_done + 1;
    end
    always @(posedge clk_sdr) if (ld_req) mv_req <= mv_req + 1;

    //=========================================================================
    // 任务
    //=========================================================================
    task chk32;
        input [8*32-1:0] tag;
        input [31:0]     exp;
        input [31:0]     got;
        begin
            if (exp !== got) begin
                scen_fail = scen_fail + 1;
                $display("  CHECK_FAIL %0s exp=%08X got=%08X", tag, exp, got);
            end
        end
    endtask

    task chkint;
        input [8*32-1:0] tag;
        input integer    exp;
        input integer    got;
        begin
            if (exp !== got) begin
                scen_fail = scen_fail + 1;
                $display("  CHECK_FAIL %0s exp=%0d got=%0d", tag, exp, got);
            end
        end
    endtask

    // 读真素材进 src_mem
    task load_src;
        input [8*64-1:0] path;
        integer fd;
        begin
            fd = $fopen(path, "rb");
            if (fd == 0) begin
                $display("TEST_FAIL cannot open %0s", path);
                $finish;
            end
            fsize_actual = $fread(src_mem, fd);
            $fclose(fd);
        end
    endtask

    // 现场合成源（给 FF-03 用 ✓；专测补零/对齐，不测打包 ✓）
    task gen_src;
        input integer n;
        begin
            for (i = 0; i < n; i = i + 1) src_mem[i] = i[7:0] ^ 8'h5A;
        end
    endtask

    task cap_begin;
        input integer    nwords;
        input [8*64-1:0] gpath;
        input integer    use_gold;
        begin
            gen       = gen + 8'd1;
            wr_cnt    = 0;
            burst_cnt = 0;
            cmp_errs  = 0;
            mis_model = 0;
            prot_len0 = 0;
            prot_align= 0;
            prot_reqlate = 0;
            prot_dmove   = 0;
            anom_cnt  = 0;
            have_prev = 1'b0;
            cmp_first_idx = -1;
            cmp_en    = use_gold;
            exp_words = nwords;
            if (use_gold) $readmemh(gpath, gold_mem);
        end
    endtask

    // 起一次装载并等 done（negedge 采样 ⇒ 不漏单拍脉冲、无采样竞争 ✓）
    task do_load;
        input [7:0]  fidx;
        input [20:0] sbase;
        input [31:0] blen;
        input integer tmol;
        begin
            file_index  = fidx;
            slot_base   = sbase;
            byte_len    = blen;
            file_size_r = fsize_shown;
            @(negedge clk);
            mv_open = 0; mv_want = 0; mv_ready = 0; mv_done = 0;
            mv_req  = 0;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            w = 0;
            while ((done !== 1'b1) && (w < tmol)) begin
                @(negedge clk);
                w = w + 1;
            end
            if (done !== 1'b1) begin
                $display("TEST_FAIL scenario timeout: busy=%b err=%02X waited=%0d", busy, err, w);
                $display("  DUT st=%0d bst=%0d wdone=%0d a_words=%0d stop=%0d wr_bytes=%0d rdu=%0d",
                         u_dut.st, u_dut.g_standalone.u_writeback.bst, u_dut.g_standalone.u_writeback.wdone, u_dut.a_words, u_dut.g_standalone.u_writeback.stop_words,
                         u_dut.wr_bytes, u_dut.g_standalone.u_writeback.u_fifo.rdusedw);
                $display("  TB  ld_state=%0d cur_len=%0d take_k=%0d ld_req=%b ld_ack=%b",
                         ld_state, cur_len, take_k, ld_req, ld_ack);
                $finish;
            end
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    // 统一判据
    task check_load;
        input [8*28-1:0] id;
        input [7:0]      exp_err;
        input integer    exp_wcnt_min;      // 至少写了这么多字（错误路径用 ✓）
        input integer    need_burst;
        begin
            chk32({id, "_err"},   {24'd0, exp_err}, {24'd0, err});
            chk32({id, "_busy"},  32'd0, {31'd0, busy});
            chk32({id, "_done"},  32'd1, {31'd0, mv_done});
            chk32({id, "_open#"}, 32'd1, mv_open);
            if (mv_want < 1) begin
                scen_fail = scen_fail + 1;
                $display("  CHECK_FAIL %0s lo_want never high", id);
            end
            if (mv_ready < 1) begin
                scen_fail = scen_fail + 1;
                $display("  CHECK_FAIL %0s lo_rd_ready never high", id);
            end
            chkint({id, "_len0"},  0, prot_len0);
            chkint({id, "_align"}, 0, prot_align);      // ★ 突发恒为 4 的倍数 ✓
            chkint({id, "_reqlate"}, 0, prot_reqlate);
            chkint({id, "_dmove"},   0, prot_dmove);
            chkint({id, "_anom"},    0, anom_cnt);      // 地址线性连续 ✓
            chkint({id, "_mis"},     0, mis_model);
            if (need_burst) begin
                if (burst_cnt < 1) begin
                    scen_fail = scen_fail + 1;
                    $display("  CHECK_FAIL %0s no ld burst", id);
                end
                if (wr_cnt < exp_wcnt_min) begin
                    scen_fail = scen_fail + 1;
                    $display("  CHECK_FAIL %0s wr_cnt=%0d < %0d", id, wr_cnt, exp_wcnt_min);
                end
                if (wr_cnt > exp_words) begin
                    scen_fail = scen_fail + 1;
                    $display("  CHECK_FAIL %0s wr_cnt=%0d > exp_words=%0d", id, wr_cnt, exp_words);
                end
            end
            $display("  %0s: err=%02X wr=%0d burst=%0d/%0d bytes=%0d mis=%0d",
                     id, err, wr_cnt, burst_cnt, mv_req, nbytes, mis_model);
        end
    endtask

    task scen_start;
        begin
            scen_fail  = 0;
            inj_err_at = -1;
            ld_delay   = 0;
            ld_stuck   = 0;
            err_lvl    = 1'b0;
            seen_open_index = 8'hFF;
        end
    endtask

    task scen_end;
        input [8*24-1:0] id;
        begin
            if (scen_fail == 0) begin
                $display("SCENARIO_PASS %0s", id);
            end else begin
                $display("TEST_FAIL %0s: %0d check(s) failed", id, scen_fail);
                $finish;
            end
        end
    endtask

    // 错误路径后复位一次，避免把"卡住的残留请求"带进下一个场景 ✓（同 tb_bmp_load ✓）
    task pulse_reset;
        begin
            rst_n = 1'b0; rst_sdr_n = 1'b0;
            repeat (10) @(negedge clk);
            rst_n = 1'b1; rst_sdr_n = 1'b1;
            repeat (20) @(negedge clk);
        end
    endtask

    //=========================================================================
    // 场景
    //=========================================================================
    initial begin
        rst_n = 1'b0; rst_sdr_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_sdr_n = 1'b1;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        //---------------------------------------------------------------------
        // FF-01 真字库全量：FONT.HZK 1,046,784 B → 261,696 字（golden 独立 ✓）
        //---------------------------------------------------------------------
        scen_start();
        load_src(P_FONT);
        chkint("FF01_srcsize", 1046784, fsize_actual);
        fsize_shown = fsize_actual;
        src_n       = fsize_actual;
        cap_begin(261696, G_FONT, 1);
        do_load(8'd5, FONT_BASE, 32'd1046784, TMO);
        chk32("FF01_nbytes", 32'd1046784, nbytes);
        chkint("FF01_wr",    261696, wr_cnt);
        chk32("FF01_openidx", 32'd5, {24'd0, seen_open_index});
        check_load("FF01_font_full", 8'h00, 261696, 1);
        scen_end("FF-01");

        //---------------------------------------------------------------------
        // FF-02 真字库小文件：ASC.HZK 6,144 B → 1,536 字（golden 独立 ✓）
        //---------------------------------------------------------------------
        scen_start();
        load_src(P_ASC);
        chkint("FF02_srcsize", 6144, fsize_actual);
        fsize_shown = fsize_actual;
        src_n       = fsize_actual;
        cap_begin(1536, G_ASC, 1);
        do_load(8'd6, ASC_BASE, 32'd6144, TMO);
        chk32("FF02_nbytes", 32'd6144, nbytes);
        chkint("FF02_wr",    1536, wr_cnt);
        check_load("FF02_asc_full", 8'h00, 1536, 1);
        scen_end("FF-02");

        //---------------------------------------------------------------------
        // FF-03 非 16B 对齐：402 B ⇒ 补零到 416 B ⇒ 104 字（尾部 3 字全 0 ✓）
        //      ★ 本场景的 golden 由 TB 现场按**补零规则**生成（专测补零/对齐 ✓）
        //---------------------------------------------------------------------
        scen_start();
        gen_src(402);
        src_n       = 402;
        fsize_shown = 32'd402;
        cap_begin(104, G_ASC, 0);            // ★ 先 cap_begin（它会清计数器），再填现场 golden ✓
        for (i = 0; i < 104; i = i + 1) begin
            gold_mem[i] = {(4*i+3 < 402) ? src_mem[4*i+3] : 8'h00,
                           (4*i+2 < 402) ? src_mem[4*i+2] : 8'h00,
                           (4*i+1 < 402) ? src_mem[4*i+1] : 8'h00,
                           (4*i+0 < 402) ? src_mem[4*i+0] : 8'h00};
        end
        cmp_en = 1'b1;                       // 用现场 golden ✓（打包正确性由 FF-01/02 独立 golden 保证 ✓）
        do_load(8'd7, 21'h100000, 32'd402, TMO);
        chk32("FF03_nbytes", 32'd416, nbytes);
        chkint("FF03_wr",    104, wr_cnt);
        chk32("FF03_last3", 32'd0, cap_mem[103]);
        check_load("FF03_pad16", 8'h00, 104, 1);
        scen_end("FF-03");

        //---------------------------------------------------------------------
        // FF-04 文件太短：声称 1100 B、实际只有 1000 B ⇒ 提前 eof ⇒ err=0x03 ✓
        //---------------------------------------------------------------------
        scen_start();
        gen_src(1000);
        src_n       = 1000;
        fsize_shown = 32'd1100;
        cap_begin(275, G_ASC, 0);
        do_load(8'd8, 21'h101000, 32'd1100, TMO);
        chk32("FF04_err", 8'h03, err);
        check_load("FF04_short", 8'h03, 0, 1);
        scen_end("FF-04");

        //---------------------------------------------------------------------
        // FF-05 lo 中途报错（电平）⇒ err=0x04 ✓ 不卡死 ✓
        //---------------------------------------------------------------------
        scen_start();
        gen_src(40000);
        src_n       = 40000;
        fsize_shown = 32'd40000;
        inj_err_at  = 5000;
        cap_begin(10000, G_ASC, 0);
        do_load(8'd9, 21'h102000, 32'd40000, TMO);
        chk32("FF05_err", 8'h04, err);
        check_load("FF05_loerr", 8'h04, 0, 1);
        scen_end("FF-05");

        //---------------------------------------------------------------------
        // FF-06 ld 从不 ack ⇒ 看门狗 ⇒ err=0x04 ✓ done 必须出 ✓
        //---------------------------------------------------------------------
        scen_start();
        gen_src(20000);
        src_n       = 20000;
        fsize_shown = 32'd20000;
        ld_stuck    = 1;
        cap_begin(5000, G_ASC, 0);
        fork
            do_load(8'd10, 21'h103000, 32'd20000, TMO);
            begin
                repeat (60000) @(negedge clk);
                if (!busy || done || !ld_req || u_dut.err_hold !== 8'h04) begin
                    $display("TEST_FAIL FONT released an unacknowledged write"); $finish;
                end
                ld_stuck = 0;
            end
        join
        chk32("FF06_err", 8'h04, err);
        check_load("FF06_stuck", 8'h04, 0, 0);
        scen_end("FF-06");
        ld_stuck = 0;
        repeat (50) @(negedge clk);
        pulse_reset();                       // 清掉卡住的残留请求 ✓

        //---------------------------------------------------------------------
        // FF-07 参数非法：byte_len=0 ⇒ err=0x02 ✓ **一次都不碰 lo** ✓
        //---------------------------------------------------------------------
        scen_start();
        gen_src(64);
        src_n       = 64;
        fsize_shown = 32'd64;
        cap_begin(16, G_ASC, 0);
        do_load(8'd11, 21'h104000, 32'd0, TMO);
        chk32("FF07_err",  8'h02, err);
        chk32("FF07_noopen", 32'd0, mv_open);        // ★ 不打扰 storage ✓
        chk32("FF07_nbytes", 32'd0, nbytes);
        scen_end("FF-07");

        // Copy a prefix, pad it, then drain the longer file. The drain bytes
        // must never change the published byte count or reach the write FIFO.
        scen_start();
        gen_src(4103);
        src_n = 4103;
        fsize_shown = 32'd4103;
        cap_begin(104, G_ASC, 0);
        for (i = 0; i < 104; i = i + 1) begin
            gold_mem[i] = {(4*i+3 < 402) ? src_mem[4*i+3] : 8'h00,
                           (4*i+2 < 402) ? src_mem[4*i+2] : 8'h00,
                           (4*i+1 < 402) ? src_mem[4*i+1] : 8'h00,
                           (4*i+0 < 402) ? src_mem[4*i+0] : 8'h00};
        end
        cmp_en = 1'b1;
        ld_delay = 73;
        do_load(8'd12, 21'h104000, 32'd402, TMO);
        chk32("FF08_nbytes", 32'd416, nbytes);
        chkint("FF08_drained", 4103, di);
        chkint("FF08_words", 104, wr_cnt);
        check_load("FF08_prefix_drain", 8'h00, 104, 1);
        scen_end("FF-08");

        // Advertised EOF boundary precedes the physical EOF: reject as short,
        // pad only accepted bytes, and still drain every remaining source byte.
        scen_start();
        gen_src(4103);
        src_n = 4103;
        fsize_shown = 32'd402;
        cap_begin(104, G_ASC, 0);
        do_load(8'd13, 21'h104000, 32'd1000, TMO);
        chk32("FF09_nbytes", 32'd416, nbytes);
        chkint("FF09_drained", 4103, di);
        check_load("FF09_size_boundary", 8'h03, 104, 1);
        scen_end("FF-09");

        // All byte residues, including boundaries and a second 16-byte group.
        // Repeat without resetting to exercise the next transaction as well.
        scen_start();
        for (residue = 1; residue <= 33; residue = residue + 1) begin
            gen_src(96);
            src_n = 96;
            fsize_shown = 32'd96;
            cap_begin(((residue+15)/16)*4, G_ASC, 0);
            for (i = 0; i < exp_words; i = i + 1) begin
                gold_mem[i] = {(4*i+3 < residue) ? src_mem[4*i+3] : 8'h00,
                               (4*i+2 < residue) ? src_mem[4*i+2] : 8'h00,
                               (4*i+1 < residue) ? src_mem[4*i+1] : 8'h00,
                               (4*i+0 < residue) ? src_mem[4*i+0] : 8'h00};
            end
            cmp_en = 1'b1;
            do_load(8'd14, 21'h104000, residue, TMO);
            chk32("FF10_nbytes", ((residue+15)/16)*16, nbytes);
            chkint("FF10_drained", 96, di);
            chkint("FF10_words", exp_words, wr_cnt);
            check_load("FF10_residue", 8'h00, exp_words, 1);
        end
        scen_end("FF-10");

        $display("TEST_PASS");
        $finish;
    end

    //---------------------------------------------------------------------
    // 全局兜底 + 可选 VCD
    //---------------------------------------------------------------------
    initial begin
        #900000000;
        $display("TEST_FAIL global watchdog timeout at %0t", $time);
        $finish;
    end

    reg [8*128-1:0] vcd_file;
    initial begin
        if ($value$plusargs("VCD=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_font_load);
        end
    end

endmodule

`default_nettype wire
