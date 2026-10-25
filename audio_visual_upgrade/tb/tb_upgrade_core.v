`timescale 1ns/1ps
`default_nettype none
// Real SPI/FAT/loader, real encrypted SDR controller and IS42s32200 model.
// HDMI wrapper is a stub: TMDS/monitor behavior is outside this test.
module tb_upgrade_core;
    reg clk=0, clk_sdr=0, clk_sft=0, pix=0, pix5=0;
    always #10 clk=~clk;
    always #3.333 clk_sdr=~clk_sdr;
    initial begin #1.667; forever begin clk_sft=1; #3.333; clk_sft=0; #3.333; end end
    always #20 pix=~pix;
    always #4 pix5=~pix5;
    reg rst_n=0,rst_pix=1,rst_sdr=1,key4=1;
    wire sck,cs,mosi,miso,de,av,au,al;
    wire [23:0] rgb;
    wire [7:0] ad,cmd0;
    skeleton_core #(.SDR_CLK_MHZ(150),.KEY_DEBOUNCE_MS(1),.ROT_MS(100),
        .FADE_STEP(9'd128),.en_rot(1'b1),.en_pre(1'b1),.en_a9(1'b1),.en_fft(1'b1)) dut (
        .clk(clk),.rst_n(rst_n),.clk_pix(pix),.clk_pix5x(pix5),.rst_pix(rst_pix),
        .clk_sdr(clk_sdr),.clk_sdr_sft(clk_sft),.rst_sdr(rst_sdr),.key4(key4),
        .sd_sck(sck),.sd_cs_n(cs),.sd_mosi(mosi),.sd_miso(miso),
        .obs_de(de),.obs_rgb(rgb),.obs_axis_valid(av),.obs_axis_user(au),
        .obs_axis_last(al),.obs_axis_data(ad));
    sd_card_model_min #(.IMG_BYTES(262144),.MEM_FILE("sim/fat32_core.mem")) card (
        .sck(sck),.cs_n(cs),.mosi(mosi),.miso(miso),.cmd0_cnt(cmd0));

    integer bg_w[0:5],bg_h[0:5],bg_off[0:5],cv_w[0:5],cv_h[0:5],cv_off[0:5];
    `include "core_fixture.vh"
    reg [23:0] pixels[0:PIXEL_COUNT-1];
    initial $readmemh("sim/core_pixels.mem",pixels);
    integer map_bg[0:3],map_cv[0:3];
    integer i,sel,aid;
    integer cur=-1,old=-1,accepts=0,keys=0,rotations=0,ends=0;
    integer manual_accepts=0,auto_accepts=0,song_accepts=0;
    reg key_pending=0,auto_pending=0,song_pending=0;
    integer pin_checks=0;
    function integer bg_pair;
        input [20:0] a;
        begin case(a)
            21'h000000:bg_pair=0;21'h038400:bg_pair=1;
            21'h150000:bg_pair=2;21'h188400:bg_pair=3;
            default:bg_pair=-1;
        endcase end
    endfunction
    function integer cv_pair;
        input [20:0] a;
        begin case(a)
            21'h070800:cv_pair=0;21'h0a8c00:cv_pair=1;
            21'h1225a0:cv_pair=2;21'h1c0800:cv_pair=3;
            default:cv_pair=-1;
        endcase end
    endfunction
    function [23:0] scene_pixel;
        input integer sid,x,y;
        integer sx,sy;
        reg [23:0] c,v;
        begin
            c=24'h0a140a;
            if(sid>=0) begin
                sx=x-(640-bg_w[sid])/2;sy=y-(480-bg_h[sid])/2;
                if(sx>=0 && sx<bg_w[sid] && sy>=0 && sy<bg_h[sid])
                    c=pixels[bg_off[sid]+sy*bg_w[sid]+sx];
                sx=x-(260-cv_w[sid]/2);sy=y-(165-cv_h[sid]/2);
                if(sx>=0 && sx<cv_w[sid] && sy>=0 && sy<cv_h[sid]) begin
                    v=pixels[cv_off[sid]+sy*cv_w[sid]+sx];
                    if(v!=24'hff00ff) c=v;
                end
            end
            scene_pixel=c;
        end
    endfunction
    function [23:0] blend;
        input [23:0] o,n;
        input integer alpha;
        integer r,g,b;
        begin
            r=(o[23:16]*(256-alpha)+n[23:16]*alpha+128)/256;
            g=(o[15:8]*(256-alpha)+n[15:8]*alpha+128)/256;
            b=(o[7:0]*(256-alpha)+n[7:0]*alpha+128)/256;
            blend={r[7:0],g[7:0],b[7:0]};
        end
    endfunction
    function [23:0] color_model;
        input [23:0] src;
        input integer rel;
        integer r,g,b,lum;
        integer sat_delta,con_delta;
        integer sr,sg,sb,lr,lg,lb,cr,cg,cb;
        integer rr,gg,bb;
        begin
            if (rel<=0) begin
                color_model=src;
            end else begin
                r=src[23:16]; g=src[15:8]; b=src[7:0];
                // CSS filter luma matrix used by the HTML reference.
                lum=(55*r+183*g+18*b)>>8;
                sat_delta=(rel>>1)+(rel>>2)+(rel>>5)+(rel>>6);
                con_delta=(rel>>2)+(rel>>4)+(rel>>5);
                sr=(r-lum)*256+(r-lum)*sat_delta;
                sg=(g-lum)*256+(g-lum)*sat_delta;
                sb=(b-lum)*256+(b-lum)*sat_delta;
                lr=lum+((sr+128)>>>8)-128;
                lg=lum+((sg+128)>>>8)-128;
                lb=lum+((sb+128)>>>8)-128;
                cr=lr*256+lr*con_delta;
                cg=lg*256+lg*con_delta;
                cb=lb*256+lb*con_delta;
                rr=128+((cr+128)>>>8);
                gg=128+((cg+128)>>>8);
                bb=128+((cb+128)>>>8);
                if(rr<0) rr=0; else if(rr>255) rr=255;
                if(gg<0) gg=0; else if(gg>255) gg=255;
                if(bb<0) bb=0; else if(bb>255) bb=255;
                color_model={rr[7:0],gg[7:0],bb[7:0]};
            end
        end
    endfunction
    initial begin
        for(i=0;i<4;i=i+1) begin map_bg[i]=-1;map_cv[i]=-1;end
        if (dut.color_link(24'h0a140a,8'd3)!==color_model(24'h0a140a,3) ||
            dut.color_link(24'h0a140a,8'd162)!==color_model(24'h0a140a,162) ||
            dut.color_link(24'h7ebef2,8'd162)!==color_model(24'h7ebef2,162) ||
            dut.color_link(24'hd8a050,8'd255)!==color_model(24'hd8a050,255)) begin
            $display("TEST_FAIL color matrix samples");$finish;
        end
        $display("COLOR_SPOT_PASS");
        if(dut.u_lyr.C_SUNG!==24'hFF5FCB || dut.u_lyr.C_UNSUNG!==24'hE8E4FF ||
           dut.u_lyr.C_NEXT!==24'hE8E4FF) begin
            $display("TEST_FAIL lyric palette parameters");$finish;
        end
        #1000;rst_n=1;rst_pix=0;rst_sdr=0;
        #40;
        if (dut.color_rel!==dut.env_rel_q8) begin
            $display("TEST_FAIL color rel wiring");$finish;
        end
        wait(cur==0);
        #2000000; key4=0; #2000000;key4=1;
    end
    // Observe real source requests and loader destinations. No DUT force.
    always @(posedge clk) if(rst_n) begin
        if(dut.key_press) begin keys=keys+1;key_pending=1;end
        if(dut.rot_pulse) begin rotations=rotations+1;auto_pending=1;end
        if(dut.sw_req) song_pending=1;
        // Header probes have no SDRAM write; only record actual image loads.
        if(dut.task_start && !dut.task_raw && !dut.task_probe) begin
            aid=asset_of_file(dut.task_index);
            sel=bg_pair(dut.task_base);
            if(sel>=0) begin
                if(dut.pinned_slots[sel]) begin $display("TEST_FAIL writing pinned background");$finish;end
                map_bg[sel]=aid;
            end else begin
                sel=cv_pair(dut.task_base);
                if(sel<0 || dut.pinned_slots[sel]) begin $display("TEST_FAIL writing pinned cover");$finish;end
                map_cv[sel]=aid;
            end
        end
    end
    always @(negedge pix) if(!rst_pix) begin
        if(dut.wp_end) ends=ends+1;
        if(dut.scene_accepted) begin
            sel=bg_pair(dut.bg_slot);
            if(sel<0 || sel!=cv_pair(dut.cv_slot) || map_bg[sel]<0 || map_bg[sel]!=map_cv[sel]) begin
                $display("TEST_FAIL invalid scene identity bg=%h cv=%h bgID=%0d cvID=%0d",dut.bg_slot,dut.cv_slot,map_bg[sel],map_cv[sel]);$finish;
            end
            old=cur;cur=map_bg[sel];accepts=accepts+1;
            if(dut.cv_x!==260-cv_w[cur]/2 || dut.cv_y!==165-cv_h[cur]/2 ||
               dut.bg_w!==bg_w[cur] || dut.cv_h!==cv_h[cur]) begin
                $display("TEST_FAIL scene geometry");$finish;
            end
            if(key_pending && old>=0 && cur==1) begin manual_accepts=manual_accepts+1;key_pending=0;end
            if(auto_pending && old>=0 && cur!=old) begin auto_accepts=auto_accepts+1;auto_pending=0;end
            if(song_pending && cur>=3) begin song_accepts=song_accepts+1;song_pending=0;end
            $display("CORE_SCENE t=%0t old=%0d new=%0d slot=%0d alpha=%0d",$time,old,cur,sel,dut.fade_alpha);
        end
    end
    // Every SDR cycle during a fade protects old and new physical pairs.
    always @(posedge clk_sdr) if(!rst_sdr && dut.old_enable) begin
        pin_checks=pin_checks+1;
        if(!dut.pinned_slots[bg_pair(dut.bg_slot)] || !dut.pinned_slots[bg_pair(dut.obg_slot)]) begin
            $display("TEST_FAIL old/new scene not pinned through fade");$finish;
        end
    end

    integer x=0,y=0,gap=3000,frames=0,frame_pixels=0,checked=0,midpixels=0;
    integer axis_x=0,axis_y=0,axis_frames=0,audio_n=0,fft_n=0,text_n=0,next_lyric_n=0;
    integer audio_index=0,audio_song=0;
    reg lastde=0,lastav=0;
    reg [23:0] exp;
    reg [15:0] pcm;
    // Text/FFT ink is checked separately for activity. Golden comparison covers
    // background/transparent cover/fade in their image rows, outside text bands.
    always @(negedge pix) if(!rst_pix) begin
        if(dut.ff_vld) fft_n=fft_n+1;
        if(dut.ly_vld) begin
            text_n=text_n+1;
            if(!dut.u_lyr.any_ttl) begin
                if(dut.u_lyr.sel==2'd0 && dut.u_lyr.code==2'd2 && dut.ly_rgb!==24'hFF5FCB) begin
                    $display("TEST_FAIL sung lyric color %h",dut.ly_rgb);$finish;
                end
                if(dut.u_lyr.sel==2'd0 && dut.u_lyr.code!=2'd2 && dut.ly_rgb!==24'hE8E4FF) begin
                    $display("TEST_FAIL unsung lyric color %h",dut.ly_rgb);$finish;
                end
                if(dut.u_lyr.sel==2'd1) begin
                    next_lyric_n=next_lyric_n+1;
                    if(dut.ly_rgb!==24'hE8E4FF) begin
                        $display("TEST_FAIL second lyric color %h",dut.ly_rgb);$finish;
                    end
                end
            end
        end
        // Before prefill the player intentionally emits silence, not PCM.
        if(dut.wp_valid && dut.wp_primed) begin
            pcm=(audio_index+(audio_song==0 ? 0 : 16'h4000)) & 16'hffff;
            if(dut.wp_l!==pcm || dut.wp_r!==(~pcm & 16'hffff)) begin
                $display("TEST_FAIL PCM song=%0d index=%0d L=%h R=%h expectedL=%h",audio_song,audio_index,dut.wp_l,dut.wp_r,pcm);$finish;
            end
            audio_n=audio_n+1;audio_index=audio_index+1;
            if(audio_index==9600) begin audio_index=0;audio_song=audio_song+1;end
        end
        if(dut.wp_uc!=0) begin $display("TEST_FAIL audio underrun %0d",dut.wp_uc);$finish;end
        if(de) begin
            if(!lastde) begin
                x=0;
                if(gap>2000) begin
                    if(frames>0 && (y!=480 || frame_pixels!=307200)) begin
                        $display("TEST_FAIL frame size rows=%0d pixels=%0d",y,frame_pixels);$finish;
                    end
                    y=0;frame_pixels=0;frames=frames+1;
                end
            end
            if(cur>=0 && ((y>=232 && y<248) || (y>=157 && y<173))) begin
                exp=blend(scene_pixel(old,x,y),scene_pixel(cur,x,y),dut.fade_alpha);
                exp=color_model(exp,dut.color_rel);
                if(rgb!==exp) begin
                    $display("TEST_FAIL RGB t=%0t x=%0d y=%0d old=%0d cur=%0d alpha=%0d got=%h expected=%h raw=%h rel=%0d loud=%0d",$time,x,y,old,cur,dut.fade_alpha,rgb,exp,dut.cmp_raw_rgb,dut.color_rel,dut.env_loud_q8);$finish;
                end
                checked=checked+1;
                if(dut.fade_alpha==128) midpixels=midpixels+1;
            end
            x=x+1;frame_pixels=frame_pixels+1;gap=0;
        end else begin
            gap=gap+1;
            if(lastde) begin
                if(x!=640) begin $display("TEST_FAIL DE line length %0d",x);$finish;end
                y=y+1;
            end
        end
        lastde=de;
        if(av) begin
            if(au) begin
                if(axis_frames>0 && (axis_y!=480 || axis_x!=0)) begin $display("TEST_FAIL AXIS frame length");$finish;end
                axis_y=0;axis_x=0;axis_frames=axis_frames+1;
            end
            if(al!==(axis_x==639)) begin $display("TEST_FAIL AXIS last x=%0d",axis_x);$finish;end
            if(ad!==dut.ax_data[7:0]) begin $display("TEST_FAIL AXIS data");$finish;end
            if(axis_x==639) begin axis_x=0;axis_y=axis_y+1;end
            else axis_x=axis_x+1;
        end
        lastav=av;
        if(song_accepts>0 && !dut.fade_busy && audio_n>10000 && midpixels>1000 && frames>18) begin
            if(keys<1 || manual_accepts<1 || auto_accepts<1 || rotations<1 || ends<1 ||
               pin_checks<1000 || checked<50000 || fft_n<1 || text_n<1 || cmd0<1) begin
                $display("TEST_FAIL missing activity manual=%0d auto=%0d song=%0d fft=%0d text=%0d next=%0d",manual_accepts,auto_accepts,song_accepts,fft_n,text_n,next_lyric_n);$finish;
            end
            $display("CORE_COUNTS frames=%0d checked=%0d mid=%0d pcm=%0d pins=%0d second_lyric=%0d",frames,checked,midpixels,audio_n,pin_checks,next_lyric_n);
            $display("SCENARIO_PASS real_spi_boot_and_layout");
            $display("SCENARIO_PASS key_and_timer_fade_pixels");
            $display("SCENARIO_PASS natural_song_end_fade_and_slot_protection");
            $display("SCENARIO_PASS pcm_and_video_stream_integrity");
            $display("TEST_PASS");$finish;
        end
    end
    initial begin #550000000;
        $display("TEST_FAIL core timeout accepts=%0d song=%0d pcm=%0d manual=%0d auto=%0d",accepts,song_accepts,audio_n,manual_accepts,auto_accepts);$finish;
    end
endmodule
`default_nettype wire
