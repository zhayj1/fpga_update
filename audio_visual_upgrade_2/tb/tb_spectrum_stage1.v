`timescale 1ns/1ps
`default_nettype none
module tb_spectrum_stage1;
    reg clk=0, rst_n=0;
    always #20 clk=~clk;
    reg sample_valid=0;
    reg signed [11:0] sample_data=0;
    wire fft_valid, fft_ready, overrun;
    wire signed [11:0] fft_sample;
    wire bin_stb, frame_stb;
    wire [8:0] bin_idx, peak_bin;
    wire [7:0] bin_mag, peak_val;
    wire bar_stb, bars_done;
    wire [5:0] bar_idx;
    wire [7:0] bar_level;
    spec_window window_i(clk,rst_n,sample_valid,sample_data,
                         fft_ready,fft_valid,fft_sample,overrun);
    spec_fft #(.N(1024),.SAMP_W(12),.WINDOW_HANN(1),.LOG_MAG(1)) fft_i(
        .clk(clk),.rst_n(rst_n),.samp_stb(fft_valid),.samp(fft_sample),
        .samp_ready(fft_ready),.frame_stb(frame_stb),.bin_stb(bin_stb),
        .bin_idx(bin_idx),.bin_mag(bin_mag),.peak_bin(peak_bin),.peak_val(peak_val));
    spec_bands64 bands_i(
        .clk(clk), .rst_n(rst_n), .bin_stb(bin_stb), .bin_idx(bin_idx),
        .bin_mag(bin_mag), .frame_stb(frame_stb), .bar_stb(bar_stb),
        .bar_idx(bar_idx), .bar_level(bar_level), .bars_done(bars_done),
        .attack_band_stb(), .attack_band_idx(), .attack_band_level());

    function signed [11:0] tone;
        input [3:0] phase;
        begin case(phase)
        0:tone=0; 1:tone=459; 2:tone=849; 3:tone=1109;
        4:tone=1200; 5:tone=1109; 6:tone=849; 7:tone=459;
        8:tone=0; 9:tone=-459; 10:tone=-849; 11:tone=-1109;
        12:tone=-1200; 13:tone=-1109; 14:tone=-849; 15:tone=-459;
        endcase end
    endfunction
    integer samples=0, divider=0;
    always @(negedge clk) if(rst_n) begin
        sample_valid=0;
        if(divider==79) begin
            divider=0;
            sample_valid=1;
            sample_data=(samples<1024)?12'sd0:tone(samples[3:0]);
            samples=samples+1;
        end else divider=divider+1;
    end
    integer frames=0, band_frames=0, bins_in_frame=0;
    integer tone64=0, tone10=0, band39=0, band10=0, bar_count=0;
    reg done_silence=0, done_tone=0, done_bands=0;
    always @(negedge clk) if(rst_n) begin
        if(overrun) begin $display("TEST_FAIL ring overrun"); $finish; end
        if(bin_stb) begin
            if(bin_idx!==bins_in_frame) begin
                $display("TEST_FAIL bin index expected=%0d actual=%0d",bins_in_frame,bin_idx);$finish;
            end
            bins_in_frame=bins_in_frame+1;
            if(frames==0 && bin_mag!==0) begin $display("TEST_FAIL silence magnitude");$finish;end
            if(frames>=2 && bin_idx==9'd64) tone64=bin_mag;
            if(frames>=2 && bin_idx==9'd10) tone10=bin_mag;
        end
        if(frame_stb) begin
            if(bins_in_frame!=512) begin $display("TEST_FAIL bin count %0d",bins_in_frame);$finish;end
            if(frames==0) begin done_silence=1; $display("SCENARIO_PASS silence_1024");end
            if(frames==2) begin
                if(peak_bin!==9'd64 || tone64<120 || tone10>=tone64) begin
                    $display("TEST_FAIL 3kHz peak=%0d bin64=%0d bin10=%0d",peak_bin,tone64,tone10);$finish;
                end
                done_tone=1; $display("SCENARIO_PASS tone_3khz_1024");
            end
            frames=frames+1; bins_in_frame=0;
        end
        if(bar_stb) begin
            if(bar_idx!==bar_count) begin
                $display("TEST_FAIL bar index expected=%0d actual=%0d",bar_count,bar_idx);$finish;
            end
            if(band_frames>=2 && bar_idx==6'd39) band39=bar_level;
            if(band_frames>=2 && bar_idx==6'd10) band10=bar_level;
            bar_count=bar_count+1;
        end
        if(bars_done) begin
            if(bar_count!=64) begin $display("TEST_FAIL bar count %0d",bar_count);$finish;end
            if(band_frames==2) begin
                if(band39<=band10 || band39<60) begin
                    $display("TEST_FAIL 3kHz band39=%0d band10=%0d",band39,band10);$finish;
                end
                done_bands=1; $display("SCENARIO_PASS tone_3khz_band39");
            end
            band_frames=band_frames+1; bar_count=0;
        end
        if(done_silence && done_tone && done_bands) begin
            $display("SCENARIO_PASS continuous_pcm_window");
            $display("TEST_PASS");$finish;
        end
    end
    initial begin #100 rst_n=1; end
    initial begin #100000000; $display("TEST_FAIL spectrum timeout frames=%0d",frames);$finish;end
endmodule
`default_nettype wire
