`timescale 1ns/1ps
`default_nettype none
module tb_scene;
    reg clk=0;
    always #20 clk=~clk;
    reg rst=1,tick=0,req=0,idle=1;
    reg [15:0] next_scene=0;
    wire [15:0] cur,old;
    wire old_en,busy,ack,accepted;
    wire [8:0] alpha;
    scene_fade #(.WIDTH(16),.ALPHA_STEP(9'd64)) fade(
        .clk(clk),.rst(rst),.frame_tick(tick),.request_toggle(req),.old_idle(idle),
        .next_scene(next_scene),.current_scene(cur),.previous_scene(old),
        .old_enable(old_en),.busy(busy),.ack_toggle(ack),.alpha(alpha),.accepted(accepted));
    reg [23:0] a=0,b=0,ov=0;
    reg [8:0] mix=0;
    reg de=0,vs=0,hs=0,ovv=0;
    wire [23:0] rgb;
    wire od,ovsync,ohsync;
    scene_blend blend(.clk(clk),.rst(rst),.de(de),.vs(vs),.hs(hs),
        .old_rgb(a),.new_rgb(b),.overlay_rgb(ov),.overlay_valid(ovv),.alpha(mix),
        .rgb(rgb),.out_de(od),.out_vs(ovsync),.out_hs(ohsync));
    task frame;
        begin @(negedge clk); tick=1; @(negedge clk); tick=0; end
    endtask
    task check;
        input good;
        input [511:0] reason;
        begin if (good!==1'b1) begin $display("TEST_FAIL %0s",reason); $finish; end end
    endtask
    function [23:0] golden;
        input [23:0] x,y;
        input integer n;
        integer r,g,bv;
        begin
            r=(x[23:16]*(256-n)+y[23:16]*n+128)/256;
            g=(x[15:8]*(256-n)+y[15:8]*n+128)/256;
            bv=(x[7:0]*(256-n)+y[7:0]*n+128)/256;
            golden={r[7:0],g[7:0],bv[7:0]};
        end
    endfunction
    integer i,j;
    reg [23:0] expect0,expect1;
    reg [2:0] sync0,sync1;
    reg check_mix=0;
    always @(posedge clk) if (check_mix) begin
        expect1=expect0; sync1=sync0;
        expect0=ovv ? ov : golden(a,b,mix); sync0={de,vs,hs};
        #1;
        check(rgb===expect1,"blend arithmetic / overlay pipeline");
        check({od,ovsync,ohsync}===sync1,"blend sync alignment");
    end
    initial begin
        repeat(5) @(negedge clk); rst=0;
        next_scene=16'h1234; req=1;
        repeat(6) @(negedge clk);
        check(cur==0 && ack==0,"no midframe commit");
        frame;
        check(cur==16'h1234 && ack && !busy && alpha==256,"first scene");
        $display("SCENARIO_PASS first_scene_frame_boundary");
        next_scene=16'habcd; req=0;
        repeat(6) @(negedge clk); frame;
        check(cur==16'habcd && old==16'h1234 && busy && old_en && alpha==0 && ack,"fade start");
        idle=0;
        for(i=1;i<=4;i=i+1) begin
            repeat(3) @(negedge clk); frame;
            check(alpha==i*64 && ack,"frame-stepped fade / delayed ack");
        end
        check(!old_en && busy,"old fetch disabled before release");
        frame; check(ack && busy,"cannot release in-flight old reads");
        idle=1; frame; check(!ack && !busy,"drained release");
        $display("SCENARIO_PASS fade_and_reader_retirement");
        next_scene=16'h9876; req=1;
        repeat(6) @(negedge clk); frame;
        check(old==16'habcd && cur==16'h9876,"back-to-back scene");
        rst=1; repeat(3) @(negedge clk); rst=0; req=0;
        check(!busy && !old_en && cur==0,"reset during fade");
        $display("SCENARIO_PASS reset_during_fade");
        expect0=0; sync0=0;
        repeat(3) @(negedge clk); check_mix=1;
        for(i=0;i<=256;i=i+1) for(j=0;j<12;j=j+1) begin
            @(negedge clk);
            a=$random; b=$random; mix=i; ov=$random;
            ovv=(j==9); de=j[0]; vs=j[1]; hs=j[2];
        end
        repeat(3) @(negedge clk); check_mix=0;
        $display("SCENARIO_PASS blend_all_weights_and_sync");
        $display("TEST_PASS"); $finish;
    end
    initial begin #10000000; $display("TEST_FAIL watchdog"); $finish; end
endmodule
`default_nettype wire
