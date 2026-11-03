`timescale 1ns/1ps
`default_nettype none
module tb_circular_spectrum;
    reg clk=0;always #20 clk=~clk;
    reg rn=0,de=0,en=1,frame=0,bs=0,bd=0,hit=0,spike=1,rings=1;
    reg [5:0] index=0;reg [7:0] level=0;reg [4:0] hit_band=0;
    reg [9:0] x=0,y=0;
    reg [23:0] color=24'hD97A26;
    wire [23:0] distance,rgb;wire valid;
    reg [6:0] geometry[0:307199];
    integer active[0:63],pending[0:63];
    integer strength=0,center=0,ready=0,n,xx,yy,band,diff,boost,h,body,outer;
    integer physical_distance,expected_valid,expected_rgb,ch,target,channel,ink=0,pixels=0,fd;
    integer scenario=0;
    attack_rings #(.CENTER_X(320),.CENTER_Y(254),.SHARED_DISTANCE(1)) shared(
        .clk(clk),.rst(!rn || !rings),.geometry_rst(!rn),.frame_tick(frame),.hit(hit),
        .de(de),.x(x),.y(y),.valid(),.rgb(),.alpha(),.radius_distance(distance));
    layer_spectrum_ring dut(.clk(clk),.rst_n(rn),.bar_stb(bs),.bars_done(bd),
        .bar_idx(index),.bar_level(level),.frame_stb(frame),.attack_hit(hit),.attack_band(hit_band),
        .spike_enable(spike),.de(de),.en(en),.x(x),.y(y),.radius_distance(distance),
        .target_color(color),.dout(rgb),.dout_vld(valid));
    task upload;
        input integer mode;
        begin
            @(negedge clk);de=0;
            for(n=0;n<64;n=n+1) begin
                pending[n]=mode==0 ? 0 : mode==1 ? 24+n*3 : 200;
                bs=1;index=n;level=pending[n];@(negedge clk);
            end
            bs=0;bd=1;@(negedge clk);bd=0;
        end
    endtask
    task commit;
        input integer swap;
        input integer onset;
        begin
            @(negedge clk);de=0;
            if(onset) begin hit=1;hit_band=0;@(negedge clk);hit=0;strength=214;center=0;end
            else if(strength<=8) strength=0;
            else strength=strength-(strength>>3)-(strength>>5)-1;
            if(!spike) strength=0;
            frame=1;@(negedge clk);frame=0;
            if(swap) begin for(n=0;n<64;n=n+1) active[n]=pending[n];ready=1;end
            repeat(400) @(negedge clk);
        end
    endtask
    task scan;
        begin
            ink=0;pixels=0;
            for(yy=0;yy<480;yy=yy+1) begin
                @(negedge clk);de=0;x=0;y=yy;repeat(4) @(negedge clk);
                de=1;
                for(xx=0;xx<640;xx=xx+1) begin
                    x=xx;#1;
                    physical_distance=36*(xx-320)*(xx-320)+25*(yy-254)*(yy-254);
                    if(distance!==physical_distance) begin
                        $display("TEST_FAIL shared distance %0d,%0d %0d/%0d",xx,yy,distance,physical_distance);$finish;
                    end
                    band=geometry[yy*640+xx]&63;
                    diff=band>=center ? band-center : center-band;if(diff>32)diff=64-diff;
                    boost=!spike?0:diff<=2?strength/2:diff<=4?strength/4+strength/8:
                          diff<=6?strength/4:diff<=8?strength/8:diff<=10?strength/16:diff<=12?strength/32:0;
                    h=active[band]-active[band]/8+boost;if(h>255)h=255;
                    body=136+2+h/8+h/32+h/64;outer=body+3;
                    expected_valid=ready && en && geometry[yy*640+xx][6] && h!=0 && physical_distance<=25*outer*outer;
                    expected_rgb=0;
                    for(ch=0;ch<3;ch=ch+1) begin
                        target=(color>>(8*ch))&255;
                        channel=255-((255-target)*band+31)/63;
                        expected_rgb=expected_rgb|(channel<<(8*ch));
                    end
                    if(boost>6 && physical_distance>25*body*body)expected_rgb=24'hFFFFFF;
                    if(valid!==expected_valid[0] || (valid && rgb!==expected_rgb[23:0])) begin
                        $display("TEST_FAIL radial pixel case=%0d xy=%0d,%0d band=%0d phase=%0d valid=%b/%b rgb=%h/%h d=%0d h=%0d data=%h",
                            scenario,xx,yy,band,dut.phase,valid,expected_valid[0],rgb,expected_rgb[23:0],physical_distance,h,dut.pixel_data);$finish;
                    end
                    if(valid)ink=ink+1;pixels=pixels+1;
                    if(scenario==1)$fdisplay(fd,"%06h",valid?rgb:24'd0);
                    @(negedge clk);
                end
                de=0;
            end
            if(ready && en && scenario!=5 && ink==0)begin $display("TEST_FAIL empty radial frame");$finish;end
        end
    endtask
    initial begin
        $readmemh("sim/circular_geometry_golden.mem",geometry);
        for(n=0;n<64;n=n+1)begin active[n]=0;pending[n]=0;end
        repeat(8)@(negedge clk);rn=1;scan;
        $display("SCENARIO_PASS CIRC-no-uncommitted-spectrum");
        upload(1);commit(1,0);scenario=1;fd=$fopen("sim/circular_spectrum_frame.hex","w");scan;$fclose(fd);
        $display("SCENARIO_PASS CIRC-64-bands-geometry-colors");
        upload(2);scenario=2;scan;
        $display("SCENARIO_PASS CIRC-frame-atomic-update");
        commit(1,1);scenario=3;scan;
        $display("SCENARIO_PASS CIRC-spike-wrap-and-white-cap");
        rings=0;scenario=4;scan;
        $display("SCENARIO_PASS CIRC-ripple-toggle-independent");
        spike=0;color=24'h2487C9;commit(0,0);scenario=5;scan;
        $display("SCENARIO_PASS CIRC-palette-and-spike-controls");
        en=0;scenario=6;scan;
        $display("SCENARIO_PASS CIRC-spectrum-toggle");
        en=1;@(negedge clk);de=0;rn=0;repeat(4)@(negedge clk);rn=1;ready=0;scenario=7;scan;
        $display("SCENARIO_PASS CIRC-reset-clears-old-frame");
        $display("TEST_PASS");$finish;
    end
    initial begin #150000000;$display("TEST_FAIL circular watchdog");$finish;end
endmodule
`default_nettype wire
