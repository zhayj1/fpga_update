`timescale 1ns/1ps
`default_nettype none
module tb_osd_typography;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    reg de=1, visible=1;
    reg [9:0] x=0,y=0;
    reg [2:0] page=0;
    reg [5:0] sensitivity=16;
    reg [8:0] volume=0,sat_base=60,sat_max=100,con_base=80,con_max=100;
    reg [8:0] sat_current=145,con_current=120;
    reg [7:0] loud=160,relative=120;
    reg analysis_stb=0,attack_hit=0,song_clear=0;
    reg [12:0] flux=25,threshold=10;
    wire [23:0] rgb;
    wire valid;
    osd_layer_small dut(.clk(clk),.rst(rst),.de(de),.x(x),.y(y),
        .visible(visible),.page(page),.selected(3'd2),.sensitivity(sensitivity),
        .volume(volume),.sat_base(sat_base),.sat_max(sat_max),.con_base(con_base),
        .con_max(con_max),.sat_current(sat_current),.con_current(con_current),
        .loud(loud),.relative(relative),.analysis_stb(analysis_stb),.attack_hit(attack_hit),
        .song_clear(song_clear),.flux(flux),.threshold(threshold),.scope_max(17'd100),
        .rgb(rgb),.valid(valid));
    reg [6:0] glyph=0;
    reg [3:0] glyph_row=0;
    wire [63:0] bits;
    osd_font_youyuan font_check(.clk(clk),.glyph(glyph),.row(glyph_row),.bits(bits));
    reg [24:0] golden[0:983039];
    reg [3:0] glyph_golden[0:11263];
    reg [24:0] previous, previous2, want;
    integer g,r,c,i,xx,yy,frame_id,extreme,p,fd;
    integer previous_x,previous_y;
    integer idx,idx_prev,amp,amp_prev,lo,hi,level;
    reg [24:0] dynamic0,dynamic1,dynamic_want;
    task sample_history;
        input hit;
        begin
            @(negedge clk); analysis_stb=1;attack_hit=hit;
            @(negedge clk); analysis_stb=0;attack_hit=0;
            repeat(24) @(negedge clk);
        end
    endtask
    task check_delayed;
        begin
            if(valid!==previous2[24] || (previous2[24] && rgb!==previous2[23:0])) begin
                $display("TEST_FAIL OSD frame=%0d x=%0d y=%0d got=%b_%h want=%h history=%h idx=%0d amp=%0d prev=%0d",
                    frame_id,previous_x,previous_y,valid,rgb,previous2,dut.history_read,
                    dut.source_idx,dut.sample_amp,dut.prev_amp);
                $finish;
            end
        end
    endtask
    initial begin
        $readmemh("sim/typography_osd_golden.mem",golden);
        $readmemh("sim/typography_osd_glyphs.mem",glyph_golden);
        repeat(8) @(negedge clk);rst=0;
        for(g=0;g<44;g=g+1) for(r=0;r<16;r=r+1) begin
            @(negedge clk);glyph=g;glyph_row=r;
            @(posedge clk);#1;
            for(c=0;c<16;c=c+1) if(((bits>>((15-c)*4))&64'hf)!==glyph_golden[g*256+r*16+c]) begin
                $display("TEST_FAIL glyph=%0d row=%0d col=%0d bits=%h",g,r,c,bits);$finish;
            end
        end
        $display("SCENARIO_PASS TYP-05-glyphs");
        for(i=0;i<320;i=i+1) sample_history(i<3);
        if(dut.count!==320 || dut.write_ptr!==0 || dut.hits_bcd!==20'h3 || dut.scale_q14!==9175) begin
            $display("TEST_FAIL scope setup");$finish;
        end
        fd=$fopen("sim/osd_bottom_right_actual.mem","w");
        for(extreme=0;extreme<2;extreme=extreme+1) begin
            @(negedge clk);
            sensitivity=extreme ? 40 : 16; loud=extreme ? 255 : 160; relative=extreme ? 255 : 120;
            sat_current=extreme ? 260 : 145; con_current=extreme ? 170 : 120;
            volume=extreme ? 100 : 0; sat_base=extreme ? 150 : 60; sat_max=extreme ? 260 : 100;
            con_base=extreme ? 130 : 80;con_max=extreme ? 170 : 100;
            for(p=0;p<3;p=p+1) begin
                @(negedge clk);page=p;x=0;y=0;
                repeat(30) @(negedge clk);
                frame_id=extreme*3+p;previous=0;previous2=0;previous_x=0;previous_y=0;
                for(yy=0;yy<480;yy=yy+1) for(xx=0;xx<640;xx=xx+1) begin
                    @(negedge clk);x=xx;y=yy;// Inverse-translate the independently rendered original image.
                    // Outside its bounds the expected output is transparent.
                    want=0;
                    if(xx>=16 && yy>=240 && yy<496)
                        want=golden[frame_id*163840+(yy-240)*640+(xx-16)];
                    @(posedge clk);#1;check_delayed;
                    if(xx+yy*640>=2) $fdisplay(fd,"%06h",valid ? rgb : 24'h070e13);
                    previous2=previous;previous=want;previous_x=xx;previous_y=yy;
                end
                for(i=0;i<2;i=i+1) begin
                @(negedge clk);x=0;y=0;
                @(posedge clk);#1;check_delayed;
                $fdisplay(fd,"%06h",valid ? rgb : 24'h070e13);
                previous2=previous;previous=0;
                end
            end
        end
        $fclose(fd);
        $display("SCENARIO_PASS TYP-05-frames");
        @(negedge clk);x=466;y=270;visible=0;
        repeat(8) @(posedge clk);#1;
        if(valid!==0) begin $display("TEST_FAIL hidden");$finish;end
        @(negedge clk);visible=1;de=0;
        repeat(8) @(posedge clk);#1;
        if(valid!==0) begin $display("TEST_FAIL DE blanking");$finish;end
        @(negedge clk);de=1;x=0;y=0;sample_history(1);
        if(dut.write_ptr!==1 || dut.count!==320 || dut.hits_bcd!==20'h4) begin
            $display("TEST_FAIL history wrap");$finish;
        end
        @(negedge clk);song_clear=1;
        @(negedge clk);song_clear=0;
        repeat(4) @(posedge clk);#1;
        if(dut.count!==0 || dut.write_ptr!==0 || dut.hits_bcd!==0) begin
            $display("TEST_FAIL history clear");$finish;
        end
        $display("SCENARIO_PASS TYP-05-state");
        // Independent raster model with changing history values. Constant
        // history alone cannot detect a one-pixel normalization skew.
        for(i=0;i<320;i=i+1) begin
            flux=(i*17)%101;sample_history((i%23)==0);
        end
        @(negedge clk);page=0;x=0;y=0;
        repeat(30) @(negedge clk);
        dynamic0=0;dynamic1=0;
        for(yy=370;yy<436;yy=yy+1) for(xx=0;xx<640;xx=xx+1) begin
            dynamic_want=0;
            if(xx>=452 && xx<628) begin
                idx=((xx-452)*20)/11;
                idx_prev=xx==452 ? idx : ((xx-453)*20)/11;
                amp=((((idx*17)%101)*9175)>>14);
                amp_prev=((((idx_prev*17)%101)*9175)>>14);
                if(amp>56) amp=56;
                if(amp_prev>56) amp_prev=56;
                lo=amp<amp_prev ? amp : amp_prev;
                hi=amp>amp_prev ? amp : amp_prev;
                level=432-yy;
                dynamic_want={1'b1,24'h070b10};
                if(yy<=432 && level>=lo && level<=hi) dynamic_want[23:0]=24'h35d0c4;
                if(yy<=432 && level==5 && (xx%8)<4) dynamic_want[23:0]=24'hb8893c;
                if((idx%23)==0) dynamic_want[23:0]=24'hffb347;
            end
            @(negedge clk);x=xx;y=yy;
            @(posedge clk);#1;
            if(dynamic1[24] && (valid!==1 || rgb!==dynamic1[23:0])) begin
                $display("TEST_FAIL dynamic scope x=%0d y=%0d got=%h want=%h",xx,yy,rgb,dynamic1);$finish;
            end
            dynamic1=dynamic0;dynamic0=dynamic_want;
        end
        $display("SCENARIO_PASS FIX-04-osd-normalization-pipeline");
        $display("TEST_PASS");$finish;
    end
    initial begin #30000000;$display("TEST_FAIL timeout");$finish;end
endmodule
`default_nettype wire
