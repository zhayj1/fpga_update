`timescale 1ns/1ps
`default_nettype none
module tb_capsule_spectrum;
    reg clk=0;always #20 clk=~clk;
    reg rn=0,de=0,en=1,frame=0,bs=0,bd=0,hit=0,spike=1;
    reg [5:0] index=0;reg [7:0] level=0;reg [4:0] hit_band=0;
    reg [9:0] x=0,y=0;
    reg [23:0] color=24'hd97a26;
    wire [23:0] rgb;wire valid;wire [3:0] alpha;
    reg [41:0] geometry[0:307199];
    integer active[0:63],pending[0:63],bands[0:63];
    integer strength=0,ready=0,n,xx,yy,band,diff,boost,h,ext,along,across,over,aq,oq,d2;
    integer ea,ec,ch,target,channel,ink=0,edge_n=0,fd=-1,case_id=0;
    integer q0a=0,q1a=0,q2a=0,q0b=0,q1b=0,q2b=0,q0x=0,q1x=0,q2x=0,q0y=0,q1y=0,q2y=0;
    reg [23:0] q0c=0,q1c=0,q2c=0;
    reg q0de=0,q1de=0,q2de=0;
    layer_spectrum_ring dut(.clk(clk),.rst_n(rn),.bar_stb(bs),.bars_done(bd),
        .bar_idx(index),.bar_level(level),.frame_stb(frame),.attack_hit(hit),.attack_band(hit_band),
        .spike_enable(spike),.de(de),.en(en),.x(x),.y(y),.radius_distance(24'd0),
        .target_color(color),.dout(rgb),.dout_vld(valid),.coverage(alpha));
    always @(posedge clk) begin
        ea=0;ec=0;band=0;
        if(rn&&ready&&de&&en)begin
            band=geometry[y*640+x][41:36];along=geometry[y*640+x][35:18];across=geometry[y*640+x][17:0];
            diff=band;if(diff>32)diff=64-diff;
            boost=!spike?0:diff<=2?strength/2:diff<=4?strength/4+strength/8:
                diff<=6?strength/4:diff<=8?strength/8:diff<=10?strength/16:diff<=12?strength/32:0;
            h=active[band]-active[band]/8+boost;if(h>255)h=255;
            ext=h/8+h/32+h/64;
            over=along<138*256?138*256-along:along>(138+ext)*256?along-(138+ext)*256:0;
            aq=(across+32)/64;oq=(over+32)/64;d2=aq*aq+oq*oq;
            ea=$rtoi((3.5-$sqrt(d2)/4.0)*15.0+0.5);if(ea<0)ea=0;if(ea>15)ea=15;
            for(ch=0;ch<3;ch=ch+1)begin
                target=(color>>(8*ch))&255;channel=255-((255-target)*band+31)/63;
                ec=ec|(channel<<(8*ch));
            end
            if(boost>6&&along>(138+ext)*256)ec=24'hffffff;
        end
        q2a<=q1a;q1a<=q0a;q0a<=ea;
        q2c<=q1c;q1c<=q0c;q0c<=ec;
        q2b<=q1b;q1b<=q0b;q0b<=band;
        q2x<=q1x;q1x<=q0x;q0x<=x;q2y<=q1y;q1y<=q0y;q0y<=y;
        q2de<=q1de;q1de<=q0de;q0de<=de;
        #1;
        if(rn)begin
            if(alpha!==q2a[3:0]||valid!==(q2a!=0)||(valid&&rgb!==q2c))begin
                $display("TEST_FAIL capsule case=%0d xy=%0d,%0d alpha=%0d/%0d rgb=%h/%h",case_id,q2x,q2y,alpha,q2a,rgb,q2c);$finish;
            end
            if(valid)begin ink=ink+1;bands[q2b]=bands[q2b]+1;end
            if(alpha>0&&alpha<15)edge_n=edge_n+1;
            if(fd!=-1&&q2de)$fdisplay(fd,"%01h%06h",alpha,rgb);
        end
    end
    task upload;
        input integer mode;
        begin
            @(negedge clk);de=0;
            for(n=0;n<64;n=n+1)begin
                pending[n]=mode==0?0:mode==1?24+n*3:200;
                bs=1;index=n;level=pending[n];@(negedge clk);
            end
            bs=0;bd=1;@(negedge clk);bd=0;
        end
    endtask
    task commit;
        input integer swap,onset;
        begin
            @(negedge clk);de=0;
            if(onset)begin hit=1;hit_band=0;@(negedge clk);hit=0;strength=214;end
            else if(strength<=8)strength=0;else strength=strength-strength/8-strength/32-1;
            if(!spike)strength=0;
            frame=1;@(negedge clk);frame=0;
            if(swap)for(n=0;n<64;n=n+1)active[n]=pending[n];
            repeat(220)@(negedge clk);ready=1;
        end
    endtask
    task scan;
        begin
            ink=0;edge_n=0;for(n=0;n<64;n=n+1)bands[n]=0;
            for(yy=0;yy<480;yy=yy+1)begin
                @(negedge clk);de=0;x=0;y=yy;repeat(5)@(negedge clk);de=1;
                for(xx=0;xx<640;xx=xx+1)begin x=xx;@(negedge clk);end
                de=0;
            end
            repeat(5)@(negedge clk);
            if(ready&&en)begin
                for(n=0;n<64;n=n+1)if(bands[n]==0)begin $display("TEST_FAIL missing band %0d",n);$finish;end
                if(edge_n<100)begin $display("TEST_FAIL no antialias coverage");$finish;end
            end
        end
    endtask
    initial begin
        $readmemh("sim/capsule_geometry.mem",geometry);
        for(n=0;n<64;n=n+1)begin active[n]=0;pending[n]=0;end
        repeat(8)@(negedge clk);rn=1;commit(0,0);case_id=1;
        fd=$fopen("sim/capsule_silence_frame.hex","w");scan;$fclose(fd);fd=-1;
        $display("SCENARIO_PASS CAPS-silent-64-dots-and-AA");
        upload(1);commit(1,0);case_id=2;
        fd=$fopen("sim/capsule_music_frame.hex","w");scan;$fclose(fd);fd=-1;
        $display("SCENARIO_PASS CAPS-full-frame-64-rays-colors-caps");
        upload(2);case_id=3;scan;
        $display("SCENARIO_PASS CAPS-frame-atomic-update");
        commit(1,1);case_id=4;scan;
        $display("SCENARIO_PASS CAPS-spike-wrap-white-tips");
        spike=0;color=24'h2487c9;commit(0,0);case_id=5;scan;
        $display("SCENARIO_PASS CAPS-palette-and-spike-controls");
        upload(0);commit(1,0);case_id=6;scan;
        $display("SCENARIO_PASS CAPS-return-to-silence");
        en=0;case_id=7;scan;
        $display("SCENARIO_PASS CAPS-switch-hides-dots");
        en=1;@(negedge clk);rn=0;ready=0;repeat(5)@(negedge clk);rn=1;
        commit(0,0);for(n=0;n<64;n=n+1)active[n]=0;case_id=8;scan;
        $display("SCENARIO_PASS CAPS-reset-restores-dots");
        $display("TEST_PASS");$finish;
    end
    initial begin #200000000;$display("TEST_FAIL capsule watchdog");$finish;end
endmodule
`default_nettype wire
