`timescale 1ns/1ps
`default_nettype none
module tb_spec_bands64_distinct;
    reg clk=0, rst_n=0;
    always #20 clk=~clk;
    reg bin_stb=0, frame_stb=0;
    reg [8:0] bin_idx=0;
    reg [7:0] bin_mag=0;
    wire bar_stb, bars_done;
    wire [5:0] bar_idx;
    wire [7:0] bar_level;
    spec_bands64 dut(
        .clk(clk), .rst_n(rst_n), .bin_stb(bin_stb), .bin_idx(bin_idx),
        .bin_mag(bin_mag), .frame_stb(frame_stb), .bar_stb(bar_stb),
        .bar_idx(bar_idx), .bar_level(bar_level), .bars_done(bars_done));

    integer reads [0:511];
    integer low_reads [0:20];
    integer i, bar_count=0, read_count=0;
    reg [7:0] expected_mag, expected_level;
    initial begin
        for(i=0;i<512;i=i+1) reads[i]=0;
        for(i=0;i<21;i=i+1) low_reads[i]=0;
        repeat(4) @(negedge clk);
        rst_n=1;
        for(i=0;i<512;i=i+1) begin
            @(negedge clk);
            bin_stb=1;
            bin_idx=i;
            bin_mag=(i>=1 && i<=21)?(24+(i-1)*7):
                    ((i>=22 && i<=256)?8'd80:8'd0);
        end
        @(negedge clk);
        bin_stb=0;
        frame_stb=1;
        @(negedge clk);
        frame_stb=0;
    end

    always @(negedge clk) if(rst_n) begin
        // State 3 is the accumulator's ADD cycle, one visit per consumed bin.
        if(dut.state===3'd3) begin
            if((^dut.cursor)===1'bx || (^bar_idx)===1'bx ||
               dut.cursor<9'd1 || dut.cursor>9'd256) begin
                $display("TEST_FAIL invalid band read bar=%0d bin=%0d",bar_idx,dut.cursor);$finish;
            end
            reads[dut.cursor]=reads[dut.cursor]+1;
            read_count=read_count+1;
            if(bar_idx<6'd21) begin
                if(dut.cursor!==({3'd0,bar_idx}+9'd1)) begin
                    $display("TEST_FAIL low bar %0d read bin %0d",bar_idx,dut.cursor);$finish;
                end
                low_reads[bar_idx]=low_reads[bar_idx]+1;
            end
        end
        if(bar_stb) begin
            if(bar_count>=64 || bar_idx!==bar_count) begin
                $display("TEST_FAIL bar order count=%0d index=%0d",bar_count,bar_idx);$finish;
            end
            if(bar_idx<6'd21) begin
                expected_mag=24+bar_idx*7;
                expected_level=expected_mag-(expected_mag>>3);
            end else expected_level=8'd70;
            if(bar_level!==expected_level) begin
                $display("TEST_FAIL bar %0d level=%0d expected=%0d",bar_idx,bar_level,expected_level);$finish;
            end
            bar_count=bar_count+1;
        end
        if(bars_done) begin
            if(!bar_stb || bar_idx!==6'd63 || bar_count!=64) begin
                $display("TEST_FAIL bars_done index=%0d count=%0d",bar_idx,bar_count);$finish;
            end
            for(i=0;i<21;i=i+1) if(low_reads[i]!=1) begin
                $display("TEST_FAIL low bar %0d read count %0d",i,low_reads[i]);$finish;
            end
            $display("SCENARIO_PASS distinct_low_bins");
            if(read_count!=256 || reads[0]!=0) begin
                $display("TEST_FAIL band coverage read_count=%0d bin0=%0d",read_count,reads[0]);$finish;
            end
            for(i=1;i<=256;i=i+1) if(reads[i]!=1) begin
                $display("TEST_FAIL bin %0d read count %0d",i,reads[i]);$finish;
            end
            for(i=257;i<512;i=i+1) if(reads[i]!=0) begin
                $display("TEST_FAIL excess bin %0d read count %0d",i,reads[i]);$finish;
            end
            $display("SCENARIO_PASS nonoverlap_64_bands");
            $display("SCENARIO_PASS bars_done_64");
            $display("TEST_PASS");$finish;
        end
    end
    initial begin #200000; $display("TEST_FAIL bands64 timeout count=%0d",bar_count);$finish;end
endmodule
`default_nettype wire
