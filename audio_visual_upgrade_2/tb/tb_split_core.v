`timescale 1ns/1ps
`default_nettype none
// Focused integration: real scene/filter/text/OSD pipelines; controlled layer
// pixels replace storage here. Real SPI/SDRAM/audio run in the system regression.
module tb_split_core;
    reg clk=0,pix=0,pix5=0,sdr=0;
    always #10 clk=~clk;
    always #20 pix=~pix;
    always #4 pix5=~pix5;
    always #5 sdr=~sdr;
    reg rst_n=0,rst_pix=1,drive_de=0,drive_vs=1;
    reg [23:0] new_pixel=0,old_pixel=0,fft_pixel=0,text_pixel=0;
    reg fft_valid=0;
    reg [3:0] spectrum_alpha=0;
    reg [23:0] sf0=0,sf1=0,sf2=0;
    reg [3:0] sa0=0,sa1=0,sa2=0;
    always @(posedge pix)begin
        sf0<=fft_pixel;sf1<=sf0;sf2<=sf1;
        sa0<=fft_valid?spectrum_alpha:0;sa1<=sa0;sa2<=sa1;
    end
    reg [3:0] coverage=0;
    reg [8:0] fade=256;
    reg [1:0] osd_show=0;
    wire de;wire [23:0] rgb;
    skeleton_core #(.SPLIT_UI(1),.CIRCULAR_UI(1),.TYPOGRAPHY(1),.VISUAL_CONTROLS(1),.SDR_CLK_MHZ(100),.en_osd(1),
        .en_rot(0),.en_pre(0),.en_a9(0)) dut (
        .clk(clk),.rst_n(rst_n),.clk_pix(pix),.clk_pix5x(pix5),.rst_pix(rst_pix),
        .clk_sdr(sdr),.clk_sdr_sft(sdr),.rst_sdr(1'b1),
        .key2(1'b1),.key3(1'b1),.key4(1'b1),.sd_miso(1'b1),.obs_de(de),.obs_rgb(rgb));
    reg [24:0] osd_golden[0:983039];
    reg [23:0] exp0=0,exp1=0,exp2=0,exp3=0,input_expected=0;
    reg de0=0,de1=0,de2=0,de3=0;
    reg checking=0,render=0;
    reg axis_expected_de=0,axis_expected_last=0;
    reg [23:0] axis_expected_rgb=0;
    integer axis_x=0,axis_pixels=0,axis_lines=0;
    integer checked=0,fd,xx,yy,j,i;
    integer px,py,rr,gg,bb,rot,grp,physical;
    reg [20:0] map_address=0;
    reg [23:0] scene_expected;
    reg [3:0] cover_gold[0:253235];
    reg [23:0] cv_new=24'hbf2f71,cv_old=24'h249d87;
    reg cv_on=0,ocv_on=0,ring_on=0;
    reg [7:0] ring_a=0;
    reg [1:0] pop=0;
    integer sz,cx,cy,addr,ca;
    reg [1:0] text_kind=0;
    reg text_current=0;
    reg [7:0] text_sample=0;
    reg [23:0] expected_text;
    function [23:0] under;
        input [23:0] bg;
        integer n,b,f,v;
        begin
            under=bg;
            if(ring_on) for(n=0;n<3;n=n+1) begin
                b=(bg>>(n*8))&255; f=(24'h5ee8ed>>(n*8))&255;
                v=b+(((f-b)*ring_a+128)>>>8);
                under=(under & ~(24'hff<<(n*8))) | ((v&255)<<(n*8));
            end
        end
    endfunction
    function [23:0] covered;
        input [23:0] bg,fg;
        input integer a;
        integer n,b,f,v;
        begin
            covered=0;
            for(n=0;n<3;n=n+1) begin
                b=(bg>>(n*8))&255;f=(fg>>(n*8))&255;
                v=(b*(15-a)+f*a+7)/15;
                covered=covered|((v&255)<<(n*8));
            end
        end
    endfunction
    function [7:0] clip;
        input integer a;
        begin clip=(a<0)?0:((a>255)?255:a);end
    endfunction
    function [23:0] filter;
        input [23:0] s;
        integer r,g,b,l,ar,ag,ab;
        begin
            r=s[23:16];g=s[15:8];b=s[7:0];l=(55*r+183*g+18*b)>>8;
            ar=l+(((r-l)*320+128)>>>8);
            ag=l+(((g-l)*320+128)>>>8);
            ab=l+(((b-l)*320+128)>>>8);
            filter={clip(128+(((ar-128)*288+128)>>>8)),
                    clip(128+(((ag-128)*288+128)>>>8)),
                    clip(128+(((ab-128)*288+128)>>>8))};
        end
    endfunction
    function [23:0] reference_filter;
        input [23:0] src;
        input [9:0] sat_gain, con_gain;
        reg [7:0] r,g,b,lum;
        reg signed [10:0] sat_delta,con_delta;
        reg signed [17:0] dr,dg,db;
        reg signed [19:0] sr,sg,sb;
        reg signed [19:0] sat_r,sat_g,sat_b;
        reg signed [19:0] lr,lg,lb;
        reg signed [19:0] cr,cg,cb;
        begin
            r=src[23:16]; g=src[15:8]; b=src[7:0];
            // Canvas saturate()/contrast() uses the CSS filter luma matrix
            // 0.213/0.715/0.072. 55/183/18 is its Q8 shift/add form.
            lum=({3'd0,r,5'd0}+{4'd0,r,4'd0}+{6'd0,r,2'd0}+{7'd0,r,1'd0}+{8'd0,r}+
                 {1'd0,g,7'd0}+{3'd0,g,5'd0}+{4'd0,g,4'd0}+{6'd0,g,2'd0}+
                 {7'd0,g,1'd0}+{8'd0,g}+
                 {4'd0,b,4'd0}+{7'd0,b,1'd0}) >> 8;
            sat_delta=$signed({1'b0,sat_gain})-11'sd256;
            con_delta=$signed({1'b0,con_gain})-11'sd256;
            if (sat_gain==10'd256 && con_gain==10'd256) begin
                reference_filter=src;
            end else begin
            dr=$signed({1'b0,r})-$signed({1'b0,lum});
            dg=$signed({1'b0,g})-$signed({1'b0,lum});
            db=$signed({1'b0,b})-$signed({1'b0,lum});
            sr=dr*20'sd256+dr*sat_delta;
            sg=dg*20'sd256+dg*sat_delta;
            sb=db*20'sd256+db*sat_delta;
            sat_r=$signed({1'b0,lum})+((sr+20'sd128)>>>8);
            sat_g=$signed({1'b0,lum})+((sg+20'sd128)>>>8);
            sat_b=$signed({1'b0,lum})+((sb+20'sd128)>>>8);
            lr=sat_r-20'sd128; lg=sat_g-20'sd128; lb=sat_b-20'sd128;
            cr=lr*20'sd256+lr*con_delta;
            cg=lg*20'sd256+lg*con_delta;
            cb=lb*20'sd256+lb*con_delta;
            reference_filter={clip(20'sd128+((cr+20'sd128)>>>8)),
                        clip(20'sd128+((cg+20'sd128)>>>8)),
                        clip(20'sd128+((cb+20'sd128)>>>8))};
            end
        end
    endfunction
    task prepare_expected;
        integer oc,nc,ch,outc;
        reg [23:0] mixed,filtered,new_scene,old_scene;
        begin
            case(pop) 0:begin sz=240;addr=0;end 1:begin sz=250;addr=57600;end
                2:begin sz=256;addr=120100;end 3:begin sz=260;addr=185636;end endcase
            cx=dut.ff_x-40+(sz-240)/2;cy=dut.ff_y-134+(sz-240)/2;
            ca=0;if(cx>=0 && cx<sz && cy>=0 && cy<sz) ca=cover_gold[addr+cy*sz+cx];
            new_scene=covered(under(new_pixel),cv_new,cv_on?ca:0);
            old_scene=covered(under(old_pixel),cv_old,ocv_on?ca:0);
            mixed=0;
            for(ch=0;ch<3;ch=ch+1) begin
                oc=(old_scene>>(ch*8))&255;nc=(new_scene>>(ch*8))&255;
                outc=oc+(((nc-oc)*fade+128)>>>8);
                mixed=mixed | ((outc&255)<<(ch*8));
            end
            if(fft_valid) mixed=covered(mixed,fft_pixel,spectrum_alpha);
            filtered=filter(mixed);input_expected=0;
            for(ch=0;ch<3;ch=ch+1) begin
                oc=(filtered>>(ch*8))&255;nc=(text_pixel>>(ch*8))&255;
                outc=(oc*(15-coverage)+nc*coverage+7)/15;
                input_expected=input_expected | ((outc&255)<<(ch*8));
            end
            if(render && drive_de && osd_show!=0) begin
                px=dut.ff_x;py=dut.ff_y+32;
                // Preserve the independent original OSD reference and apply
                // the requested (+16,+240) translation at the checker boundary.
                if(px>=16 && py>=240 && py<496) begin
                    if(osd_golden[327680+(py-240)*640+(px-16)][24])
                        input_expected=osd_golden[327680+(py-240)*640+(px-16)][23:0];
                end
            end
        end
    endtask
    task step;
        begin
            #1;prepare_expected;
            // Independently track the actual final raster before the output
            // register samples it; this catches sideband/pixel skew introduced
            // by an added composition stage, including the 640th pixel.
            axis_expected_de=de;axis_expected_rgb=rgb;
            axis_expected_last=de && axis_x==639;
            if(de) axis_x=axis_x+1;else axis_x=0;
            @(posedge pix);#1;
            if(checking) begin
                if(de!==de3 || (de3 && rgb!==exp3)) begin
                    $display("TEST_FAIL typography core t=%0t DE=%b/%b rgb=%h/%h src=%h a=%0d raster=%0d,%0d",
                        $time,de,de3,rgb,exp3,input_expected,coverage,dut.ff_x,dut.ff_y);$finish;
                end
                if(dut.ax_valid!==axis_expected_de ||
                   (axis_expected_de && dut.ax_data!==axis_expected_rgb) ||
                   dut.ax_last_use!==axis_expected_last) begin
                    $display("TEST_FAIL typography AX t=%0t valid=%b/%b data=%h/%h last=%b/%b x=%0d",
                        $time,dut.ax_valid,axis_expected_de,dut.ax_data,axis_expected_rgb,
                        dut.ax_last_use,axis_expected_last,axis_x);$finish;
                end
                if(render && axis_expected_de) axis_pixels=axis_pixels+1;
                if(render && axis_expected_last) axis_lines=axis_lines+1;
                if(de3) begin
                    checked=checked+1;
                    if(render) $fdisplay(fd,"%06h",rgb);
                end
            end
            exp3=exp2;exp2=exp1;exp1=exp0;exp0=input_expected;de3=de2;de2=de1;de1=de0;de0=drive_de;
            @(negedge pix);
        end
    endtask
    integer gs,gc,ci,ri,seed_math;
    reg [23:0] math_rgb,math_got,math_expected;
    task check_filter;
        begin
            math_got=dut.color_link_gains(math_rgb,gs[9:0],gc[9:0]);
            math_expected=reference_filter(math_rgb,gs[9:0],gc[9:0]);
            if(math_got!==math_expected) begin
                $display("TEST_FAIL filter equivalence rgb=%h sat=%0d con=%0d got=%h expected=%h",math_rgb,gs,gc,math_got,math_expected);$finish;
            end
        end
    endtask
    initial begin
        seed_math=32'h1af08a;
        for(gs=0;gs<1024;gs=gs+1) begin
            for(ci=0;ci<9;ci=ci+1) begin
                case(ci) 0:gc=0;1:gc=1;2:gc=255;3:gc=256;4:gc=257;
                5:gc=435;6:gc=511;7:gc=666;8:gc=1023;endcase
                for(ri=0;ri<16;ri=ri+1) begin
                    math_rgb={ri[0]?8'hff:8'h00,ri[1]?8'hff:8'h00,ri[2]?8'hff:8'h00};
                    if(ri>=8) math_rgb=24'h010101*(32*(ri-8)+16);
                    check_filter;
                end
            end
        end
        for(ri=0;ri<65536;ri=ri+1) begin
            math_rgb=$random(seed_math);gs=$random(seed_math)&1023;gc=$random(seed_math)&1023;
            check_filter;
        end
        $display("SCENARIO_PASS VIS-filter-exact-arithmetic");
        if(dut.g_aa_text.u_lyr.TTL_Y0!=82 || dut.g_aa_text.u_lyr.SGR_Y0!=116 ||
           dut.g_aa_text.u_lyr.WIN_Y0!=166 || dut.g_aa_text.u_lyr.ROW_Y0!=262 ||
           dut.g_aa_text.u_lyr.PITCH!=32 || dut.g_aa_text.u_lyr.WIN_H!=216 ||
           dut.g_aa_text.u_lyr.LAST_GAP_TRIM!=0 || dut.u_pick.SC_PX!=32 ||
           dut.g_aa_text.u_lyr.LRC_SMALL!=1 || dut.g_aa_text.u_lyr.LRC_X!=340 ||
           dut.g_aa_text.u_lyr.LRC_W!=280) begin
            $display("TEST_FAIL circular text anchor mismatch");$finish;
        end
        $readmemh("sim/typography_osd_golden.mem",osd_golden);
        $readmemh("sim/cover_coverage_golden.mem",cover_gold);
        force dut.cb_de=drive_de;force dut.cb_vs=drive_vs;force dut.cb_hs=1'b1;
        force dut.bg_vld=1;force dut.obg_vld=1;
        force dut.bg_rgb=new_pixel;force dut.obg_rgb=old_pixel;
        force dut.cv_vld=cv_on;force dut.ocv_vld=ocv_on;force dut.ring_vld=ring_on;
        force dut.cv_rgb=cv_new;force dut.ocv_rgb=cv_old;force dut.ring_alpha=ring_a;
        force dut.cover_pop_level=pop;
        force dut.ff_vld=(sa2!=0);force dut.ff_rgb=sf2;force dut.spectrum_coverage=sa2;
        force dut.ly_rgb=text_pixel;force dut.ly_vld=(coverage!=0);force dut.text_alpha=coverage;
        force dut.fade_alpha=fade;
        force dut.sat_gain_cfg=320;force dut.con_gain_cfg=288;
        force dut.osd_visible_sync=osd_show;
        force dut.osd_page_s2=2;force dut.osd_selected_s2=2;
        force dut.osd_volume_s2=0;force dut.osd_sat_base_s2=60;force dut.osd_sat_max_s2=100;
        force dut.osd_con_base_s2=80;force dut.osd_con_max_s2=100;
        repeat(8) @(negedge pix);rst_n=1;rst_pix=0;
        repeat(5) step;
        checking=1;
        for(i=0;i<512;i=i+1) begin
            drive_de=(i%17)<13;new_pixel=(i*24'h030709)^24'h294161;
            old_pixel=(i*24'h0b0503)^24'hb56237;fft_pixel=(i*24'h070311)^24'h3ca68f;
            text_pixel=(i*24'h030b0d)^24'hff5fcb;coverage=i%16;spectrum_alpha=(i/3)%16;fft_valid=(i%3)==0;
            case(i%3) 0:fade=0;1:fade=128;2:fade=256;endcase
            step;
        end
        drive_de=0;coverage=0;fft_valid=0;repeat(5) step;
        if(checked<300) begin $display("TEST_FAIL insufficient mixed pixels");$finish;end
        $display("SCENARIO_PASS VIS-core-composition");
        drive_vs=0;repeat(5) step;drive_vs=1;repeat(5) step;
        osd_show=0;render=1;checked=0;cv_on=1;ocv_on=1;ring_on=1;ring_a=96;
        fd=$fopen("sim/capsule_core_actual.mem","w");
        for(yy=0;yy<480;yy=yy+1) begin
            pop=yy%4;cv_new=(yy*24'h070301)^24'hbf2f71;
            ring_a=yy%256;cv_on=(yy%5)!=0;ocv_on=(yy%7)!=0;
            for(xx=0;xx<640;xx=xx+1) begin
                drive_de=1;coverage=xx%16;text_pixel=24'hff5fcb;
                new_pixel=(xx*24'h010003)^(yy*24'h030100);old_pixel=24'h314151;
                fft_valid=xx[5];spectrum_alpha=xx%16;fft_pixel=24'h4bcab4;fade=(yy%3)*128;
                step;
            end
            drive_de=0;coverage=0;repeat(12) step;
        end
        repeat(5) step;$fclose(fd);
        if(checked!=307200) begin $display("TEST_FAIL frame pixels=%0d",checked);$finish;end
        if(axis_pixels!=307200 || axis_lines!=480) begin
            $display("TEST_FAIL AX frame pixels=%0d lines=%0d",axis_pixels,axis_lines);$finish;
        end
        $display("SCENARIO_PASS VIS-core-AA-fade-rings");
        $display("SCENARIO_PASS VIS-core-axis");
        for(rot=0;rot<4;rot=rot+1) for(grp=1;grp<=3;grp=grp+1) begin
            physical=(grp-1+rot)%4;
            if(dut.bg_base_f(grp,rot)!==physical*230400 ||
               dut.cv_base_f(grp,rot)!==(921600+physical*43200) ||
               dut.u_assets.image_base(2*physical)!==dut.bg_base_f(grp,rot) ||
               dut.u_assets.image_base(2*physical+1)!==dut.cv_base_f(grp,rot)) begin
                $display("TEST_FAIL TYP2 image slot map rot=%0d grp=%0d",rot,grp);$finish;
            end
        end
        if(dut.u_pick.LRC_BASE!==21'h10B300 || dut.g_aa_text.u_lyr.LRC_BASE!==21'h10B300 ||
           dut.g_aa_text.u_lyr.FONT_BASE!==21'h10BBB0) begin
            $display("TEST_FAIL TYP2 text module base");$finish;end
        force dut.c2_addr_raw=map_address;force dut.lp_px_addr_raw=map_address;
        force dut.lrc_slot_sync=2'b11;
        for(i=0;i<1112;i=i+1) begin
            map_address=21'h10B300+i;#1;
            if(dut.c2_addr!==map_address+1112 || dut.lp_px_addr!==map_address+1112) begin
                $display("TEST_FAIL TYP2 LRC slot remap");$finish;end
        end
        map_address=21'h10BBB0;#1;
        if(dut.c2_addr!==map_address) begin $display("TEST_FAIL font incorrectly remapped");$finish;end
        map_address=21'h10B2FC;#1;
        if(dut.c2_addr!==map_address) begin $display("TEST_FAIL image incorrectly remapped");$finish;end
        release dut.c2_addr_raw;release dut.lp_px_addr_raw;release dut.lrc_slot_sync;
        $display("SCENARIO_PASS VIS-core-memory-map");
        // Exercise the real text output and its top-level colour connections.
        // RAM content/geometric validity are controlled; colour selection is not.
        release dut.ly_rgb;release dut.ly_vld;release dut.text_alpha;
        force dut.color_title=24'h123456;force dut.color_singer=24'hab7319;
        force dut.color_sung=24'h4271d5;force dut.color_other=24'h91d228;
        force dut.g_aa_text.u_lyr.active_kind=text_kind;
        force dut.g_aa_text.u_lyr.active_cur=text_current;
        force dut.g_aa_text.u_lyr.memory_pixel=text_sample;
        force dut.g_aa_text.u_lyr.active_ok=1;
        force dut.g_aa_text.u_lyr.pixel_inside=1;
        force dut.g_aa_text.u_lyr.de=1;
        force dut.g_aa_text.u_lyr.en=1;force dut.g_aa_text.u_lyr.en_ttl=1;
        for(i=0;i<3;i=i+1) for(j=0;j<64;j=j+1) begin
            text_kind=i;text_current=j/32;text_sample=j%32;#1;
            expected_text=i==1?24'h123456:i==2?24'hab7319:
                (j>=48?24'h4271d5:24'h91d228);
            if(dut.ly_rgb!==expected_text || dut.text_alpha!==text_sample[3:0] ||
               dut.ly_vld!==(text_sample[3:0]!=0)) begin
                $display("TEST_FAIL text color connection kind=%0d sample=%0d rgb=%h expected=%h",i,j,dut.ly_rgb,expected_text);$finish;
            end
        end
        $display("SCENARIO_PASS VIS-core-text-colors");
        $display("TEST_PASS");$finish;
    end
    initial begin #20000000;$display("TEST_FAIL typography core timeout");$finish;end
endmodule
`default_nettype wire

