`timescale 1ns/1ps
`default_nettype none

// Isolate the scroll controller at the row-renderer completion boundary.
// Expected offsets use an integer model of distance, sample count and hold time.
// Pixel rendering and real row fetches are covered by the existing regressions.
module layer_text_scroll_case #(
    parameter integer CASE_ID = 0,
    parameter integer BOX_PIX = 160,
    parameter integer SAMPLES_PER_PIXEL = 5,
    parameter integer HOLD_SAMPLES = 7
)(input wire clk_sdr, input wire clk_pix, output reg finished);
    reg rst_n = 1'b0;
    reg sample = 1'b0;
    reg render_done = 1'b0;
    reg render_title = 1'b1;
    reg render_is_text = 1'b1;
    reg [5:0] render_words = 6'd0;
    reg [15:0] render_first = 16'd0;
    wire [11:0] title_offset;

    layer_text #(.BOX_W(BOX_PIX), .SPP(SAMPLES_PER_PIXEL),
                 .HOLD_N(HOLD_SAMPLES)) u_dut (
        .clk_pix(clk_pix), .rst_pix_n(rst_n), .hs(1'b1), .vs(1'b1),
        .de(1'b0), .en(1'b0), .en_ttl(1'b0), .dout(), .dout_vld(),
        .gap_cnt(), .on_cnt(), .ttl_off(title_offset),
        .clk_sdr(clk_sdr), .rst_sdr_n(rst_n), .played(24'd0),
        .cur_fc(16'd0), .nxt_fc(16'd0), .n3_fc(16'd0),
        .cur_cnt(16'd0), .nxt_cnt(16'd0), .n3_cnt(16'd0),
        .cur_vld(1'b0), .nxt_vld(1'b0), .n3_vld(1'b0),
        .off_px(6'd0), .desc_tgl(1'b0), .samp_stb(sample),
        .ttl_fc(16'd0), .ttl_cnt(16'd0), .sgr_fc(16'd0),
        .sgr_cnt(16'd0), .ttl_vld(1'b0), .sgr_vld(1'b0),
        .px_req(), .px_addr(), .px_len(), .px_ack(1'b0),
        .px_done(1'b0), .px_data(32'd0), .px_valid(1'b0)
    );

    integer model_t, model_s, width_t, width_s, first_t, first_s;
    integer divider, pause_samples, wraps, checked, skipped;
    reg done1, done2;
    reg wrap_title, wrap_singer;
    reg [11:0] sweep_width_t, sweep_width_s;
    reg [10:0] sweep_t, sweep_s;
    integer n, offset, i, long_words, steps;
    reg expected_t, expected_s;

    task reset_controller;
        begin
            @(negedge clk_sdr);
            rst_n = 1'b0; sample = 1'b0; render_done = 1'b0;
            repeat (3) @(negedge clk_sdr);
            model_t = 0; model_s = 0; width_t = 0; width_s = 0;
            first_t = 0; first_s = 0; divider = 0; pause_samples = 0;
            done1 = 1'b0; done2 = 1'b0; wraps = 0; checked = 0; skipped = 0;
            if (title_offset !== 12'd0 || u_dut.off_s !== 11'd0 ||
                u_dut.div !== 11'd0 || u_dut.hold !== 15'd0) begin
                $display("TEST_FAIL scroll reset case=%0d", CASE_ID); $finish;
            end
            rst_n = 1'b1;
        end
    endtask

    task cycle;
        input take_sample;
        input complete_row;
        begin
            @(negedge clk_sdr);
            sample = take_sample; render_done = complete_row;
            @(posedge clk_sdr);
            if (done2) begin
                if (take_sample) skipped = skipped + 1;
                if (render_is_text) begin
                    if (render_title) begin
                        width_t = render_words * 16;
                        if (render_first != first_t) model_t = 0;
                        first_t = render_first;
                    end else begin
                        width_s = render_words * 16;
                        if (render_first != first_s) model_s = 0;
                        first_s = render_first;
                    end
                end
            end else if (take_sample) begin
                if (pause_samples > 0) pause_samples = pause_samples - 1;
                else if (divider + 1 < SAMPLES_PER_PIXEL) divider = divider + 1;
                else begin
                    divider = 0;
                    wrap_title = (width_t > BOX_PIX) &&
                                 (model_t + 1 >= width_t + BOX_PIX);
                    wrap_singer = (width_s > BOX_PIX) &&
                                  (model_s + 1 >= width_s + BOX_PIX);
                    if (width_t <= BOX_PIX || wrap_title) model_t = 0;
                    else model_t = (model_t + 1) % 2048;
                    if (width_s <= BOX_PIX || wrap_singer) model_s = 0;
                    else model_s = (model_s + 1) % 2048;
                    if (wrap_title || wrap_singer) begin
                        pause_samples = HOLD_SAMPLES;
                        wraps = wraps + 1;
                    end
                end
            end
            done2 = done1; done1 = complete_row;
            #1;
            checked = checked + 1;
            if (title_offset !== model_t || u_dut.off_s !== model_s ||
                u_dut.div !== divider || u_dut.hold !== pause_samples ||
                u_dut.w_t !== width_t || u_dut.w_s !== width_s) begin
                $display("TEST_FAIL scroll case=%0d cycle=%0d title=%0d/%0d singer=%0d/%0d div=%0d/%0d hold=%0d/%0d widths=%0d,%0d/%0d,%0d",
                    CASE_ID, checked, title_offset, model_t, u_dut.off_s, model_s,
                    u_dut.div, divider, u_dut.hold, pause_samples,
                    u_dut.w_t, u_dut.w_s, width_t, width_s); $finish;
            end
        end
    endtask

    task publish_row;
        input is_title;
        input [5:0] words;
        input [15:0] first;
        begin
            render_title = is_title; render_words = words; render_first = first;
            cycle(1'b1, 1'b1);
            cycle(1'b1, 1'b0);
            cycle(1'b1, 1'b0);
            cycle(1'b1, 1'b0);
        end
    endtask

    initial begin
        finished = 1'b0;
        force u_dut.row_done = render_done;
        force u_dut.row_nw = render_words;
        force u_dut.row_err = 8'd0;
        force u_dut.c_ttl = render_is_text;
        force u_dut.c_is_t = render_title;
        force u_dut.c_fc = render_first;

        // Every reachable rendered width and every 11-bit offset, including
        // offsets outside the current text period after width changes.
        force u_dut.w_t = sweep_width_t; force u_dut.w_s = sweep_width_s;
        force u_dut.off_t = sweep_t; force u_dut.off_s = sweep_s;
        for (n = 0; n < 64; n = n + 1) begin
            sweep_width_t = n * 16; sweep_width_s = (63-n) * 16;
            for (offset = 0; offset < 2048; offset = offset + 1) begin
                sweep_t = offset; sweep_s = 2047-offset;
                expected_t = (n*16 > BOX_PIX) && (offset+1 >= n*16+BOX_PIX);
                expected_s = ((63-n)*16 > BOX_PIX) &&
                             (2048-offset >= (63-n)*16+BOX_PIX);
                #1;
                if (u_dut.wrp_t !== expected_t || u_dut.wrp_s !== expected_s) begin
                    $display("TEST_FAIL scroll boundary case=%0d words=%0d offset=%0d",
                             CASE_ID, n, offset); $finish;
                end
            end
        end
        release u_dut.w_t; release u_dut.w_s;
        release u_dut.off_t; release u_dut.off_s;
        reset_controller;
        long_words = BOX_PIX/16 + 2;
        if (long_words > 63) long_words = 63;
        publish_row(1'b1, long_words, 16'd10);
        publish_row(1'b0, BOX_PIX/16, 16'd20);
        // Two complete title periods, including exact hold duration.
        steps = 2*(long_words*16+BOX_PIX+1)*SAMPLES_PER_PIXEL + 2*HOLD_SAMPLES;
        for (i = 0; i < steps; i = i + 1) cycle(1'b1, 1'b0);
        if (BOX_PIX < 1008 && wraps < 2) begin
            $display("TEST_FAIL missing wraps case=%0d got=%0d", CASE_ID, wraps); $finish;
        end
        // Same text must retain its offset; new text resets only that band.
        publish_row(1'b1, long_words, 16'd10);
        for (i = 0; i < 3*SAMPLES_PER_PIXEL+11; i = i + 1)
            cycle((i%3 != 0), 1'b0);
        publish_row(1'b0, long_words+1, 16'd21);
        publish_row(1'b1, long_words, 16'd11);
        for (i = 0; i < 3*(long_words*16+BOX_PIX+20)*SAMPLES_PER_PIXEL + HOLD_SAMPLES;
             i = i + 1) cycle((i%7 != 0), 1'b0);
        // A non-title render still suppresses a coincident sample.
        render_is_text = 1'b0;
        publish_row(1'b1, 6'd0, 16'd30);
        render_is_text = 1'b1;
        publish_row(1'b1, 6'd0, 16'd30);
        publish_row(1'b0, 6'd0, 16'd31);
        for (i = 0; i < HOLD_SAMPLES + 2*SAMPLES_PER_PIXEL; i = i + 1)
            cycle(1'b1, 1'b0);
        if (skipped < 8) begin
            $display("TEST_FAIL missing render/sample collisions case=%0d", CASE_ID); $finish;
        end
        $display("SCROLL_COUNTS case=%0d box=%0d spp=%0d hold=%0d checked=%0d wraps=%0d collisions=%0d",
                 CASE_ID, BOX_PIX, SAMPLES_PER_PIXEL, HOLD_SAMPLES, checked, wraps, skipped);
        reset_controller;
        $display("SCENARIO_PASS scroll_case_%0d", CASE_ID);
        finished = 1'b1;
    end
endmodule

module tb_layer_text_scroll;
    reg clk_sdr = 1'b0, clk_pix = 1'b0;
    always #5 clk_sdr = ~clk_sdr;
    always #20 clk_pix = ~clk_pix;
    wire [6:0] finished;
    layer_text_scroll_case #(.CASE_ID(0), .BOX_PIX(0)) c0(clk_sdr,clk_pix,finished[0]);
    layer_text_scroll_case #(.CASE_ID(1), .BOX_PIX(1)) c1(clk_sdr,clk_pix,finished[1]);
    layer_text_scroll_case #(.CASE_ID(2), .BOX_PIX(31), .SAMPLES_PER_PIXEL(1), .HOLD_SAMPLES(0)) c2(clk_sdr,clk_pix,finished[2]);
    layer_text_scroll_case #(.CASE_ID(3), .BOX_PIX(160)) c3(clk_sdr,clk_pix,finished[3]);
    layer_text_scroll_case #(.CASE_ID(4), .BOX_PIX(511)) c4(clk_sdr,clk_pix,finished[4]);
    layer_text_scroll_case #(.CASE_ID(5), .BOX_PIX(2047)) c5(clk_sdr,clk_pix,finished[5]);
    layer_text_scroll_case #(.CASE_ID(6), .BOX_PIX(160), .SAMPLES_PER_PIXEL(1200), .HOLD_SAMPLES(24000)) c6(clk_sdr,clk_pix,finished[6]);
    initial begin
        wait (&finished);
        $display("TEST_PASS"); $finish;
    end
    initial begin
        #100000000;
        $display("TEST_FAIL scroll watchdog"); $finish;
    end
endmodule
`default_nettype wire
