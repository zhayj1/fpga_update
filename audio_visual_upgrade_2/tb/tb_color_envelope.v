`timescale 1ns/1ps
`default_nettype none

module tb_color_envelope;
    reg pix = 1'b0;
    always #20 pix = ~pix;

    reg rst_pix = 1'b1;
    reg feed_stb = 1'b0;
    reg feed_frame = 1'b0;
    reg [8:0] feed_idx = 9'd0;
    reg [7:0] feed_mag = 8'd0;
    integer i;
    integer frame_no;

    skeleton_core #(.en_fft(1'b1)) dut (
        .clk_pix(pix), .clk_pix5x(1'b0), .rst_pix(rst_pix),
        .clk_sdr(1'b0), .clk_sdr_sft(1'b0), .rst_sdr(1'b1),
        .clk(1'b0), .rst_n(1'b0), .key4(1'b1)
    );

    task send_frame;
        input [7:0] magnitude;
        begin
            feed_mag = magnitude;
            feed_stb = 1'b1;
            for (i = 0; i < 512; i = i + 1) begin
                feed_idx = i[8:0];
                @(negedge pix);
            end
            feed_stb = 1'b0;
            feed_frame = 1'b1;
            @(negedge pix);
            feed_frame = 1'b0;
            frame_no = frame_no + 1;
        end
    endtask

    initial begin
        frame_no = 0;
        force dut.sp_bin_stb = feed_stb;
        force dut.sp_bin_idx = feed_idx;
        force dut.sp_bin_mag = feed_mag;
        force dut.sp_frame_stb = feed_frame;
        force dut.spec_song_clear = 1'b0;
        repeat (5) @(negedge pix);
        rst_pix = 1'b0;
        // Feed the restored FFT byte scale. These values correspond to the
        // former 145-floor diagnostic values 149/155/164.
        repeat (40) send_frame(8'd82);
        if (dut.env_loud_q8 < 8'd16 || dut.env_loud_q8 > 8'd32 ||
            dut.env_rel_q8 > 8'd8) begin
            $display("TEST_FAIL quiet loud=%0d rel=%0d", dut.env_loud_q8, dut.env_rel_q8);
            $finish;
        end
        $display("COLOR_ENV_QUIET loud=%0d rel=%0d", dut.env_loud_q8, dut.env_rel_q8);

        repeat (50) send_frame(8'd88);
        if (dut.env_loud_q8 < 8'd60 || dut.env_loud_q8 > 8'd80 ||
            dut.env_rel_q8 < 8'd65 || dut.env_rel_q8 > 8'd120) begin
            $display("TEST_FAIL medium loud=%0d rel=%0d", dut.env_loud_q8, dut.env_rel_q8);
            $finish;
        end
        $display("COLOR_ENV_MEDIUM loud=%0d rel=%0d", dut.env_loud_q8, dut.env_rel_q8);

        repeat (40) send_frame(8'd97);
        if (dut.env_loud_q8 < 8'd130 || dut.env_rel_q8 < 8'd200) begin
            $display("TEST_FAIL strong loud=%0d rel=%0d", dut.env_loud_q8, dut.env_rel_q8);
            $finish;
        end
        $display("COLOR_ENV_STRONG loud=%0d rel=%0d", dut.env_loud_q8, dut.env_rel_q8);

        repeat (100) send_frame(8'd82);
        if (dut.env_loud_q8 > 8'd45 || dut.env_rel_q8 > 8'd40) begin
            $display("TEST_FAIL release loud=%0d rel=%0d", dut.env_loud_q8, dut.env_rel_q8);
            $finish;
        end
        $display("COLOR_ENV_RELEASE loud=%0d rel=%0d", dut.env_loud_q8, dut.env_rel_q8);
        $display("SCENARIO_PASS color_envelope_quiet_medium_strong_release");
        $display("TEST_PASS");
        $finish;
    end

    initial begin
        #10000000;
        $display("TEST_FAIL timeout frame=%0d", frame_no);
        $finish;
    end
endmodule

`default_nettype wire
