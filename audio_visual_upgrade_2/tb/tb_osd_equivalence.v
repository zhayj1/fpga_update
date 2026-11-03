`timescale 1ns/1ps
`default_nettype none
module tb_osd_equivalence;
    reg clk=0,rst=1,de=1,visible=1,analysis_stb=0,attack_hit=0,song_clear=0;
    always #5 clk=~clk;
    reg [9:0] x=0,y=0;
    reg [2:0] page=0,selected=0;
    reg [4:0] effects=0;
    reg [1:0] transition_effect=0,transition_speed=1;
    reg [41:0] indices={7'd70,7'd69,7'd45,7'd27,7'd13,7'd0};
    reg [7:0] loud=0,relative=0;
    reg [12:0] flux=0,threshold=0;
    reg [16:0] scope_max=100;
    wire [6:0] swatch0,swatch1;
    wire [23:0] rgb0,rgb1;
    wire valid0,valid1;
    osd_layer_small #(.EXTENDED(1)) u0(.clk(clk),.rst(rst),.de(de),.x(x),.y(y),
        .visible(visible),.page(page),.selected(selected),.color_indices(indices),.effects(effects),
        .transition_effect(transition_effect),.transition_speed(transition_speed),
        .swatch_index(swatch0),.swatch_rgb(24'h13579B),.sensitivity(6'd16),
        .volume(9'd123),.sat_base(9'd60),.sat_max(9'd100),.con_base(9'd80),.con_max(9'd100),
        .sat_current(9'd145),.con_current(9'd120),.loud(loud),.relative(relative),
        .analysis_stb(analysis_stb),.attack_hit(attack_hit),.song_clear(song_clear),
        .flux(flux),.threshold(threshold),.scope_max(scope_max),.rgb(rgb0),.valid(valid0));
    osd_layer_small_reference #(.EXTENDED(1)) u1(.clk(clk),.rst(rst),.de(de),.x(x),.y(y),
        .visible(visible),.page(page),.selected(selected),.color_indices(indices),.effects(effects),
        .transition_effect(transition_effect),.transition_speed(transition_speed),
        .swatch_index(swatch1),.swatch_rgb(24'h13579B),.sensitivity(6'd16),
        .volume(9'd123),.sat_base(9'd60),.sat_max(9'd100),.con_base(9'd80),.con_max(9'd100),
        .sat_current(9'd145),.con_current(9'd120),.loud(loud),.relative(relative),
        .analysis_stb(analysis_stb),.attack_hit(attack_hit),.song_clear(song_clear),
        .flux(flux),.threshold(threshold),.scope_max(scope_max),.rgb(rgb1),.valid(valid1));
    integer i,j,k,p,r,s,xx,yy;
    reg compare_enable=0;
    always @(posedge clk) begin
        #1;
        if(compare_enable && (valid0!==valid1 || swatch0!==swatch1 ||
             (valid0 && rgb0!==rgb1) || u0.glyph_req!==u1.glyph_req || u0.value!==u1.value)) begin
            $display("TEST_FAIL equivalent OSD page=%0d x=%0d y=%0d rgb=%h/%h",page,x,y,rgb0,rgb1);$finish;
        end
    end
    initial begin
        // Exhaust every address, including unused glyph slots/pages.
        for(p=0;p<8;p=p+1) for(r=0;r<8;r=r+1) for(s=0;s<8;s=s+1) begin
            if(u0.label_glyph(p,r,s)!==u1.label_glyph(p,r,s)) begin
                $display("TEST_FAIL label p=%0d row=%0d slot=%0d",p,r,s);$finish;
            end
        end
        for(p=0;p<2;p=p+1) for(r=0;r<4;r=r+1) for(s=0;s<4;s=s+1) begin
            if(u0.transition_glyph(p,r,s)!==u1.transition_glyph(p,r,s)) begin
                $display("TEST_FAIL transition glyph");$finish;
            end
        end
        $display("SCENARIO_PASS TR-OSD-equivalent-all-glyph-addresses");
        repeat(8) @(negedge clk);rst=0;
        // Both independent level inputs, every combination, both percentage rows.
        page=1;
        for(r=0;r<2;r=r+1) begin
            y=306+32*r;
            repeat(4) @(negedge clk);
            for(i=0;i<256;i=i+1) for(j=0;j<256;j=j+1) begin
                loud=i;relative=j;#1;
                if(u0.value!==u1.value || u0.value!==((r==0?i:j)*100/256)) begin
                    $display("TEST_FAIL percentage %0d %0d %0d",r,i,j);$finish;
                end
                @(negedge clk);
            end
        end
        $display("SCENARIO_PASS TR-OSD-equivalent-all-percent-inputs");
        compare_enable=1;
        for(i=0;i<340;i=i+1) begin
            analysis_stb=(i%2==0);flux=i*13;threshold=i*3;attack_hit=(i%7==0);
            @(negedge clk);
        end
        analysis_stb=0;
        for(p=0;p<6;p=p+1) begin
            page=p;selected=p%3;effects=p*7;transition_effect=p%4;transition_speed=(p+1)%4;
            x=0;y=0;repeat(8) @(negedge clk);
            for(yy=254;yy<482;yy=yy+1) for(xx=0;xx<642;xx=xx+1) begin
                x=xx;y=yy;de=(xx<640 && yy<480);loud=xx;relative=xx+yy;
                analysis_stb=(xx==0 && yy%17==0);flux=(yy*23)%8192;threshold=yy*7;
                scope_max=yy*100;attack_hit=(yy%3==0);
                @(negedge clk);
            end
        end
        // Exercise every legal 17-bit normalizer divisor, including clamps.
        visible=0;de=0;x=0;y=0;page=0;analysis_stb=0;
        for(i=0;i<131072;i=i+1) begin
            scope_max=i;analysis_stb=1;@(negedge clk);analysis_stb=0;
            repeat(22) @(negedge clk);
            if(u0.scale_q14!==u1.scale_q14 || u0.threshold_amp!==u1.threshold_amp ||
               u0.scale_q14!==(917504/(i<5?5:i))) begin
                $display("TEST_FAIL scope divisor=%0d new=%0d old=%0d",i,u0.scale_q14,u1.scale_q14);$finish;
            end
        end
        $display("SCENARIO_PASS TR-OSD-equivalent-all-scope-divisors");
        visible=0;de=0;analysis_stb=0;
        repeat(8) @(negedge clk);
        $display("SCENARIO_PASS TR-OSD-equivalent-six-pages-live-raster");
        $display("TEST_PASS");$finish;
    end
    initial begin #60000000;$display("TEST_FAIL OSD equivalence timeout");$finish;end
endmodule
`default_nettype wire
