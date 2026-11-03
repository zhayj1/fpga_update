`timescale 1ns/1ps
`default_nettype none
module tb_layer_text_aa;
    reg cp=0,cs=0; always #20 cp=~cp; always #3.333 cs=~cs;
    reg rn=0,hs=1,vs=1,de=0,dt=0,stb=0;
    reg [5:0] off=0;
    wire [23:0] rgb; wire valid; wire [3:0] alpha;
    wire [11:0] title_offset;
    wire req; wire [20:0] addr; wire [15:0] len;
    reg ack=0,done=0,dv=0; reg [31:0] data=0;
    reg [31:0] font[0:964239],lrc[0:1111]; reg [3:0] gold[0:6055];
    integer bs=0,delay_n=0,rx=0,wait_cycles=0,slow=0,saved_len=0;
    reg [20:0] saved;
    layer_text_aa #(.SPP(2),.HOLD_N(3)) dut(
        .clk_pix(cp),.rst_pix_n(rn),.hs(hs),.vs(vs),.de(de),.en(1'b1),.en_ttl(1'b1),
        .dout(rgb),.dout_vld(valid),.alpha(alpha),.gap_cnt(),.on_cnt(),.ttl_off(title_offset),
        .clk_sdr(cs),.rst_sdr_n(rn),.played(24'd2500),
        .cur_fc(16'd0),.nxt_fc(16'd0),.n3_fc(16'd0),
        .cur_cnt(16'd8),.nxt_cnt(16'd8),.n3_cnt(16'd8),
        .cur_vld(1'b1),.nxt_vld(1'b1),.n3_vld(1'b1),.off_px(off),.desc_tgl(dt),
        .prev2_fc(16'd0),.prev2_cnt(16'd0),.prev_fc(16'd0),.prev_cnt(16'd0),
        .n4_fc(16'd0),.n4_cnt(16'd0),.prev2_vld(1'b0),.prev_vld(1'b0),
        .n4_vld(1'b0),.song_clear(1'b0),
        .samp_stb(stb),.ttl_fc(16'd0),.ttl_cnt(16'd16),.sgr_fc(16'd0),.sgr_cnt(16'd8),
        .ttl_vld(1'b1),.sgr_vld(1'b1),.px_req(req),.px_addr(addr),.px_len(len),
        .px_ack(ack),.px_done(done),.px_data(data),.px_valid(dv));
    always @(negedge cs) begin
        ack=0; done=0; dv=0;
        if(!rn) bs=0;
        else case(bs)
        0:if(req) begin saved=addr; saved_len=len; delay_n=2; bs=1; end
        1:if(delay_n==0) begin ack=1; rx=0; bs=2; delay_n=slow; end else delay_n=delay_n-1;
        2:if(delay_n==0) begin
            if(saved>=21'h10BBB0 && saved<21'h10BBB0+964240) data=font[saved-21'h10BBB0+rx];
            else if(saved>=21'h10B300 && saved<21'h10B300+1112) data=lrc[saved-21'h10B300+rx];
            else begin $display("TEST_FAIL invalid address"); $finish; end
            dv=1;
            if(rx==saved_len-1) begin done=1; bs=0; end else rx=rx+1;
        end else delay_n=delay_n-1;
        endcase
    end
    integer checked=0,ink=0,late_ink=0,cancels=0;
    always @(posedge cs) if(rn) begin
        if(dut.cancel_job) cancels=cancels+1;
        if(de && dut.wr_en && dut.wr_addr[10]==dut.current_y[0]) begin
            $display("TEST_FAIL writing bank during active scan"); $finish;
        end
    end
    integer frame_mode=0,expected_off=0;
    integer ly=0,xx=0,yy=0,source=0,gy=0,typ=0,idx=0,j;
    reg [3:0] ea; reg [23:0] ec;
    task pixel_check;
        input integer px,py;
        begin
            ea=0; ec=24'hFFFFFF; source=-1; gy=0; typ=0;
            if(py>=16 && py<40 && px>=32 && px<192) begin
                source=(px-32+expected_off)%458; gy=py-16; typ=1;
                if(source>=298) source=-1;
            end else if(py>=48 && py<68 && px>=32 && px<156) begin
                source=px-32; gy=py-48; typ=2; ec=24'hBCC4D2;
            end else if(py>=396 && py<468 && px>=245 && px<394) begin
                if(py>=404-off && py<428-off) begin gy=py-404+off; typ=3; end
                else if(py>=436-off && py<460-off) begin gy=py-436+off; typ=4; end
                else if(py>=468-off && py<492-off) begin gy=py-468+off; typ=4; end
                if(typ!=0) begin
                    source=px-245; ec=(typ==3 && source<65) ? 24'hFFE8AA : 24'hE8E4FF;
                end
            end
            if(source>=0 && typ!=0) begin
                if(typ==2) ea=gold[3576+gy*124+source];
                else ea=gold[gy*149+(source%149)];
            end
            if(frame_mode<2) begin
                if(alpha!==ea || valid!==(ea!=0) || (ea!=0 && rgb!==ec)) begin
                    $display("TEST_FAIL layer mode=%0d x=%0d y=%0d alpha=%h/%h rgb=%h/%h off=%0d cur_y=%0d tag=%b",frame_mode,px,py,alpha,ea,rgb,ec,expected_off,dut.current_y,dut.active_ok); $finish;
                end
                checked=checked+1; if(ea!=0) ink=ink+1;
            end else if(valid) late_ink=late_ink+1;
        end
    endtask
    task draw_frame;
        begin
            @(negedge cp); vs=0; hs=1; de=0;
            repeat(800) @(negedge cp); vs=1;
            for(ly=0;ly<515;ly=ly+1) begin
                for(xx=0;xx<800;xx=xx+1) begin
                    hs=xx>=96; de=xx>=144 && xx<784 && ly>=34 && ly<514;
                    #1;
                    if(de) pixel_check(xx-144,ly-34);
                    @(negedge cp);
                end
            end
            de=0; hs=1;
        end
    endtask
    task samples;
        input integer n;
        begin for(j=0;j<n;j=j+1) begin @(negedge cs); stb=1; @(negedge cs); stb=0; end end
    endtask
    initial begin
        $readmemh("sim/typography_font.mem",font); $readmemh("sim/typography_sample_lrc.mem",lrc);
        $readmemh("sim/typography_row_golden.mem",gold);
        for(j=0;j<16;j=j+1) lrc[136+16+j]=lrc[136+j];
        repeat(8) @(negedge cp); rn=1; dt=1;
        repeat(12) @(negedge cp);
        draw_frame;
        if(ink==0 || checked!=307200) begin $display("TEST_FAIL empty frame"); $finish; end
        $display("SCENARIO_PASS TYP-04-pixels");
        samples(2*458);
        if(title_offset!==0) begin $display("TEST_FAIL scroll wrap"); $finish; end
        samples(3); if(title_offset!==0) begin $display("TEST_FAIL scroll hold"); $finish; end
        samples(34); expected_off=17;
        if(title_offset!==17) begin $display("TEST_FAIL scroll step"); $finish; end
        off=16; dt=0; repeat(12) @(negedge cp); frame_mode=1;
        draw_frame;
        $display("SCENARIO_PASS TYP-04-scroll");
        slow=6000; frame_mode=2; draw_frame;
        if(late_ink!=0 || cancels==0) begin $display("TEST_FAIL late row visible ink=%0d cancel=%0d",late_ink,cancels); $finish; end
        slow=0; repeat(7000) @(negedge cs); frame_mode=1; draw_frame;
        $display("SCENARIO_PASS TYP-04-deadline");
        $display("TEST_PASS"); $finish;
    end
    initial begin #100000000; $display("TEST_FAIL watchdog"); $finish; end
endmodule
`default_nettype wire
