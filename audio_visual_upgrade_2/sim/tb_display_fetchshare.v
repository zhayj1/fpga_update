`timescale 1ns/1ps
`default_nettype none
// Real raster + four image readers + both arbiters + encrypted SDR controller
// + vendor DRAM/BRAM models. Data is installed through the real loader port.
// Additional clients issue 38 text reads per line and 128-word preload writes.
module tb_display_fetchshare;
    parameter integer LINES=16,COVER_LINES=8;
    parameter integer PHYSICAL=1;
    parameter real SDR_HALF=5.0,SDR_SHIFT=5.0;
    reg cp=0,cs=0,shift=0,rn=0,display_on=0;
    always #20 cp=~cp;
    always #(SDR_HALF) cs=~cs;
    initial begin #(SDR_HALF+SDR_SHIFT); shift=1; forever #(SDR_HALF) shift=~shift; end
    wire hs,vs,de;
    color_bar #(.V_ACTIVE(LINES)) raster(.clk(cp),.rst(!rn || !display_on),
        .hs(hs),.vs(vs),.de(de),.rgb_r(),.rgb_g(),.rgb_b());
    wire [4:0] req,ack,done,valid;
    wire [66:0] scan_state;
    wire [3:0] cmds,slots,banks,taken,wr_take,wr_active,wr_done,wr_err,wr_en;
    wire [83:0] cmd_addresses;
    wire [63:0] cmd_lengths;
    wire [9:0] wr_addr;
    wire wr_good;
    wire shared_req;
    wire [20:0] shared_addr;
    wire [15:0] shared_len;
    assign req[3:0]={3'd0,shared_req};
    scene_raster shared_raster(.clk_pix(cp),.rst_pix_n(rn),.hs(hs),.vs(vs),.de(de),.state(scan_state));
    // This stress fixture orders BG, old BG, CV, old CV.
    fetch_writer4 #(.MAX_W0(640),.MAX_W1(640),.MAX_W2(320),.MAX_W3(320)) writer(
        .clk_sdr(cs),.rst_sdr_n(rn),.cmd_valid(cmds),.slot_free(slots),.next_bank(banks),
        .cmd_addr(cmd_addresses),.cmd_words(cmd_lengths),.cmd_ack(taken),
        .wr_take(wr_take),.wr_active(wr_active),.wr_done(wr_done),.wr_error(wr_err),.wr_en(wr_en),
        .wr_addr(wr_addr),.wr_good(wr_good),.px_req(shared_req),.px_addr(shared_addr),.px_len(shared_len),
        .px_ack(ack[0]),.px_done(done[0]),.px_valid(valid[0]));
    wire [23:0] rgb[0:3];
    wire [3:0] visible;
    wire [31:0] und[0:3],stall[0:3],ferr[0:3],gap[0:3];
    reg scene=0,hp=0,vp=0,dp=0,epoch=0;
    integer frame=0,xx=0,yy=0,checked[0:3],errors[0:3],collisions[0:3];
    function [23:0] pixel;
        input integer layer,row,col,sc;
        reg [7:0] r,g,b;
        begin r=layer*43+row*11+sc*73+col/256;
            g=col*3+row*7+sc*29; b=col+row*19+layer*17+sc*47;
            pixel={r,g,b}; end
    endfunction
    function [31:0] word_at;
        input integer addr;
        integer sc,layer,off,w,row,wcol,j,bpos;
        reg [23:0] p;
        begin
            sc=addr/1048576; off=addr%1048576;
            layer=off/262144; off=off%262144; w=(layer<2)?640:320;
            row=off/(w*3/4); wcol=off%(w*3/4); word_at=0;
            for(j=0;j<4;j=j+1) begin
                bpos=wcol*4+j; p=pixel(layer,row,bpos/3,sc);
                case(bpos%3)
                    0:word_at[j*8+:8]=p[23:16];
                    1:word_at[j*8+:8]=p[15:8];
                    2:word_at[j*8+:8]=p[7:0];
                endcase
            end
        end
    endfunction
    wire [31:0] bus_data;
    genvar g;
    generate for(g=0;g<4;g=g+1) begin: images
        localparam integer W=(g<2)?640:320, WX=(g<2)?0:100, WY=(g<2)?0:3;
        localparam integer H=(g<2)?LINES:COVER_LINES, WPR=W*3/4;
        wire [20:0] base=g*262144+(scene ? 1048576 : 0);
        layer_bg #(.MAX_W(W),.V_ACT_LIN(LINES),.SHARED_RASTER(1),.SHARED_WRITER(1)) dut(
            .clk_pix(cp),.rst_pix_n(rn),.hs(hs),.vs(vs),.de(de),.en(display_on),
            .win_x(WX[15:0]),.win_y(WY[15:0]),.win_w(W[15:0]),.win_h(H[15:0]),
            .img_w(W[15:0]),.img_h(H[15:0]),.words_per_row(WPR[15:0]),.slot_base(base),
            .dout(rgb[g]),.dout_vld(visible[g]),.underrun_cnt(und[g]),.stall_cnt(stall[g]),
            .ferr_cnt(ferr[g]),.gap_cnt(gap[g]),.idle(),.clk_sdr(cs),.rst_sdr_n(rn),
            .px_req(),.px_addr(),.px_len(),.px_ack(1'b0),
            .px_done(1'b0),.px_data(bus_data),.px_valid(1'b0),
            .scan_state(scan_state),.cmd_valid(cmds[g]),.slot_free(slots[g]),.next_bank(banks[g]),
            .cmd_addr(cmd_addresses[g*21+:21]),.cmd_words(cmd_lengths[g*16+:16]),.cmd_ack(taken[g]),
            .wr_take(wr_take[g]),.wr_active(wr_active[g]),.wr_done(wr_done[g]),
            .wr_error(wr_err[g]),.wr_en(wr_en[g]),.wr_good(wr_good),.wr_addr(wr_addr));
        always @(posedge cs) if(rn && dut.u_fl.mem_we && dut.u_fl.stream_on &&
            dut.u_fl.wr_buf_l==dut.u_fl.rd_buf) collisions[g]=collisions[g]+1;
    end endgenerate
    wire bus_req,bus_ack,bus_done,bus_valid;
    wire [20:0] bus_addr;
    wire [15:0] bus_len;
    reg text_req=0,text_busy=0;
    integer text_left=0,text_jobs=0;
    reg [1:0] epoch_sync=0;
    reg epoch_seen=0;
    assign req[4]=text_req;
    px_arb5 arb5(.clk_sdr(cs),.rst_sdr_n(rn),.c_req(req),
        .c_addr({21'd0,63'd0,shared_addr}),
        .c_len({16'd4,48'd0,shared_len}),
        .c_ack(ack),.c_done(done),.c_valid(valid),.arb_req(bus_req),.arb_addr(bus_addr),
        .arb_len(bus_len),.arb_ack(bus_ack),.arb_done(bus_done),.arb_valid(bus_valid),
        .grant_cnt(),.contend_cnt());
    always @(posedge cs) if(rn && display_on) begin
        epoch_sync<={epoch_sync[0],epoch};
        if(epoch_sync[1]!=epoch_seen) begin epoch_seen<=epoch_sync[1]; text_left<=38; end
        if(!text_busy && !text_req && text_left>0) begin text_req<=1; text_busy<=1; end
        if(ack[4]) text_req<=0;
        if(done[4]) begin text_busy<=0; text_left<=text_left-1; text_jobs<=text_jobs+1; end
    end
    wire init_done,ref_vld,sdr_busy,app_rd,app_wr,rdv;
    wire [20:0] ra,wa;
    wire [3:0] dm;
    wire [31:0] wd,rd;
    reg ld_req=0;
    reg [20:0] ld_addr=0;
    reg [15:0] ld_len=0;
    integer wi=0,write_jobs=0;
    wire ld_rd,ld_ack,ld_done;
    wire [31:0] ld_data=word_at(ld_addr+wi);
    always @(posedge cs) if(ld_rd) wi<=wi+1;
    sdram_arb arb(.clk(cs),.rst_n(rn),.app_rd_en(app_rd),.app_rd_addr(ra),
        .app_wr_en(app_wr),.app_wr_addr(wa),.app_wr_dm(dm),.app_wr_din(wd),
        .sdr_rd_en(rdv),.sdr_rd_dout(rd),.sdr_busy(sdr_busy),
        .sdr_init_done(init_done),.sdr_init_ref_vld(ref_vld),
        .px_req(bus_req),.px_addr(bus_addr),.px_len(bus_len),.px_ack(bus_ack),
        .px_done(bus_done),.px_data(bus_data),.px_valid(bus_valid),
        .ctl_req(1'b0),.ctl_addr(21'd0),.ctl_len(16'd0),.ctl_ack(),.ctl_done(),.ctl_data(),.ctl_valid(),
        .ld_req(ld_req),.ld_addr(ld_addr),.ld_len(ld_len),.ld_data(ld_data),
        .ld_rd(ld_rd),.ld_ack(ld_ack),.ld_done(ld_done),.arb_busy(),.gnt());
    generate if(PHYSICAL) begin: physical
    sdram_top phy(.Clk(cs),.Clk_sft(shift),.Rst(!rn),.Sdr_init_done(init_done),
        .Sdr_init_ref_vld(ref_vld),.Sdr_busy(sdr_busy),.App_wr_en(app_wr),.App_wr_addr(wa),
        .App_wr_dm(dm),.App_wr_din(wd),.App_rd_en(app_rd),.App_rd_addr(ra),
        .Sdr_rd_en(rdv),.Sdr_rd_dout(rd),.SDR_RAS_MON(),.SDR_CAS_MON(),.SDR_WE_MON());
    end else begin: application_model
        // Logical application-port model only. Preserves real arbiters, their
        // 128-word writes, return latency and refresh-idle arbitration. It
        // cannot validate pin timing or the encrypted SDR PHY at 100 MHz.
        reg [11:0] pipe=0;
        reg [20:0] addresses[0:11];
        integer j,ref_count=0,refresh_left=0;
        reg refresh=0;
        assign init_done=rn;
        assign ref_vld=refresh;
        assign sdr_busy=refresh;
        assign rdv=pipe[11];
        assign rd=word_at(addresses[11]);
        always @(posedge cs) begin
            if(!rn) begin pipe<=0; ref_count<=0; refresh<=0; refresh_left<=0; end
            else begin
                pipe<={pipe[10:0],app_rd}; addresses[0]<=ra;
                for(j=1;j<12;j=j+1) addresses[j]<=addresses[j-1];
                ref_count<=ref_count+1;
                if(refresh_left>0) begin refresh_left<=refresh_left-1; refresh<=1; end
                else begin
                    refresh<=0;
                    if(ref_count>=1562 && arb.st==0 && arb.ref_block && !app_rd && !app_wr && pipe==0) begin
                        ref_count<=0; refresh_left<=12; refresh<=1;
                    end
                end
            end
        end
    end endgenerate
    task write_block;
        input integer addr,n;
        begin
            @(negedge cs); ld_addr=addr; ld_len=n; wi=0; ld_req=1;
            wait(ld_ack); @(negedge cs); ld_req=0;
            wait(ld_done); @(negedge cs); write_jobs=write_jobs+1;
        end
    endtask
    integer i,wx,wy,w,h;
    reg [23:0] expected;
    always @(posedge cp) if(rn && display_on) begin
        hp<=hs; vp<=vs; dp<=de;
        if(hp && !hs) epoch<=~epoch;
        if(vp && !vs) begin frame=frame+1; yy=0; scene<=(frame==2); end
        else if(dp && !de) yy=yy+1;
        if(!de) xx=0;
        if(de && frame>=1 && frame<=2) begin
            for(i=0;i<4;i=i+1) begin
                wx=(i<2)?0:100; wy=(i<2)?0:3; w=(i<2)?640:320; h=(i<2)?LINES:COVER_LINES;
                if(xx>=wx && xx<wx+w && yy>=wy && yy<wy+h) begin
                    expected=pixel(i,yy-wy,xx-wx,frame-1); checked[i]=checked[i]+1;
                    if(visible[i]!==1'b1 || rgb[i]!==expected) begin
                        if(errors[i]<3) $display("PIXEL_ERROR layer=%0d frame=%0d x=%0d y=%0d v=%b got=%h exp=%h",i,frame,xx,yy,visible[i],rgb[i],expected);
                        errors[i]=errors[i]+1;
                    end
                end else if(visible[i]!==1'b0) errors[i]=errors[i]+1;
            end
        end
        if(de) xx=xx+1;
    end
    integer sc,layer,offset,total,n,init_jobs;
    initial begin
        for(i=0;i<4;i=i+1) begin checked[i]=0; errors[i]=0; collisions[i]=0; end
        #213; rn=1; wait(init_done);
        for(sc=0;sc<2;sc=sc+1) for(layer=0;layer<4;layer=layer+1) begin
            total=(layer<2)?LINES*480:COVER_LINES*240;
            for(offset=0;offset<total;offset=offset+128) begin
                n=(total-offset<128)?total-offset:128;
                write_block(sc*1048576+layer*262144+offset,n);
            end
        end
        init_jobs=write_jobs;
        @(negedge cp); display_on=1;
        while(frame<3) write_block(21'h0fff00,128);
        for(i=0;i<4;i=i+1) begin
            $display("IMAGE_RESULT layer=%0d pixels=%0d errors=%0d und=%0d stall=%0d ferr=%0d gap=%0d collisions=%0d",i,checked[i],errors[i],und[i],stall[i],ferr[i],gap[i],collisions[i]);
            if(checked[i]!=((i<2)?1280*LINES:640*COVER_LINES) || errors[i]!=0 ||
               und[i]!=0 || stall[i]!=0 || ferr[i]!=0 || gap[i]!=0 || collisions[i]!=0) begin
                $display("TEST_FAIL image content or ownership"); $finish;
            end
        end
        if(text_jobs<100 || write_jobs-init_jobs<100) begin $display("TEST_FAIL pressure missing"); $finish; end
        $display("PRESSURE text=%0d preload=%0d",text_jobs,write_jobs-init_jobs);
        $display("MEMORY_SCOPE physical=%0d half_period_ns=%0f",PHYSICAL,SDR_HALF);
        $display("SCENARIO_PASS four_images_and_scene_change");
        $display("TEST_PASS"); $finish;
    end
    initial begin #200000000; $display("TEST_FAIL watchdog"); $finish; end
endmodule
`default_nettype wire
