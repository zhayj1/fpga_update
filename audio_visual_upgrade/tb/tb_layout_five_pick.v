`timescale 1ns/1ps
`default_nettype none
module tb_layout_five_pick;
    reg clk=0;always #5 clk=~clk;
    reg rn=0,tick=0,stb=0;reg [23:0] played=0;
    wire busy,done,ok,req;wire [7:0] err;wire [20:0] addr;wire [15:0] len;
    wire [15:0] fc[0:5],cnt[0:5];wire [5:0] vl;wire [5:0] off;
    reg ack=0,rdone=0,dv=0;reg [31:0] data=0,tab[0:135];
    integer state=0,rx=0,cut=136,silent=0,i,j,expected,nl=64;
    integer fi,ci,k;
    reg [15:0] edge_fc[0:10],test_count;
    reg legal;
    lyric_pick #(.CONTEXT(1),.SC_SAMP(36),.SC_PX(36),.CLK_HZ(1000000),.WD_MS(1)) dut(
        .clk_sdr(clk),.rst_sdr_n(rn),.tick(tick),.samp_stb(stb),.played(played),
        .busy(busy),.done(done),.err(err),.tab_ok(ok),.n_lines(),
        .cur_idx(),.nxt_idx(),.n3_idx(),.cur_s(),.nxt_s(),.n3_s(),
        .prev2_fc(fc[0]),.prev2_cnt(cnt[0]),.prev2_vld(vl[0]),
        .prev_fc(fc[1]),.prev_cnt(cnt[1]),.prev_vld(vl[1]),
        .cur_fc(fc[2]),.cur_cnt(cnt[2]),.cur_vld(vl[2]),
        .nxt_fc(fc[3]),.nxt_cnt(cnt[3]),.nxt_vld(vl[3]),
        .n3_fc(fc[4]),.n3_cnt(cnt[4]),.n3_vld(vl[4]),
        .n4_fc(fc[5]),.n4_cnt(cnt[5]),.n4_vld(vl[5]),
        .ttl_fc(),.ttl_cnt(),.ttl_vld(),.sgr_fc(),.sgr_cnt(),.sgr_vld(),
        .off_px(off),.scroll_on(),.px_req(req),.px_addr(addr),.px_len(len),
        .px_ack(ack),.px_done(rdone),.px_data(data),.px_valid(dv));
    always @(negedge clk) begin
        ack=0;rdone=0;dv=0;
        if(!rn) state=0;
        else case(state)
        0:if(req && !silent) begin
            if(addr!==21'h17F040 || len!==136) begin $display("TEST_FAIL burst contract");$finish;end
            ack=1;rx=0;state=1;
        end
        1:begin data=tab[rx];dv=1;
            if(rx==cut-1) begin rdone=1;state=0;end else rx=rx+1;
        end
        endcase
    end
    task scan;
        input integer sample;
        begin @(negedge clk);played=sample;tick=1;@(negedge clk);tick=0;
            wait(done);@(negedge clk);
        end
    endtask
    task check;
        input integer cur;
        begin
            if(err!==0 || ok!==1) begin $display("TEST_FAIL table status");$finish;end
            for(j=0;j<6;j=j+1) begin
                expected=cur-2+j;
                if(cur<0) expected=-1;
                if(vl[j]!==((expected>=0)&&(expected<nl))) begin
                    $display("TEST_FAIL valid cur=%0d slot=%0d vl=%b",cur,j,vl);$finish;end
                if(vl[j] && (fc[j]!==expected*5 || cnt[j]!==5)) begin
                    $display("TEST_FAIL context cur=%0d slot=%0d fc=%0d cnt=%0d",cur,j,fc[j],cnt[j]);$finish;end
            end
        end
    endtask
    task rejected;
        input [7:0] code;
        begin
            scan(100000);
            if(err!==code || ok!==0 || vl!==0 || busy!==0) begin $display("TEST_FAIL rejection");$finish;end
        end
    endtask
    initial begin
        for(i=0;i<136;i=i+1) tab[i]=0;
        tab[0]=32'h3143524c;tab[4]=64<<16;
        for(i=0;i<64;i=i+1) begin tab[8+2*i]=10000+i*20000;tab[9+2*i]=(5<<16)|i*5;end
        repeat(8) @(negedge clk);rn=1;
        scan(0);check(-1);
        for(i=0;i<64;i=i+1) begin scan(10000+i*20000);check(i);end
        $display("SCENARIO_PASS LAY-01-context64");
        nl=1;tab[4]=1<<16;scan(10000);check(0);
        nl=0;tab[4]=0;scan(10000);check(-1);
        nl=64;tab[4]=64<<16;tab[12]=tab[10];scan(30000);check(2);
        tab[12]=50000;
        $display("SCENARIO_PASS LAY-01-edges");
        tab[0]=0;rejected(8'h65);tab[0]=32'h3143524c;
        tab[4]=65<<16;rejected(8'h65);tab[4]=64<<16;
        cut=20;rejected(8'h04);cut=136;
        silent=1;rejected(8'h04);silent=0;
        scan(10000);check(0);
        $display("SCENARIO_PASS LAY-01-errors");
        scan(29964);
        for(i=0;i<37;i=i+1) begin
            @(negedge clk);stb=1;@(negedge clk);stb=0;repeat(2) @(negedge clk);
            if(off!==(i>36 ? 36 : i)) begin $display("TEST_FAIL scroll i=%0d off=%0d",i,off);$finish;end
        end
        scan(30000);check(1);
        if(off!==0) begin $display("TEST_FAIL scroll commit");$finish;end
        @(negedge clk);rn=0;repeat(4) @(negedge clk);rn=1;scan(90000);check(4);
        $display("SCENARIO_PASS LAY-01-scroll-reset");
        edge_fc[0]=0;edge_fc[1]=464;edge_fc[2]=469;edge_fc[3]=470;
        edge_fc[4]=487;edge_fc[5]=488;edge_fc[6]=489;edge_fc[7]=511;
        edge_fc[8]=512;edge_fc[9]=65535;edge_fc[10]=16'h8000;
        for(fi=0;fi<11;fi=fi+1) for(ci=0;ci<35;ci=ci+1) begin
            test_count=ci<33 ? ci : ci==33 ? 16'h8013 : 16'hffff;
            legal=test_count!=0 && test_count<=19 &&
                  ({1'b0,edge_fc[fi]}+{1'b0,test_count}<=17'd488);
            for(k=0;k<64;k=k+1) tab[9+2*k]={test_count,edge_fc[fi]};
            scan(210000);
            if(err!==0 || ok!==1 || vl!=={6{legal}}) begin
                $display("TEST_FAIL slot bound fc=%0d cnt=%0d vl=%b expected=%b",edge_fc[fi],test_count,vl,legal);$finish;
            end
            if(legal) for(k=0;k<6;k=k+1) if(fc[k]!==edge_fc[fi] || cnt[k]!==test_count) begin
                $display("TEST_FAIL slot descriptor payload");$finish;
            end
        end
        $display("SCENARIO_PASS TIMING-pick-fullwidth-boundaries");
        $display("TEST_PASS");$finish;
    end
    initial begin #10000000;$display("TEST_FAIL watchdog");$finish;end
endmodule
`default_nettype wire
