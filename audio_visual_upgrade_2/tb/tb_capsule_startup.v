`timescale 1ns/1ps
`default_nettype none
// Production display switches and 100 MHz / 180-degree SDRAM clocks.
// Real SPI, FAT, loaders and SDRAM; compact images, legacy fixture font skipped.
// No forces. HDMI and PLL analog behavior remain outside this simulation.
module tb_capsule_startup;
    reg clk=0,pix=0,pix5=0,sdr=0;
    always #10 clk=~clk;always #20 pix=~pix;always #4 pix5=~pix5;always #5 sdr=~sdr;
    wire sft=~sdr;
    reg rn=0,rp=1,rs=1;
    wire sck,cs,mosi,miso,de;wire [23:0] rgb;wire [7:0] cmd0;
    skeleton_core #(.CIRCULAR_UI(1),.TYPOGRAPHY(1),.VISUAL_CONTROLS(1),.en_osd(1),
        .SDR_CLK_MHZ(100),.BMP_BG_W(8),.BMP_BG_H(6),.BMP_COVER_W(5),.BMP_COVER_H(5),
        .BMP_DOWNSCALE(1)) dut(
        .clk(clk),.rst_n(rn),.clk_pix(pix),.clk_pix5x(pix5),.rst_pix(rp),
        .clk_sdr(sdr),.clk_sdr_sft(sft),.rst_sdr(rs),.key2(1'b1),.key3(1'b1),.key4(1'b1),
        .sd_sck(sck),.sd_cs_n(cs),.sd_mosi(mosi),.sd_miso(miso),.obs_de(de),.obs_rgb(rgb));
    sd_card_model_min #(.IMG_BYTES(262144),.MEM_FILE("sim/fat32_downscale.mem")) card(
        .sck(sck),.cs_n(cs),.mosi(mosi),.miso(miso),.cmd0_cnt(cmd0));
    integer pcm_n=0,scene_n=0,frame_n=0,ink=0,bg_n=0,aa_n=0;
    integer row_pixels=0,rows=0,total=0,gap=3000;
    reg lastde=0;reg [15:0] expected;
    always @(negedge pix) if(!rp)begin
        if(dut.scene_accepted)begin
            scene_n=scene_n+1;
            if(!dut.bg_en||!dut.cv_en||dut.cv_x!=318||dut.cv_y!=252)begin
                $display("TEST_FAIL startup scene metadata bg=%b cv=%b xy=%0d,%0d",dut.bg_en,dut.cv_en,dut.cv_x,dut.cv_y);$finish;
            end
        end
        if(dut.wp_valid&&dut.wp_primed)begin
            expected=pcm_n;
            if(dut.wp_l!==expected||dut.wp_r!==(~expected & 16'hffff))begin
                $display("TEST_FAIL startup PCM n=%0d L=%h R=%h",pcm_n,dut.wp_l,dut.wp_r);$finish;
            end
            pcm_n=pcm_n+1;
        end
        if(dut.wp_uc!=0)begin $display("TEST_FAIL startup underrun");$finish;end
        if(dut.bg_vld)bg_n=bg_n+1;
        if(dut.spectrum_coverage>0&&dut.spectrum_coverage<15)aa_n=aa_n+1;
        if(de)begin
            if(!lastde)begin
                row_pixels=0;
                if(gap>2000)begin
                    if(frame_n>0&&(rows!=480||total!=307200))begin $display("TEST_FAIL startup frame size");$finish;end
                    rows=0;total=0;frame_n=frame_n+1;
                end
            end
            if(^rgb===1'bx)begin $display("TEST_FAIL startup unknown RGB t=%0t rgb=%h raw=%h scene=%h sp=%h a=%h text=%h ta=%h col=%h bg=%h/%b cv=%h/%b old=%h new=%h fade=%d lf=%d",$time,rgb,dut.cmp_raw_rgb,dut.scene_raw_rgb,dut.ff_rgb,dut.spectrum_coverage,dut.ly_rgb,dut.text_alpha,dut.colorized_rgb,dut.bg_rgb,dut.bg_vld,dut.cv_rgb,dut.cv_vld,dut.old_image,dut.new_image,dut.fade_alpha,dut.lf_st);$finish;end
            if(rgb!=24'h0a140a)ink=ink+1;
            row_pixels=row_pixels+1;total=total+1;gap=0;
        end else begin
            gap=gap+1;
            if(lastde)begin
                if(row_pixels!=640)begin $display("TEST_FAIL startup line length");$finish;end
                rows=rows+1;
            end
        end
        lastde=de;
        if(pcm_n>=1500&&frame_n>=4&&bg_n>30&&aa_n>1000&&scene_n>0)begin
            if(dut.lf_st!=7||!dut.au_wav_sel||cmd0==0)begin $display("TEST_FAIL startup incomplete");$finish;end
            $display("CAPS_BOOT pcm=%0d scenes=%0d frames=%0d background=%0d AA=%0d",pcm_n,scene_n,frame_n,bg_n,aa_n);
            $display("SCENARIO_PASS CAPS-real-100MHz-SPI-SDRAM-startup");
            $display("SCENARIO_PASS CAPS-production-display-switches-frame-alignment");
            $display("SCENARIO_PASS CAPS-real-PCM-after-media-load");
            $display("TEST_PASS");$finish;
        end
    end
    initial begin #1000;rn=1;rp=0;rs=0;end
    initial begin #180000000;
        $display("TEST_FAIL startup timeout lf=%0d au=%0d err=%h pcm=%0d scenes=%0d frames=%0d bg=%0d aa=%0d",dut.lf_st,dut.au_st,dut.au_werr,pcm_n,scene_n,frame_n,bg_n,aa_n);$finish;
    end
endmodule
`default_nettype wire
