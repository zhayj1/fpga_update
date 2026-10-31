`timescale 1ns/1ps
`default_nettype none
module tb_layout_five;
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
    layer_text_aa #(.CLK_HZ(100000000),.SPP(2),.HOLD_N(4),.FIVE_LINES(1),
        .WIN_Y0(118),.WIN_H(167),.ROW_Y0(190),.PITCH(36),.LAST_GAP_TRIM(1),.TTL_Y0(45),.SGR_Y0(77),
        .BOX_X(336),.BOX_W(288)) dut(
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
        .ttl_fc(info[9]),.ttl_cnt(info[10]),.sgr_fc(info[9]),.sgr_cnt(info[10]),
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
    integer cancels=0,ink=0,checked=0;
    always @(posedge cs) if(rn) begin
        if(dut.cancel_job) cancels=cancels+1;
        if(de && dut.wr_en && dut.wr_addr[10]==dut.current_y[0]) begin
            $display("TEST_FAIL active bank overwrite");$finish;end
    end
    integer current=2,mode=0,ly,xx,slot,sentence,top,width,source,hphase,left,j,k,n;
    integer title_phase=0,singer_phase=0,title_div=0,title_hold=0,sample_no;
    integer dump_file,rotation;reg [7:0] pixel;reg [3:0] ea;reg [23:0] ec;
    function integer row_top;
        input integer index,phase_px;
        integer start_y,end_y;
        begin
            case(index)
            0:begin start_y=118;end_y=82;end
            1:begin start_y=154;end_y=118;end
            2:begin start_y=190;end_y=154;end
            3:begin start_y=226;end_y=190;end
            4:begin start_y=261;end_y=226;end
            default:begin start_y=297;end_y=261;end
            endcase
            // Ceil interpolation keeps the 35px move continuous with its peers.
            row_top=end_y+((start_y-end_y)*(36-phase_px)+35)/36;
        end
    endfunction
    task check_pixel;
        input integer x,y;
        begin
            ea=0;ec=24'hE8E4FF;
            for(slot=0;slot<6;slot=slot+1) begin
                top=row_top(slot,off);sentence=current-2+slot;
                if(vl[slot] && sentence>=0 && sentence<8 && y>=118 && y<285 && y>=top && y<top+24) begin
                    width=info[sentence*3+2];source=-1;
                    if(width<=336) begin
                        left=296+(336-width)/2;
                        if(x>=left && x<left+width) source=x-left;
                    end else if(x>=296 && x<632) begin
                        hphase=phase[sentence]<2 ? 0 : phase[sentence]-2;
                        source=(x-296+hphase)%(width+336);
                        if(source>=width) source=-1;
                    end
                    if(source>=0) begin
                        pixel=gold[sentence*13824+(y-top)*576+source];ea=pixel[3:0];
                        if(slot==2 && pixel[4]) ec=24'hFF5FCB;
                    end
                end
            end
            if(x>=336 && x<624 && y>=45 && y<69) begin
                source=(x-336+title_phase)%744;ec=24'hFFFFFF;
                if(source<456) ea=gold[3*13824+(y-45)*576+source]&15;
            end
            if(x>=336 && x<624 && y>=77 && y<97) begin
                source=(x-336+singer_phase)%668;ec=24'hBCC4D2;
                if(source<380) ea=small_gold[3*9600+(y-77)*480+source];
            end
            if(mode==5) ea=0;
            if(alpha!==ea || valid!==(ea!=0) || (ea!=0 && rgb!==ec)) begin
                $display("TEST_FAIL layout mode=%0d x=%0d y=%0d a=%h/%h rgb=%h/%h",mode,x,y,alpha,ea,rgb,ec);$finish;end
            checked=checked+1;if(ea!=0) ink=ink+1;
            if(mode==0) $fwrite(dump_file,"%06x\n",alpha!=0 ? rgb : 24'h0b1420);
        end
    endtask
    task descriptors;
        begin
            for(j=0;j<6;j=j+1) begin
                k=current-2+j;
                vl[j]=k>=0 && k<8;
                if(vl[j]) begin fc[j]=info[k*3];cnt[j]=info[k*3+1];end
                else begin fc[j]=0;cnt[j]=0;end
            end
            dt=~dt;repeat(12) @(negedge cp);
        end
    endtask
    task draw_frame;
        begin
            @(negedge cp);vs=0;hs=1;de=0;
            repeat(800) @(negedge cp);vs=1;
            for(ly=0;ly<515;ly=ly+1) for(xx=0;xx<800;xx=xx+1) begin
                hs=xx>=96;de=xx>=144 && xx<784 && ly>=34 && ly<514;
                #1;if(de) check_pixel(xx-144,ly-34);@(negedge cp);
            end
            de=0;hs=1;
            if(mode!=5) for(j=0;j<6;j=j+1) begin
                k=current-2+j;
                if(vl[j] && row_top(j,off)<285 && row_top(j,off)+24>118) measured[k]=1;
            end
        end
    endtask
    task steps;
        input integer amount;
        begin
            for(n=0;n<amount;n=n+1) begin
                for(j=0;j<8;j=j+1) if(measured[j] && info[j*3+2]>336)
                    phase[j]=(phase[j]+1)%(info[j*3+2]+338);
                for(sample_no=0;sample_no<2;sample_no=sample_no+1) begin
                    if(title_hold>0) title_hold=title_hold-1;
                    else if(title_div<1) title_div=title_div+1;
                    else begin
                        title_div=0;
                        if(title_phase==743 || singer_phase==667) title_hold=4;
                        title_phase=(title_phase+1)%744;singer_phase=(singer_phase+1)%668;
                    end
                    @(negedge cs);stb=1;@(negedge cs);stb=0;
                    repeat(10) @(negedge cp);
                end
            end
            repeat(12) @(negedge cp);
        end
    endtask
    initial begin
        $readmemh("sim/typography_font.mem",font);$readmemh("sim/layout_five_lrc.mem",lrc);
        $readmemh("sim/layout_five_gold.mem",gold);$readmemh("sim/layout_five_info.mem",info);
        $readmemh("sim/layout_five_small.mem",small_gold);
        for(j=0;j<8;j=j+1) begin phase[j]=0;measured[j]=0;end
        dump_file=$fopen(REAL_SDRAM ? "sim/lyricspace_real_frame.hex" : "sim/lyricspace_fast_frame.hex","w");
        repeat(8) @(negedge cp);rn=1;wait(memory_ready);descriptors;raster_on=1;draw_frame;$fclose(dump_file);
        if(REAL_SDRAM) begin
            if(ink==0 || checked!=307200 || cancels!=0) begin
                $display("TEST_FAIL real frame ink=%0d checked=%0d cancels=%0d",ink,checked,cancels);$finish;end
            $display("SCENARIO_PASS FIX-01-real-layer-contended-pixels");
            steps(19);off=18;contention_delay=40;descriptors;mode=1;draw_frame;
            off=36;contention_delay=120;descriptors;mode=2;draw_frame;
            current=3;off=0;contention_delay=3;descriptors;mode=3;draw_frame;
            if(cancels!=0) begin $display("TEST_FAIL real layer late jobs %0d",cancels);$finish;end
            $display("SCENARIO_PASS FIX-02-real-layer-scroll-deadline");
            $display("TEST_PASS");$finish;
        end
        if(ink==0 || checked!=307200) begin $display("TEST_FAIL empty frame");$finish;end
        $display("SCENARIO_PASS LAY-02-pixels");
        steps(19);off=1;descriptors;mode=1;draw_frame;
        off=18;descriptors;draw_frame;
        off=35;descriptors;draw_frame;
        off=36;descriptors;mode=2;draw_frame;
        $display("SCENARIO_PASS LAY-04-vertical");
        current=3;off=0;descriptors;mode=3;draw_frame;
        steps(800);mode=4;draw_frame;
        $display("SCENARIO_PASS LAY-03-marquee");
        slow=6000;mode=5;draw_frame;
        if(cancels==0) begin $display("TEST_FAIL cancellation absent");$finish;end
        slow=0;repeat(7000) @(negedge cs);mode=6;draw_frame;
        $display("SCENARIO_PASS LAY-05-deadline");
        @(negedge cs);clear=1;@(negedge cs);clear=0;
        for(j=0;j<8;j=j+1) begin phase[j]=0;measured[j]=0;end
        current=0;descriptors;mode=7;draw_frame;
        current=7;descriptors;mode=8;draw_frame;
        $display("SCENARIO_PASS LAY-02-boundaries");
        @(negedge cs);clear=1;@(negedge cs);clear=0;
        for(j=0;j<8;j=j+1) begin phase[j]=0;measured[j]=0;end
        off=0;mode=9;
        for(rotation=0;rotation<8;rotation=rotation+1) begin
            current=rotation;descriptors;draw_frame;steps(4);
        end
        $display("SCENARIO_PASS LAY-03-phase-rotation");
        $display("TEST_PASS");$finish;
    end
    initial begin #400000000;$display("TEST_FAIL watchdog");$finish;end
endmodule
`default_nettype wire
