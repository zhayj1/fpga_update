`timescale 1ns/1ps
`default_nettype none
module tb_attack_pcm;
    reg clk=0, rst_n=0, samp_stb=0;
    reg signed [11:0] samp=0;
    wire samp_ready, fft_frame, bin_stb;
    wire [8:0] bin_idx, peak_bin;
    wire [7:0] bin_mag, peak_val;
    wire bar_stb, bars_done, attack_band_stb;
    wire [5:0] bar_idx;
    wire [4:0] attack_band_idx, hit_band;
    wire [7:0] bar_level, attack_band_level;
    wire analysis_stb, hit;
    wire [12:0] flux, threshold;
    wire [15:0] hit_count;
    integer fft_frames=0, analyses=0, saturated=0, tone_bin=0;
    integer tone_bands=0;
    reg [7:0] strongest_level=0;
    reg [4:0] strongest_band=0;
    always #20 clk=~clk;
    spec_fft #(.N(1024),.SAMP_W(12),.WINDOW_HANN(1),.LOG_MAG(1)) fft_i(
        .clk(clk),.rst_n(rst_n),.samp_stb(samp_stb),.samp(samp),
        .samp_ready(samp_ready),.frame_stb(fft_frame),
        .bin_stb(bin_stb),.bin_idx(bin_idx),.bin_mag(bin_mag),
        .peak_bin(peak_bin),.peak_val(peak_val));
    spec_bands64 bands_i(
        .clk(clk),.rst_n(rst_n),.bin_stb(bin_stb),.bin_idx(bin_idx),
        .bin_mag(bin_mag),.frame_stb(fft_frame),
        .bar_stb(bar_stb),.bar_idx(bar_idx),.bar_level(bar_level),
        .bars_done(bars_done),.attack_band_stb(attack_band_stb),
        .attack_band_idx(attack_band_idx),
        .attack_band_level(attack_band_level));
    spec_attack18 attack_i(
        .clk(clk),.rst_n(rst_n),.band_stb(attack_band_stb),
        .band_idx(attack_band_idx),.band_level(attack_band_level),
        .sensitivity(6'd16),.analysis_stb(analysis_stb),
        .hit(hit),.hit_band(hit_band),.flux(flux),
        .threshold(threshold),.hit_count(hit_count));

    function signed [11:0] tone;
        input [3:0] phase;
        begin case(phase)
        0:tone=0;1:tone=459;2:tone=849;3:tone=1109;
        4:tone=1200;5:tone=1109;6:tone=849;7:tone=459;
        8:tone=0;9:tone=-459;10:tone=-849;11:tone=-1109;
        12:tone=-1200;13:tone=-1109;14:tone=-849;15:tone=-459;
        endcase end
    endfunction

    always @(negedge clk) if(rst_n) begin
        if(bin_stb && bin_mag==8'd255) saturated=saturated+1;
        if(bin_stb && bin_idx==9'd64) tone_bin=bin_mag;
        if(fft_frame) fft_frames=fft_frames+1;
        if(attack_band_stb && fft_frames==2) begin
            tone_bands=tone_bands+1;
            if(attack_band_level>strongest_level) begin
                strongest_level=attack_band_level;
                strongest_band=attack_band_idx;
            end
        end
    end
    task feed_frame;
        input tone_enable;
        integer n;
        begin
            for(n=0;n<1024;n=n+1) begin
                wait(samp_ready);
                @(negedge clk);samp_stb=1;
                samp=tone_enable?tone(n[3:0]):12'sd0;
                @(negedge clk);samp_stb=0;
                repeat(78) @(negedge clk);
            end
            wait(analyses==fft_frames && analyses!=0);
        end
    endtask

    always @(posedge analysis_stb) if(rst_n) begin
        #1;
        if(analyses==0) begin
            if(hit!==0 || flux!==0 || hit_count!==0) begin
                $display("TEST_FAIL silence analysis hit=%b flux=%0d",hit,flux);$finish;
            end
            $display("SCENARIO_PASS pcm_silence_no_hit");
        end else if(analyses==1) begin
            if(tone_bin!==8'd255 || saturated<1 || tone_bands!=18 ||
               strongest_level==0 || hit!==1 || hit_band!==strongest_band ||
               hit_count!==16'd1) begin
                $display("TEST_FAIL tone saturation=%0d bin64=%0d bands=%0d max=%0d:%0d hit=%b band=%0d flux=%0d threshold=%0d",saturated,tone_bin,tone_bands,strongest_band,strongest_level,hit,hit_band,flux,threshold);$finish;
            end
            $display("SCENARIO_PASS saturated_pcm_attack_detected");
        end else if(analyses==2) begin
            if(hit!==0 || hit_count!==16'd1) begin
                $display("TEST_FAIL steady tone retrigger hit=%b count=%0d",hit,hit_count);$finish;
            end
            $display("SCENARIO_PASS steady_pcm_no_retrigger");
            $display("TEST_PASS");$finish;
        end
        analyses=analyses+1;
    end

    initial begin
        #100;rst_n=1;
        feed_frame(0);
        feed_frame(1);
        feed_frame(1);
    end
    initial begin #500000000;$display("TEST_FAIL PCM attack timeout analyses=%0d",analyses);$finish;end
endmodule
`default_nettype wire
