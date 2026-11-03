`timescale 1ns/1ps
`default_nettype none
// Compare all attack outputs to the saved original, and base bars to a copy
// fed independently filtered input. No production reference logic is changed.
module display_floor_check(
    input wire clk, rst_n, bin_stb, frame_stb,
    input wire [8:0] bin_idx,
    input wire [7:0] bin_mag,
    input wire [5:0] sensitivity,
    output wire bar_stb, bars_done,
    output wire [5:0] bar_idx,
    output wire [7:0] bar_level,
    output wire attack_stb,
    output wire [4:0] attack_idx,
    output wire [7:0] attack_level,
    output wire old_bar_stb,
    output wire [7:0] old_bar_level
);
    wire old_done, old_attack_stb, filtered_stb, filtered_done;
    wire [5:0] old_idx, filtered_idx;
    wire [4:0] old_attack_idx;
    wire [7:0] old_attack_level, filtered_level;
    // 123 is the first code above log_level(4)=122.
    wire [7:0] filtered = bin_mag < 8'd123 ? 8'd0 : bin_mag;
    wire [65:0] attack_result, old_attack_result;
    spec_bands64 dut(clk,rst_n,bin_stb,bin_idx,bin_mag,frame_stb,
        bar_stb,bar_idx,bar_level,bars_done,attack_stb,attack_idx,attack_level);
    spec_bands64_original original(clk,rst_n,bin_stb,bin_idx,bin_mag,frame_stb,
        old_bar_stb,old_idx,old_bar_level,old_done,old_attack_stb,old_attack_idx,old_attack_level);
    spec_bands64_original filtered_reference(clk,rst_n,bin_stb,bin_idx,filtered,frame_stb,
        filtered_stb,filtered_idx,filtered_level,filtered_done);
    spec_attack18 attack_new(clk,rst_n,attack_stb,attack_idx,attack_level,sensitivity,
        attack_result[65],attack_result[64],attack_result[63:59],attack_result[58:46],
        attack_result[45:33],attack_result[32:16],attack_result[15:0]);
    spec_attack18 attack_old(clk,rst_n,old_attack_stb,old_attack_idx,old_attack_level,sensitivity,
        old_attack_result[65],old_attack_result[64],old_attack_result[63:59],old_attack_result[58:46],
        old_attack_result[45:33],old_attack_result[32:16],old_attack_result[15:0]);
    always @(posedge clk) begin
        #1;
        if(rst_n) begin
            if({bar_stb,bar_idx,bars_done} !== {old_bar_stb,old_idx,old_done} ||
               {bar_stb,bar_idx,bar_level,bars_done} !== {filtered_stb,filtered_idx,filtered_level,filtered_done}) begin
                $display("TEST_FAIL base bar/reference mismatch idx=%0d level=%0d expected=%0d",bar_idx,bar_level,filtered_level); $finish;
            end
            if({attack_stb,attack_idx,attack_level} !== {old_attack_stb,old_attack_idx,old_attack_level} ||
                attack_result !== old_attack_result) begin
                $display("TEST_FAIL attack path differs from original"); $finish;
            end
        end
    end
endmodule

module tb_display_floor;
    reg clk=0,rst_n=0,bs=0,fs=0;
    always #20 clk=~clk;
    reg [8:0] bi=0;
    reg [7:0] bm=0;
    reg [5:0] sensitivity=16;
    wire stb,done,astb,old_stb;
    wire [5:0] idx;
    wire [4:0] ai;
    wire [7:0] level,al,old_level;
    display_floor_check check_i(clk,rst_n,bs,fs,bi,bm,sensitivity,
        stb,done,idx,level,astb,ai,al,old_stb,old_level);
    integer k,f,attacks=0,bars=0,zeros=0,total=0;
    always @(posedge clk) begin
        #2;
        if(rst_n) begin
            if(stb) begin bars=bars+1; if(level==0) zeros=zeros+1; end
            if(astb) attacks=attacks+1;
        end
    end
    task frame;
        input integer value,pattern;
        begin
            bars=0;attacks=0;zeros=0;
            for(k=0;k<512;k=k+1) begin
                @(negedge clk);bs=1;bi=k;
                bm=pattern ? ((k*37+value*71)%256) : value;
            end
            @(negedge clk);bs=0;fs=1;
            @(negedge clk);fs=0;
            wait(attacks==18);
            repeat(100) @(negedge clk);
            if(bars!=64) begin $display("TEST_FAIL count %0d",bars);$finish;end
            total=total+1;
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        // Full 8-bit domain, including both sides of the threshold.
        for(f=0;f<256;f=f+1) begin
            sensitivity=2+(f%39);
            frame(f,0);
            if(f<=122 && zeros!=64) begin $display("TEST_FAIL below-floor bars");$finish;end
        end
        $display("SCENARIO_PASS floor_all_256_codes_and_boundaries");
        for(f=0;f<64;f=f+1) frame(f,1);
        $display("SCENARIO_PASS mixed_bins_and_original_smoothing");
        for(f=0;f<10;f=f+1) frame(0,0);
        if(zeros!=64) begin $display("TEST_FAIL decay to silence");$finish;end
        $display("SCENARIO_PASS history_decays_to_zero");
        @(negedge clk);rst_n=0;
        repeat(4) @(negedge clk);rst_n=1;
        frame(122,0);
        if(zeros!=64) begin $display("TEST_FAIL reset history");$finish;end
        $display("SCENARIO_PASS reset_restores_silence");
        $display("SCENARIO_PASS original_attack_outputs_cycle_identical");
        $display("TEST_PASS");$finish;
    end
    initial begin #100000000;$display("TEST_FAIL floor timeout");$finish;end
endmodule
`default_nettype wire
