`timescale 1ns/1ps
`default_nettype none
// Display integration: actual raster, two scaled covers, one shared writer,
// color-key transparency, rings and the production scene blender. SDRAM is a
// deterministic burst responder here; the full-core TB uses the vendor model.
module tb_cover_scene;
    reg cp=0,cs=0,rst=1,hit=0;
    always #20 cp=~cp;
    initial begin #3; forever #3.333 cs=~cs; end
    wire hs,vs,de;
    color_bar timing(.clk(cp),.rst(rst),.hs(hs),.vs(vs),.de(de),
                     .rgb_r(),.rgb_g(),.rgb_b());
    wire [66:0] scan;
    scene_raster raster(.clk_pix(cp),.rst_pix_n(~rst),.hs(hs),.vs(vs),.de(de),.state(scan));
    reg vs_d=0,vs_p=0;
    always @(posedge cp) if(rst) begin vs_d<=0;vs_p<=0;end
                        else begin vs_d<=vs;vs_p<=vs_d;end
    wire frame_tick=vs_p && !vs_d;
    wire [1:0] level;
    wire [15:0] wx,wy,ww,wh;
    cover_pop pop(.clk(cp),.rst(rst),.frame_tick(frame_tick),.hit(hit),.level(level));
    cover_pop_geom geom(.x(16'd140),.y(16'd45),.w(16'd240),.h(16'd240),
        .level(level),.out_x(wx),.out_y(wy),.out_w(ww),.out_h(wh));
    wire [3:0] cmd,free_bank,bank,ack,take,active,done,error,we;
    wire [83:0] addresses;
    wire [63:0] words;
    wire [9:0] wr_addr;
    wire good,px_req;
    wire [20:0] px_addr;
    wire [15:0] px_len;
    reg px_ack=0,px_done=0,px_valid=0;
    reg [31:0] px_data=0;
    fetch_writer4 #(.MAX_W0(320),.MAX_W1(320)) writer(
        .clk_sdr(cs),.rst_sdr_n(~rst),.cmd_valid(cmd),.slot_free(free_bank),
        .next_bank(bank),.cmd_addr(addresses),.cmd_words(words),.cmd_ack(ack),
        .wr_take(take),.wr_active(active),.wr_done(done),.wr_error(error),.wr_en(we),
        .wr_addr(wr_addr),.wr_good(good),.px_req(px_req),.px_addr(px_addr),.px_len(px_len),
        .px_ack(px_ack),.px_done(px_done),.px_valid(px_valid));
    wire [47:0] cover_rgb;
    wire [1:0] cover_valid;
    assign cmd[3:2]=0; assign free_bank[3:2]=0; assign bank[3:2]=0;
    assign addresses[83:42]=0; assign words[63:32]=0;
    genvar g;
    generate for(g=0;g<2;g=g+1) begin: covers
        layer_cover #(.MAX_W(320),.SHARED_RASTER(1),.SHARED_WRITER(1),.SCALE(1)) image(
            .clk_pix(cp),.rst_pix_n(~rst),.hs(hs),.vs(vs),.de(de),.en(1'b1),
            .ch_key(24'hff00ff),.win_x(wx),.win_y(wy),.win_w(ww),.win_h(wh),
            .img_w(16'd240),.img_h(16'd240),.words_per_row(16'd180),
            .slot_base(g==0 ? 21'h01000 : 21'h20000),
            .dout(cover_rgb[g*24+:24]),.dout_vld(cover_valid[g]),
            .underrun_cnt(),.stall_cnt(),.ferr_cnt(),.gap_cnt(),.keyed_cnt(),.idle(),
            .clk_sdr(cs),.rst_sdr_n(~rst),.px_req(),.px_addr(),.px_len(),
            .px_ack(1'b0),.px_done(1'b0),.px_data(px_data),.px_valid(1'b0),
            .scan_state(scan),.cmd_valid(cmd[g]),.slot_free(free_bank[g]),.next_bank(bank[g]),
            .cmd_addr(addresses[g*21+:21]),.cmd_words(words[g*16+:16]),.cmd_ack(ack[g]),
            .wr_take(take[g]),.wr_active(active[g]),.wr_done(done[g]),.wr_error(error[g]),
            .wr_en(we[g]),.wr_good(good),.wr_addr(wr_addr));
    end endgenerate
    wire [9:0] pixel_x=scan[24:15];
    wire [9:0] pixel_y=scan[40:31]-10'd35;
    wire ring_valid;
    wire [23:0] ring_rgb;
    wire [7:0] ring_alpha;
    attack_rings rings(.clk(cp),.rst(rst),.frame_tick(frame_tick),.hit(hit),
        .de(de),.x(pixel_x),.y(pixel_y),.valid(ring_valid),.rgb(ring_rgb),
        .alpha(ring_alpha));
    function [7:0] tint_channel;
        input [7:0] background,foreground,opacity;
        integer value;
        begin
            value=(background*256+(foreground-background)*opacity+128)/256;
            tint_channel=value[7:0];
        end
    endfunction
    function [23:0] tint;
        input [23:0] background,foreground;
        input [7:0] opacity;
        begin tint={tint_channel(background[23:16],foreground[23:16],opacity),
                    tint_channel(background[15:8],foreground[15:8],opacity),
                    tint_channel(background[7:0],foreground[7:0],opacity)}; end
    endfunction
    wire [8:0] alpha=scan[14:0]<2 ? 9'd0 : scan[14:0]<7 ? 9'd128 : 9'd256;
    reg [47:0] cover_rgb_d=0;
    reg [1:0] cover_valid_d=0;
    reg ring_valid_d=0,scene_de_d=0,scene_vs_d=0,scene_hs_d=0;
    reg [7:0] ring_alpha_d=0;
    reg [8:0] alpha_d=0;
    always @(posedge cp) begin
        cover_rgb_d<=cover_rgb; cover_valid_d<=cover_valid;
        ring_valid_d<=ring_valid; ring_alpha_d<=ring_alpha;
        alpha_d<=alpha; scene_de_d<=de; scene_vs_d<=vs; scene_hs_d<=hs;
    end
    wire [23:0] old_image=cover_valid_d[0] ? cover_rgb_d[0+:24] :
                             ring_valid_d ? tint(24'h102030,ring_rgb,ring_alpha_d) : 24'h102030;
    wire [23:0] new_image=cover_valid_d[1] ? cover_rgb_d[24+:24] :
                             ring_valid_d ? tint(24'h405060,ring_rgb,ring_alpha_d) : 24'h405060;
    wire [23:0] rgb;
    wire out_de;
    scene_blend blender(.clk(cp),.rst(rst),.de(scene_de_d),.vs(scene_vs_d),.hs(scene_hs_d),
        .old_rgb(old_image),.new_rgb(new_image),.alpha(alpha_d),
        .overlay_rgb(24'd0),.overlay_valid(1'b0),.rgb(rgb),.out_de(out_de),.out_vs(),.out_hs());

    function [23:0] source_pixel;
        input integer asset,sx,sy;
        integer r,gc;
        begin
            r=asset==0 ? sx : 255-sx; gc=asset==0 ? sy : 255-sy;
            if(36*(sx-120)*(sx-120)+25*(sy-120)*(sy-120)>25*119*119)
                source_pixel=24'hff00ff;
            else source_pixel={r[7:0],gc[7:0],asset==0 ? 8'h31 : 8'hc3};
        end
    endfunction
    function [7:0] source_byte;
        input integer address;
        integer asset,b;
        reg [23:0] p;
        begin
            asset=address>=32'h20000*4 ? 1 : 0;
            b=address-(asset==0 ? 32'h01000*4 : 32'h20000*4);
            p=source_pixel(asset,(b%720)/3,b/720);
            case(b%3) 0:source_byte=p[23:16];1:source_byte=p[15:8];default:source_byte=p[7:0];endcase
        end
    endfunction
    integer sending=0,index=0,burst_addr=0,burst_words=0,requests=0;
    always @(negedge cs) if(!rst) begin
        px_ack=0;px_done=0;px_valid=0;
        if(!sending && px_req) begin
            if(px_len!==16'd180) begin $display("TEST_FAIL shared burst length");$finish;end
            burst_addr=px_addr;burst_words=px_len;index=0;sending=1;px_ack=1;requests=requests+1;
        end else if(sending) begin
            if(index<burst_words) begin
                px_data={source_byte((burst_addr+index)*4+3),source_byte((burst_addr+index)*4+2),
                         source_byte((burst_addr+index)*4+1),source_byte((burst_addr+index)*4)};
                px_valid=1;index=index+1;
            end else begin px_done=1;sending=0;end
        end
    end
    // One onset during the first frame; geometry must wait for the next frame.
    always @(negedge cp) if(!rst)
        hit=(scan[14:0]==1 && scan[46:31]==400 && scan[63:47]==200);

    function [23:0] expected_scene;
        input integer asset,x,y,f;
        integer width,margin,sx,sy,age,lo,hi,dist,opacity;
        real radius,fade,width_px;
        reg [23:0] c,p;
        begin
            width=(f==2 || f==3) ? 260 : (f==4 || f==5) ? 256 :
                  (f==6 || f==7) ? 250 : 240;
            margin=(width-240)/2;
            c=asset==0 ? 24'h102030 : 24'h405060;
            age=f-2;
            if(f>=2) begin
                radius=131.4+3.4*age;fade=0.8*$pow(0.92,age+1);
                width_px=2.0+2.0*fade;
                lo=$rtoi(radius-width_px/2.0);
                if(lo<radius-width_px/2.0) lo=lo+1;
                hi=$rtoi(radius+width_px/2.0);
                opacity=$rtoi(255.0*fade+0.5);
                dist=36*(x-260)*(x-260)+25*(y-165)*(y-165);
                if(dist>=25*lo*lo && dist<=25*hi*hi)
                    c=tint(c,24'h5ee8ed,opacity[7:0]);
            end
            sx=x-(140-margin);sy=y-(45-margin);
            if(sx>=0 && sx<width && sy>=0 && sy<width) begin
                // Closed-form output-to-source mapping, independent of the RTL accumulators.
                sx=((sx+1)*240+width-1)/width-1; sy=(sy*240)/width;
                p=source_pixel(asset,sx,sy); if(p!=24'hff00ff) c=p;
            end
            expected_scene=c;
        end
    endfunction
    function [23:0] mix;
        input [23:0] o,n;
        input integer a;
        integer r,gc,b;
        begin
            r=(o[23:16]*(256-a)+n[23:16]*a+128)/256;
            gc=(o[15:8]*(256-a)+n[15:8]*a+128)/256;
            b=(o[7:0]*(256-a)+n[7:0]*a+128)/256;
            mix={r[7:0],gc[7:0],b[7:0]};
        end
    endfunction
    reg previous_de=0,older_de=0,current_de;
    reg [23:0] previous_expected=0,older_expected=0,current_expected;
    integer current_x,current_y,current_frame,previous_x=0,previous_y=0,previous_frame=0;
    integer older_x=0,older_y=0,older_frame=0;
    integer checked=0,scaled=0,transparent=0,ring_pixels=0;
    always @(posedge cp) if(!rst) begin
        current_de=de && scan[14:0]>=1;
        current_x=pixel_x;current_y=pixel_y;current_frame=scan[14:0];
        current_expected=mix(expected_scene(0,current_x,current_y,current_frame),
                             expected_scene(1,current_x,current_y,current_frame),alpha);
        #1;
        if(older_de) begin
            if(!out_de || rgb!==older_expected) begin
                $display("TEST_FAIL shared cover frame=%0d x=%0d y=%0d rgb=%h expected=%h level=%0d",
                         older_frame,older_x,older_y,rgb,older_expected,level);$finish;
            end
            checked=checked+1;
            if(older_frame>=2 && older_frame<=7) scaled=scaled+1;
            if(older_x==140 && older_y==45) transparent=transparent+1;
            if(ring_valid_d) ring_pixels=ring_pixels+1;
            if(older_frame==8 && older_x==639 && older_y==479) begin
                if(checked<8*307200 || scaled<6*307200 || transparent<8 || ring_pixels<100) begin
                    $display("TEST_FAIL display coverage %0d %0d %0d %0d",checked,scaled,transparent,ring_pixels);$finish;
                end
                $display("COVER_SCENE_COUNTS pixels=%0d scaled=%0d ring=%0d bursts=%0d",checked,scaled,ring_pixels,requests);
                $display("SCENARIO_PASS shared_writer_scaled_cover_pixels");
                $display("SCENARIO_PASS pop_decay_fade_and_transparency");
                $display("SCENARIO_PASS ring_under_cover_and_over_background");
                $display("TEST_PASS");$finish;
            end
        end
        older_de=previous_de;older_expected=previous_expected;
        older_x=previous_x;older_y=previous_y;older_frame=previous_frame;
        previous_de=current_de;previous_expected=current_expected;
        previous_x=current_x;previous_y=current_y;previous_frame=current_frame;
    end
    initial begin repeat(8) @(negedge cp);rst=0;end
    initial begin #180000000;$display("TEST_FAIL cover scene watchdog");$finish;end
endmodule
`default_nettype wire
