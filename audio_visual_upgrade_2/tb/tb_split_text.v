`timescale 1ns/1ps
`default_nettype none
module tb_split_text;
    parameter integer REAL_SDRAM=0;
    wire memory_ready;
    reg raster_on=0;
    reg [7:0] contention_delay=0;
    reg cp=0,cs=0; always #20 cp=~cp; always #5 cs=~cs;
    reg rn=0,hs=1,vs=1,de=0,dt=0,stb=0,clear=0;
    reg [5:0] off=0;
    reg [15:0] fc[0:7],cnt[0:7];reg [7:0] vl=255;
    wire [23:0] rgb;wire valid;wire [3:0] alpha;
    wire req;wire [20:0] addr;wire [15:0] len;
    wire ack,done,dv;wire [31:0] data;
    reg [31:0] font[0:964239],lrc[0:1111];
    reg [7:0] gold[0:110591],lyric_gold[0:76799];
    reg [3:0] small_gold[0:76799];reg [15:0] info[0:23],small_width[0:7];
    integer phase[0:7],measured[0:7];
    integer bs=0,delay_n=0,rx=0,slow=0,saved_len=0;
    reg [20:0] saved;
    layer_text_aa #(.CLK_HZ(100000000),.SPP(2),.HOLD_N(4),.SEVEN_LINES(1),.VALIDATED_LYRICS(1),.LRC_SMALL(1),.CENTER_METADATA(1),.LRC_X(340),.LRC_W(280),
        .WIN_Y0(166),.WIN_H(216),.ROW_Y0(262),.PITCH(32),.LAST_GAP_TRIM(0),.TTL_Y0(82),.SGR_Y0(116),
        .BOX_X(336),.BOX_W(288)) dut(
        .clk_pix(cp),.rst_pix_n(rn),.hs(hs),.vs(vs),.de(de),.en(1'b1),.en_ttl(1'b1),
        .dout(rgb),.dout_vld(valid),.alpha(alpha),.gap_cnt(),.on_cnt(),.ttl_off(),
        .clk_sdr(cs),.rst_sdr_n(rn),.played(24'd2500),
        .prev3_fc(fc[0]),.prev3_cnt(cnt[0]),.prev3_vld(vl[0]),
        .n5_fc(fc[7]),.n5_cnt(cnt[7]),.n5_vld(vl[7]),
        .prev2_fc(fc[1]),.prev2_cnt(cnt[1]),.prev2_vld(vl[1]),
        .prev_fc(fc[2]),.prev_cnt(cnt[2]),.prev_vld(vl[2]),
        .cur_fc(fc[3]),.cur_cnt(cnt[3]),.cur_vld(vl[3]),
        .nxt_fc(fc[4]),.nxt_cnt(cnt[4]),.nxt_vld(vl[4]),
        .n3_fc(fc[5]),.n3_cnt(cnt[5]),.n3_vld(vl[5]),
        .n4_fc(fc[6]),.n4_cnt(cnt[6]),.n4_vld(vl[6]),.song_clear(clear),
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
    integer mode=0;
    integer cancels=0,ink=0,checked=0,phase_collisions=0,width_collisions=0;
    integer capacity14_jobs=0,capacity15_jobs=0;
    always @(posedge cp) if(rn) begin
        if(dut.g_ram_phase.phase_write && dut.phase_slot==dut.selected_phase_index)
            phase_collisions=phase_collisions+1;
        if(dut.g_ram_phase.width_write && dut.completed_phase_index==dut.phase_slot)
            width_collisions=width_collisions+1;
        if(mode==10 && dut.hs_f && dut.want && dut.kind==0 &&
           (^dut.lyric_offset===1'bx)) begin
            $display("TEST_FAIL live marquee unknown phase");$finish;
        end
    end
    always @(posedge cs) if(rn) begin
        if(dut.row_done && dut.working && dut.c_kind==0 && dut.row_error==0) begin
            if(mode==11 && dut.c_cnt==14) begin
                if(dut.row_width!=280) begin $display("TEST_FAIL 14 character width");$finish;end
                capacity14_jobs=capacity14_jobs+1;
            end
            if(mode==12 && dut.c_cnt==15) begin
                if(dut.row_width!=300) begin $display("TEST_FAIL 15 character width");$finish;end
                capacity15_jobs=capacity15_jobs+1;
            end
        end
        if(dut.cancel_job) cancels=cancels+1;
        if(de && dut.wr_en && dut.wr_addr[10]==dut.current_y[0]) begin
            $display("TEST_FAIL active bank overwrite");$finish;end
    end
    integer current=3,ly,xx,slot,sentence,top,width,source,hphase,left,j,k,n;
    integer title_phase=0,singer_phase=0,title_div=0,title_hold=0,sample_no;
    integer dump_file,rotation;reg [7:0] pixel;reg [3:0] ea;reg [23:0] ec;
    function integer row_top;
        input integer index,phase_px;
        integer start_y,end_y;
        begin
            row_top=166+index*32-phase_px;
        end
    endfunction
    function integer lyric_width;
        input integer sentence;
        begin
            lyric_width=small_width[sentence];
            if(sentence==3 && mode==11) lyric_width=280;
            if(sentence==3 && mode==12) lyric_width=300;
        end
    endfunction
    task check_pixel;
        input integer x,y;
        begin
            ea=0;ec=24'hE8E4FF;
            for(slot=0;slot<8;slot=slot+1) begin
                top=row_top(slot,off);sentence=current-3+slot;
                if(vl[slot] && sentence>=0 && sentence<8 && y>=166 && y<382 && y>=top && y<top+20) begin
                    width=lyric_width(sentence);source=-1;
                    if(width<=280) begin
                        left=340+(280-width)/2;
                        if(x>=left && x<left+width) source=x-left;
                    end else if(x>=340 && x<620) begin
                        hphase=mode==10 ? dut.active_scroll : (phase[sentence]<2 ? 0 : phase[sentence]-2);
                        source=(x-340+hphase)%(width+280);
                        if(source>=width) source=-1;
                    end
                    if(source>=0) begin
                        pixel=lyric_gold[sentence*9600+(y-top)*480+source];ea=pixel[3:0];
                        if(slot==3 && pixel[4]) ec=24'hFFE8AA;
                    end
                end
            end
            if(x>=336 && x<624 && y>=82 && y<106) begin
                source=(x-336+(mode>=10 ? dut.active_scroll : title_phase))%744;ec=24'hFFFFFF;
                if(source<456) ea=gold[3*13824+(y-82)*576+source]&15;
            end
            if(x>=336 && x<624 && y>=116 && y<136) begin
                source=(x-336+(mode>=10 ? dut.active_scroll : singer_phase))%668;ec=24'hBCC4D2;
                if(source<380) ea=small_gold[3*9600+(y-116)*480+source];
            end
            if(mode==5) ea=0;
            if(alpha!==ea || valid!==(ea!=0) || (ea!=0 && rgb!==ec)) begin
                $display("TEST_FAIL layout mode=%0d x=%0d y=%0d a=%h/%h rgb=%h/%h",mode,x,y,alpha,ea,rgb,ec);$finish;end
            checked=checked+1;if(ea!=0) ink=ink+1;
            if(mode==0) $fwrite(dump_file,"%01x%06x\n",alpha,rgb);
        end
    endtask
    task descriptors;
        begin
            for(j=0;j<8;j=j+1) begin
                k=current-3+j;
                vl[j]=k>=0 && k<8;
                if(vl[j]) begin fc[j]=info[k*3];cnt[j]=info[k*3+1];end
                else begin fc[j]=0;cnt[j]=0;end
                if(k==3 && mode==11) cnt[j]=14;
                if(k==3 && mode==12) cnt[j]=15;
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
            if(mode!=5) for(j=0;j<8;j=j+1) begin
                k=current-3+j;
                if(vl[j] && row_top(j,off)<382 && row_top(j,off)+20>166) measured[k]=1;
            end
        end
    endtask
    task steps;
        input integer amount;
        begin
            for(n=0;n<amount;n=n+1) begin
                for(j=0;j<8;j=j+1) if(measured[j] && lyric_width(j)>280)
                    phase[j]=(phase[j]+1)%(lyric_width(j)+282);
                for(sample_no=0;sample_no<2;sample_no=sample_no+1) begin
                    if(title_hold>0) title_hold=title_hold-1;
                    else if(title_div<1) title_div=title_div+1;
                    else begin
                        title_div=0;
                        if(title_phase==743 || singer_phase==667) title_hold=4;
                        title_phase=(title_phase+1)%744;singer_phase=(singer_phase+1)%668;
                    end
                    @(negedge cs);stb=1;@(negedge cs);stb=0;
                    repeat(40) @(negedge cp);
                end
            end
            repeat(12) @(negedge cp);
        end
    endtask
    task capacity_boundaries;
        begin
            for(mode=11;mode<=12;mode=mode+1) begin
                @(negedge cs);clear=1;@(negedge cs);clear=0;
                for(j=0;j<8;j=j+1) begin phase[j]=0;measured[j]=0;end
                current=3;off=0;descriptors;draw_frame;steps(19);draw_frame;
                if(mode==11 && phase[3]!=0) begin $display("TEST_FAIL 14 character marquee");$finish;end
                if(mode==12 && phase[3]<=2) begin $display("TEST_FAIL 15 character marquee absent");$finish;end
            end
            if(capacity14_jobs<20 || capacity15_jobs<20) begin
                $display("TEST_FAIL capacity jobs %0d %0d",capacity14_jobs,capacity15_jobs);$finish;end
            $display("SCENARIO_PASS CAP-14-stationary-15-marquee");
        end
    endtask
    initial begin
        $readmemh("sim/typography_font.mem",font);$readmemh("sim/layout_five_lrc.mem",lrc);
        $readmemh("sim/layout_five_gold.mem",gold);$readmemh("sim/layout_five_info.mem",info);
        $readmemh("sim/layout_five_small.mem",small_gold);
        $readmemh("sim/split14_gold.mem",lyric_gold);$readmemh("sim/split14_widths.mem",small_width);
        for(j=0;j<8;j=j+1) begin phase[j]=0;measured[j]=0;end
        dump_file=$fopen(REAL_SDRAM ? "sim/split_real_frame.hex" : "sim/split_fast_frame.hex","w");
        repeat(8) @(negedge cp);rn=1;wait(memory_ready);descriptors;raster_on=1;draw_frame;$fclose(dump_file);
        if(REAL_SDRAM) begin
            if(ink==0 || checked!=307200 || cancels!=0) begin
                $display("TEST_FAIL real frame ink=%0d checked=%0d cancels=%0d",ink,checked,cancels);$finish;end
            $display("SCENARIO_PASS FIX-01-real-layer-contended-pixels");
            steps(19);off=16;contention_delay=40;descriptors;mode=1;draw_frame;
            off=32;contention_delay=120;descriptors;mode=2;draw_frame;
            current=4;off=0;contention_delay=3;descriptors;mode=3;draw_frame;
            if(cancels!=0) begin $display("TEST_FAIL real layer late jobs %0d",cancels);$finish;end
            $display("SCENARIO_PASS FIX-02-real-layer-scroll-deadline");
            capacity_boundaries;
            $display("TEST_PASS");$finish;
        end
        if(ink==0 || checked!=307200) begin $display("TEST_FAIL empty frame");$finish;end
        $display("SCENARIO_PASS LAY-02-pixels");
        steps(19);off=1;descriptors;mode=1;draw_frame;
        off=16;descriptors;draw_frame;
        off=31;descriptors;draw_frame;
        off=32;descriptors;mode=2;draw_frame;
        $display("SCENARIO_PASS LAY-04-vertical");
        current=4;off=0;descriptors;mode=3;draw_frame;
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
        current=3;off=0;descriptors;mode=10;
        phase_collisions=0;width_collisions=0;
        fork
            begin
                repeat(800) begin
                    repeat(520) @(negedge cp);
                    @(negedge cs);stb=1;@(negedge cs);stb=0;
                end
            end
            begin draw_frame;end
        join
        if(phase_collisions==0) begin $display("TEST_FAIL live RAM collision absent");$finish;end
        $display("LIVE_RAM phase_collisions=%0d width_collisions=%0d",phase_collisions,width_collisions);
        $display("SCENARIO_PASS LAY-06-live-marquee-collision");
        capacity_boundaries;
        $display("TEST_PASS");$finish;
    end
    initial begin #500000000;$display("TEST_FAIL watchdog");$finish;end
endmodule
`default_nettype wire
