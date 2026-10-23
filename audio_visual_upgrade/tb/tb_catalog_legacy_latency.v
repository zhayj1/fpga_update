`timescale 1ns/1ps
`default_nettype none
module tb_resource_catalog;
    // The public busy/done handshake permits the serialized selection pass.
    // All legacy data, validity, duplicate and rejection checks are unchanged.
    localparam integer SELECT_TIMEOUT_CYCLES = 160;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0, clear = 1'b0, wr_en = 1'b0;
    reg [87:0] wr_name = 88'd0;
    reg [1:0] wr_type = 2'd0;
    reg [31:0] wr_size = 32'd0, wr_cluster = 32'd0;
    reg [7:0] rd_index = 8'd0, start_from = 8'd0;
    reg select_start = 1'b0;
    wire [31:0] rd_size, rd_cluster, font_size, asc_size;
    wire rd_valid, select_busy, select_done, nx_vld, lrc_vld;
    wire font_valid, asc_valid;
    wire [7:0] song_total, song_cur, pl_err, skip_cnt, song_max, nx_song;
    wire [7:0] wav_ft, bg_ft1, bg_ft2, bg_ft3;
    wire [7:0] cv_ft1, cv_ft2, cv_ft3, lrc_ft;
    integer failures = 0;

    resource_catalog dut (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .wr_en(wr_en), .wr_name(wr_name), .wr_type(wr_type),
        .wr_size(wr_size), .wr_cluster(wr_cluster),
        .rd_index(rd_index), .rd_size(rd_size), .rd_cluster(rd_cluster),
        .rd_valid(rd_valid), .lo_index(8'd0), .hi_index(8'd0),
        .lo_valid(), .hi_valid(),
        .select_start(select_start), .start_from(start_from),
        .select_busy(select_busy), .select_done(select_done),
        .song_total(song_total), .song_cur(song_cur), .pl_err(pl_err),
        .skip_cnt(skip_cnt), .song_max(song_max), .nx_song(nx_song),
        .nx_vld(nx_vld), .wav_ft(wav_ft),
        .bg_ft1(bg_ft1), .bg_ft2(bg_ft2), .bg_ft3(bg_ft3),
        .cv_ft1(cv_ft1), .cv_ft2(cv_ft2), .cv_ft3(cv_ft3),
        .lrc_ft(lrc_ft), .lrc_vld(lrc_vld),
        .nx_bg1(), .nx_bg2(), .nx_bg3(),
        .nx_cv1(), .nx_cv2(), .nx_cv3(),
        .nx_wav_ft(), .nx_lrc_ft(), .nx_lrc_vld(),
        .font_valid(font_valid), .asc_valid(asc_valid),
        .font_size(font_size), .asc_size(asc_size)
    );

    task write_entry;
        input [87:0] name;
        input [1:0] kind;
        input [31:0] size, cluster;
        begin
            @(negedge clk);
            wr_name = name; wr_type = kind;
            wr_size = size; wr_cluster = cluster; wr_en = 1'b1;
            @(negedge clk);
            wr_en = 1'b0;
        end
    endtask

    task add_song;
        input integer number;
        input integer with_lrc;
        integer k;
        reg [7:0] tens, ones, group_digit;
        reg [87:0] name;
        begin
            tens = 8'h30 + (number / 10);
            ones = 8'h30 + (number % 10);
            for (k = 0; k < 7; k = k + 1) begin
                group_digit = 8'h31 + (k % 3);
                if (k < 3)
                    name = {8'h53,tens,ones,8'h42,8'h47,group_digit,8'h20,8'h20,8'h42,8'h4d,8'h50};
                else if (k < 6)
                    name = {8'h53,tens,ones,8'h43,8'h56,group_digit,8'h20,8'h20,8'h42,8'h4d,8'h50};
                else
                    name = {8'h53,tens,ones,8'h20,8'h20,8'h20,8'h20,8'h20,8'h57,8'h41,8'h56};
                write_entry(name, k == 6 ? 2'd1 : 2'd0, 32'd128 + k, number * 100 + k);
            end
            if (with_lrc != 0)
                write_entry({8'h53,tens,ones,8'h20,8'h20,8'h20,8'h20,8'h20,8'h4c,8'h52,8'h43},
                            2'd2, 32'd96, number * 100 + 7);
        end
    endtask

    task reset_catalog;
        begin
            @(negedge clk); clear = 1'b1;
            @(negedge clk); clear = 1'b0;
        end
    endtask

    task choose;
        input [7:0] first;
        integer cycles;
        begin
            @(negedge clk); start_from = first; select_start = 1'b1;
            @(negedge clk); select_start = 1'b0;
            cycles = 0;
            while (select_done !== 1'b1 && cycles < SELECT_TIMEOUT_CYCLES) begin
                @(negedge clk); cycles = cycles + 1;
            end
            if (cycles == SELECT_TIMEOUT_CYCLES) begin
                failures = failures + 1;
                $display("CHECK_FAIL select timeout from=%0d", first);
            end
        end
    endtask

    task expect_selection;
        input [7:0] total, current, next_song, error_code;
        begin
            if (song_total !== total || song_cur !== current ||
                nx_song !== next_song || pl_err !== error_code ||
                nx_vld !== (next_song != 8'd0)) begin
                failures = failures + 1;
                $display("CHECK_FAIL selection got total=%0d cur=%0d next=%0d err=%02h expected %0d,%0d,%0d,%02h",
                         song_total, song_cur, nx_song, pl_err,
                         total, current, next_song, error_code);
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        choose(8'd0);
        expect_selection(8'd0, 8'd0, 8'd0, 8'h71);

        write_entry({8'h46,8'h4f,8'h4e,8'h54,8'h20,8'h20,8'h20,8'h20,8'h48,8'h5a,8'h4b},
                    2'd3, 32'd4096, 32'd41);
        write_entry({8'h41,8'h53,8'h43,8'h20,8'h20,8'h20,8'h20,8'h20,8'h48,8'h5a,8'h4b},
                    2'd3, 32'd1024, 32'd42);
        if (!font_valid || !asc_valid || font_size !== 32'd4096 || asc_size !== 32'd1024) begin
            failures = failures + 1;
            $display("CHECK_FAIL font descriptors");
        end
        add_song(1, 1);
        choose(8'd0);
        expect_selection(8'd1, 8'd1, 8'd1, 8'd0);
        if (bg_ft1 !== 8'd8 || cv_ft3 !== 8'd13 || wav_ft !== 8'd14 ||
            lrc_ft !== 8'd15 || !lrc_vld) begin
            failures = failures + 1;
            $display("CHECK_FAIL song 1 resource IDs");
        end
        @(negedge clk); rd_index = 8'd8;
        @(negedge clk);
        if (!rd_valid || rd_size !== 32'd128 || rd_cluster !== 32'd100) begin
            failures = failures + 1;
            $display("CHECK_FAIL synchronous descriptor read");
        end
        write_entry({8'h53,8'h30,8'h31,8'h42,8'h47,8'h31,8'h20,8'h20,8'h42,8'h4d,8'h50},
                    2'd0, 32'd500, 32'd999);
        @(negedge clk);
        if (rd_size !== 32'd128 || rd_cluster !== 32'd100) begin
            failures = failures + 1;
            $display("CHECK_FAIL duplicate replaced first descriptor");
        end
        $display("SCENARIO_PASS catalog-single-and-descriptors");

        reset_catalog;
        add_song(1, 0);
        add_song(16, 0);
        choose(8'd0);  expect_selection(8'd2, 8'd1, 8'd16, 8'd0);
        choose(8'd16); expect_selection(8'd2, 8'd16, 8'd1, 8'd0);
        choose(8'd2);  expect_selection(8'd2, 8'd16, 8'd1, 8'd0);
        choose(8'd17); expect_selection(8'd2, 8'd1, 8'd16, 8'd0);
        if (song_max !== 8'd16 || lrc_vld) begin
            failures = failures + 1;
            $display("CHECK_FAIL song max or absent LRC");
        end
        $display("SCENARIO_PASS catalog-wrap");

        reset_catalog;
        add_song(16, 0);
        choose(8'd17); expect_selection(8'd1, 8'd16, 8'd16, 8'd0);
        $display("SCENARIO_PASS catalog-last-only");

        reset_catalog;
        write_entry({8'h53,8'h30,8'h32,8'h42,8'h47,8'h31,8'h20,8'h20,8'h42,8'h4d,8'h50},
                    2'd0, 32'd128, 32'd20);
        choose(8'd0); expect_selection(8'd0, 8'd0, 8'd0, 8'h60);
        reset_catalog;
        write_entry({8'h53,8'h30,8'h31,8'h42,8'h47,8'h31,8'h20,8'h20,8'h42,8'h4d,8'h50},
                    2'd0, 32'd921655, 32'd20);
        add_song(1, 0);
        choose(8'd0); expect_selection(8'd0, 8'd0, 8'd0, 8'h64);
        if (dut.valid[8] !== 1'b0) begin
            failures = failures + 1;
            $display("CHECK_FAIL oversized first image was replaced by duplicate");
        end
        $display("SCENARIO_PASS catalog-rejection");

        if (failures == 0) $display("TEST_PASS");
        else begin
            $display("TEST_FAIL catalog failures=%0d", failures);
            $stop;
        end
        $finish;
    end
endmodule
`default_nettype wire
