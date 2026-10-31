`timescale 1ns/1ps
`default_nettype none
module tb_visual_osd;
    reg clk=0,rst=1,de=1,visible=1;
    always #5 clk=~clk;
    reg [9:0] x=0,y=0;
    reg [2:0] page=3,selected=0;
    reg [4:0] effects=0;
    reg [41:0] indices={7'd70,7'd69,7'd45,7'd27,7'd13,7'd0};
    wire [6:0] swatch_index;
    wire [23:0] swatch_rgb,rgb;
    wire valid;
    visual_palette palette(.clk(clk),.index_a(7'd0),.index_b(swatch_index),.rgb_a(),.rgb_b(swatch_rgb));
    osd_layer_small #(.EXTENDED(1)) dut(.clk(clk),.rst(rst),.de(de),.x(x),.y(y),
        .visible(visible),.page(page),.selected(selected),.color_indices(indices),.effects(effects),
        .swatch_index(swatch_index),.swatch_rgb(swatch_rgb),.sensitivity(6'd16),
        .volume(9'd0),.sat_base(9'd60),.sat_max(9'd100),.con_base(9'd80),.con_max(9'd100),
        .sat_current(9'd145),.con_current(9'd120),.loud(8'd160),.relative(8'd120),
        .analysis_stb(1'b0),.attack_hit(1'b0),.song_clear(1'b0),
        .flux(13'd25),.threshold(13'd10),.scope_max(17'd100),.rgb(rgb),.valid(valid));
    reg [23:0] golden[0:358399];
    reg [24:0] d0=0,d1=0,want;
    integer f,xx,yy,i,fd;
    task tick;
        begin
            @(posedge clk);#1;
            if(valid!==d1[24] || (valid && rgb!==d1[23:0])) begin
                $display("TEST_FAIL visual OSD f=%0d x=%0d y=%0d actual=%b_%h expected=%h",f,x,y,valid,rgb,d1);$finish;
            end
            if(valid) $fdisplay(fd,"%06h",rgb);
            d1=d0;d0=want;
        end
    endtask
    initial begin
        $readmemh("sim/visual_osd_golden.mem",golden);
        repeat(8) @(negedge clk);rst=0;
        fd=$fopen("sim/visual_osd_actual.mem","w");
        for(f=0;f<8;f=f+1) begin
            @(negedge clk);page=f<6?3:4;selected=f<6?f:f-6;effects=f==7?31:0;
            x=0;y=0;d0=0;d1=0;
            repeat(8) @(negedge clk);
            for(yy=254;yy<482;yy=yy+1) for(xx=0;xx<642;xx=xx+1) begin
                @(negedge clk);x=xx;y=yy;want=0;
                if(xx>=440 && xx<640 && yy>=256 && yy<480)
                    want={1'b1,golden[f*44800+(yy-256)*200+xx-440]};
                tick;
            end
            repeat(3) begin @(negedge clk);x=0;y=0;want=0;tick;end
        end
        $fclose(fd);
        $display("SCENARIO_PASS VIS-OSD-pages-glyphs-palette");
        $display("SCENARIO_PASS VIS-OSD-effects-on-off");
        @(negedge clk);x=500;y=350;visible=0;
        repeat(8) @(posedge clk);#1;
        if(valid!==0) begin $display("TEST_FAIL hidden OSD");$finish;end
        @(negedge clk);visible=1;de=0;
        repeat(8) @(posedge clk);#1;
        if(valid!==0) begin $display("TEST_FAIL blanking OSD");$finish;end
        $display("SCENARIO_PASS VIS-OSD-boundary-latency");
        $display("TEST_PASS");$finish;
    end
    initial begin #30000000;$display("TEST_FAIL visual OSD timeout");$finish;end
endmodule
`default_nettype wire
