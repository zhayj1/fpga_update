`timescale 1ns/1ps
`default_nettype none
module tb_display_floor_wav;
    reg clk=0,rst_n=0,valid=0;
    always #20 clk=~clk;
    reg signed [11:0] sample_data=0;
    reg [11:0] pcm[0:32767];
    wire ready,fft_valid,overrun,bs,fs;
    wire signed [11:0] fft_sample;
    wire [8:0] bi,peak_bin;
    wire [7:0] bm,peak_val;
    wire stb,done,astb,old_stb;
    wire [5:0] idx;
    wire [4:0] ai;
    wire [7:0] level,al,old_level;
    spec_window win(clk,rst_n,valid,sample_data,ready,fft_valid,fft_sample,overrun);
    spec_fft #(.N(1024),.SAMP_W(12),.WINDOW_HANN(1),.LOG_MAG(1)) fft(
        .clk(clk),.rst_n(rst_n),.samp_stb(fft_valid),.samp(fft_sample),
        .samp_ready(ready),.frame_stb(fs),.bin_stb(bs),.bin_idx(bi),.bin_mag(bm),
        .peak_bin(peak_bin),.peak_val(peak_val));
    display_floor_check check_i(clk,rst_n,bs,fs,bi,bm,6'd16,
        stb,done,idx,level,astb,ai,al,old_stb,old_level);
    integer samples=0,divider=0,frames=0,barframes=0,main_min=255,main_max=0;
    integer old_residual_bars=0,raw_floor_max=0,second_max=0;
    always @(negedge clk) if(rst_n) begin
        valid=0;
        if(divider==520 && samples<32768) begin
            divider=0;valid=1;sample_data=pcm[samples];samples=samples+1;
        end else divider=divider+1;
    end
    always @(posedge clk) begin
        #2;
        if(rst_n) begin
            if(overrun) begin $display("TEST_FAIL WAV overrun");$finish;end
            if(bs && bi>=9 && bi<=256 && bm>raw_floor_max) raw_floor_max=bm;
            if(fs) begin
                frames=frames+1;
                if(peak_bin!=4) begin $display("TEST_FAIL WAV peak %0d",peak_bin);$finish;end
            end
            if(old_stb && idx>=2 && old_level!=0) old_residual_bars=old_residual_bars+1;
            if(stb) begin
                if(idx>=2 && level!==0) begin
                    $display("TEST_FAIL WAV non-tone bar idx=%0d level=%0d",idx,level);$finish;
                end
                if(idx==1 && level>second_max) second_max=level;
                if(barframes>=10 && idx==0) begin
                    if(level<main_min) main_min=level;
                    if(level>main_max) main_max=level;
                    // The unchanged 800-sample hop changes FFT phase. Fixed-point
                    // rounding can change a strong tone by a display level.
                    if(main_max-main_min>2 || level<60) begin
                        $display("TEST_FAIL first bar unstable min=%0d max=%0d",main_min,main_max);$finish;
                    end
                end
            end
            if(done) begin
                barframes=barframes+1;
                if(barframes==30) begin
                    if(old_residual_bars==0) begin $display("TEST_FAIL original symptom not reproduced");$finish;end
                    $display("WAV_RESULT frames=%0d first_min=%0d first_max=%0d second_max=%0d original_residual_bar_events=%0d residual_log_max=%0d",barframes,main_min,main_max,second_max,old_residual_bars,raw_floor_max);
                    $display("SCENARIO_PASS actual_wav_187p5_first_bar_stable_within_2_levels");
                    $display("SCENARIO_PASS actual_wav_other_62_bars_zero");
                    $display("SCENARIO_PASS actual_wav_original_attack_preserved");
                    $display("TEST_PASS");$finish;
                end
            end
        end
    end
    initial begin
        $readmemh("output/display_floor_20261102_r1/tone_left_12bit.hex",pcm);
        repeat(4) @(negedge clk);rst_n=1;
    end
    initial begin #1000000000;$display("TEST_FAIL WAV timeout frames=%0d",frames);$finish;end
endmodule
`default_nettype wire
