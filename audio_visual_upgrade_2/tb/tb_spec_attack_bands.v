`timescale 1ns/1ps
`default_nettype none
module tb_spec_attack_bands;
    reg clk=0, rst_n=0, bin_stb=0, frame_stb=0;
    reg [8:0] bin_idx=0;
    reg [7:0] bin_mag=0;
    wire bar_stb, bars_done, attack_band_stb;
    wire [5:0] bar_idx;
    wire [7:0] bar_level, attack_band_level;
    wire [4:0] attack_band_idx;
    always #20 clk=~clk;
    spec_bands64 dut(
        .clk(clk), .rst_n(rst_n), .bin_stb(bin_stb),
        .bin_idx(bin_idx), .bin_mag(bin_mag), .frame_stb(frame_stb),
        .bar_stb(bar_stb), .bar_idx(bar_idx), .bar_level(bar_level),
        .bars_done(bars_done), .attack_band_stb(attack_band_stb),
        .attack_band_idx(attack_band_idx),
        .attack_band_level(attack_band_level));

    integer mode=0, bar_count=0, band_count=0, done_count=0;
    integer expected_level;
    integer k;
    always @(negedge clk) if(rst_n) begin
        if(bar_stb) begin
            if(bar_count>=64 || bar_idx!==bar_count) begin
                $display("TEST_FAIL frame=%0d bar order count=%0d idx=%0d",mode,bar_count,bar_idx);$finish;
            end
            bar_count=bar_count+1;
        end
        if(bars_done) begin
            if(!bar_stb || bar_idx!==6'd63 || bar_count!=64) begin
                $display("TEST_FAIL frame=%0d bars_done count=%0d",mode,bar_count);$finish;
            end
            done_count=done_count+1;
        end
        if(attack_band_stb) begin
            if(band_count>=18 || attack_band_idx!==band_count || done_count!=1) begin
                $display("TEST_FAIL frame=%0d attack order count=%0d idx=%0d done=%0d",mode,band_count,attack_band_idx,done_count);$finish;
            end
            expected_level=0;
            if(mode==1 && band_count==17) expected_level=3;
            if(mode==3 && band_count<=2) expected_level=100;
            if(attack_band_level!==expected_level) begin
                $display("TEST_FAIL frame=%0d attack band=%0d level=%0d expected=%0d",mode,band_count,attack_band_level,expected_level);$finish;
            end
            band_count=band_count+1;
        end
    end

    task run_frame;
        input integer selected_mode;
        begin
            mode=selected_mode;
            bar_count=0;band_count=0;done_count=0;
            for(k=0;k<512;k=k+1) begin
                @(negedge clk);
                bin_stb=1;bin_idx=k;
                bin_mag=0;
                if(mode==1 && (k==277 || k==278)) bin_mag=255;
                if(mode==2 && k==278) bin_mag=255;
                if(mode==3 && k==1) bin_mag=200;
            end
            @(negedge clk);bin_stb=0;frame_stb=1;
            @(negedge clk);frame_stb=0;
            wait(band_count==18);
            @(negedge clk);
            if(bar_count!=64 || band_count!=18 || done_count!=1) begin
                $display("TEST_FAIL frame=%0d bars=%0d bands=%0d done=%0d",mode,bar_count,band_count,done_count);$finish;
            end
        end
    endtask

    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        run_frame(1);
        $display("SCENARIO_PASS attack_bin277_included");
        run_frame(2);
        $display("SCENARIO_PASS attack_bin278_excluded");
        run_frame(3);
        $display("SCENARIO_PASS low_overlap_and_64_bars");
        $display("TEST_PASS");$finish;
    end
    initial begin #2000000;$display("TEST_FAIL attack band scan timeout mode=%0d",mode);$finish;end
endmodule
`default_nettype wire
