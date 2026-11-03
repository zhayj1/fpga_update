`timescale 1ns/1ps
`default_nettype none
// Focused top-level test: real OSD, pixel counter, blend pipeline and parameter
// wiring. Storage is idle here; the separate full integration test covers it.
module tb_osd_core;
    reg clk=0,pix=0,pix5=0,sdr=0;
    always #10 clk=~clk;
    always #20 pix=~pix;
    always #4 pix5=~pix5;
    always #5 sdr=~sdr;
    reg rst_n=0,rst_pix=1,drive_de=0;
    wire de;
    wire [23:0] rgb;
    skeleton_core #(.SDR_CLK_MHZ(100),.en_osd(1),.en_rot(0),.en_pre(0),.en_a9(0)) dut (
        .clk(clk),.rst_n(rst_n),.clk_pix(pix),.clk_pix5x(pix5),.rst_pix(rst_pix),
        .clk_sdr(sdr),.clk_sdr_sft(sdr),.rst_sdr(1'b1),
        .key2(1'b1),.key3(1'b1),.key4(1'b1),.sd_miso(1'b1),
        .obs_de(de),.obs_rgb(rgb)
    );
    integer out_x=0,out_y=0,line_pixels=0,checked=0,j;
    reg prev_de=0,check_video=0;
    always @(posedge pix) begin
        #1;
        if (check_video) begin
            if(de) begin
                if(out_x>=392 && rgb!==((out_x==392 || out_y==0)?24'h48636a:24'h070e13)) begin
                    $display("TEST_FAIL core OSD alignment x=%0d y=%0d rgb=%h",out_x,out_y,rgb);$finish;
                end
                if(out_x<392 && dut.osd_vld) begin
                    $display("TEST_FAIL core OSD early x=%0d",out_x);$finish;
                end
                out_x=out_x+1;checked=checked+1;
            end else if(prev_de) begin
                if(out_x!=640) begin $display("TEST_FAIL core active width %0d",out_x);$finish;end
                out_x=0;out_y=out_y+1;
            end
            prev_de=de;
        end
    end
    reg [8:0] volume_test=100;
    reg [7:0] relative_test=0;
    reg analysis_test=0;
    task coefficient;
        input [7:0] rel;
        input [8:0] sat,con;
        begin
            @(negedge pix);relative_test=rel;analysis_test=1;
            @(negedge pix);analysis_test=0;
            if(dut.sat_current_pct!=sat || dut.con_current_pct!=con) begin
                $display("TEST_FAIL current coefficient rel=%0d sat=%0d con=%0d",rel,dut.sat_current_pct,dut.con_current_pct);$finish;
            end
        end
    endtask
    initial begin
        force dut.cb_de=drive_de;force dut.cb_vs=1'b1;
        force dut.bg_vld=0;force dut.cv_vld=0;
        force dut.obg_vld=0;force dut.ocv_vld=0;
        force dut.ff_vld=0;force dut.ly_vld=0;force dut.ring_vld=0;
        force dut.env_rel_q8=relative_test;force dut.sa_analysis_stb=analysis_test;
        repeat(8) @(negedge pix);rst_n=1;rst_pix=0;
        repeat(12) @(negedge pix);
        if (dut.osd_visible_clk!==1'b0 || dut.osd_vld!==1'b0) begin
            $display("TEST_FAIL core OSD should start hidden");$finish;
        end
        force dut.osd_visible_sync=2'b11;
        repeat(3) @(negedge pix);
        check_video=1;
        repeat(3) begin
            @(negedge pix);drive_de=1;
            repeat(640) @(negedge pix);
            drive_de=0;
            repeat(16) @(negedge pix);
        end
        check_video=0;
        release dut.osd_visible_sync;
        if(out_y!=3 || checked!=1920) begin $display("TEST_FAIL core raster coverage");$finish;end
        $display("SCENARIO_PASS osd_core_pixel_alignment");
        force dut.osd_volume_s2=volume_test;
        volume_test=0;#1;
        if(dut.user_gain!=0) begin $display("TEST_FAIL mute gain");$finish;end
        volume_test=50;#1;
        if(dut.user_gain!=128) begin $display("TEST_FAIL half volume gain");$finish;end
        volume_test=99;#1;
        if(dut.user_gain!=253) begin $display("TEST_FAIL 99 percent gain");$finish;end
        volume_test=100;#1;
        if(dut.user_gain!=256) begin $display("TEST_FAIL unity volume gain");$finish;end
        release dut.osd_volume_s2;
        $display("SCENARIO_PASS osd_core_volume_gain");
        coefficient(0,100,100);coefficient(128,140,118);coefficient(255,180,135);
        force dut.osd_sat_base_s2=60;force dut.osd_sat_max_s2=260;
        force dut.osd_con_base_s2=80;force dut.osd_con_max_s2=170;
        coefficient(0,60,80);coefficient(128,160,125);coefficient(255,259,170);
        $display("SCENARIO_PASS osd_core_color_parameters");
        $display("TEST_PASS");$finish;
    end
    initial begin #500000; $display("TEST_FAIL core OSD timeout");$finish;end
endmodule
`default_nettype wire
