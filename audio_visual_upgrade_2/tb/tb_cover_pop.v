`timescale 1ns/1ps
`default_nettype none
module tb_cover_pop;
    reg clk=0,rst=1,frame_tick=0,hit=0,de=0;
    always #20 clk=~clk;
    reg [9:0] x=0,y=0;
    wire [1:0] level;
    wire [15:0] ox,oy,ow,oh;
    wire ring_valid;
    wire [23:0] ring_rgb;
    wire [7:0] ring_alpha;
    cover_pop pop(.clk(clk),.rst(rst),.frame_tick(frame_tick),.hit(hit),.level(level));
    cover_pop_geom geom(.x(16'd140),.y(16'd45),.w(16'd240),.h(16'd240),
        .level(level),.out_x(ox),.out_y(oy),.out_w(ow),.out_h(oh));
    attack_rings rings(.clk(clk),.rst(rst),.frame_tick(frame_tick),.hit(hit),
        .de(de),.x(x),.y(y),.valid(ring_valid),.rgb(ring_rgb),.alpha(ring_alpha));
    function integer lower_bound;
        input integer frame_age;
        real radius,width,opacity;
        begin
            opacity=0.8*$pow(0.92,frame_age+1);
            radius=131.4+3.4*frame_age;
            width=2.0+2.0*opacity;
            lower_bound=$rtoi(radius-width/2.0);
            if(lower_bound<radius-width/2.0) lower_bound=lower_bound+1;
        end
    endfunction
    function integer upper_bound;
        input integer frame_age;
        real radius,opacity;
        begin
            opacity=0.8*$pow(0.92,frame_age+1);
            radius=131.4+3.4*frame_age;
            upper_bound=$rtoi(radius+1.0+opacity);
        end
    endfunction
    function integer opacity_byte;
        input integer frame_age;
        begin opacity_byte=$rtoi(255.0*0.8*$pow(0.92,frame_age+1)+0.5); end
    endfunction
    function integer physical_dist;
        input integer xx,yy;
        begin physical_dist=36*(xx-260)*(xx-260)+25*(yy-165)*(yy-165); end
    endfunction
    task tick_frame;
        begin
            @(negedge clk); de=0; frame_tick=1;
            @(negedge clk); frame_tick=0;
            // Production has thousands of vertical blank clocks. Check the
            // module's shorter housekeeping bound before scanning pixels.
            repeat(21) @(negedge clk);
            if(rings.refresh_busy!==0) begin
                $display("TEST_FAIL ring frame housekeeping timeout");$finish;
            end
        end
    endtask
    // Exercise the production raster contract, including two blank clocks
    // for line setup and every x in order. The oracle remains a square formula.
    task check_ring_line;
        input integer yy,frame_age;
        integer px;
        begin
            @(negedge clk); de=0; x=0; y=yy;
            repeat(3) @(negedge clk);
            de=1;
            for(px=0;px<640;px=px+1) begin
                check_ring_pixel(px,yy,frame_age);
                @(negedge clk);
            end
            de=0; #1;
            if(ring_valid!==0) begin $display("TEST_FAIL ring during blank");$finish;end
        end
    endtask
    // Four different ages exercise every cache slot and every shared update.
    task check_four_line;
        input integer yy,advance;
        integer px,slot,a,d,expected_alpha;
        reg expected_valid;
        reg [23:0] expected_rgb;
        begin
            @(negedge clk); de=0; x=0; y=yy;
            repeat(3) @(negedge clk);
            de=1;
            for(px=0;px<640;px=px+1) begin
                x=px; expected_valid=0; expected_rgb=0;
                d=physical_dist(px,yy); expected_alpha=0;
                for(slot=3;slot>=0;slot=slot-1) begin
                    a=(slot==0 ? 0 : 4-slot)+advance;
                    if(a<39 && d>=25*lower_bound(a)*lower_bound(a) &&
                       d<=25*upper_bound(a)*upper_bound(a)) begin
                        expected_valid=1;
                        expected_rgb=24'h5EE8ED;
                        if(opacity_byte(a)>expected_alpha) expected_alpha=opacity_byte(a);
                    end
                end
                #1;
                if(ring_valid!==expected_valid || (expected_valid &&
                   (ring_rgb!==expected_rgb || ring_alpha!==expected_alpha))) begin
                    $display("TEST_FAIL four ring pixels frame=%0d x=%0d y=%0d",advance,px,yy);$finish;
                end
                @(negedge clk);
            end
            de=0;
        end
    endtask
    task pulse_hit;
        begin @(negedge clk); hit=1; @(negedge clk); hit=0; end
    endtask
    task check_geom;
        input [1:0] expected_level;
        input [15:0] expected_w;
        begin
            #1;
            if(level!==expected_level || ow!==expected_w || oh!==expected_w ||
               ox!==16'd260-(expected_w>>1) || oy!==16'd165-(expected_w>>1)) begin
                $display("TEST_FAIL pop geometry level=%0d width=%0d x=%0d y=%0d",level,ow,ox,oy);
                $finish;
            end
        end
    endtask
    // Independent HTML-derived radius, width and opacity reference.
    task check_ring_pixel;
        input integer xx,yy,frame_age;
        integer d;
        reg expected_valid;
        reg [23:0] expected_rgb;
        begin
            d=physical_dist(xx,yy);
            expected_valid=de && frame_age<39 &&
                d>=25*lower_bound(frame_age)*lower_bound(frame_age) &&
                d<=25*upper_bound(frame_age)*upper_bound(frame_age);
            expected_rgb=24'h5EE8ED;
            x=xx; y=yy; #1;
            if(ring_valid!==expected_valid || (expected_valid &&
               (ring_rgb!==expected_rgb || ring_alpha!==opacity_byte(frame_age)))) begin
                $display("TEST_FAIL ring pixel age=%0d x=%0d y=%0d valid=%b rgb=%h expected=%b/%h",
                         frame_age,xx,yy,ring_valid,ring_rgb,expected_valid,expected_rgb);
                $finish;
            end
        end
    endtask
    integer n,f,xx,yy,r;
    initial begin
        repeat(3) @(negedge clk); rst=0;
        check_geom(0,240);
        x=10'd388; y=10'd165; #1;
        if(ring_valid!==0) begin $display("TEST_FAIL ring before hit"); $finish; end
        $display("SCENARIO_PASS quiet_baseline");
        pulse_hit(); check_geom(0,240);
        if(rings.alive!==0) begin $display("TEST_FAIL mid-frame ring insertion");$finish;end
        tick_frame(); check_geom(3,260);
        check_ring_line(165,0);
        $display("SCENARIO_PASS onset_pop_and_ring");
        tick_frame(); check_geom(3,260);
        tick_frame(); check_geom(2,256);
        tick_frame(); tick_frame(); check_geom(1,250);
        tick_frame(); tick_frame(); check_geom(0,240);
        $display("SCENARIO_PASS pop_decay");
        pulse_hit(); tick_frame(); pulse_hit(); tick_frame();
        pulse_hit(); tick_frame(); pulse_hit(); tick_frame();
        if(rings.alive!==4'b1111) begin $display("TEST_FAIL four concurrent rings"); $finish; end
        for(f=0;f<13;f=f+1) begin
            check_four_line(165,f); check_four_line(71,f); check_four_line(300,f);
            tick_frame();
        end
        $display("SCENARIO_PASS four_slots");
        for(n=0;n<41;n=n+1) tick_frame();
        if(rings.alive!==0 || ring_valid!==0) begin
            $display("TEST_FAIL ring expiry"); $finish;
        end
        $display("SCENARIO_PASS ring_expiry");
        @(negedge clk); rst=1;
        repeat(2) @(negedge clk); rst=0;
        pulse_hit(); tick_frame();
        for(f=0;f<39;f=f+1) begin
            r=upper_bound(f);
            check_ring_line(165,f); check_ring_line(71,f); check_ring_line(479,f);
            // Include diagonal boundaries and the vertical annulus edges.
            check_ring_line(165+(r*4)/5,f);
            for(yy=-2;yy<=2;yy=yy+1) check_ring_line(165+r+yy,f);
            tick_frame();
        end
        check_ring_line(165,39);
        $display("SCENARIO_PASS ring_annulus_growth_fade_and_de");
        $display("TEST_PASS"); $finish;
    end
    initial begin #12000000; $display("TEST_FAIL watchdog"); $finish; end
endmodule
`default_nettype wire
