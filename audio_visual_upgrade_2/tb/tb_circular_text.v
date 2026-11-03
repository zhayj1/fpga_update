`timescale 1ns/1ps
`default_nettype none
module tb_circular_text;
    parameter integer REAL_SDRAM=0;
    wire memory_ready;
    reg raster_on=0;
    reg [7:0] contention_delay=0;
    reg cp=0,cs=0; always #20 cp=~cp; always #5 cs=~cs;
    reg rn=0,hs=1,vs=1,de=0,dt=0,stb=0,clear=0;
    reg [5:0] off=0;
    reg [15:0] fc[0:5],cnt[0:5];reg [5:0] vl=63;
    wire [23:0] rgb;wire valid;wire [3:0] alpha;
    wire req;wire [20:0] addr;wire [15:0] len;
    wire ack,done,dv;wire [31:0] data;
    reg [31:0] font[0:964239],lrc[0:1111];
    reg [7:0] gold[0:110591];reg [3:0] small_gold[0:76799];reg [15:0] info[0:23];
    integer phase[0:7],measured[0:7];
    integer bs=0,delay_n=0,rx=0,slow=0,saved_len=0;
    reg [20:0] saved;
    integer metadata=3;
    layer_text_aa #(.CLK_HZ(100000000),.SPP(2),.HOLD_N(4),.FIVE_LINES(0),.SINGLE_LINE(1),.CENTER_METADATA(1),.LRC_X(96),.LRC_W(448),
        .WIN_Y0(448),.WIN_H(24),.ROW_Y0(448),.PITCH(36),.LAST_GAP_TRIM(1),.TTL_Y0(16),.SGR_Y0(44),
        .BOX_X(96),.BOX_W(448)) dut(
        .clk_pix(cp),.rst_pix_n(rn),.hs(hs),.vs(vs),.de(de),.en(1'b1),.en_ttl(1'b1),
        .dout(rgb),.dout_vld(valid),.alpha(alpha),.gap_cnt(),.on_cnt(),.ttl_off(),
        .clk_sdr(cs),.rst_sdr_n(rn),.played(24'd2500),
        .prev2_fc(fc[0]),.prev2_cnt(cnt[0]),.prev2_vld(vl[0]),
        .prev_fc(fc[1]),.prev_cnt(cnt[1]),.prev_vld(vl[1]),
        .cur_fc(fc[2]),.cur_cnt(cnt[2]),.cur_vld(vl[2]),
        .nxt_fc(fc[3]),.nxt_cnt(cnt[3]),.nxt_vld(vl[3]),
        .n3_fc(fc[4]),.n3_cnt(cnt[4]),.n3_vld(vl[4]),
        .n4_fc(fc[5]),.n4_cnt(cnt[5]),.n4_vld(vl[5]),.song_clear(clear),
        .off_px(off),.desc_tgl(dt),.samp_stb(stb),
        .ttl_fc(info[metadata*3]),.ttl_cnt(info[metadata*3+1]),.sgr_fc(info[metadata*3]),.sgr_cnt(info[metadata*3+1]),
        .ttl_vld(1'b1),.sgr_vld(1'b1),.px_req(req),.px_addr(addr),.px_len(len),
        .px_ack(ack),.px_done(done),.px_data(data),.px_valid(dv));
    generate if(REAL_SDRAM) begin : g_real
        text_sdram_environment env(.clk(cs),.rst_n(rn),.hs(hs),.raster_on(raster_on),
            .contention_delay(contention_delay),.ready(memory_ready),
            .req(req),.addr(addr),.len(len),.ack(ack),.done(done),.valid(dv),.data(data));
    end else begin : g_fast
        reg ack_r=0,done_r=0,dv_r=0;reg [31:0] data_r=0;
        assign ack=ack_r;assign done=done_r;assign dv=dv_r;assign data=data_r;
        assign memory_ready=1'b1;
    always @(negedge cs) begin
        ack_r=0;done_r=0;dv_r=0;
        if(!rn) bs=0;
        else case(bs)
        0:if(req) begin saved=addr;saved_len=len;delay_n=2;bs=1;end
        1:if(delay_n==0) begin ack_r=1;rx=0;bs=2;delay_n=slow;end else delay_n=delay_n-1;
        2:if(delay_n==0) begin
            if(saved>=21'h10BBB0 && saved+rx<21'h10BBB0+964240) data_r=font[saved-21'h10BBB0+rx];
            else if(saved>=21'h10B300 && saved+rx<21'h10B300+1112) data_r=lrc[saved-21'h10B300+rx];
            else begin $display("TEST_FAIL address");$finish;end
            dv_r=1;if(rx==saved_len-1) begin done_r=1;bs=0;end else rx=rx+1;
        end else delay_n=delay_n-1;
        endcase
    end
    end endgenerate

    integer cancels=0,ink=0,checked=0,sung_pixels=0,other_pixels=0;
    always @(posedge cs) if(rn) begin
        if(dut.cancel_job)cancels=cancels+1;
        if(de && dut.wr_en && dut.wr_addr[10]==dut.current_y[0]) begin
            $display("TEST_FAIL active text bank overwritten");$finish;
        end
    end
    integer current=0,ly,xx,j,k,n,source,width,left,lp=0,tp=0,sp=0;
    integer divn=0,holdn=0,sample_no,fd,mode=0;
    reg [7:0] pixel;reg [3:0] ea;reg [23:0] ec;
    task check_pixel;
        input integer x,y;
        begin
            ea=0;ec=24'hE8E4FF;source=-1;
            if(y>=448 && y<472 && vl[2]) begin
                width=info[current*3+2];
                if(width<=448)begin left=96+(448-width)/2;if(x>=left && x<left+width)source=x-left;end
                else if(x>=96 && x<544)begin
                    source=(x-96+(lp<2?0:lp-2))%(width+448);if(source>=width)source=-1;
                end
                if(source>=0)begin pixel=gold[current*13824+(y-448)*576+source];ea=pixel[3:0];if(pixel[4])ec=24'hFFE8AA;end
            end
            if(y>=16 && y<40)begin
                width=info[metadata*3+2];source=-1;
                if(width<=448)begin left=96+(448-width)/2;if(x>=left && x<left+width)source=x-left;end
                else if(x>=96 && x<544)begin source=(x-96+tp)%(width+448);if(source>=width)source=-1;end
                ec=24'hFFFFFF;if(source>=0)ea=gold[metadata*13824+(y-16)*576+source]&15;
            end
            if(y>=44 && y<64)begin
                // Fixture sentence 3 is nineteen fullwidth glyphs: 20px singer
                // glyphs produce 380px, centered in the same 448px window.
                width=metadata==3?380:0;source=-1;left=96+(448-width)/2;
                if(x>=left && x<left+width)source=x-left;
                ec=24'hBCC4D2;if(source>=0)ea=small_gold[3*9600+(y-44)*480+source];
            end
            if(mode!=4 && (alpha!==ea || valid!==(ea!=0) || (ea!=0 && rgb!==ec)))begin
                $display("TEST_FAIL single text xy=%0d,%0d alpha=%h/%h rgb=%h/%h line=%0d phase=%0d",x,y,alpha,ea,rgb,ec,current,lp);$finish;
            end
            if(valid)begin ink=ink+1;if(rgb==24'hFFE8AA)sung_pixels=sung_pixels+1;if(rgb==24'hE8E4FF)other_pixels=other_pixels+1;end
            checked=checked+1;if(mode==0)$fdisplay(fd,"%01h%06h",alpha,rgb);
        end
    endtask
    task descriptors;
        begin
            for(j=0;j<6;j=j+1)begin
                k=current-2+j;vl[j]=k>=0 && k<8;
                if(vl[j])begin fc[j]=info[k*3];cnt[j]=info[k*3+1];end else begin fc[j]=0;cnt[j]=0;end
            end
            dt=~dt;repeat(12)@(negedge cp);
        end
    endtask
    task draw_frame;
        begin
            @(negedge cp);vs=0;hs=1;de=0;repeat(800)@(negedge cp);vs=1;
            for(ly=0;ly<515;ly=ly+1)for(xx=0;xx<800;xx=xx+1)begin
                hs=xx>=96;de=xx>=144 && xx<784 && ly>=34 && ly<514;
                #1;if(de)check_pixel(xx-144,ly-34);@(negedge cp);
            end
            de=0;hs=1;
        end
    endtask
    task steps;
        input integer count;
        begin
            for(n=0;n<count;n=n+1)begin
                if(info[current*3+2]>448)lp=(lp+1)%(info[current*3+2]+450);
                for(sample_no=0;sample_no<2;sample_no=sample_no+1)begin
                    if(holdn>0)holdn=holdn-1;
                    else if(divn<1)divn=divn+1;
                    else begin
                        divn=0;
                        if(tp==903)holdn=4;
                        tp=(tp+1)%904;
                    end
                    @(negedge cs);stb=1;@(negedge cs);stb=0;repeat(10)@(negedge cp);
                end
            end
        end
    endtask
    initial begin
        $readmemh("sim/typography_font.mem",font);$readmemh("sim/layout_five_lrc.mem",lrc);
        $readmemh("sim/layout_five_gold.mem",gold);$readmemh("sim/layout_five_info.mem",info);
        $readmemh("sim/layout_five_small.mem",small_gold);
        fd=$fopen(REAL_SDRAM?"sim/circular_text_real_frame.hex":"sim/circular_text_frame.hex","w");
        repeat(8)@(negedge cp);rn=1;wait(memory_ready);descriptors;raster_on=1;draw_frame;$fclose(fd);
        if(ink==0 || checked!=307200 || sung_pixels==0 || other_pixels==0)begin
            $display("TEST_FAIL text coverage ink=%0d sung=%0d other=%0d",ink,sung_pixels,other_pixels);$finish;end
        $display("SCENARIO_PASS CIRC-text-layout-and-highlight");
        current=3;off=36;lp=0;mode=1;descriptors;draw_frame;steps(19);contention_delay=40;draw_frame;
        $display("SCENARIO_PASS CIRC-text-single-row-and-marquee");
        steps(920);contention_delay=120;draw_frame;
        $display("SCENARIO_PASS CIRC-text-marquee-wrap");
        @(negedge cs);clear=1;@(negedge cs);clear=0;lp=0;current=7;off=0;mode=2;descriptors;contention_delay=3;draw_frame;
        $display("SCENARIO_PASS CIRC-text-song-reset-and-short-line");
        if(REAL_SDRAM)begin
            if(cancels!=0)begin $display("TEST_FAIL SDRAM text deadline %0d",cancels);$finish;end
            $display("SCENARIO_PASS CIRC-text-real-sdram-contention");
        end else begin
            slow=6000;mode=4;draw_frame;
            if(cancels==0)begin $display("TEST_FAIL absent cancellation");$finish;end
            slow=0;repeat(7000)@(negedge cs);mode=5;draw_frame;
            $display("SCENARIO_PASS CIRC-text-late-job-recovery");
        end
        $display("TEST_PASS");$finish;
    end
    initial begin #200000000;$display("TEST_FAIL text timeout");$finish;end
endmodule
`default_nettype wire
