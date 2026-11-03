`timescale 1ns/1ps
`default_nettype none
module tb_color_wav_probe;
    reg clk=0, rst_n=0, samp_stb=0;
    reg signed [11:0] samp=0;
    wire samp_ready, frame_stb, bin_stb;
    wire [8:0] bin_idx, peak_bin;
    wire [7:0] bin_mag, peak_val;
    reg [11:0] pcm [0:47103];
    integer frame=0, count=0, sum=0, excess=0, nonzero=0, saturated=0;
    integer i;
    always #20 clk=~clk;

    spec_fft #(.N(1024),.SAMP_W(12),.WINDOW_HANN(1),.LOG_MAG(1)) dut(
        .clk(clk),.rst_n(rst_n),.samp_stb(samp_stb),.samp(samp),
        .samp_ready(samp_ready),.frame_stb(frame_stb),
        .bin_stb(bin_stb),.bin_idx(bin_idx),.bin_mag(bin_mag),
        .peak_bin(peak_bin),.peak_val(peak_val));

    initial $readmemh("sim/color_wav_probe.mem",pcm);

    always @(negedge clk) if(rst_n) begin
        if(bin_stb) begin
            if(bin_idx!==count) begin
                $display("TEST_FAIL unexpected bin frame=%0d expected=%0d actual=%0d",frame,count,bin_idx);
                $finish;
            end
            count=count+1;
            if(bin_idx!=0) begin
                sum=sum+bin_mag;
                // The board baseline uses the 78-count logarithmic floor.
                // This is the same excess that the color envelope consumes.
                if(bin_mag>8'd78) excess=excess+bin_mag-78;
                if(bin_mag!=0) nonzero=nonzero+1;
                if(bin_mag==255) saturated=saturated+1;
            end
        end
        if(frame_stb) begin
            if(count!=512 || (frame==0 && sum!=0)) begin
                $display("TEST_FAIL frame=%0d bins=%0d sum=%0d",frame,count,sum);$finish;
            end
            if((frame==3 && (excess/512<2 || excess/512>6)) ||
               (frame==19 && excess/512<12) ||
               (frame==45 && (excess/512<8 || excess/512>14))) begin
                $display("TEST_FAIL unexpected card WAV excess frame=%0d value=%0d",frame,excess/512);
                $finish;
            end
            $display("COLOR_WAV_FRAME second=%0d avg=%0d excess=%0d nonzero=%0d saturated=%0d peak=%0d:%0d",
                     frame-1,sum/512,excess/512,nonzero,saturated,peak_bin,peak_val);
            frame=frame+1;count=0;sum=0;excess=0;nonzero=0;saturated=0;
            if(frame==46) begin
                $display("SCENARIO_PASS rtl_fft_card_wav_windows");
                $display("TEST_PASS");$finish;
            end
        end
    end

    initial begin
        #100;rst_n=1;
        for(i=0;i<47104;i=i+1) begin
            wait(samp_ready);
            @(negedge clk);samp=pcm[i];samp_stb=1;
            @(negedge clk);samp_stb=0;
        end
    end
    initial begin
        #500000000;$display("TEST_FAIL WAV probe timeout frame=%0d",frame);$finish;
    end
endmodule
`default_nettype wire
