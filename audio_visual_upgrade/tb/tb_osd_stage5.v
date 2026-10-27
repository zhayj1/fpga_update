`timescale 1ns/1ps
`default_nettype none
module tb_osd_stage5;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg key2=1, key3=1, key4=1;
    wire visible, image_next;
    wire [1:0] page;
    wire [2:0] selected;
    wire [5:0] sensitivity;
    wire [8:0] volume, sat_base, sat_max, con_base, con_max;
    osd_controls #(.CLK_HZ(1000),.DEBOUNCE_MS(2),.LONG_MS(15),
                   .AUTO_HIDE_MS(80)) keys (
        .clk(clk),.rst_n(rst_n),.key2(key2),.key3(key3),.key4(key4),
        .visible(visible),.page(page),.selected(selected),
        .image_next(image_next),
        .sensitivity(sensitivity),.volume(volume),.sat_base(sat_base),
        .sat_max(sat_max),.con_base(con_base),.con_max(con_max)
    );
    reg de=1;
    reg [9:0] x=0,y=0;
    reg [1:0] draw_page=0;
    reg analysis_stb=0, attack_hit=0, song_clear=0;
    reg [12:0] flux=0, threshold=0;
    reg [16:0] scope_max=17'd100;
    wire [23:0] rgb;
    wire valid;
    osd_layer picture (
        .clk(clk),.rst(!rst_n),.de(de),.x(x),.y(y),
        .visible(1'b1),.page(draw_page),.selected(3'd2),
        .sensitivity(6'd16),.volume(9'd100),.sat_base(9'd100),
        .sat_max(9'd180),.con_base(9'd100),.con_max(9'd135),
        .sat_current(9'd145),.con_current(9'd120),
        .loud(8'd160),.relative(8'd120),
        .analysis_stb(analysis_stb),.attack_hit(attack_hit),
        .song_clear(song_clear),.flux(flux),.threshold(threshold),.scope_max(scope_max),
        .rgb(rgb),.valid(valid)
    );
    integer ink,xx,yy;
    reg long_image_seen=0;
    always @(posedge clk) if (image_next) long_image_seen<=1;
    task press4;
        input integer cycles;
        begin
            @(negedge clk);key4=0;
            repeat(cycles) @(negedge clk);
            key4=1;
            repeat(8) @(negedge clk);
        end
    endtask
    task press2;
        begin
            @(negedge clk);key2=0;
            repeat(7) @(negedge clk);
            key2=1;
            repeat(7) @(negedge clk);
        end
    endtask
    task check_pixel;
        input [9:0] px,py;
        input expected_valid;
        begin
            @(negedge clk);x=px;y=py;
            repeat(8) @(posedge clk);
            #1;
            if(valid!==expected_valid) begin
                $display("TEST_FAIL pixel validity x=%0d y=%0d",px,py);
                $finish;
            end
        end
    endtask
    task check_glyph;
        input [9:0] px;
        input [5:0] expected_glyph;
        begin
            @(negedge clk);x=px;
            repeat(3) @(posedge clk);
            #1;
            if (picture.glyph_req!==expected_glyph) begin
                $display("TEST_FAIL numeric glyph page=%0d x=%0d got=%0d want=%0d",
                         draw_page,px,picture.glyph_req,expected_glyph);
                $finish;
            end
        end
    endtask
    task prepare_numeric_row;
        input [1:0] target_page;
        input [9:0] target_y;
        integer col;
        begin
            @(negedge clk);draw_page=target_page;y=target_y;x=0;
            for (col=1;col<=22;col=col+1) begin
                @(negedge clk);x=col[9:0];
            end
        end
    endtask
    task press3;
        begin
            @(negedge clk);key3=0;
            repeat(7) @(negedge clk);
            key3=1;
            repeat(7) @(negedge clk);
        end
    endtask
    initial begin
        repeat(8) @(negedge clk); rst_n=1;
        repeat(8) @(negedge clk);
        if (visible || page!=0 || volume!=100 || sensitivity!=16) begin
            $display("TEST_FAIL initial controls");$finish;
        end
        press4(28);
        if (!visible || page!=0) begin
            $display("TEST_FAIL long press opens panel");$finish;
        end
        press4(8);
        if (page!=1 || !visible || long_image_seen) begin
            $display("TEST_FAIL visible short press");$finish;
        end
        $display("SCENARIO_PASS osd_short_page");
        press4(28);
        if (visible || long_image_seen) begin
            $display("TEST_FAIL long press release");$finish;
        end
        $display("SCENARIO_PASS osd_long_toggle");
        press4(8);
        if (!long_image_seen || visible) begin
            $display("TEST_FAIL hidden short press");$finish;
        end
        press2();
        if (!visible || page!=2 || selected!=0 || volume!=99) begin
            $display("TEST_FAIL volume control");$finish;
        end
        press3();
        if (volume!=100) begin $display("TEST_FAIL hidden volume restore");$finish;end
        $display("SCENARIO_PASS osd_volume_adjust");
        repeat(110) press2();
        if(volume!=0) begin $display("TEST_FAIL volume lower clamp");$finish;end
        repeat(110) press3();
        if(volume!=100) begin $display("TEST_FAIL volume upper clamp");$finish;end
        press4(8);
        repeat(100) press2();
        if(sat_base!=60) begin $display("TEST_FAIL saturation base minimum");$finish;end
        repeat(100) press3();
        if(sat_base!=150) begin $display("TEST_FAIL saturation base maximum");$finish;end
        press4(8);
        repeat(200) press2();
        if(sat_max!=150) begin $display("TEST_FAIL saturation base/max crossing");$finish;end
        repeat(200) press3();
        if(sat_max!=260) begin $display("TEST_FAIL saturation maximum clamp");$finish;end
        press4(8);
        repeat(100) press2();
        if(con_base!=80) begin $display("TEST_FAIL contrast base minimum");$finish;end
        repeat(100) press3();
        if(con_base!=130) begin $display("TEST_FAIL contrast base maximum");$finish;end
        press4(8);
        repeat(200) press2();
        if(con_max!=130) begin $display("TEST_FAIL contrast base/max crossing");$finish;end
        repeat(100) press3();
        if(con_max!=170) begin $display("TEST_FAIL contrast maximum clamp");$finish;end
        press4(8);
        repeat(80) press2();
        if(sensitivity!=2) begin $display("TEST_FAIL sensitivity minimum");$finish;end
        repeat(80) press3();
        if(sensitivity!=40) begin $display("TEST_FAIL sensitivity maximum");$finish;end
        repeat(85) @(negedge clk);
        if (visible || sensitivity!=40) begin
            $display("TEST_FAIL idle hide or parameter retention");$finish;
        end
        press3();
        if (!visible || page!=2 || selected!=0 || volume!=100) begin
            $display("TEST_FAIL adjust reopens panel");$finish;
        end
        $display("SCENARIO_PASS osd_parameter_bounds");

        draw_page=0;
        check_pixel(400,100,1'b1);
        if (rgb!==24'h070e13) begin $display("TEST_FAIL panel background");$finish; end
        check_pixel(200,100,1'b0);
        ink=0;
        for(yy=12;yy<44;yy=yy+1) begin
            prepare_numeric_row(0,yy[9:0]);
            for(xx=401;xx<529;xx=xx+1) begin
                check_pixel(xx,yy,1'b1);
                if (rgb==24'he7f0f0) ink=ink+1;
            end
        end
        if (ink<100) begin $display("TEST_FAIL title glyphs %0d",ink);$finish; end
        @(negedge clk);x=10'd401;y=10'd18;
        repeat(4) @(posedge clk);#1;
        if (picture.font_bits!==32'h3FFE6000) begin
            $display("TEST_FAIL native glyph row bits=%h",picture.font_bits);$finish;
        end
        prepare_numeric_row(0,10'd20);
        check_glyph(401,1);check_glyph(433,2);
        prepare_numeric_row(0,10'd75);
        check_glyph(405,13);check_glyph(437,14);
        prepare_numeric_row(1,10'd20);
        check_glyph(401,5);check_glyph(433,6);
        prepare_numeric_row(1,10'd75);
        check_glyph(405,17);check_glyph(437,18);
        prepare_numeric_row(2,10'd20);
        check_glyph(401,9);check_glyph(433,10);
        prepare_numeric_row(2,10'd75);
        check_glyph(405,9);check_glyph(437,10);
        $display("SCENARIO_PASS osd_font_and_panel");

        @(negedge clk);x=10'd391;y=10'd200;
        repeat(3) @(posedge clk);#1;
        if (valid!==1'b0) begin $display("TEST_FAIL panel left outside");$finish;end
        @(negedge clk);x=10'd392;
        @(posedge clk);#1;
        if (valid!==1'b0) begin $display("TEST_FAIL panel left early");$finish;end
        @(posedge clk);#1;
        if (valid!==1'b1 || rgb!==24'h48636a) begin
            $display("TEST_FAIL panel left edge valid=%b rgb=%h",valid,rgb);$finish;
        end
        @(negedge clk);x=10'd391;
        @(posedge clk);#1;
        if (valid!==1'b1) begin $display("TEST_FAIL panel left lost");$finish;end
        @(posedge clk);#1;
        if (valid!==1'b0) begin $display("TEST_FAIL panel left late");$finish;end
        $display("SCENARIO_PASS osd_pixel_alignment");

        for (yy=0;yy<3;yy=yy+1) begin
            prepare_numeric_row(yy[1:0],10'd75);
            for (xx=392;xx<=402;xx=xx+1) begin
                @(negedge clk);x=xx[9:0];
                @(posedge clk);#1;
            end
            if ((yy==0 && picture.value_bcd!==12'h016) ||
                (yy==1 && picture.value_bcd!==12'h062) ||
                (yy==2 && picture.value_bcd!==12'h100)) begin
                $display("TEST_FAIL numeric BCD page=%0d bcd=%h",yy,picture.value_bcd);
                $finish;
            end
        end
        prepare_numeric_row(0,10'd75);
        check_glyph(577,0);check_glyph(593,31);check_glyph(609,36);
        prepare_numeric_row(1,10'd75);
        check_glyph(561,0);check_glyph(577,36);check_glyph(593,32);
        check_glyph(609,40);
        prepare_numeric_row(2,10'd75);
        check_glyph(561,31);check_glyph(577,30);check_glyph(593,30);
        check_glyph(609,40);
        $display("SCENARIO_PASS osd_numeric_pages");
        prepare_numeric_row(0,10'd75);
        if (picture.bar_width!==9'd80) begin
            $display("TEST_FAIL sensitivity bar width %0d",picture.bar_width);$finish;
        end
        prepare_numeric_row(1,10'd75);
        if (picture.bar_width!==9'd136) begin
            $display("TEST_FAIL loudness bar width %0d",picture.bar_width);$finish;
        end
        prepare_numeric_row(2,10'd75);
        if (picture.bar_width!==9'd217) begin
            $display("TEST_FAIL volume bar width %0d",picture.bar_width);$finish;
        end
        $display("SCENARIO_PASS osd_bar_width");
        draw_page=0;

        @(negedge clk);flux=13'd80;threshold=13'd80;attack_hit=1;analysis_stb=1;
        @(negedge clk);analysis_stb=0;attack_hit=0;
        repeat(30) @(negedge clk);
        @(negedge clk);x=10'd0;y=10'd200;
        @(negedge clk);x=10'd404;
        @(negedge clk);x=10'd405;
        @(negedge clk);x=10'd406;
        @(posedge clk);#1;
        if (rgb!==24'hffb347) begin
            $display("TEST_FAIL scope hit marker rgb=%h",rgb);$finish;
        end
        $display("SCENARIO_PASS osd_scope_mark");
        if(picture.scale_q14!=18'd9175 || picture.history[0]!=14'd8272) begin
            $display("TEST_FAIL raw scope storage/reciprocal");$finish;
        end
        @(negedge clk);x=0;scope_max=200;flux=40;analysis_stb=1;
        @(negedge clk);analysis_stb=0;
        repeat(30) @(negedge clk);
        check_pixel(405,200,1'b1);
        if(picture.sample_amp!=6'd22 || picture.threshold_amp!=6'd22) begin
            $display("TEST_FAIL scope must rescale old samples amp=%0d threshold=%0d",picture.sample_amp,picture.threshold_amp);$finish;
        end
        $display("SCENARIO_PASS osd_scope_rescale");
        draw_page=1;
        check_pixel(400,317,1'b1);
        check_pixel(400,318,1'b0);
        draw_page=2;
        check_pixel(397,171,1'b1);
        if(rgb!==24'h49ded4) begin $display("TEST_FAIL selected setting");$finish;end
        $display("SCENARIO_PASS osd_three_pages");
        $display("TEST_PASS");$finish;
    end
    initial begin
        #2000000;
        $display("TEST_FAIL timeout");$finish;
    end
endmodule
`default_nettype wire
