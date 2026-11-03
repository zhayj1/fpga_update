`timescale 1ns/1ps
`default_nettype none
module timing_arb_case #(parameter integer CAP=2048)(output reg finished=0);
    reg clk=0; always #5 clk=~clk;
    reg rn=0,ref_vld=0,px=0,ctl=0,ld=0;
    reg [15:0] length=0;
    reg [31:0] din=0,rd_data=0;
    reg rd_valid=0;
    wire [180:0] signals[0:1];
    wire [1:0] rd,wr,pa,ca,la,pd,cd,ldone;
    integer cycles=0,transactions=0,i,j;
    genvar g;
    generate for(g=0;g<2;g=g+1) begin: engines
        wire [20:0] ra,wa; wire [3:0] dm,gnt;
        wire [31:0] wd,pdata,cdata;
        wire pv,cv,lr,busy;
        if(g==0) begin: current
            sdram_arb #(.MAX_BURST(CAP)) dut(
                .clk(clk),.rst_n(rn),.app_rd_en(rd[g]),.app_rd_addr(ra),
                .app_wr_en(wr[g]),.app_wr_addr(wa),.app_wr_dm(dm),.app_wr_din(wd),
                .sdr_rd_en(rd_valid),.sdr_rd_dout(rd_data),.sdr_busy(1'b0),
                .sdr_init_done(1'b1),.sdr_init_ref_vld(ref_vld),
                .px_req(px),.px_addr(21'h12340),.px_len(length),.px_ack(pa[g]),
                .px_done(pd[g]),.px_data(pdata),.px_valid(pv),
                .ctl_req(ctl),.ctl_addr(21'h1fffe0),.ctl_len(length),.ctl_ack(ca[g]),
                .ctl_done(cd[g]),.ctl_data(cdata),.ctl_valid(cv),
                .ld_req(ld),.ld_addr(21'h1ffff0),.ld_len(length),.ld_data(din),
                .ld_rd(lr),.ld_ack(la[g]),.ld_done(ldone[g]),.arb_busy(busy),.gnt(gnt));
        end else begin: previous
            timing_sdram_arb_reference #(.MAX_BURST(CAP)) dut(
                .clk(clk),.rst_n(rn),.app_rd_en(rd[g]),.app_rd_addr(ra),
                .app_wr_en(wr[g]),.app_wr_addr(wa),.app_wr_dm(dm),.app_wr_din(wd),
                .sdr_rd_en(rd_valid),.sdr_rd_dout(rd_data),.sdr_busy(1'b0),
                .sdr_init_done(1'b1),.sdr_init_ref_vld(ref_vld),
                .px_req(px),.px_addr(21'h12340),.px_len(length),.px_ack(pa[g]),
                .px_done(pd[g]),.px_data(pdata),.px_valid(pv),
                .ctl_req(ctl),.ctl_addr(21'h1fffe0),.ctl_len(length),.ctl_ack(ca[g]),
                .ctl_done(cd[g]),.ctl_data(cdata),.ctl_valid(cv),
                .ld_req(ld),.ld_addr(21'h1ffff0),.ld_len(length),.ld_data(din),
                .ld_rd(lr),.ld_ack(la[g]),.ld_done(ldone[g]),.arb_busy(busy),.gnt(gnt));
        end
        assign signals[g]={rd[g],ra,wr[g],wa,dm,wd,pa[g],pd[g],pdata,pv,
                           ca[g],cd[g],cdata,cv,lr,la[g],ldone[g],busy,gnt};
    end endgenerate
    always @(posedge clk) begin
        rd_valid<=rn && rd[0]; rd_data<=rd_data+32'h01010101;
    end
    always @(negedge clk) din=din+32'h1234567;
    always @(posedge clk) begin
        #1;
        if(signals[0]!==signals[1]) begin
            $display("TEST_FAIL arb cycle diff CAP=%0d cycle=%0d current=%h old=%h",CAP,cycles,signals[0],signals[1]);$finish;
        end
        cycles=cycles+1;
    end
    task transaction;
        input integer who;
        input [15:0] size;
        input integer pause_after;
        begin
            @(negedge clk);rn=0;px=0;ctl=0;ld=0;ref_vld=0;
            repeat(4) @(negedge clk);
            rn=1;length=size;
            px=(who==0);ctl=(who==1);ld=(who==2);
            wait(pa[0] || ca[0] || la[0]);
            @(negedge clk);px=0;ctl=0;ld=0;
            if(pause_after!=0) begin
                repeat(pause_after) @(negedge clk);
                ref_vld=1;repeat(5) @(negedge clk);ref_vld=0;
            end
            wait(pd[0] || cd[0] || ldone[0]);
            repeat(38) @(negedge clk);
            transactions=transactions+1;
        end
    endtask
    initial begin
        for(i=0;i<3;i=i+1) begin
            for(j=0;j<8;j=j+1) transaction(i,j,0);
            transaction(i,16,0);transaction(i,2048,0);
            transaction(i,2049,0);transaction(i,65535,0);
            if(CAP!=0) begin transaction(i,16,1);transaction(i,2048,7);end
        end
        // All clients pending: verify the original PX > CTL > LD sequence.
        @(negedge clk);rn=0;repeat(4) @(negedge clk);
        rn=1;length=4;px=1;ctl=1;ld=1;
        wait(pa[0]);@(negedge clk);px=0;
        wait(ca[0]);@(negedge clk);ctl=0;
        wait(la[0]);@(negedge clk);ld=0;
        wait(ldone[0]);repeat(38) @(negedge clk);
        $display("Arb reference cycles CAP=%0d cycles=%0d transactions=%0d",CAP,cycles,transactions+3);
        finished=1;
    end
endmodule

module tb_timing_arb;
    wire a,b,c;
    timing_arb_case #(.CAP(2048)) normal(a);
    timing_arb_case #(.CAP(65535)) maximum(b);
    timing_arb_case #(.CAP(0)) zero(c);
    initial begin
        wait(a && b && c);
        $display("SCENARIO_PASS TIMING-arb-cycle-equivalence");
        $display("SCENARIO_PASS TIMING-arb-refresh-priority");
        $display("SCENARIO_PASS TIMING-arb-clamp-boundaries");
        $display("TEST_PASS");$finish;
    end
    initial begin #20000000;$display("TEST_FAIL arb watchdog");$finish;end
endmodule
`default_nettype wire
