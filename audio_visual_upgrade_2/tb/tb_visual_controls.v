`timescale 1ns/1ps
`default_nettype none
module tb_visual_controls;
    reg clk=0,src=0,rst=1;
    always #10 clk=~clk;
    always #7 src=~src;
    reg de=0;reg [9:0] x=0,y=0;reg [1:0] level=0;
    wire [3:0] alpha;
    cover_coverage cov(.clk(clk),.rst(rst),.de(de),.x(x),.y(y),.level(level),.alpha(alpha));
    reg [3:0] golden[0:253235];
    reg [31:0] palette[0:255];
    reg [46:0] settings={5'b11111,{6{7'd70}}};
    reg frame=0;reg [6:0] swatch=0;
    wire [23:0] spectrum,sung,other,title,singer,rings,swatch_rgb;
    wire [4:0] effects;wire [41:0] indices;
    reg [3:0] transition_settings=4'b0100;
    wire [3:0] transition;
    visual_settings #(.TRANSITIONS(1)) vs(.clk(src),.rst_n(!rst),.settings(settings),
        .transition_settings(transition_settings),.transition(transition),.clk_pix(clk),
        .rst_pix(rst),.frame_tick(frame),.swatch_index(swatch),.swatch_rgb(swatch_rgb),
        .spectrum(spectrum),.sung(sung),.other(other),.title(title),.singer(singer),
        .rings(rings),.effects(effects),.indices(indices));
    reg bar_stb=0,bars_done=0,attack=0,spike=1,enable=1;
    reg [5:0] bar_idx=0;reg [23:0] target=0;
    wire [23:0] fft_rgb;wire fft_valid;
    layer_fft64 #(.DYNAMIC_COLORS(1)) fft(.clk(clk),.rst_n(!rst),.bar_stb(bar_stb),
        .bars_done(bars_done),.bar_idx(bar_idx),.bar_level(8'd100),.frame_stb(frame),
        .attack_hit(attack),.attack_band(5'd7),.de(de),.en(enable),.target_color(target),
        .spike_enable(spike),.x({6'd0,x}),.y({6'd0,y}),.dout(fft_rgb),.dout_vld(fft_valid));
    reg k2=1,k3=1,k4=1;wire visible;wire [2:0] page,selected;
    wire [41:0] control_colors;wire [4:0] control_effects;
    wire [1:0] control_transition_effect,control_transition_speed;
    osd_controls #(.EXTENDED(1),.CLK_HZ(1000),.DEBOUNCE_MS(2),.LONG_MS(20),
        .AUTO_HIDE_MS(10000000)) ctl(.clk(clk),.rst_n(!rst),.key2(k2),.key3(k3),.key4(k4),
        .visible(visible),.page(page),.selected(selected),.image_next(),.sensitivity(),
        .volume(),.sat_base(),.sat_max(),.con_base(),.con_max(),
        .colors(control_colors),.effects(control_effects),
        .transition_effect(control_transition_effect),.transition_speed(control_transition_speed));
    integer s,sz,off,xx,yy,idx,i,j,c,want,expected,checked=0;
    reg [23:0] prev_spectrum;
    task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
    task press;
        input integer key;
        begin
            case(key) 2:k2=0;3:k3=0;4:k4=0;endcase
            repeat(10) tick;
            k2=1;k3=1;k4=1;repeat(10) tick;
        end
    endtask
    task commit;
        begin
            repeat(50) tick;
            frame=1;tick;frame=0;repeat(3) tick;
        end
    endtask
    task check_settings;
        reg [23:0] got;
        integer n,a;
        begin
            if(indices!==settings[41:0] || effects!==settings[46:42] || transition!==transition_settings) begin
                $display("TEST_FAIL settings atomic indices/effects %h/%h",indices,settings);$finish;end
            for(n=0;n<6;n=n+1) begin
                a=(settings>>(7*n))&127;if(a==70) a=70+n;
                case(n) 0:got=spectrum;1:got=sung;2:got=other;3:got=title;4:got=singer;5:got=rings;endcase
                if(got!==palette[a][23:0]) begin
                    $display("TEST_FAIL settings color object=%0d idx=%0d got=%h expected=%h",n,a,got,palette[a]);$finish;end
            end
        end
    endtask
    initial begin
        $readmemh("sim/cover_coverage_golden.mem",golden);
        $readmemh("rtl/gfx/visual_palette.dath",palette);
        if(palette[70][23:0]!==24'hD97A26 || palette[71][23:0]!==24'hFFE8AA ||
           palette[72][23:0]!==24'hE8E4FF || palette[73][23:0]!==24'hFFFFFF ||
           palette[74][23:0]!==24'hBCC4D2 || palette[75][23:0]!==24'h5EE8ED) begin
            $display("TEST_FAIL default color palette");$finish;end
        repeat(6) tick;rst=0;repeat(6) tick;
        off=0;
        for(s=0;s<4;s=s+1) begin
            case(s) 0:sz=240;1:sz=250;2:sz=256;3:sz=260;endcase
            level=s;
            for(yy=-1;yy<=sz;yy=yy+1) for(xx=-1;xx<=sz;xx=xx+1) begin
                x=40-(sz-240)/2+xx;y=45-(sz-240)/2+yy;de=1;
                if(xx<0 || xx>=sz || yy<0 || yy>=sz) want=0;
                else want=golden[off+yy*sz+xx];
                tick;
                if(alpha!==want[3:0]) begin
                    $display("TEST_FAIL coverage size=%0d xy=%0d,%0d got=%0d expected=%0d",sz,xx,yy,alpha,want);$finish;end
                checked=checked+1;
            end
            off=off+sz*sz;
        end
        de=0;tick;if(alpha!==0) begin $display("TEST_FAIL blank coverage");$finish;end
        $display("SCENARIO_PASS VIS-AA-four-sizes");
        commit;check_settings;
        for(i=0;i<71;i=i+1) begin
            prev_spectrum=spectrum;
            settings={i[4:0],{6{i[6:0]}}};
            transition_settings=i;
            repeat(40) tick;
            if(spectrum!==prev_spectrum) begin $display("TEST_FAIL settings changed outside frame");$finish;end
            commit;check_settings;
        end
        settings={5'd9,7'd5,7'd4,7'd3,7'd2,7'd1,7'd0};
        transition_settings=4'hf;
        repeat(12) tick;
        settings={5'd17,7'd65,7'd54,7'd43,7'd32,7'd21,7'd10};
        transition_settings=4'h2;
        commit;commit;check_settings;
        $display("SCENARIO_PASS VIS-CDC-colors-effects-transition");
        for(i=0;i<64;i=i+1) begin bar_idx=i;bar_stb=1;tick;end
        bar_stb=0;bars_done=1;tick;bars_done=0;frame=1;tick;frame=0;repeat(4) tick;
        y=450;
        for(i=0;i<76;i=i+1) begin
            target=palette[i][23:0];de=0;repeat(3) tick;de=1;
            for(xx=0;xx<640;xx=xx+1) begin
                x=xx;#1;
                expected=0;
                for(c=0;c<3;c=c+1) begin
                    want=255-((255-((target>>(c*8))&255))*(xx/10)+31)/63;
                    expected=expected|(want<<(c*8));
                end
                if(fft_rgb!==expected[23:0] || fft_valid!==((xx%10)>=1 && (xx%10)<=8)) begin
                    $display("TEST_FAIL gradient color=%0d x=%0d rgb=%h/%h valid=%b",i,xx,fft_rgb,expected[23:0],fft_valid);$finish;end
                tick;
            end
        end
        de=0;attack=1;tick;attack=0;frame=1;tick;frame=0;tick;
        if(fft.spike_strength==0) begin $display("TEST_FAIL spike not started");$finish;end
        spike=0;tick;
        if(fft.spike_strength!==0 || !fft.active_valid) begin $display("TEST_FAIL spike switch clears bank");$finish;end
        enable=0;de=1;tick;if(fft_valid!==0) begin $display("TEST_FAIL spectrum switch");$finish;end
        $display("SCENARIO_PASS VIS-gradient-and-spikes");
        de=0;k4=0;repeat(32) tick;k4=1;repeat(10) tick;
        if(!visible || page!==0) begin $display("TEST_FAIL open OSD");$finish;end
        press(4);press(4);repeat(5) press(4);
        if(page!==3 || selected!==0) begin $display("TEST_FAIL color page navigation");$finish;end
        for(i=0;i<6;i=i+1) begin
            press(3);
            if(((control_colors>>(i*7))&127)!==0) begin $display("TEST_FAIL color increment wrap");$finish;end
            press(2);
            if(((control_colors>>(i*7))&127)!==70) begin $display("TEST_FAIL color decrement wrap");$finish;end
            press(4);
        end
        if(page!==4 || selected!==0) begin $display("TEST_FAIL effects page navigation");$finish;end
        for(i=0;i<5;i=i+1) begin
            press(2);if(control_effects[i]!==0) begin $display("TEST_FAIL effect disable");$finish;end
            press(3);if(control_effects[i]!==1) begin $display("TEST_FAIL effect enable");$finish;end
            press(4);
        end
        if(page!==5 || selected!==0 || control_transition_effect!==0 || control_transition_speed!==1)
            begin $display("TEST_FAIL transition page/defaults");$finish;end
        for(i=1;i<=4;i=i+1) begin
            press(3);if(control_transition_effect!==(i%4)) begin $display("TEST_FAIL transition effect increment");$finish;end
        end
        press(2);if(control_transition_effect!==3) begin $display("TEST_FAIL transition effect decrement wrap");$finish;end
        press(4);
        if(page!==5 || selected!==1) begin $display("TEST_FAIL transition speed navigation");$finish;end
        for(i=0;i<4;i=i+1) begin
            press(3);if(control_transition_speed!==((i+2)%4)) begin $display("TEST_FAIL transition speed increment");$finish;end
        end
        press(2);if(control_transition_speed!==0) begin $display("TEST_FAIL transition speed decrement");$finish;end
        press(2);if(control_transition_speed!==3) begin $display("TEST_FAIL transition speed decrement wrap");$finish;end
        press(4);
        if(page!==0 || control_colors!=={6{7'd70}} || control_effects!==31 ||
           control_transition_effect!==3 || control_transition_speed!==3)
            begin $display("TEST_FAIL page wrap/persistence");$finish;end
        $display("SCENARIO_PASS VIS-buttons-six-pages");
        $display("TEST_PASS");$finish;
    end
    initial begin #30000000;$display("TEST_FAIL visual timeout");$finish;end
endmodule
`default_nettype wire
