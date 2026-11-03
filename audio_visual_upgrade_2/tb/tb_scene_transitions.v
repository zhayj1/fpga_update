`timescale 1ns/1ps
`default_nettype none
module tb_scene_transitions;
    reg clk=0,rst=1,frame_tick=0,request=0,old_idle=1;
    always #5 clk=~clk;
    reg [15:0] scene=0;
    reg [1:0] effect=0,speed=1;
    wire [15:0] current_scene,previous_scene;
    wire [1:0] active_effect;
    wire [8:0] progress;
    wire old_enable,busy,ack,accepted;
    scene_fade #(.WIDTH(16),.RUNTIME_CONTROLS(1)) dut(
        .clk(clk),.rst(rst),.frame_tick(frame_tick),.request_toggle(request),
        .old_idle(old_idle),.next_scene(scene),.effect(effect),.speed(speed),
        .active_effect(active_effect),.current_scene(current_scene),
        .previous_scene(previous_scene),.old_enable(old_enable),.busy(busy),
        .ack_toggle(ack),.alpha(progress),.accepted(accepted));
    reg [9:0] x=0,y=0;
    reg [8:0] p=0;
    reg [1:0] e=0;
    wire [8:0] mask_alpha;
    scene_transition_mask mask(.x(x),.y(y),.progress(p),.effect(e),.alpha(mask_alpha));
    reg [23:0] a=0,b=0,overlay=0;
    reg de=0,vs=0,hs=0,overlay_valid=0;
    reg [23:0] a_d,b_d,overlay_d;
    reg [8:0] alpha_d;
    reg de_d,vs_d,hs_d,overlay_valid_d;
    always @(posedge clk) begin
        a_d<=a;b_d<=b;overlay_d<=overlay;alpha_d<=mask_alpha;
        de_d<=de;vs_d<=vs;hs_d<=hs;overlay_valid_d<=overlay_valid;
    end
    wire [23:0] rgb;
    wire out_de,out_vs,out_hs;
    scene_blend blend(.clk(clk),.rst(rst),.old_rgb(a_d),.new_rgb(b_d),
        .overlay_rgb(overlay_d),.overlay_valid(overlay_valid_d),.alpha(alpha_d),
        .de(de_d),.vs(vs_d),.hs(hs_d),.rgb(rgb),.out_de(out_de),
        .out_vs(out_vs),.out_hs(out_hs));
    task check;
        input good;input [511:0] message;
        begin if(good!==1'b1) begin
            $display("TEST_FAIL %0s e=%0d p=%0d xy=%0d,%0d",message,e,p,x,y);$finish;
        end end
    endtask
    task tick;begin @(negedge clk);end endtask
    task frame;begin frame_tick=1;tick;frame_tick=0;end endtask
    task reset;
        begin rst=1;request=0;frame_tick=0;old_idle=1;repeat(4) tick;rst=0;repeat(4) tick;end
    endtask
    function [23:0] mix;
        input [23:0] old_rgb,new_rgb;input integer weight;
        integer r,g,bb;
        begin
            r=(old_rgb[23:16]*(256-weight)+new_rgb[23:16]*weight+128)/256;
            g=(old_rgb[15:8]*(256-weight)+new_rgb[15:8]*weight+128)/256;
            bb=(old_rgb[7:0]*(256-weight)+new_rgb[7:0]*weight+128)/256;
            mix={r[7:0],g[7:0],bb[7:0]};
        end
    endfunction
    reg [24:0] q0,q1,q2;
    reg [1:0] s0,s1,s2;
    integer i,j,n,f,frames,xx,yy,k,want,total,tile_counts[0:1199];
    reg revealed[0:307199];
    reg [8:0] prior_progress;
    reg prior_ack;
    initial begin
        reset;
        scene=16'h1000;request=1;repeat(5) tick;
        check(current_scene==0,"first scene waits frame");frame;
        check(current_scene==scene && ack && !busy && progress==256,"first scene direct");
        for(i=0;i<4;i=i+1) for(j=0;j<4;j=j+1) begin
            effect=i;speed=j;scene=scene+1;request=~request;prior_ack=ack;
            repeat(6) tick;frame;
            check(busy && old_enable && progress==0 && active_effect==i,"runtime start");
            check(previous_scene==scene-1 && current_scene==scene,"descriptor snapshot");
            // Source settings may change immediately; the active transfer must not.
            effect=3-i;speed=3-j;old_idle=0;frames=16*(1<<j);
            for(n=1;n<=frames;n=n+1) begin
                prior_progress=progress;repeat(3) tick;
                check(progress==prior_progress && active_effect==i,"no midframe/config change");
                frame;
                check(progress==(n*256/frames) && ack==prior_ack,"exact duration and held ACK");
            end
            check(!old_enable && busy,"drain after last frame");
            repeat(2) frame;check(busy && ack==prior_ack,"inflight reader pinned");
            old_idle=1;tick;check(busy,"drain ACK frame only");frame;
            check(!busy && ack==request,"reader retirement ACK");
        end
        $display("SCENARIO_PASS TR-controller-16-combinations");
        // A pending toggle survives DRAIN; it must not replace the busy scene.
        scene=16'h2000;request=~request;repeat(5) tick;frame;old_idle=0;
        scene=16'h3000;request=~request;repeat(5) tick;
        repeat(130) frame;
        check(current_scene==16'h2000 && busy,"pending request must wait");
        old_idle=1;frame;frame;
        check(current_scene==16'h3000 && progress==0,"pending request after drain");
        reset;check(!busy && !old_enable && !ack && progress==256,"reset busy/pending");
        $display("SCENARIO_PASS TR-reset-pending");
        for(f=0;f<4;f=f+1) begin
            e=f;
            for(k=0;k<307200;k=k+1) revealed[k]=0;
            for(n=0;n<=16;n=n+1) begin
                p=n*16;total=0;
                for(k=0;k<1200;k=k+1) tile_counts[k]=0;
                for(yy=0;yy<480;yy=yy+1) for(xx=0;xx<640;xx=xx+1) begin
                    x=xx;y=yy;#1;
                    if(f==0) check(mask_alpha==p,"fade weight");
                    else begin
                        check(mask_alpha===9'd0 || mask_alpha===9'd256,"binary spatial mask");
                        if(n==0) check(mask_alpha==0,"old endpoint");
                        if(n==16) check(mask_alpha==256,"new endpoint");
                        if(f==1) check((mask_alpha==256)==(xx<640*n/16),"wipe geometry");
                        if(f==3) check((mask_alpha==256)==((yy%32)<2*n),"blinds geometry");
                        if(revealed[yy*640+xx]) check(mask_alpha==256,"monotonic stable reveal");
                        revealed[yy*640+xx]=(mask_alpha==256);
                        if(mask_alpha==256) begin
                            total=total+1;
                            k=(yy/16)*40+xx/16;tile_counts[k]=tile_counts[k]+1;
                        end
                    end
                end
                if(f==2) begin
                    check(total==307200*n/16,"dissolve exact whole-frame coverage");
                    for(k=0;k<1200;k=k+1)
                        check(tile_counts[k]==16*n,"dissolve uniform tile coverage");
                end
            end
        end
        $display("SCENARIO_PASS TR-mask-endpoints-monotonic");
        // Register the spatial mask with the image, exactly as the core does.
        // Exercise every row, column, blanking and overlay with a 3-stage queue.
        for(f=0;f<4;f=f+1) begin
            e=f;p=128;de=0;vs=0;hs=0;overlay_valid=0;
            repeat(6) tick;
            q0=0;q1=0;q2=0;s0=0;s1=0;s2=0;
            for(yy=0;yy<482;yy=yy+1) for(xx=0;xx<642;xx=xx+1) begin
                x=xx;y=yy;de=xx<640 && yy<480;vs=yy==481;hs=xx>=640;
                a={xx[7:0],yy[7:0],8'h17};b={yy[7:0],8'hc9,xx[7:0]};
                overlay=24'h12abcd;overlay_valid=(xx%97)==0;
                #1;
                if(f==0) want=128;
                else if(f==1) want=xx<320?256:0;
                else if(f==3) want=(yy%32)<16?256:0;
                else want=mask_alpha; // Pattern already checked by independent coverage properties.
                q2=q1;q1=q0;q0={de,overlay_valid?overlay:mix(a,b,want)};
                s2=s1;s1=s0;s0={vs,hs};
                @(posedge clk);#1;
                if(xx+yy*642>=3) begin
                    check(out_de===q2[24] && {out_vs,out_hs}===s2,"raster/sync latency");
                    check(rgb===q2[23:0],"mask/image/overlay alignment");
                end
                tick;
            end
        end
        $display("SCENARIO_PASS TR-pipeline-raster");
        $display("TEST_PASS");$finish;
    end
    initial begin #100000000;$display("TEST_FAIL transition watchdog");$finish;end
endmodule
`default_nettype wire
