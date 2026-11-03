`timescale 1ns/1ps
`default_nettype none
module marquee_case #(parameter integer BOX_W=448,SPP=2,HOLD_N=3,ID=0)(output reg [2:0] done=0);
    reg cp=0,cs=0; always #20 cp=~cp; always #5 cs=~cs;
    reg rn=0,stb=0,inject_work=0,inject_done=0,inject_cancel=0;
    reg [1:0] inject_kind=0; reg [9:0] inject_width=0;reg [7:0] inject_error=0;
    reg [15:0] tf=0,tc=0,sf=0,sc=0;
    wire [142:0] actual,expected;
    layer_text_aa #(.BOX_W(BOX_W),.SPP(SPP),.HOLD_N(HOLD_N)) dut(
        .clk_pix(cp),.rst_pix_n(rn),.hs(1'b1),.vs(1'b1),.de(1'b0),
        .en(1'b1),.en_ttl(1'b1),.color_title(24'h123456),.color_singer(24'h567890),
        .color_sung(24'hABCDEF),.color_other(24'hFEDCBA),
        .dout(actual[23:0]),.dout_vld(actual[24]),.alpha(actual[28:25]),
        .gap_cnt(actual[60:29]),.on_cnt(actual[92:61]),.ttl_off(actual[104:93]),
        .clk_sdr(cs),.rst_sdr_n(rn),.played(24'd0),
        .cur_fc(16'd0),.nxt_fc(16'd0),.n3_fc(16'd0),
        .cur_cnt(16'd0),.nxt_cnt(16'd0),.n3_cnt(16'd0),
        .cur_vld(1'b0),.nxt_vld(1'b0),.n3_vld(1'b0),
        .prev2_fc(16'd0),.prev2_cnt(16'd0),.prev_fc(16'd0),.prev_cnt(16'd0),
        .n4_fc(16'd0),.n4_cnt(16'd0),.prev2_vld(1'b0),.prev_vld(1'b0),.n4_vld(1'b0),
        .prev3_fc(16'd0),.prev3_cnt(16'd0),.n5_fc(16'd0),.n5_cnt(16'd0),
        .prev3_vld(1'b0),.n5_vld(1'b0),.song_clear(1'b0),
        .off_px(6'd0),.desc_tgl(1'b0),.samp_stb(stb),
        .ttl_fc(tf),.ttl_cnt(tc),.sgr_fc(sf),.sgr_cnt(sc),.ttl_vld(1'b1),.sgr_vld(1'b1),
        .px_req(actual[105]),.px_addr(actual[126:106]),.px_len(actual[142:127]),
        .px_ack(1'b0),.px_done(1'b0),.px_data(32'd0),.px_valid(1'b0));
    layer_text_aa_reference #(.BOX_W(BOX_W),.SPP(SPP),.HOLD_N(HOLD_N)) reference(
        .clk_pix(cp),.rst_pix_n(rn),.hs(1'b1),.vs(1'b1),.de(1'b0),
        .en(1'b1),.en_ttl(1'b1),.color_title(24'h123456),.color_singer(24'h567890),
        .color_sung(24'hABCDEF),.color_other(24'hFEDCBA),
        .dout(expected[23:0]),.dout_vld(expected[24]),.alpha(expected[28:25]),
        .gap_cnt(expected[60:29]),.on_cnt(expected[92:61]),.ttl_off(expected[104:93]),
        .clk_sdr(cs),.rst_sdr_n(rn),.played(24'd0),
        .cur_fc(16'd0),.nxt_fc(16'd0),.n3_fc(16'd0),
        .cur_cnt(16'd0),.nxt_cnt(16'd0),.n3_cnt(16'd0),
        .cur_vld(1'b0),.nxt_vld(1'b0),.n3_vld(1'b0),
        .prev2_fc(16'd0),.prev2_cnt(16'd0),.prev_fc(16'd0),.prev_cnt(16'd0),
        .n4_fc(16'd0),.n4_cnt(16'd0),.prev2_vld(1'b0),.prev_vld(1'b0),.n4_vld(1'b0),
        .prev3_fc(16'd0),.prev3_cnt(16'd0),.n5_fc(16'd0),.n5_cnt(16'd0),
        .prev3_vld(1'b0),.n5_vld(1'b0),.song_clear(1'b0),
        .off_px(6'd0),.desc_tgl(1'b0),.samp_stb(stb),
        .ttl_fc(tf),.ttl_cnt(tc),.sgr_fc(sf),.sgr_cnt(sc),.ttl_vld(1'b1),.sgr_vld(1'b1),
        .px_req(expected[105]),.px_addr(expected[126:106]),.px_len(expected[142:127]),
        .px_ack(1'b0),.px_done(1'b0),.px_data(32'd0),.px_valid(1'b0));
    integer i,j,pos,seed;
    reg [31:0] limit;
    task tick;begin @(negedge cs);#1;end endtask
    task deposit_step;
        input integer offset;
        begin
            dut.off_t=offset;reference.off_t=offset;
            dut.off_s=offset;reference.off_s=offset;
            dut.hold_count=0;reference.hold_count=0;
            dut.hold_empty=1;reference.hold_empty=1;
            dut.div_count=SPP-1;reference.div_count=SPP-1;
            dut.divider_last=1;reference.divider_last=1;
            stb=1;tick;
        end
    endtask
    // Compare the untouched r7 sequential logic and all public outputs after
    // every SDR edge, including simultaneous row completion/sample/descriptor
    // updates. Inject only the row-renderer completion interface in both.
    always @(posedge cs) begin
        #1;
        if(actual!==expected ||
           {dut.off_t,dut.off_s,dut.div_count,dut.hold_count,dut.hold_empty,dut.divider_last,
            dut.title_changed_q,dut.singer_changed_q,dut.done_toggle,dut.completed_width,
            dut.completed_kind,dut.completed_scroll} !==
           {reference.off_t,reference.off_s,reference.div_count,reference.hold_count,
            reference.hold_empty,reference.divider_last,reference.title_changed_q,
            reference.singer_changed_q,reference.done_toggle,reference.completed_width,
            reference.completed_kind,reference.completed_scroll} ||
           dut.title_wrap!==(reference.wt>BOX_W && reference.off_t>=reference.wt+BOX_W-1) ||
           dut.singer_wrap!==(reference.ws>BOX_W && reference.off_s>=reference.ws+BOX_W-1) ||
           dut.title_wide!==(reference.wt>BOX_W) || dut.singer_wide!==(reference.ws>BOX_W)) begin
            $display("TEST_FAIL marquee id=%0d width=%0d step=%0d time=%0t off=%0d/%0d singer=%0d/%0d",
                ID,i,j,$time,dut.off_t,reference.off_t,dut.off_s,reference.off_s);$finish;
        end
    end
    initial begin
        force dut.working=inject_work;
        force dut.c_kind=inject_kind;
        force dut.row_done=inject_done;
        force dut.row_width=inject_width;
        force dut.row_error=inject_error;
        force dut.cancel_job=inject_cancel;
        force reference.working=inject_work;
        force reference.c_kind=inject_kind;
        force reference.row_done=inject_done;
        force reference.row_width=inject_width;
        force reference.row_error=inject_error;
        force reference.cancel_job=inject_cancel;
        seed=7113+ID;repeat(5) tick;rn=1;repeat(5) tick;
        for(i=0;i<1024;i=i+1) begin
            inject_work=1;inject_done=1;inject_kind=1;inject_width=i;tick;
            inject_kind=2;inject_width=1023-i;tick;
            inject_done=0;inject_work=0;
            // Width boundaries, 10-bit overflow, and both wrap limits.
            for(j=0;j<10;j=j+1) begin
                limit=j<5 ? i+BOX_W-1 : 1023-i+BOX_W-1;
                case(j%5)
                0:pos=0;1:pos=1023;2:pos=limit-1;3:pos=limit;4:pos=limit+1;
                endcase
                deposit_step(pos);
            end
        end
        done[0]=1;
        // Natural progression exercises simultaneous title/singer wraps,
        // sample gaps, exact hold lengths, and unreachable (>1023) limits.
        for(i=0;i<8;i=i+1) begin
            inject_work=1;inject_done=1;inject_kind=1;
            inject_width=(i==7) ? 1023 : BOX_W+i+1;tick;
            inject_kind=2;inject_width=BOX_W+i+3;tick;
            inject_done=0;inject_work=0;
            for(j=0;j<32000;j=j+1) begin stb=(j%7!=0);tick;end
        end
        done[1]=1;
        for(i=0;i<100000;i=i+1) begin
            stb=$random(seed);inject_width=$random(seed);inject_kind=$random(seed);
            inject_work=($random(seed)&3)!=0;inject_done=$random(seed);
            inject_error=($random(seed)&7)==0;inject_cancel=($random(seed)&7)==0;
            if(i%17==0) tf=$random(seed);
            if(i%19==0) sc=$random(seed);
            if(i%31==0) begin tc=$random(seed);sf=$random(seed);end
            rn=i%997!=0;tick;
        end
        done[2]=1;
    end
endmodule
module tb_marquee_compressed_equivalence;
    wire [26:0] done;
    marquee_case #(.BOX_W(0),.SPP(2),.HOLD_N(3),.ID(0)) c0(.done(done[2:0]));
    marquee_case #(.BOX_W(1),.SPP(2),.HOLD_N(3),.ID(1)) c1(.done(done[5:3]));
    marquee_case #(.BOX_W(160),.SPP(2),.HOLD_N(3),.ID(2)) c2(.done(done[8:6]));
    marquee_case #(.BOX_W(288),.SPP(2),.HOLD_N(3),.ID(3)) c3(.done(done[11:9]));
    marquee_case #(.BOX_W(448),.SPP(2),.HOLD_N(3),.ID(4)) c4(.done(done[14:12]));
    marquee_case #(.BOX_W(1024),.SPP(2),.HOLD_N(3),.ID(5)) c5(.done(done[17:15]));
    marquee_case #(.BOX_W(-1),.SPP(2),.HOLD_N(3),.ID(6)) c6(.done(done[20:18]));
    marquee_case #(.BOX_W(448),.SPP(1),.HOLD_N(0),.ID(7)) c7(.done(done[23:21]));
    marquee_case #(.BOX_W(448),.SPP(1200),.HOLD_N(24000),.ID(8)) c8(.done(done[26:24]));
    initial begin
        wait(done[0]&&done[3]&&done[6]&&done[9]&&done[12]&&done[15]&&done[18]&&done[21]&&done[24]);
        $display("SCENARIO_PASS MARQUEE-all-widths-and-offset-boundaries");
        wait(done[1]&&done[4]&&done[7]&&done[10]&&done[13]&&done[16]&&done[19]&&done[22]&&done[25]);
        $display("SCENARIO_PASS MARQUEE-cadence-hold-and-overflow");
        wait(&done);$display("SCENARIO_PASS MARQUEE-random-completion-reset-priority");
        $display("TEST_PASS");$finish;
    end
    initial begin #6000000;$display("TEST_FAIL marquee timeout");$finish;end
endmodule
`default_nettype wire
