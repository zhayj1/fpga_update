`timescale 1ns/1ps
`default_nettype none
// Zero-latency geometry comparison against the preserved pre-repair RTL.
// Bank exchange and attack decay are exercised separately by tb_layer_fft64.
module tb_timing_fft;
    reg clk=0,rst_n=0,de=1,en=1;
    reg [15:0] y=0;
    reg [7:0] level=0,strength=0;
    reg [5:0] bar=0,center=0;
    reg [3:0] phase=1;
    reg valid=1;
    wire [23:0] rgb,ref_rgb;
    wire vld,ref_vld;
    integer checks=0,l,s,d,k,pass,i,j;
    integer sample[0:8];
    integer distances[0:14];
    layer_fft64 dut(.clk(clk),.rst_n(rst_n),.bar_stb(1'b0),
        .bars_done(1'b0),.bar_idx(6'd0),.bar_level(8'd0),.frame_stb(1'b0),
        .attack_hit(1'b0),.attack_band(5'd0),.de(de),.en(en),.x(16'd0),
        .y(y),.dout(rgb),.dout_vld(vld));
    timing_fft_reference ref_dut(.clk(clk),.rst_n(rst_n),.bar_stb(1'b0),
        .bars_done(1'b0),.bar_idx(6'd0),.bar_level(8'd0),.frame_stb(1'b0),
        .attack_hit(1'b0),.attack_band(5'd0),.de(de),.en(en),.x(16'd0),
        .y(y),.dout(ref_rgb),.dout_vld(ref_vld));
    task check_point;
        input integer yy;
        begin
            y=yy; #1;
            if(rgb!==ref_rgb || vld!==ref_vld) begin
                $display("TEST_FAIL FFT difference level=%0d strength=%0d bar=%0d center=%0d phase=%0d y=%0d rgb=%h/%h valid=%b/%b",
                    level,strength,bar,center,phase,y,rgb,ref_rgb,vld,ref_vld);
                $finish;
            end
            checks=checks+1;
        end
    endtask
    task boundaries;
        integer distance,boost,hh,top;
        begin
            distance=bar>=center ? bar-center : center-bar;
            if(distance<=2) boost=strength>>1;
            else if(distance<=4) boost=(strength>>2)+(strength>>3);
            else if(distance<=6) boost=strength>>2;
            else if(distance<=8) boost=strength>>3;
            else if(distance<=10) boost=strength>>4;
            else if(distance<=12) boost=strength>>5;
            else boost=0;
            hh=level-(level>>3)+boost;
            if(hh>255) hh=255;
            top=478-hh;
            check_point(0);
            check_point(top-4);check_point(top-3);check_point(top-2);
            check_point(top-1);check_point(top);check_point(top+1);
            check_point(477);check_point(478);check_point(480);
            check_point(1024);check_point(65535);
        end
    endtask
    initial begin
        force dut.read_height=level; force ref_dut.read_height=level;
        force dut.spike_strength=strength; force ref_dut.spike_strength=strength;
        force dut.scan_bar=bar; force ref_dut.scan_bar=bar;
        force dut.spike_center=center; force ref_dut.spike_center=center;
        force dut.scan_phase=phase; force ref_dut.scan_phase=phase;
        force dut.active_valid=valid; force ref_dut.active_valid=valid;
        sample[0]=0;sample[1]=1;sample[2]=6;sample[3]=7;sample[4]=8;
        sample[5]=31;sample[6]=128;sample[7]=214;sample[8]=255;
        for(i=0;i<14;i=i+1) distances[i]=i;
        distances[14]=63;
        // Every input level, every strength separately, every boost-region
        // boundary and both signs of distance, including height saturation.
        for(pass=0;pass<2;pass=pass+1) begin
            for(l=0;l<256;l=l+1) for(s=0;s<9;s=s+1)
                for(d=0;d<15;d=d+1) for(k=0;k<2;k=k+1) begin
                    level=pass==0 ? l : sample[s];
                    strength=pass==0 ? sample[s] : l;
                    center=k==0 ? 0 : 63;
                    bar=k==0 ? distances[d] : 63-distances[d];
                    boundaries;
                end
        end
        $display("SCENARIO_PASS TIMING-fft-height-strength-boundaries");
        // All 64 colors and all distance pairs, then all phase/gating values.
        level=200;strength=214;
        for(i=0;i<64;i=i+1) for(j=0;j<64;j=j+1) begin
            bar=i;center=j;boundaries;
        end
        $display("SCENARIO_PASS TIMING-fft-all-color-distance-pairs");
        for(i=0;i<16;i=i+1) for(j=0;j<8;j=j+1) begin
            phase=i;de=j[0];en=j[1];valid=j[2];boundaries;
        end
        $display("SCENARIO_PASS TIMING-fft-gates-and-offscreen");
        $display("FFT exact output comparisons: %0d",checks);
        $display("TEST_PASS");$finish;
    end
    initial begin #3000000;$display("TEST_FAIL FFT comparison timeout");$finish;end
endmodule
`default_nettype wire
