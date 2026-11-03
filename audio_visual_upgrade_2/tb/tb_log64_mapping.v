`timescale 1ns/1ps
`default_nettype none
module tb_log64_mapping;
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

    integer band_high[0:63];
    integer j, lower, width, value, total_mag, q16;
    integer reads [0:511];
    integer band_reads [0:63];
    integer i, bar_count=0, read_count=0, phase=0, done_count=0;
    reg [7:0] expected_mag, expected_level;
    initial begin
        band_high[0]=1;
        band_high[1]=2;
        band_high[2]=3;
        band_high[3]=4;
        band_high[4]=5;
        band_high[5]=6;
        band_high[6]=7;
        band_high[7]=8;
        band_high[8]=9;
        band_high[9]=10;
        band_high[10]=11;
        band_high[11]=12;
        band_high[12]=13;
        band_high[13]=14;
        band_high[14]=15;
        band_high[15]=16;
        band_high[16]=17;
        band_high[17]=18;
        band_high[18]=19;
        band_high[19]=20;
        band_high[20]=21;
        band_high[21]=22;
        band_high[22]=24;
        band_high[23]=25;
        band_high[24]=27;
        band_high[25]=28;
        band_high[26]=30;
        band_high[27]=32;
        band_high[28]=34;
        band_high[29]=36;
        band_high[30]=38;
        band_high[31]=40;
        band_high[32]=43;
        band_high[33]=45;
        band_high[34]=48;
        band_high[35]=51;
        band_high[36]=54;
        band_high[37]=57;
        band_high[38]=61;
        band_high[39]=64;
        band_high[40]=68;
        band_high[41]=72;
        band_high[42]=76;
        band_high[43]=81;
        band_high[44]=86;
        band_high[45]=91;
        band_high[46]=96;
        band_high[47]=102;
        band_high[48]=108;
        band_high[49]=114;
        band_high[50]=121;
        band_high[51]=128;
        band_high[52]=136;
        band_high[53]=144;
        band_high[54]=153;
        band_high[55]=162;
        band_high[56]=171;
        band_high[57]=181;
        band_high[58]=192;
        band_high[59]=203;
        band_high[60]=215;
        band_high[61]=228;
        band_high[62]=242;
        band_high[63]=256;
        for(i=0;i<512;i=i+1) reads[i]=0;
        for(i=0;i<64;i=i+1) band_reads[i]=0;
        repeat(4) @(negedge clk);
        rst_n=1;
        for(i=0;i<512;i=i+1) begin
            @(negedge clk);
            bin_stb=1;
            bin_idx=i;
            // Varied values exercise all four bins, floor division and full scale.
            bin_mag=(i>=1 && i<=256)?((i*37+11)%256):8'd255;
        end
        @(negedge clk);
        bin_stb=0;
        frame_stb=1;
        @(negedge clk);
        frame_stb=0;
        wait(done_count==1);
        wait(dut.state==0);
        @(negedge clk); phase=1; bar_count=0; frame_stb=1;
        @(negedge clk); frame_stb=0;
        wait(done_count==2);
        @(negedge clk); rst_n=0;
        repeat(4) @(negedge clk);
        rst_n=1; phase=2; bar_count=0; frame_stb=1;
        @(negedge clk); frame_stb=0;
    end

    always @(negedge clk) if(rst_n) begin
        // State 3 is the accumulator's ADD cycle, one visit per consumed bin.
        if(phase==0 && !dut.attack_mode && dut.state===3'd3) begin
            if((^dut.cursor)===1'bx || (^bar_idx)===1'bx ||
               dut.cursor<9'd1 || dut.cursor>9'd256) begin
                $display("TEST_FAIL invalid band read bar=%0d bin=%0d",bar_idx,dut.cursor);$finish;
            end
            reads[dut.cursor]=reads[dut.cursor]+1;
            read_count=read_count+1;
            if(dut.cursor<(bar_idx==0?1:band_high[bar_idx-1]+1) || dut.cursor>band_high[bar_idx]) begin
                $display("TEST_FAIL log bar %0d read bin %0d",bar_idx,dut.cursor);$finish;
            end
            band_reads[bar_idx]=band_reads[bar_idx]+1;
        end
        if(bar_stb) begin
            if(bar_count>=64 || bar_idx!==bar_count) begin
                $display("TEST_FAIL bar order count=%0d index=%0d",bar_count,bar_idx);$finish;
            end
            lower=bar_idx==0?1:band_high[bar_idx-1]+1;
            width=band_high[bar_idx]-lower+1;
            total_mag=0;
            for(j=lower;j<=band_high[bar_idx];j=j+1) begin
                value=(j*37+11)%256;
                if(value>122) total_mag=total_mag+value;
            end
            q16=(65536+width/2)/width;
            expected_mag=width==1?total_mag:(total_mag*q16)>>16;
            expected_level=expected_mag-(expected_mag>>3);
            if(phase==1) expected_level=expected_level+(expected_level>>3);
            if(bar_level!==expected_level) begin
                $display("TEST_FAIL bar %0d level=%0d expected=%0d",bar_idx,bar_level,expected_level);$finish;
            end
            bar_count=bar_count+1;
        end
        if(bars_done) begin
            if(!bar_stb || bar_idx!==6'd63 || bar_count!=64) begin
                $display("TEST_FAIL bars_done index=%0d count=%0d",bar_idx,bar_count);$finish;
            end
            done_count=done_count+1;
            if(phase==1) begin
                $display("SCENARIO_PASS bands64_second_frame_smoothing");
            end else if(phase==2) begin
                $display("SCENARIO_PASS bands64_reset_history");
                $display("TEST_PASS");$finish;
            end else begin
            for(i=0;i<64;i=i+1) if(band_reads[i]!=band_high[i]-(i==0?0:band_high[i-1])) begin
                $display("TEST_FAIL log bar %0d read count %0d",i,band_reads[i]);$finish;
            end
            $display("SCENARIO_PASS log_widths_and_filtered_averages");
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
            end
        end
    end
    initial begin #600000; $display("TEST_FAIL bands64 timeout count=%0d",bar_count);$finish;end
endmodule
`default_nettype wire
