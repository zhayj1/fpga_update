`timescale 1ns/1ps
`default_nettype none
// Interface-level checks: all 128 required-file subsets at each of 16 song
// numbers, every start byte, first-entry precedence and selection cancellation.
// Expected results come from the file list supplied by the test, not DUT flags.
module tb_catalog_matrix #(
    parameter integer EXPECTED_SELECT_CYCLES = 16
);
    localparam integer SELECT_TIMEOUT_CYCLES = 160;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0, clear = 1'b0, wr_en = 1'b0;
    reg [87:0] wr_name = 88'd0;
    reg [1:0] wr_type = 2'd0;
    reg [31:0] wr_size = 32'd0, wr_cluster = 32'd0;
    reg [7:0] rd_index = 8'd0, lo_index = 8'd0, hi_index = 8'd0;
    reg [7:0] start_from = 8'd0;
    reg select_start = 1'b0;
    wire [31:0] rd_size, rd_cluster;
    wire rd_valid, lo_valid, hi_valid, select_busy, select_done, nx_vld;
    wire [7:0] song_total, song_cur, nx_song, pl_err, song_max;
    wire lrc_vld, nx_lrc_vld;
    integer number, mask, field, first, expected_cur, expected_next;
    integer phase, cycles, probe_song;
    reg [7:0] expected_err;

    resource_catalog dut (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .wr_en(wr_en), .wr_name(wr_name), .wr_type(wr_type),
        .wr_size(wr_size), .wr_cluster(wr_cluster),
        .rd_index(rd_index), .rd_size(rd_size), .rd_cluster(rd_cluster),
        .rd_valid(rd_valid), .lo_index(lo_index), .hi_index(hi_index),
        .lo_valid(lo_valid), .hi_valid(hi_valid),
        .select_start(select_start), .start_from(start_from),
        .select_busy(select_busy), .select_done(select_done),
        .song_total(song_total), .song_cur(song_cur), .nx_song(nx_song),
        .pl_err(pl_err), .skip_cnt(), .song_max(song_max), .nx_vld(nx_vld),
        .wav_ft(), .bg_ft1(), .bg_ft2(), .bg_ft3(),
        .cv_ft1(), .cv_ft2(), .cv_ft3(), .lrc_ft(), .lrc_vld(lrc_vld),
        .nx_bg1(), .nx_bg2(), .nx_bg3(), .nx_cv1(), .nx_cv2(), .nx_cv3(),
        .nx_wav_ft(), .nx_lrc_ft(), .nx_lrc_vld(nx_lrc_vld),
        .font_valid(), .asc_valid(), .font_size(), .asc_size()
    );

    task fail;
        input [511:0] reason;
        begin
            $display("TEST_FAIL %0s song=%0d mask=%0d time=%0t", reason, number, mask, $time);
            $finish;
        end
    endtask

    task reset_catalog;
        begin
            @(negedge clk); clear = 1'b1;
            @(negedge clk); clear = 1'b0;
        end
    endtask

    task put;
        input integer song, item;
        input [31:0] size, cluster;
        reg [7:0] tens, ones, digit;
        begin
            tens = 8'h30 + song / 10;
            ones = 8'h30 + song % 10;
            digit = 8'h31 + item % 3;
            @(negedge clk);
            if (item < 3) begin
                wr_name = {8'h53,tens,ones,8'h42,8'h47,digit,16'h2020,24'h424d50};
                wr_type = 2'd0;
            end else if (item < 6) begin
                wr_name = {8'h53,tens,ones,8'h43,8'h56,digit,16'h2020,24'h424d50};
                wr_type = 2'd0;
            end else begin
                wr_name = {8'h53,tens,ones,40'h2020202020,
                           item == 6 ? 24'h574156 : 24'h4c5243};
                wr_type = item == 6 ? 2'd1 : 2'd2;
            end
            wr_size = size; wr_cluster = cluster; wr_en = 1'b1;
            @(negedge clk); wr_en = 1'b0;
        end
    endtask

    task fill_song;
        input integer song;
        integer item;
        begin
            for (item = 0; item < 7; item = item + 1)
                put(song, item, 32'd128 + item, song * 100 + item);
        end
    endtask

    task choose;
        input [7:0] from;
        integer cycles;
        begin
            @(negedge clk); start_from = from; select_start = 1'b1;
            @(negedge clk); select_start = 1'b0;
            cycles = 0;
            while (select_done !== 1'b1 && cycles < SELECT_TIMEOUT_CYCLES) begin
                @(negedge clk); cycles = cycles + 1;
            end
            if (cycles == SELECT_TIMEOUT_CYCLES || select_busy !== 1'b0) fail("selection timeout");
        end
    endtask

    task check_selection;
        input integer total, current, next_song;
        input [7:0] error_code;
        begin
            if (song_total !== total[7:0] || song_cur !== current[7:0] ||
                nx_song !== next_song[7:0] || pl_err !== error_code ||
                nx_vld !== (next_song != 0)) begin
                $display("selection actual=%0d,%0d,%0d,%02h expected=%0d,%0d,%0d,%02h",
                         song_total, song_cur, nx_song, pl_err, total, current, next_song, error_code);
                fail("selection mismatch");
            end
        end
    endtask

    initial begin
        #6000000;
        fail("test watchdog");
    end

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        for (number = 1; number <= 16; number = number + 1) begin
            for (mask = 0; mask < 128; mask = mask + 1) begin
                reset_catalog;
                for (field = 0; field < 7; field = field + 1)
                    if ((mask & (1 << field)) != 0)
                        put(number, field, 32'd128 + field, number * 100 + field);
                choose(8'd0);
                if (mask == 127) check_selection(1, number, number, 8'd0);
                else begin
                    if (mask == 0) expected_err = 8'h71;
                    else if ((mask & 7) != 7) expected_err = 8'h60;
                    else if ((mask & 56) != 56) expected_err = 8'h61;
                    else expected_err = 8'h62;
                    check_selection(0, 0, 0, expected_err);
                end
                for (field = 0; field < 8; field = field + 1) begin
                    @(negedge clk);
                    rd_index = number * 8 + field;
                    lo_index = rd_index; hi_index = rd_index;
                    @(negedge clk);
                    if (rd_valid !== ((mask & (1 << field)) != 0) ||
                        lo_valid !== rd_valid || hi_valid !== rd_valid)
                        fail("valid port mismatch");
                    if (rd_valid && (rd_size !== (32'd128 + field) ||
                        rd_cluster !== (number * 100 + field)))
                        fail("descriptor mismatch");
                end
            end
        end
        $display("SCENARIO_PASS catalog-all-song-field-masks");

        reset_catalog;
        for (number = 1; number <= 16; number = number + 1) begin
            fill_song(number);
            if ((number % 2) == 0) put(number, 7, 32'd96, number * 100 + 7);
        end
        for (first = 0; first < 256; first = first + 1) begin
            expected_cur = (first == 0 || first > 16) ? 1 : first;
            expected_next = (expected_cur == 16) ? 1 : expected_cur + 1;
            choose(first[7:0]);
            check_selection(16, expected_cur, expected_next, 8'd0);
            if (lrc_vld !== ((expected_cur % 2) == 0) ||
                nx_lrc_vld !== ((expected_next % 2) == 0) || song_max !== 8'd16)
                fail("lyric or maximum mismatch");
        end
        $display("SCENARIO_PASS catalog-all-start-indices");

        reset_catalog;
        put(1, 0, 32'd921655, 32'd99);
        fill_song(1);
        fill_song(2);
        choose(8'd0); check_selection(1, 2, 2, 8'h64);
        reset_catalog;
        put(1, 3, 32'd732122, 32'd99);
        fill_song(1);
        choose(8'd0); check_selection(0, 0, 0, 8'h64);
        reset_catalog;
        fill_song(1);
        put(1, 0, 32'd921655, 32'd99);
        put(1, 3, 32'd732122, 32'd99);
        choose(8'd0); check_selection(1, 1, 1, 8'd0);
        @(negedge clk); rd_index = 8'd8;
        @(negedge clk);
        if (rd_size !== 32'd128 || rd_cluster !== 32'd100)
            fail("duplicate replaced first entry");
        reset_catalog;
        put(1, 0, 32'd128, 32'd1);
        put(2, 0, 32'd921655, 32'd2);
        fill_song(16);
        choose(8'd0); check_selection(1, 16, 16, 8'h60);
        $display("SCENARIO_PASS catalog-first-wins-and-error-priority");

        @(negedge clk); select_start = 1'b1;
        @(negedge clk); select_start = 1'b0;
        repeat (3) @(negedge clk);
        reset_catalog;
        if (select_busy !== 1'b0 || select_done !== 1'b0 || song_total !== 8'd0)
            fail("clear did not cancel");
        choose(8'd0); check_selection(0, 0, 0, 8'h71);
        $display("SCENARIO_PASS catalog-clear-cancels-selection");

        // Non-contiguous playlists exercise holes and wrap at the last song.
        reset_catalog;
        fill_song(1); fill_song(7); fill_song(16);
        for (first = 0; first < 256; first = first + 1) begin
            expected_cur = (first <= 1 || first > 16) ? 1 :
                           (first <= 7) ? 7 : 16;
            expected_next = expected_cur == 1 ? 7 : expected_cur == 7 ? 16 : 1;
            choose(first[7:0]);
            check_selection(3, expected_cur, expected_next, 8'd0);
        end
        $display("SCENARIO_PASS catalog-sparse-all-start-indices");

        // Three independent valid ports and the synchronous descriptor port
        // remain usable during selection. Extra start pulses must not restart it.
        @(negedge clk); start_from = 8'd7; select_start = 1'b1;
        @(negedge clk); select_start = 1'b0;
        cycles = 0;
        while (select_done !== 1'b1 && cycles < SELECT_TIMEOUT_CYCLES) begin
            rd_index = cycles;
            lo_index = 8 + cycles % 7;
            hi_index = 16 + cycles % 7;
            select_start = (cycles == 11 || cycles == 31 || cycles == 71);
            #1;
            probe_song = rd_index >> 3;
            if (rd_valid !== (((probe_song == 1) || (probe_song == 7) ||
                              (probe_song == 16)) && rd_index[2:0] < 7) ||
                lo_valid !== 1'b1 || hi_valid !== 1'b0)
                fail("concurrent valid ports mismatch");
            @(negedge clk);
            if (rd_valid && (rd_size !== (32'd128 + rd_index[2:0]) ||
                rd_cluster !== (probe_song * 100 + rd_index[2:0])))
                fail("concurrent descriptor mismatch");
            cycles = cycles + 1;
        end
        select_start = 1'b0;
        if (cycles != EXPECTED_SELECT_CYCLES || select_busy !== 1'b0)
            fail("selection restarted or wrong bounded latency");
        check_selection(3, 7, 16, 8'd0);
        $display("SCENARIO_PASS catalog-concurrent-ports-and-busy-start");

        // Cancel at every phase, including the retirement phase. No delayed
        // completion may escape, and a fresh empty selection must still work.
        for (phase = 0; phase < 8; phase = phase + 1) begin
            reset_catalog;
            fill_song(1);
            @(negedge clk); select_start = 1'b1;
            @(negedge clk); select_start = 1'b0;
            repeat (phase) @(negedge clk);
            clear = 1'b1;
            @(negedge clk); clear = 1'b0;
            repeat (SELECT_TIMEOUT_CYCLES) begin
                @(negedge clk);
                if (select_busy !== 1'b0 || select_done !== 1'b0 ||
                    song_total !== 8'd0 || song_cur !== 8'd0 || nx_song !== 8'd0)
                    fail("phase clear did not cancel cleanly");
            end
            choose(8'd0); check_selection(0, 0, 0, 8'h71);

            fill_song(1);
            @(negedge clk); select_start = 1'b1;
            @(negedge clk); select_start = 1'b0;
            repeat (phase) @(negedge clk);
            rst_n = 1'b0;
            @(negedge clk); rst_n = 1'b1;
            repeat (SELECT_TIMEOUT_CYCLES) begin
                @(negedge clk);
                if (select_busy !== 1'b0 || select_done !== 1'b0 ||
                    song_total !== 8'd0 || song_cur !== 8'd0 || nx_song !== 8'd0)
                    fail("phase reset did not cancel cleanly");
            end
            choose(8'd0); check_selection(0, 0, 0, 8'h71);
        end
        $display("SCENARIO_PASS catalog-all-phase-cancellation");
        $display("TEST_PASS");
        $finish;
    end
endmodule
`default_nettype wire
