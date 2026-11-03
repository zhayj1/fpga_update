`timescale 1ns/1ps
`default_nettype none
// Focused integration: real scene/filter/text/OSD pipelines; controlled layer
// pixels replace storage here. Real SPI/SDRAM/audio run in the system regression.
module tb_typography_core;
    reg clk=0,pix=0,pix5=0,sdr=0;
    always #10 clk=~clk;
    always #20 pix=~pix;
    always #4 pix5=~pix5;
    always #5 sdr=~sdr;
    reg rst_n=0,rst_pix=1,drive_de=0,drive_vs=1;
    reg [23:0] new_pixel=0,old_pixel=0,fft_pixel=0,text_pixel=0;
    reg fft_valid=0;
    reg [3:0] coverage=0;
    reg [8:0] fade=256;
    reg [1:0] osd_show=0;
    wire de;wire [23:0] rgb;
    skeleton_core #(.TYPOGRAPHY(1),.SDR_CLK_MHZ(100),.en_osd(1),
        .en_rot(0),.en_pre(0),.en_a9(0)) dut (
        .clk(clk),.rst_n(rst_n),.clk_pix(pix),.clk_pix5x(pix5),.rst_pix(rst_pix),
        .clk_sdr(sdr),.clk_sdr_sft(sdr),.rst_sdr(1'b1),
        .key2(1'b1),.key3(1'b1),.key4(1'b1),.sd_miso(1'b1),.obs_de(de),.obs_rgb(rgb));
    reg [24:0] osd_golden[0:983039];
    reg [23:0] exp0=0,exp1=0,exp2=0,input_expected=0;
    reg de0=0,de1=0,de2=0;
    reg checking=0,render=0;
    reg axis_expected_de=0,axis_expected_last=0;
    reg [23:0] axis_expected_rgb=0;
    integer axis_x=0,axis_pixels=0,axis_lines=0;
    integer checked=0,fd,xx,yy,j,i;
    integer px,py,rr,gg,bb,rot,grp,physical;
    reg [20:0] map_address=0;
    reg [23:0] scene_expected;
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
    task prepare_expected;
        integer oc,nc,ch,outc;
        reg [23:0] mixed,filtered;
        begin
            mixed=0;
            for(ch=0;ch<3;ch=ch+1) begin
                oc=(old_pixel>>(ch*8))&255;nc=(new_pixel>>(ch*8))&255;
                outc=oc+(((nc-oc)*fade+128)>>>8);
                mixed=mixed | ((outc&255)<<(ch*8));
            end
            if(fft_valid) mixed=fft_pixel;
            filtered=filter(mixed);input_expected=0;
            for(ch=0;ch<3;ch=ch+1) begin
                oc=(filtered>>(ch*8))&255;nc=(text_pixel>>(ch*8))&255;
                outc=(oc*(15-coverage)+nc*coverage+7)/15;
                input_expected=input_expected | ((outc&255)<<(ch*8));
            end
            if(render && drive_de) begin
                px=dut.ff_x;py=dut.ff_y;
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
                if(de!==de2 || (de2 && rgb!==exp2)) begin
                    $display("TEST_FAIL typography core t=%0t DE=%b/%b rgb=%h/%h src=%h a=%0d raster=%0d,%0d",
                        $time,de,de2,rgb,exp2,input_expected,coverage,dut.ff_x,dut.ff_y);$finish;
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
                if(de2) begin
                    checked=checked+1;
                    if(render) $fdisplay(fd,"%06h",rgb);
                end
            end
            exp2=exp1;exp1=exp0;exp0=input_expected;de2=de1;de1=de0;de0=drive_de;
            @(negedge pix);
        end
    endtask
    initial begin
        if(dut.g_aa_text.u_lyr.TTL_Y0!=45 || dut.g_aa_text.u_lyr.SGR_Y0!=77 ||
           dut.g_aa_text.u_lyr.WIN_Y0!=118 || dut.g_aa_text.u_lyr.ROW_Y0!=190 ||
           dut.g_aa_text.u_lyr.PITCH!=36 || dut.g_aa_text.u_lyr.WIN_H!=167 ||
           dut.g_aa_text.u_lyr.LAST_GAP_TRIM!=1 || dut.u_pick.SC_PX!=36) begin
            $display("TEST_FAIL text group does not align with cover y=45");$finish;
        end
        $readmemh("sim/typography_osd_golden.mem",osd_golden);
        force dut.cb_de=drive_de;force dut.cb_vs=drive_vs;force dut.cb_hs=1'b1;
        force dut.bg_vld=1;force dut.obg_vld=1;
        force dut.bg_rgb=new_pixel;force dut.obg_rgb=old_pixel;
        force dut.cv_vld=0;force dut.ocv_vld=0;force dut.ring_vld=0;
        force dut.ff_vld=fft_valid;force dut.ff_rgb=fft_pixel;
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
            text_pixel=(i*24'h030b0d)^24'hff5fcb;coverage=i%16;fft_valid=(i%3)==0;
            case(i%3) 0:fade=0;1:fade=128;2:fade=256;endcase
            step;
        end
        drive_de=0;coverage=0;fft_valid=0;repeat(5) step;
        if(checked<300) begin $display("TEST_FAIL insufficient mixed pixels");$finish;end
        $display("SCENARIO_PASS TYP-06-composition");
        drive_vs=0;repeat(5) step;drive_vs=1;repeat(5) step;
        osd_show=3;render=1;checked=0;
        fd=$fopen("sim/osd_bottom_right_core_actual.mem","w");
        for(yy=0;yy<480;yy=yy+1) begin
            for(xx=0;xx<640;xx=xx+1) begin
                drive_de=1;coverage=xx%16;text_pixel=24'hff5fcb;
                new_pixel=(xx*24'h010003)^(yy*24'h030100);old_pixel=24'h314151;
                fft_valid=xx[5];fft_pixel=24'h4bcab4;fade=(yy%3)*128;
                step;
            end
            drive_de=0;coverage=0;repeat(12) step;
        end
        repeat(5) step;$fclose(fd);
        if(checked!=307200) begin $display("TEST_FAIL frame pixels=%0d",checked);$finish;end
        if(axis_pixels!=307200 || axis_lines!=480) begin
            $display("TEST_FAIL AX frame pixels=%0d lines=%0d",axis_pixels,axis_lines);$finish;
        end
        $display("SCENARIO_PASS TYP-06-osd-alignment");
        $display("SCENARIO_PASS FIX-03-axis-pixel-valid-last");
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
        $display("SCENARIO_PASS FULL-04-core-memory-map-and-lyric-slots");
        $display("TEST_PASS");$finish;
    end
    initial begin #20000000;$display("TEST_FAIL typography core timeout");$finish;end
endmodule
`default_nettype wire
