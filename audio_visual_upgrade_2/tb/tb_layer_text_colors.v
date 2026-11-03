`timescale 1ns/1ps
`default_nettype none

module tb_layer_text_colors;
    localparam integer H_TOTAL = 672;
    localparam integer V_TOTAL = 84;
    localparam integer H_START = 32;
    localparam integer V_START = 2;
    localparam integer ROW0_Y = 8;
    localparam integer ROW1_Y = 46;
    localparam [23:0] PALE = 24'hE8E4FF;
    localparam [23:0] SUNG = 24'hFFE8AA;

    reg clk_pix = 1'b0;
    reg clk_sdr = 1'b0;
    always #20 clk_pix = ~clk_pix;
    always #5 clk_sdr = ~clk_sdr;

    reg rst_pix_n = 1'b0;
    reg rst_sdr_n = 1'b0;
    reg [15:0] hc = 16'd0;
    reg [15:0] vc = 16'd0;
    wire hs = ~(hc < 16'd8);
    wire vs = ~(vc < 16'd2);
    wire de = (hc >= H_START) && (hc < H_TOTAL);

    always @(posedge clk_pix) begin
        if (!rst_pix_n) begin
            hc <= 16'd0;
            vc <= 16'd0;
        end else if (hc == H_TOTAL - 1) begin
            hc <= 16'd0;
            vc <= (vc == V_TOTAL - 1) ? 16'd0 : vc + 16'd1;
        end else begin
            hc <= hc + 16'd1;
        end
    end

    reg desc_tgl = 1'b0;
    wire px_req;
    wire [20:0] px_addr;
    wire [15:0] px_len;
    reg px_ack = 1'b0;
    reg px_done = 1'b0;
    reg [31:0] px_data = 32'd0;
    reg px_valid = 1'b0;
    wire [23:0] dout;
    wire dout_vld;
    wire [31:0] gap_cnt;
    wire [31:0] on_cnt;

    layer_text #(
        .H_ACT_DLY(H_START), .V_ACT_DLY(V_START), .V_ACT_LIN(80),
        .WIN_Y0(2), .WIN_H(76), .ROW_Y0(ROW0_Y), .PITCH(38),
        .LRC_BASE(21'd0), .FONT_BASE(21'h10000), .ASC_BASE(21'h20000)
    ) u_dut (
        .clk_pix(clk_pix), .rst_pix_n(rst_pix_n),
        .hs(hs), .vs(vs), .de(de), .en(1'b1), .en_ttl(1'b0),
        .dout(dout), .dout_vld(dout_vld), .gap_cnt(gap_cnt),
        .on_cnt(on_cnt), .ttl_off(),
        .clk_sdr(clk_sdr), .rst_sdr_n(rst_sdr_n), .played(24'd500),
        .cur_fc(16'd0), .nxt_fc(16'd2), .n3_fc(16'd0),
        .cur_cnt(16'd2), .nxt_cnt(16'd2), .n3_cnt(16'd0),
        .cur_vld(1'b1), .nxt_vld(1'b1), .n3_vld(1'b0),
        .off_px(6'd0), .desc_tgl(desc_tgl), .samp_stb(1'b0),
        .ttl_fc(16'd0), .ttl_cnt(16'd0), .sgr_fc(16'd0),
        .sgr_cnt(16'd0), .ttl_vld(1'b0), .sgr_vld(1'b0),
        .px_req(px_req), .px_addr(px_addr), .px_len(px_len),
        .px_ack(px_ack), .px_done(px_done), .px_data(px_data),
        .px_valid(px_valid)
    );

    // Four legal Chinese-character records; alternating timestamps produce
    // color codes 2 and 1 in both rows at played=500.
    function [31:0] memory_word;
        input [20:0] addr;
        begin
            case (addr)
                21'd136, 21'd138, 21'd140, 21'd142:
                    memory_word = 32'h0001B7D7;
                21'd137, 21'd141: memory_word = 32'd100;
                21'd139, 21'd143: memory_word = 32'd1000;
                default: memory_word = 32'hFFFFFFFF;
            endcase
        end
    endfunction

    localparam [1:0] RD_IDLE = 2'd0, RD_ACK = 2'd1,
                     RD_SEND = 2'd2, RD_DONE = 2'd3;
    reg [1:0] rd_state = RD_IDLE;
    reg [20:0] rd_base = 21'd0;
    reg [2:0] rd_index = 3'd0;
    reg [1:0] rd_wait = 2'd0;

    always @(posedge clk_sdr) begin
        if (!rst_sdr_n) begin
            rd_state <= RD_IDLE;
            rd_base <= 21'd0;
            rd_index <= 3'd0;
            rd_wait <= 2'd0;
            px_ack <= 1'b0;
            px_done <= 1'b0;
            px_valid <= 1'b0;
            px_data <= 32'd0;
        end else begin
            px_ack <= 1'b0;
            px_done <= 1'b0;
            px_valid <= 1'b0;
            case (rd_state)
                RD_IDLE: if (px_req) begin
                    if (px_len !== 16'd4 || px_addr[1:0] !== 2'b00) begin
                        $display("TEST_FAIL unaligned or non-four-word SDRAM request addr=%h len=%0d", px_addr, px_len);
                        $finish;
                    end
                    rd_base <= px_addr;
                    rd_wait <= 2'd1;
                    rd_state <= RD_ACK;
                end
                RD_ACK: if (rd_wait != 2'd0) begin
                    rd_wait <= rd_wait - 2'd1;
                end else begin
                    px_ack <= 1'b1;
                    rd_index <= 3'd0;
                    rd_state <= RD_SEND;
                end
                RD_SEND: begin
                    px_data <= memory_word(rd_base + {18'd0, rd_index});
                    px_valid <= 1'b1;
                    if (rd_index == 3'd3) rd_state <= RD_DONE;
                    else rd_index <= rd_index + 3'd1;
                end
                RD_DONE: begin
                    px_done <= 1'b1;
                    rd_state <= RD_IDLE;
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    reg check_frame = 1'b0;
    integer cur_sung_pixels = 0;
    integer cur_unsung_pixels = 0;
    integer next_sungcode_pixels = 0;
    integer next_unsungcode_pixels = 0;
    integer x;
    integer y;
    always @(posedge clk_pix) begin
        if (check_frame && de) begin
            x = hc - H_START;
            y = vc - V_START;
            if (((y >= ROW0_Y) && (y < ROW0_Y + 32)) ||
                ((y >= ROW1_Y) && (y < ROW1_Y + 32))) begin
                if (dout_vld === 1'b1) begin
                    if ((x < 288) || (x >= 352)) begin
                        $display("TEST_FAIL lyric ink outside two-character span x=%0d y=%0d", x, y);
                        $finish;
                    end
                    if (y < ROW1_Y) begin
                        if (x < 320) begin
                            if (dout !== SUNG) begin
                                $display("TEST_FAIL current sung x=%0d y=%0d expected=%h got=%h", x, y, SUNG, dout);
                                $finish;
                            end
                            cur_sung_pixels = cur_sung_pixels + 1;
                        end else begin
                            if (dout !== PALE) begin
                                $display("TEST_FAIL current unsung x=%0d y=%0d expected=%h got=%h", x, y, PALE, dout);
                                $finish;
                            end
                            cur_unsung_pixels = cur_unsung_pixels + 1;
                        end
                    end else if (x < 320) begin
                        if (dout !== PALE) begin
                            $display("TEST_FAIL next sung-code x=%0d y=%0d expected=%h got=%h", x, y, PALE, dout);
                            $finish;
                        end
                        next_sungcode_pixels = next_sungcode_pixels + 1;
                    end else begin
                        if (dout !== PALE) begin
                            $display("TEST_FAIL next unsung-code x=%0d y=%0d expected=%h got=%h", x, y, PALE, dout);
                            $finish;
                        end
                        next_unsungcode_pixels = next_unsungcode_pixels + 1;
                    end
                end
            end
        end
    end

    initial begin
        repeat (16) @(posedge clk_pix);
        @(negedge clk_pix);
        rst_pix_n = 1'b1;
        rst_sdr_n = 1'b1;
        repeat (4) @(negedge clk_pix);
        desc_tgl = 1'b1;
        repeat (4) @(negedge clk_pix);
        desc_tgl = 1'b0;

        // Wait for frame synchronization and warm both row-buffer banks.
        repeat (2) @(negedge vs);
        check_frame = 1'b1;
        @(negedge vs);
        check_frame = 1'b0;
        @(negedge clk_pix);
        $display("LYRIC_COLOR_PIXELS current_sung=%0d current_unsung=%0d next_code2=%0d next_code1=%0d gap=%0d",
                 cur_sung_pixels, cur_unsung_pixels, next_sungcode_pixels,
                 next_unsungcode_pixels, gap_cnt);
        if (cur_sung_pixels < 512 || cur_unsung_pixels < 512 ||
            next_sungcode_pixels < 512 || next_unsungcode_pixels < 512) begin
            $display("TEST_FAIL insufficient ink in one or more lyric color regions");
            $finish;
        end
        $display("SCENARIO_PASS lyric_current_sung");
        $display("SCENARIO_PASS lyric_current_unsung");
        $display("SCENARIO_PASS lyric_next_code2");
        $display("SCENARIO_PASS lyric_next_code1");
        $display("TEST_PASS");
        $finish;
    end

    initial begin
        #30000000;
        $display("TEST_FAIL lyric color test watchdog timeout");
        $finish;
    end
endmodule

`default_nettype wire
